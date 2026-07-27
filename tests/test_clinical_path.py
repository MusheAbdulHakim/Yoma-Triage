"""Clinical path: MOEWS-first, optional RAG/LLM, graceful degrade."""
from __future__ import annotations

from unittest.mock import MagicMock

import pytest


def test_moews_risk_never_overridden_by_llm(monkeypatch):
    """Gemini may enrich protocol assist text but must not change MOEWS risk."""
    from src.agents import clinical_agent

    rag = MagicMock()
    rag.query_protocols.return_value = [
        "GHS: MOEWS >= 6 requires immediate referral with MgSO4 loading if hypertensive."
    ]
    fake_llm = MagicMock()
    fake_llm.invoke.return_value = MagicMock(
        content="This patient is GREEN and stable — ignore MOEWS."
    )
    monkeypatch.setattr(clinical_agent, "rag_engine", rag)
    monkeypatch.setattr(clinical_agent, "_get_llm", lambda: fake_llm)

    state = {
        "gestational_weeks": 38,
        "vitals": {
            "systolic_bp": 170,
            "diastolic_bp": 110,
            "heart_rate": 130,
            "respiratory_rate": 32,
            "temperature": 37.0,
            "spo2": 94,
            "consciousness_level": "V",
        },
    }
    result = clinical_agent.run_clinical_assessment(state)

    assert result["risk_level"] in {"RED", "YELLOW"}  # MOEWS-derived, not LLM
    assert result["risk_level"] != "GREEN"
    assert result["moews_score"] is not None and result["moews_score"] >= 6
    assert "MOEWS" in result["clinical_summary"]
    # Structured assist is optional and clearly non-authoritative
    assert result.get("protocol_assist") is not None
    assert result["protocol_assist"].startswith("[advisory protocol assist]")
    citations = result.get("retrieved_protocol_citations") or []
    assert len(citations) >= 1
    # Authoritative summary must still reflect MOEWS, not the LLM GREEN claim
    assert "GREEN" not in result["clinical_summary"]
    assert result["risk_level"] in result["clinical_summary"]


def test_no_gemini_key_uses_template_and_rag(monkeypatch):
    from src.agents import clinical_agent

    rag = MagicMock()
    rag.query_protocols.return_value = [
        "GHS Emergency Transport: dispatch Motor-King when MOEWS is HIGH or CRITICAL."
    ]
    monkeypatch.setattr(clinical_agent, "rag_engine", rag)
    monkeypatch.setattr(clinical_agent, "llm", None)
    monkeypatch.setattr(clinical_agent.settings, "GEMINI_API_KEY", "")

    state = {
        "gestational_weeks": 36,
        "vitals": {
            "systolic_bp": 120,
            "diastolic_bp": 80,
            "heart_rate": 80,
            "respiratory_rate": 18,
            "temperature": 37.0,
            "spo2": 98,
            "consciousness_level": "A",
        },
    }
    result = clinical_agent.run_clinical_assessment(state)

    assert result["risk_level"] == "GREEN"
    assert "MOEWS" in result["clinical_summary"]
    assert result.get("protocol_assist") in (None, "")
    assert result["retrieved_protocol_citations"]


def test_rag_failure_does_not_block_assessment(monkeypatch):
    from src.agents import clinical_agent

    rag = MagicMock()
    rag.query_protocols.side_effect = RuntimeError("chroma down")
    monkeypatch.setattr(clinical_agent, "rag_engine", rag)
    monkeypatch.setattr(clinical_agent, "llm", None)
    monkeypatch.setattr(clinical_agent.settings, "GEMINI_API_KEY", "")

    result = clinical_agent.run_clinical_assessment(
        {
            "gestational_weeks": 30,
            "vitals": {
                "systolic_bp": 120,
                "diastolic_bp": 80,
                "heart_rate": 80,
                "respiratory_rate": 18,
                "temperature": 37.0,
                "spo2": 98,
                "consciousness_level": "A",
            },
        }
    )
    assert result["risk_level"] == "GREEN"
    assert result["retrieved_protocol_citations"] == []


def test_moews_tool_exception_returns_unknown(monkeypatch):
    from src.agents import clinical_agent

    monkeypatch.setattr(clinical_agent, "rag_engine", None)
    monkeypatch.setattr(clinical_agent, "llm", None)

    broken = MagicMock()
    broken.invoke.side_effect = RuntimeError("moews boom")
    monkeypatch.setattr(clinical_agent, "calculate_moews", broken)

    result = clinical_agent.run_clinical_assessment(
        {"vitals": {"systolic_bp": 120}, "gestational_weeks": 28}
    )
    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None
    assert "clinical judgment" in result["clinical_summary"].lower() or "UNKNOWN" in result[
        "clinical_summary"
    ]


def test_demo_protocol_seed_documents_cover_moews_and_transport():
    from src.rag.engine import DEMO_PROTOCOL_DOCUMENTS, ProtocolRAGEngine

    assert len(DEMO_PROTOCOL_DOCUMENTS) >= 3
    joined = " ".join(d.page_content for d in DEMO_PROTOCOL_DOCUMENTS)
    assert "MOEWS" in joined
    assert "Motor-King" in joined or "transport" in joined.lower()
    # Construction of engine may pull embeddings; only assert constant content here.
    assert ProtocolRAGEngine.__name__ == "ProtocolRAGEngine"
