"""BUG-9: a driver is ON_TRIP from accepting until the trip ends, and isn't offered more."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import AuditLog, Dispatch, Driver, OutboundMessage, Referral
from src.services.dispatch_orchestrator import ON_TRIP_REPLY, DispatchOrchestrator
from src.services.outbox import OutboxSender
from tests.conftest import queued_sms

DRIVER_1 = "+233240000001"


async def _open(db_session, patient_hash: str = "a" * 64) -> Dispatch:
    referral = Referral(
        chps_compound_id=1, facility_id=1, cho_id=1, patient_hash=patient_hash,
        emergency_type="pph", status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await DispatchOrchestrator().initiate_dispatch(db_session, referral.id)
    await db_session.commit()
    return dispatch


async def _availability(db_session, driver_id: int = 1) -> str:
    driver = await db_session.get(Driver, driver_id)
    await db_session.refresh(driver)
    return driver.availability


async def _audit(db_session) -> list[tuple]:
    rows = await db_session.scalars(
        select(AuditLog).where(AuditLog.entity_type == "driver").order_by(AuditLog.id)
    )
    return [
        (r.entity_id, r.actor_id, r.metadata_json["from"], r.metadata_json["to"]) for r in rows
    ]


async def _accept(db_session, dispatch: Dispatch, driver_id: int = 1) -> str:
    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch.id, driver_id)
    await db_session.commit()
    return reply


@pytest.mark.asyncio
async def test_accept_puts_the_driver_on_a_trip_and_arrival_ends_it(db_session, seeded_db):
    dispatch = await _open(db_session)

    assert "Accepted" in await _accept(db_session, dispatch)
    assert await _availability(db_session) == "ON_TRIP"

    await DispatchOrchestrator().handle_arrival(db_session, dispatch.id, 1)
    await db_session.commit()
    assert await _availability(db_session) == "AVAILABLE"
    assert await _audit(db_session) == [
        ("1", "dispatch", "AVAILABLE", "ON_TRIP"),
        ("1", "dispatch", "ON_TRIP", "AVAILABLE"),
    ]
    rows = list(await db_session.scalars(select(AuditLog).where(AuditLog.entity_type == "driver")))
    assert {r.metadata_json["dispatch_id"] for r in rows} == {dispatch.id}


@pytest.mark.asyncio
async def test_cancelling_the_trip_frees_the_driver(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _accept(db_session, dispatch)

    await DispatchOrchestrator().cancel_dispatch(db_session, dispatch.id, cho_id=1)
    await db_session.commit()

    assert await _availability(db_session) == "AVAILABLE"


@pytest.mark.asyncio
async def test_a_driver_who_went_off_duty_mid_trip_stays_off_duty(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _accept(db_session, dispatch)
    driver = await db_session.get(Driver, 1)
    driver.availability = "OFF_DUTY"
    await db_session.commit()

    await DispatchOrchestrator().handle_arrival(db_session, dispatch.id, 1)
    await db_session.commit()

    assert await _availability(db_session) == "OFF_DUTY"


@pytest.mark.asyncio
async def test_a_driver_on_a_trip_is_not_offered_the_next_referral(db_session, seeded_db):
    first = await _open(db_session)
    await _accept(db_session, first)

    second = await _open(db_session, "b" * 64)

    offers = [
        m.recipient
        for m in await queued_sms(db_session, "driver_offer")
        if m.dispatch_id == second.id
    ]
    assert offers == ["+233240000002"]


@pytest.mark.asyncio
async def test_a_driver_on_a_trip_cannot_accept_an_offer_they_already_had(db_session, seeded_db):
    first = await _open(db_session)
    second = await _open(db_session, "b" * 64)  # offered to driver 1 too
    await _accept(db_session, first)

    assert await _accept(db_session, second) == ON_TRIP_REPLY
    await db_session.refresh(second)
    assert (second.driver_id, second.status) == (None, "TIER1_NOTIFIED")
    # Driver 2 can still take it.
    assert "Accepted" in await _accept(db_session, second, driver_id=2)


@pytest.mark.asyncio
async def test_an_offer_waiting_to_send_is_dropped_once_the_driver_is_on_a_trip(
    db_session, seeded_db
):
    first = await _open(db_session)
    second = await _open(db_session, "b" * 64)
    await _accept(db_session, first)
    waiting = await db_session.scalar(
        select(OutboundMessage).where(
            OutboundMessage.dispatch_id == second.id, OutboundMessage.recipient == DRIVER_1
        )
    )
    to_driver_2 = await db_session.scalar(
        select(OutboundMessage).where(
            OutboundMessage.dispatch_id == second.id,
            OutboundMessage.recipient == "+233240000002",
        )
    )

    assert await OutboxSender._offer_is_stale(db_session, waiting)
    assert not await OutboxSender._offer_is_stale(db_session, to_driver_2)


@pytest.mark.asyncio
async def test_an_offer_never_sent_does_not_make_a_driver_eligible(db_session, seeded_db):
    """A dropped offer isn't a notification: the driver never heard about the referral."""
    dispatch = await _open(db_session)
    message = await db_session.scalar(
        select(OutboundMessage).where(
            OutboundMessage.dispatch_id == dispatch.id, OutboundMessage.recipient == DRIVER_1
        )
    )
    message.status = "CANCELLED"
    await db_session.commit()

    assert not await DispatchOrchestrator()._was_notified(db_session, dispatch.id, 1)
    message.status = "SENT"
    await db_session.commit()
    assert await DispatchOrchestrator()._was_notified(db_session, dispatch.id, 1)


@pytest.mark.asyncio
async def test_rest_availability_change_is_audited(client, db_session, seeded_db):
    response = await client.post("/api/v1/driver/1/availability", json={"availability": "OFF_DUTY"})
    assert response.status_code == 200
    assert await _audit(db_session) == [("1", "api", "AVAILABLE", "OFF_DUTY")]
