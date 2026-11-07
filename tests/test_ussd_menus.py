"""BUG-9: the USSD menu says which referral it's about, lets a driver with several offers
pick one, confirms arrival for the driver's own trip, and lets a driver set availability."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from src.api.ussd import process_ussd
from src.db.models import AuditLog, Dispatch, Driver, Referral
from src.services.dispatch_orchestrator import ON_TRIP_REPLY, DispatchOrchestrator
from tests.conftest import queued_sms
from tests.ussd_paths import (
    ARRIVAL,
    AVAILABILITY,
    CONFIRM_ARRIVAL,
    OFFERS,
    ROOT,
    SET_AVAILABLE,
    SET_OFF_DUTY,
    accept,
    decline,
    offer,
)

DRIVER_1 = "+233240000001"
DRIVER_2 = "+233240000002"
FALLBACK = "+233240000003"


async def _open(db_session, emergency: str = "pph", minutes_ago: int = 0) -> Dispatch:
    referral = Referral(
        chps_compound_id=1, facility_id=1, cho_id=1, patient_hash="a" * 64,
        emergency_type=emergency, status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await DispatchOrchestrator().initiate_dispatch(db_session, referral.id)
    await db_session.flush()
    await db_session.refresh(dispatch)
    if minutes_ago:
        dispatch.initiated_at = datetime.now(UTC) - timedelta(minutes=minutes_ago)
    await db_session.commit()
    return dispatch


async def _say(db_session, phone: str, text: str) -> str:
    return (await process_ussd(db_session, phone, text)).body.decode()


@pytest.mark.asyncio
async def test_root_menu(db_session, seeded_db):
    await _open(db_session)
    assert await _say(db_session, DRIVER_1, ROOT) == (
        "CON Yoma Triage (AVAILABLE)\n"
        "1. Open referrals (1)\n"
        "2. Confirm arrival\n"
        "3. Availability"
    )


@pytest.mark.asyncio
async def test_root_menu_names_the_trip(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _say(db_session, DRIVER_1, accept(dispatch.referral_id))
    assert (await _say(db_session, DRIVER_1, ROOT)).startswith(
        f"CON Yoma Triage (ON TRIP: Ref {dispatch.referral_id})\n1. Open referrals (0)"
    )


@pytest.mark.asyncio
async def test_root_menu_counts_no_offers_during_a_trip(db_session, seeded_db):
    """A referral offered to the driver before they took a trip isn't listed during it."""
    first = await _open(db_session)
    await _open(db_session)  # offered to driver 1 as well
    await _say(db_session, DRIVER_1, accept(first.referral_id))

    root = await _say(db_session, DRIVER_1, ROOT)

    assert "1. Open referrals (0)" in root
    assert "1. Open referrals (1)" in await _say(db_session, DRIVER_2, ROOT)


@pytest.mark.asyncio
async def test_unknown_phone(db_session, seeded_db):
    assert await _say(db_session, "+233599999999", ROOT) == "END Unknown driver."


@pytest.mark.asyncio
async def test_the_offer_says_what_where_and_how_long_ago(db_session, seeded_db):
    dispatch = await _open(db_session, minutes_ago=7)
    ref = dispatch.referral_id

    assert await _say(db_session, DRIVER_1, OFFERS) == (
        f"CON Reply with the Ref no.\nRef {ref}: PPH bleeding, 7 min ago"
    )
    assert await _say(db_session, DRIVER_1, offer(ref)) == (
        f"CON Ref {ref}: PPH bleeding\n"
        "From Tamale South CHPS\n"
        "To Tamale Teaching Hospital\n"
        "Sent 7 min ago\n"
        "1. Accept\n"
        "2. Decline"
    )


@pytest.mark.asyncio
async def test_with_several_offers_the_driver_picks_one(db_session, seeded_db):
    older = await _open(db_session, "eclampsia", minutes_ago=9)
    newer = await _open(db_session, "pph", minutes_ago=2)

    listing = await _say(db_session, DRIVER_1, OFFERS)
    assert listing == (
        "CON Reply with the Ref no.\n"
        f"Ref {older.referral_id}: Eclampsia, 9 min ago\n"
        f"Ref {newer.referral_id}: PPH bleeding, 2 min ago"
    )

    reply = await _say(db_session, DRIVER_1, accept(older.referral_id))

    assert "Accepted" in reply
    await db_session.refresh(older)
    await db_session.refresh(newer)
    assert (older.driver_id, newer.driver_id) == (1, None)


@pytest.mark.asyncio
async def test_decline_one_of_several(db_session, seeded_db):
    older = await _open(db_session, minutes_ago=9)
    newer = await _open(db_session, minutes_ago=2)

    assert await _say(db_session, DRIVER_1, decline(newer.referral_id)) == "END Referral declined."

    await db_session.refresh(older)
    await db_session.refresh(newer)
    assert older.declined_driver_ids == [] and newer.declined_driver_ids == [1]


@pytest.mark.asyncio
async def test_a_referral_that_is_not_open_for_this_driver(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _say(db_session, DRIVER_2, accept(dispatch.referral_id))

    reply = await _say(db_session, DRIVER_1, accept(dispatch.referral_id))

    assert reply == (
        f"END Ref {dispatch.referral_id} is not open for you. Dial again to see open referrals."
    )
    await db_session.refresh(dispatch)
    assert dispatch.driver_id == 2


@pytest.mark.asyncio
async def test_a_driver_not_offered_it_does_not_see_it(db_session, seeded_db):
    """The fallback driver is tier 2; tier 1 hasn't timed out."""
    await _open(db_session)
    assert await _say(db_session, FALLBACK, OFFERS) == "END No open referrals for you."


@pytest.mark.asyncio
async def test_offers_while_on_a_trip(db_session, seeded_db):
    first = await _open(db_session)
    await _open(db_session)
    await _say(db_session, DRIVER_1, accept(first.referral_id))
    assert await _say(db_session, DRIVER_1, OFFERS) == ON_TRIP_REPLY


@pytest.mark.asyncio
async def test_arrival_menu_shows_the_trip_and_confirms_it(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _say(db_session, DRIVER_1, accept(dispatch.referral_id))

    screen = await _say(db_session, DRIVER_1, ARRIVAL)
    assert screen == (
        "CON Confirm arrival?\n"
        f"Ref {dispatch.referral_id}: PPH bleeding\n"
        "From Tamale South CHPS\n"
        "To Tamale Teaching Hospital\n"
        "Accepted just now\n"
        "1. Yes, patient arrived"
    )
    assert await _say(db_session, DRIVER_1, CONFIRM_ARRIVAL) == (
        "END Arrival confirmed. Referral complete."
    )
    await db_session.refresh(dispatch)
    assert dispatch.status == "COMPLETED"


@pytest.mark.asyncio
async def test_arrival_menu_shows_a_diverted_destination(client, db_session, seeded_db):
    from tests.hospital_replies import divert_text

    dispatch = await _open(db_session)
    await _say(db_session, DRIVER_1, accept(dispatch.referral_id))
    text = await divert_text(db_session, dispatch.id, 2)
    await client.post("/api/v1/sms/inbound", json={"from": "+233240000200", "text": text})

    assert "To Navrongo War Memorial Hospital" in await _say(db_session, DRIVER_1, ARRIVAL)


@pytest.mark.asyncio
async def test_arrival_with_no_trip(db_session, seeded_db):
    await _open(db_session)
    assert await _say(db_session, DRIVER_1, ARRIVAL) == "END You have no trip to confirm."
    assert await _say(db_session, DRIVER_1, CONFIRM_ARRIVAL) == "END You have no trip to confirm."


@pytest.mark.asyncio
async def test_two_open_trips_from_before_on_trip_existed(db_session, seeded_db):
    """Trips from before batch 6 can leave a driver with two. Each is picked by Ref."""
    first = await _open(db_session)
    second = await _open(db_session)
    for dispatch in (first, second):
        dispatch.driver_id, dispatch.status = 1, "HOSPITAL_NOTIFIED"
    await db_session.commit()

    listing = await _say(db_session, DRIVER_1, ARRIVAL)
    assert listing.startswith("CON Which trip? Reply with the Ref no.")
    assert f"Ref {first.referral_id}" in listing and f"Ref {second.referral_id}" in listing

    pick = f"2*{first.referral_id}"
    assert (await _say(db_session, DRIVER_1, pick)).startswith("CON Confirm arrival?")
    assert "Arrival confirmed" in await _say(db_session, DRIVER_1, f"{pick}*1")
    await db_session.refresh(first)
    await db_session.refresh(second)
    assert (first.status, second.status) == ("COMPLETED", "HOSPITAL_NOTIFIED")


# --- Availability -----------------------------------------------------------------------


async def _driver_audit(db_session) -> list[tuple]:
    rows = await db_session.scalars(
        select(AuditLog).where(AuditLog.entity_type == "driver").order_by(AuditLog.id)
    )
    return [(r.actor_id, r.metadata_json["to"]) for r in rows]


@pytest.mark.asyncio
async def test_driver_sets_off_duty_and_back(db_session, seeded_db):
    assert await _say(db_session, DRIVER_1, AVAILABILITY) == (
        "CON You are AVAILABLE.\n1. Available\n2. Off duty"
    )
    assert await _say(db_session, DRIVER_1, SET_OFF_DUTY) == (
        "END You are now OFF DUTY. You will not get referral SMS."
    )
    driver = await db_session.get(Driver, 1)
    assert driver.availability == "OFF_DUTY"
    assert (await _say(db_session, DRIVER_1, AVAILABILITY)).startswith("CON You are OFF DUTY.")

    assert await _say(db_session, DRIVER_1, SET_AVAILABLE) == (
        "END You are now AVAILABLE for referrals."
    )
    assert driver.availability == "AVAILABLE"
    assert await _driver_audit(db_session) == [("driver", "OFF_DUTY"), ("driver", "AVAILABLE")]


@pytest.mark.asyncio
async def test_an_off_duty_driver_is_not_offered_referrals(db_session, seeded_db):
    await _say(db_session, DRIVER_1, SET_OFF_DUTY)
    dispatch = await _open(db_session)
    offers = [m.recipient for m in await queued_sms(db_session, "driver_offer")]
    assert offers == [DRIVER_2]
    assert dispatch.status == "TIER1_NOTIFIED"


@pytest.mark.asyncio
async def test_availability_cannot_change_during_a_trip(db_session, seeded_db):
    dispatch = await _open(db_session)
    await _say(db_session, DRIVER_1, accept(dispatch.referral_id))

    for text in (AVAILABILITY, SET_OFF_DUTY, SET_AVAILABLE):
        assert (await _say(db_session, DRIVER_1, text)).startswith("END You are on a trip.")
    driver = await db_session.get(Driver, 1)
    assert driver.availability == "ON_TRIP"


@pytest.mark.asyncio
@pytest.mark.parametrize("text", ["3*3", "3*1*1", "4", "2*2", "1*x"])
async def test_invalid_choices(db_session, seeded_db, text):
    await _open(db_session)
    assert (await _say(db_session, DRIVER_1, text)).startswith("END ")
    driver = await db_session.get(Driver, 1)
    assert driver.availability == "AVAILABLE"
