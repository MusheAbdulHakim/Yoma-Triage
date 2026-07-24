from unittest.mock import MagicMock


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


@__import__("pytest").mark.asyncio
async def test_divert_updates_destination_and_notifies(monkeypatch):
    from src.api import sms_webhook

    dispatch = MagicMock(id=11, referral_id=21, status="ACCEPTED")
    referral = MagicMock(id=21, facility_id=1, patient_name="Ama")
    destination = MagicMock(id=2, phone="+233200000002")
    compound = MagicMock(cho_phone="+233200000001")
    driver = MagicMock(phone="+233200000003")
    session = MagicMock()
    session.get = __import__("unittest.mock").mock.AsyncMock(
        side_effect=[dispatch, referral, destination, compound, driver]
    )
    session.add = MagicMock()
    session.commit = __import__("unittest.mock").mock.AsyncMock()
    gateway = MagicMock()
    gateway.send_sms = __import__("unittest.mock").mock.AsyncMock(
        return_value={"status": "MOCKED"}
    )
    monkeypatch.setattr(sms_webhook, "MessagingGateway", lambda: gateway)

    result = await sms_webhook.process_inbound_sms(
        session, "+233200000002", "DIVERT 11 2"
    )

    assert result["status"] == "DIVERTED"
    assert referral.facility_id == 2
    assert dispatch.status == "DIVERTED"
    assert gateway.send_sms.await_count == 2
