from unittest.mock import AsyncMock, MagicMock

import pytest


def test_clinical_assessment_returns_unknown_template_for_missing_vitals(monkeypatch):
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

    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None
    assert "UNKNOWN" in result["clinical_summary"]


def test_clinical_assessment_handles_absent_vitals_and_gestational_weeks(monkeypatch):
    from src.agents import clinical_agent

    monkeypatch.setattr(clinical_agent, "rag_engine", None)
    monkeypatch.setattr(clinical_agent, "llm", None)
    monkeypatch.setattr(clinical_agent.settings, "GEMINI_API_KEY", "")

    result = clinical_agent.run_clinical_assessment({"vitals": {}})

    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None
    assert "Gestational age: unknown weeks." in result["clinical_summary"]


def test_clinical_rag_initialization_seeds_protocols(monkeypatch):
    from src.agents import clinical_agent

    engine = MagicMock()
    monkeypatch.setattr(clinical_agent, "rag_engine", None)
    monkeypatch.setattr(
        clinical_agent, "ProtocolRAGEngine", lambda *args, **kwargs: engine
    )

    assert clinical_agent._get_rag_engine() is engine
    engine.seed_initial_protocols.assert_called_once_with()


def test_prepare_dispatch_encodes_unknown_score_as_zero():
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


@pytest.mark.asyncio
async def test_divert_updates_destination_and_notifies(monkeypatch):
    from src.api import sms_webhook

    dispatch = MagicMock(id=11, referral_id=21, facility_id=1, status="ACCEPTED")
    referral = MagicMock(id=21, facility_id=1, patient_name="Ama")
    current_facility = MagicMock(id=1, phone="020 000 0001")
    destination = MagicMock(id=2, phone="+233200000002")
    compound = MagicMock(cho_phone="+233200000001")
    driver = MagicMock(phone="+233200000003")
    session = MagicMock()
    session.get = AsyncMock(
        side_effect=[dispatch, referral, current_facility, destination, compound, driver]
    )
    session.add = MagicMock()
    session.commit = AsyncMock()
    gateway = MagicMock()
    gateway.send_sms = __import__("unittest.mock").mock.AsyncMock(
        return_value={"status": "MOCKED"}
    )
    monkeypatch.setattr(sms_webhook, "MessagingGateway", lambda: gateway)

    result = await sms_webhook.process_inbound_sms(
        session, "+233 200 000 001", "DIVERT 11 2"
    )

    assert result["status"] == "DIVERTED"
    assert referral.facility_id == 2
    assert dispatch.status == "DIVERTED"
    assert gateway.send_sms.await_count == 2


@pytest.mark.asyncio
async def test_inbound_sms_rejects_sender_other_than_current_facility():
    from src.api import sms_webhook

    dispatch = MagicMock(id=11, referral_id=21, facility_id=1, status="ACCEPTED")
    referral = MagicMock(id=21)
    current_facility = MagicMock(id=1, phone="+233200000001")
    session = MagicMock()
    session.get = AsyncMock(side_effect=[dispatch, referral, current_facility])
    session.add = MagicMock()
    session.commit = AsyncMock()

    with pytest.raises(ValueError, match="Unauthorized sender"):
        await sms_webhook.process_inbound_sms(
            session, "+233200000099", "CONFIRM 11"
        )

    assert dispatch.status == "ACCEPTED"
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_inbound_sms_rejects_commands_before_driver_acceptance():
    from src.api import sms_webhook

    dispatch = MagicMock(id=11, referral_id=21, facility_id=1, status="TIER1_NOTIFIED")
    referral = MagicMock(id=21)
    current_facility = MagicMock(id=1, phone="+233200000001")
    session = MagicMock()
    session.get = AsyncMock(side_effect=[dispatch, referral, current_facility])
    session.add = MagicMock()
    session.commit = AsyncMock()

    with pytest.raises(ValueError, match="not available"):
        await sms_webhook.process_inbound_sms(
            session, "0200000001", "CONFIRM 11"
        )

    assert dispatch.status == "TIER1_NOTIFIED"
    session.commit.assert_not_awaited()
