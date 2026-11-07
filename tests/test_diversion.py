"""BUG-5: a diversion changes the destination; the trip carries on and can finish."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import Dispatch, DispatchLog, Referral
from src.services.dispatch_orchestrator import ARRIVAL_ELIGIBLE, DispatchOrchestrator
from tests.conftest import SEEDED_CHO_PHONE, queued_sms

HOSPITAL_1 = "+233240000200"
HOSPITAL_2 = "+233240000201"
DRIVER_1 = "+233240000001"


async def _refer_and_accept(client, db_session, payload) -> int:
    response = await client.post("/api/v1/referral", json=payload)
    assert response.status_code == 201, response.text
    dispatch_id = response.json()["dispatch"]["id"]
    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch_id, driver_id=1)
    await db_session.commit()
    assert "Accepted" in reply
    return dispatch_id


async def divert(client, db_session, dispatch_id: int, facility_id: int, sender=HOSPITAL_1):
    """The hospital's DIVERT reply, in the form its notice asks for."""
    from tests.hospital_replies import divert_text

    text = await divert_text(db_session, dispatch_id, facility_id)
    return await client.post("/api/v1/sms/inbound", json={"from": sender, "text": text})


async def confirm(client, db_session, dispatch_id: int, sender: str):
    from tests.hospital_replies import confirm_text

    text = await confirm_text(db_session, dispatch_id)
    return await client.post("/api/v1/sms/inbound", json={"from": sender, "text": text})


@pytest.mark.asyncio
async def test_divert_then_arrival_at_the_new_facility_completes(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)

    response = await divert(client, db_session, dispatch_id, 2)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "DIVERTED"

    dispatch = await db_session.get(Dispatch, dispatch_id)
    await db_session.refresh(dispatch)
    referral = await db_session.get(Referral, dispatch.referral_id)
    assert dispatch.facility_id == 2 and referral.facility_id == 2
    # Not a terminal status: the trip is still going, now to the new facility.
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    assert dispatch.status in ARRIVAL_ELIGIBLE

    reply = await DispatchOrchestrator().handle_arrival(db_session, dispatch_id, driver_id=1)
    await db_session.commit()
    assert "Arrival confirmed" in reply
    await db_session.refresh(dispatch)
    assert dispatch.status == "COMPLETED"
    assert dispatch.completed_at is not None


@pytest.mark.asyncio
async def test_divert_tells_each_party_what_they_need(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    before = {m.id for m in await queued_sms(db_session)}

    response = await divert(client, db_session, dispatch_id, 2)
    assert response.status_code == 200, response.text

    sent = [m for m in await queued_sms(db_session) if m.id not in before]
    by_purpose = {(m.purpose, m.recipient) for m in sent}
    assert by_purpose == {
        ("hospital_pre_arrival", HOSPITAL_2),
        ("divert_old_hospital", HOSPITAL_1),
        ("divert_driver", DRIVER_1),
        ("divert_cho", SEEDED_CHO_PHONE),
    }
    assert len(sent) == 4
    notice = next(m for m in sent if m.purpose == "hospital_pre_arrival")
    assert "DIVERTED here from Tamale Teaching Hospital" in notice.body
    assert "EMERGENCY REFERRAL" in notice.body
    old = next(m for m in sent if m.purpose == "divert_old_hospital")
    assert "Navrongo War Memorial Hospital" in old.body
    assert "Do not expect this patient" in old.body
    for purpose in ("divert_driver", "divert_cho"):
        body = next(m.body for m in sent if m.purpose == purpose)
        assert "Navrongo War Memorial Hospital" in body


@pytest.mark.asyncio
async def test_new_facility_can_confirm_after_a_diversion(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    assert (await divert(client, db_session, dispatch_id, 2)).status_code == 200

    response = await confirm(client, db_session, dispatch_id, HOSPITAL_2)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "CONFIRMED"
    dispatch = await db_session.get(Dispatch, dispatch_id)
    await db_session.refresh(dispatch)
    assert dispatch.status == "HOSPITAL_CONFIRMED"


@pytest.mark.asyncio
async def test_a_confirmed_dispatch_can_still_be_diverted(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    assert (await confirm(client, db_session, dispatch_id, HOSPITAL_1)).status_code == 200

    response = await divert(client, db_session, dispatch_id, 2)
    assert response.status_code == 200, response.text
    dispatch = await db_session.get(Dispatch, dispatch_id)
    await db_session.refresh(dispatch)
    assert (dispatch.status, dispatch.facility_id) == ("HOSPITAL_NOTIFIED", 2)


@pytest.mark.asyncio
async def test_an_unsent_notice_to_the_old_facility_is_dropped(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    assert (await divert(client, db_session, dispatch_id, 2)).status_code == 200

    notices = await queued_sms(db_session, "hospital_pre_arrival")
    old = [m for m in notices if m.recipient == HOSPITAL_1]
    assert [m.status for m in old] == ["CANCELLED"]
    new = [m for m in notices if m.recipient == HOSPITAL_2]
    assert [m.status for m in new] == ["PENDING"]


@pytest.mark.asyncio
async def test_divert_to_the_current_destination_changes_nothing(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    before = len(await queued_sms(db_session))

    response = await divert(client, db_session, dispatch_id, 1)
    assert response.json()["status"] == "DIVERT_REJECTED"
    dispatch = await db_session.get(Dispatch, dispatch_id)
    await db_session.refresh(dispatch)
    assert (dispatch.status, dispatch.facility_id) == ("HOSPITAL_NOTIFIED", 1)
    logs = await db_session.scalars(
        select(DispatchLog).where(DispatchLog.action == "hospital_divert")
    )
    assert list(logs) == []
    # Only the reply explaining why; no notices to anyone else.
    new = (await queued_sms(db_session))[before:]
    assert [(m.recipient, m.purpose) for m in new] == [(HOSPITAL_1, "inbound_reply")]
    assert "already going to Tamale Teaching Hospital" in new[0].body


@pytest.mark.asyncio
async def test_dispatch_api_shows_the_new_destination(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    before = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert before["facility_name"] == "Tamale Teaching Hospital"
    assert before["diverted_from"] is None

    assert (await divert(client, db_session, dispatch_id, 2)).status_code == 200

    after = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert after["status"] == "HOSPITAL_NOTIFIED"
    assert after["facility_id"] == 2
    assert after["facility_name"] == "Navrongo War Memorial Hospital"
    assert after["diverted_from"] == "Tamale Teaching Hospital"
    assert after["eta_minutes"] is not None


@pytest.mark.asyncio
async def test_a_dispatch_left_diverted_by_an_older_version_can_still_finish(
    db_session, seeded_db
):
    referral = Referral(
        chps_compound_id=1,
        facility_id=2,
        patient_hash="0" * 64,
        emergency_type="pph",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id, facility_id=2, driver_id=1, status="DIVERTED", current_tier=1
    )
    db_session.add(dispatch)
    await db_session.flush()

    reply = await DispatchOrchestrator().handle_arrival(db_session, dispatch.id, driver_id=1)
    assert "Arrival confirmed" in reply
    assert dispatch.status == "COMPLETED"
