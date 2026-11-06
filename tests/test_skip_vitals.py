"""Emergency: skip vitals, and dispatch is never gated on MOEWS (A2)."""
from __future__ import annotations

import uuid
from unittest.mock import MagicMock

import pytest

NORMAL_VITALS = {
    "systolic_bp": 120,
    "diastolic_bp": 80,
    "heart_rate": 80,
    "respiratory_rate": 18,
    "temperature": 37.0,
    "spo2": 98,
    "consciousness_level": "A",
}




def _payload(**overrides):
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "0123456789abcdef" * 4,
        "emergency_type": "pph",
        "client_request_id": str(uuid.uuid4()),
        "vitals_taken": False,
        **overrides,
    }


@pytest.mark.asyncio
async def test_skip_vitals_dispatches_as_unknown_without_any_assessment(
    client, seeded_db, monkeypatch
):
    invoke = MagicMock(side_effect=AssertionError("scoring must not run"))
    monkeypatch.setattr("src.api.referral.score_vitals", invoke)

    response = await client.post("/api/v1/referral", json=_payload())

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["referral"]["risk_level"] == "UNKNOWN"
    assert body["referral"]["moews_score"] is None
    assert body["referral"]["vitals_taken"] is False
    assert body["dispatch"]["status"] == "TIER1_NOTIFIED"
    invoke.assert_not_called()


@pytest.mark.asyncio
async def test_replay_is_idempotent_and_keeps_the_flag(client, seeded_db):
    payload = _payload()
    first = await client.post("/api/v1/referral", json=payload)
    second = await client.post("/api/v1/referral", json=payload)
    assert second.json()["idempotent"] is True
    assert second.json()["referral"]["id"] == first.json()["referral"]["id"]
    assert second.json()["referral"]["vitals_taken"] is False


@pytest.mark.asyncio
async def test_emergency_type_and_facility_are_still_required(client, seeded_db):
    for field in ("emergency_type", "facility_id"):
        payload = _payload()
        del payload[field]
        assert (await client.post("/api/v1/referral", json=payload)).status_code == 422


@pytest.mark.asyncio
async def test_flag_cannot_be_sent_with_vitals(client, seeded_db):
    response = await client.post("/api/v1/referral", json=_payload(vitals=NORMAL_VITALS))
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_hospital_sms_says_vitals_not_taken(db_session):
    from src.db.models import Referral
    from src.services.hospital_notifier import HospitalNotifier
    from tests.conftest import queued_sms

    referral = Referral(
        patient_hash="a" * 64,
        chps_compound_id=1,
        emergency_type="pph",
        risk_level="UNKNOWN",
        vitals_json={"systolic_bp": None, "vitals_taken": False},
    )
    HospitalNotifier().notify_pre_arrival(
        db_session, referral, MagicMock(), MagicMock(phone="+233240000200"), 7
    )
    await db_session.flush()

    body = (await queued_sms(db_session))[0].body
    assert "Vitals not taken" in body
    assert "Not measured" not in body


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("vitals", "risk"),
    [
        (NORMAL_VITALS, "GREEN"),
        ({**NORMAL_VITALS, "respiratory_rate": 25}, "YELLOW"),
        ({**NORMAL_VITALS, "systolic_bp": 60}, "RED"),
        ({**NORMAL_VITALS, "temperature": None}, "INCOMPLETE"),
    ],
)
async def test_dispatch_is_never_gated_on_risk(client, seeded_db, vitals, risk):
    payload = _payload(vitals=vitals, vitals_taken=True)

    response = await client.post("/api/v1/referral", json=payload)

    assert response.status_code == 201, response.text
    assert response.json()["referral"]["risk_level"] == risk
    assert response.json()["dispatch"]["status"] == "TIER1_NOTIFIED"


@pytest.mark.asyncio
async def test_a_scoring_failure_still_dispatches(client, seeded_db, monkeypatch):
    monkeypatch.setattr(
        "src.api.referral.score_vitals", MagicMock(side_effect=RuntimeError("scoring bug"))
    )
    response = await client.post(
        "/api/v1/referral", json=_payload(vitals=NORMAL_VITALS, vitals_taken=True)
    )
    assert response.status_code == 201, response.text
    assert response.json()["referral"]["risk_level"] == "UNKNOWN"
    assert response.json()["dispatch"]["status"] == "TIER1_NOTIFIED"
