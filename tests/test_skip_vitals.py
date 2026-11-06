"""Dispatch never waits on MOEWS: skip-vitals path and assessment time limits."""
from __future__ import annotations

import asyncio
import time
import uuid
from unittest.mock import MagicMock

import pytest

CRITICAL_VITALS = {
    "systolic_bp": 60,
    "diastolic_bp": 80,
    "heart_rate": 80,
    "respiratory_rate": 18,
    "temperature": 37.0,
    "spo2": 98,
    "consciousness_level": "A",
}


@pytest.fixture(autouse=True)
def no_timers(monkeypatch):
    monkeypatch.setattr(
        "src.services.dispatch_orchestrator.DispatchOrchestrator.schedule_tier_timeouts",
        lambda self, *a, **k: None,
    )


def _skip_payload(**overrides):
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "0123456789abcdef" * 4,
        "emergency_type": "pph",
        "client_request_id": str(uuid.uuid4()),
        "vitals_not_taken": True,
        **overrides,
    }


def _measured_payload():
    payload = _skip_payload(vitals=CRITICAL_VITALS)
    del payload["vitals_not_taken"]
    return payload


@pytest.mark.asyncio
async def test_skip_vitals_dispatches_without_running_the_assessment(
    client, seeded_db, monkeypatch
):
    invoke = MagicMock(side_effect=AssertionError("assessment must not run"))
    monkeypatch.setattr("src.api.referral.yoma_graph.invoke", invoke)

    response = await client.post("/api/v1/referral", json=_skip_payload())

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["referral"]["risk_level"] == "UNKNOWN"
    assert body["referral"]["severity"] == "UNKNOWN"
    assert body["referral"]["moews_score"] is None
    assert body["referral"]["vitals_not_taken"] is True
    assert "Vitals not taken" in body["referral"]["clinical_summary"]
    assert body["dispatch"]["status"] == "TIER1_NOTIFIED"
    invoke.assert_not_called()


@pytest.mark.asyncio
async def test_skip_vitals_replay_is_idempotent_and_keeps_the_flag(client, seeded_db):
    payload = _skip_payload()
    first = await client.post("/api/v1/referral", json=payload)
    second = await client.post("/api/v1/referral", json=payload)
    assert second.json()["idempotent"] is True
    assert second.json()["referral"]["id"] == first.json()["referral"]["id"]
    assert second.json()["referral"]["vitals_not_taken"] is True


@pytest.mark.asyncio
async def test_skip_vitals_still_requires_the_emergency_type(client, seeded_db):
    payload = _skip_payload()
    del payload["emergency_type"]
    assert (await client.post("/api/v1/referral", json=payload)).status_code == 422


@pytest.mark.asyncio
async def test_flag_cannot_hide_vitals_that_were_sent(client, seeded_db):
    response = await client.post(
        "/api/v1/referral", json=_skip_payload(vitals=CRITICAL_VITALS)
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_normal_referral_flag_is_false(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.agents.clinical_agent._get_rag_engine", lambda: None)
    monkeypatch.setattr("src.agents.clinical_agent._get_llm", lambda: None)
    response = await client.post("/api/v1/referral", json=_measured_payload())
    assert response.json()["referral"]["vitals_not_taken"] is False


@pytest.mark.asyncio
async def test_hospital_sms_says_vitals_not_taken():
    from unittest.mock import AsyncMock

    from src.db.models import Referral
    from src.services.hospital_notifier import HospitalNotifier

    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "SENT"})
    referral = Referral(
        patient_hash="a" * 64,
        chps_compound_id=1,
        emergency_type="pph",
        risk_level="UNKNOWN",
        vitals_json={"systolic_bp": None, "vitals_not_taken": True},
    )
    await HospitalNotifier(gateway).notify_pre_arrival(
        MagicMock(),
        referral,
        MagicMock(name="driver"),
        MagicMock(phone="+233240000200"),
        7,
    )
    body = gateway.send_sms.await_args.args[1]
    assert "Vitals: NOT TAKEN" in body
    assert "Not measured" not in body


@pytest.mark.asyncio
async def test_slow_assessment_does_not_delay_dispatch_or_hide_red(
    client, seeded_db, monkeypatch
):
    monkeypatch.setattr("src.api.referral.ASSESSMENT_TIMEOUT_SECONDS", 0.05)
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke", lambda state: time.sleep(1.5)
    )

    started = time.monotonic()
    response = await client.post("/api/v1/referral", json=_measured_payload())
    elapsed = time.monotonic() - started

    assert elapsed < 1.0
    assert response.status_code == 201, response.text
    referral = response.json()["referral"]
    assert referral["risk_level"] == "RED"
    assert referral["moews_score"] == 3
    assert response.json()["dispatch"]["status"] == "TIER1_NOTIFIED"


@pytest.mark.asyncio
async def test_failed_assessment_does_not_hide_red(client, seeded_db, monkeypatch):
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke",
        MagicMock(side_effect=RuntimeError("graph down")),
    )
    response = await client.post("/api/v1/referral", json=_measured_payload())
    assert response.status_code == 201, response.text
    assert response.json()["referral"]["risk_level"] == "RED"
    assert response.json()["referral"]["moews_score"] == 3


@pytest.mark.asyncio
async def test_slow_assessment_does_not_block_the_server(client, seeded_db, monkeypatch):
    """A cold protocol lookup used to freeze USSD and every other request."""
    monkeypatch.setattr("src.api.referral.ASSESSMENT_TIMEOUT_SECONDS", 5)
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke", lambda state: time.sleep(1.0)
    )

    from src.api.referral import VitalsInput, _assess

    assessing = asyncio.create_task(_assess({}, VitalsInput(**CRITICAL_VITALS)))
    await asyncio.sleep(0.05)
    started = time.monotonic()
    health = await client.get("/")
    during = time.monotonic() - started

    assert health.status_code == 200
    assert not assessing.done(), "assessment should still be running"
    assert during < 0.5, "event loop was blocked"
    await assessing
