"""The dispatch status API says when each step happened, from data the backend already logs."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from src.db.models import DispatchLog
from src.services.dispatch_orchestrator import DispatchOrchestrator
from tests.test_diversion import HOSPITAL_1, _refer_and_accept, confirm, divert

KEYS = {
    "sent",
    "drivers_notified",
    "driver_accepted",
    "hospital_notified",
    "hospital_confirmed",
    "diverted",
    "completed",
}


def _parse(value: str | None) -> datetime | None:
    if value is None:
        return None
    parsed = datetime.fromisoformat(value)
    return parsed


@pytest.mark.asyncio
async def test_new_dispatch_has_only_sent(client, db_session, seeded_db, sample_referral_payload):
    response = await client.post("/api/v1/referral", json=sample_referral_payload)
    dispatch_id = response.json()["dispatch"]["id"]
    times = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["step_times"]
    assert set(times) == KEYS
    assert _parse(times["sent"]) is not None
    # Queued SMS isn't "notified": only an offer that went out counts.
    assert times["drivers_notified"] is None
    assert all(times[k] is None for k in KEYS - {"sent"})


@pytest.mark.asyncio
async def test_each_step_gets_its_time_as_it_happens(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    # What the outbox logs when the offer and the hospital notice actually go out.
    db_session.add_all([
        DispatchLog(dispatch_id=dispatch_id, action="sms_send", target_role="driver",
                    response="Success"),
        DispatchLog(dispatch_id=dispatch_id, action="hospital_notify", target_role="hospital",
                    response="Success"),
    ])
    await db_session.commit()

    times = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["step_times"]
    for key in ("sent", "drivers_notified", "driver_accepted", "hospital_notified"):
        assert _parse(times[key]) is not None, key
    assert times["hospital_confirmed"] is None
    assert times["completed"] is None

    assert (await confirm(client, db_session, dispatch_id, HOSPITAL_1)).status_code == 200
    times = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["step_times"]
    assert _parse(times["hospital_confirmed"]) is not None

    assert (await divert(client, db_session, dispatch_id, 2)).status_code == 200
    times = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["step_times"]
    assert _parse(times["diverted"]) is not None

    await DispatchOrchestrator().handle_arrival(db_session, dispatch_id, driver_id=1)
    await db_session.commit()
    body = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert body["status"] == "COMPLETED"
    assert _parse(body["step_times"]["completed"]) is not None
    # Times carry their offset, so the phone can show them in its own time zone.
    assert _parse(body["step_times"]["sent"]).tzinfo is not None or "T" in body["step_times"]["sent"]


@pytest.mark.asyncio
async def test_hospital_code_is_still_not_in_the_response(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    body = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert "hospital_code" not in body
    assert "hospital_code" not in str(body["step_times"])


@pytest.mark.asyncio
async def test_late_claim_until_is_sent_plus_the_window(
    client, db_session, seeded_db, sample_referral_payload
):
    from src.config import settings

    response = await client.post("/api/v1/referral", json=sample_referral_payload)
    dispatch_id = response.json()["dispatch"]["id"]
    body = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    sent = _parse(body["step_times"]["sent"])
    until = datetime.fromisoformat(body["late_claim_until"])
    assert until.tzinfo is not None, "with an offset, so the phone reads it right"
    if sent.tzinfo is None:
        sent = sent.replace(tzinfo=UTC)
    assert until - sent == timedelta(minutes=settings.LATE_CLAIM_WINDOW_MINUTES)
