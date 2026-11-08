from unittest.mock import MagicMock

import pytest


def test_clinical_assessment_reports_incomplete_for_missing_vitals(monkeypatch):
    from src.agents import clinical_agent

    rag = MagicMock()
    rag.query_protocols.return_value = []
    monkeypatch.setattr(clinical_agent, "rag_engine", rag)
    monkeypatch.setattr(clinical_agent, "llm", None)
    state = {
        "vitals": {
            "systolic_bp": None,
            "diastolic_bp": 80,
            "heart_rate": 80,
            "respiratory_rate": 18,
            "temperature": 37.0,
        },
        "gestational_weeks": 32,
    }

    result = clinical_agent.run_clinical_assessment(state)

    assert result["risk_level"] == "INCOMPLETE"
    assert result["missing_vitals"] == ["systolic_bp", "spo2", "consciousness_level"]
    assert "INCOMPLETE" in result["clinical_summary"]
    assert "Not measured: systolic_bp" in result["clinical_summary"]


def test_clinical_assessment_handles_absent_vitals_and_gestational_weeks(monkeypatch):
    from src.agents import clinical_agent

    monkeypatch.setattr(clinical_agent, "rag_engine", None)
    monkeypatch.setattr(clinical_agent, "llm", None)
    monkeypatch.setattr(clinical_agent.settings, "GEMINI_API_KEY", "")

    result = clinical_agent.run_clinical_assessment({"vitals": {}})

    assert result["risk_level"] == "INCOMPLETE"
    assert result["moews_score"] is None
    assert "Gestational age: unknown weeks." in result["clinical_summary"]


def test_clinical_rag_initialization_seeds_protocols(monkeypatch):
    from src.agents import clinical_agent

    engine = MagicMock()
    monkeypatch.setattr(clinical_agent, "rag_engine", None)
    pytest.importorskip("langchain_chroma", reason="needs requirements-rag.txt")
    monkeypatch.setattr("src.config.settings.RAG_ENABLED", True)
    monkeypatch.setattr(
        "src.rag.engine.ProtocolRAGEngine", lambda *args, **kwargs: engine
    )

    assert clinical_agent._get_rag_engine() is engine
    engine.seed_initial_protocols.assert_called_once_with()


def test_prepare_dispatch_encodes_unknown_score_as_zero():
    pytest.importorskip("langgraph", reason="needs requirements-rag.txt")
    from src.agents.coordinator import prepare_dispatch_node

    result = prepare_dispatch_node(
        {
            "chps_id": "CHPS-7",
            "moews_score": None,
            "risk_level": "UNKNOWN",
            "vitals": {"heart_rate": 80, "systolic_bp": 120},
        }
    )

    assert result["compressed_sms_payload"]
