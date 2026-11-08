"""USSD retries are safe, and nothing is sent inside the request."""
from __future__ import annotations

import uuid

import pytest

from src.api.ussd import process_ussd
from src.db.models import Referral
from src.services.dispatch_orchestrator import (
    ACCEPTED_REPLY,
    ON_TRIP_REPLY,
    DispatchOrchestrator,
)
from tests.conftest import queued_sms
from tests.ussd_paths import CONFIRM_ARRIVAL, accept, decline

DRIVER_1 = "+233240000001"
DRIVER_2 = "+233240000002"


async def _open(db_session):
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="abcdef0123456789" * 4,
        emergency_type="pph",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id=str(uuid.uuid4()),
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await DispatchOrchestrator().initiate_dispatch(db_session, referral.id)
    await db_session.commit()
    return dispatch


@pytest.mark.asyncio
async def test_double_accept_returns_the_same_terminal_response(db_session, seeded_db):
    dispatch = await _open(db_session)

    first = await process_ussd(db_session, DRIVER_1, accept(dispatch.referral_id))
    second = await process_ussd(db_session, DRIVER_1, accept(dispatch.referral_id))

    assert first.body == ACCEPTED_REPLY.encode()
    assert second.body == first.body
    assert len(await queued_sms(db_session, "hospital_pre_arrival")) == 1


@pytest.mark.asyncio
async def test_double_arrival_returns_the_same_terminal_response(db_session, seeded_db):
    dispatch = await _open(db_session)
    await process_ussd(db_session, DRIVER_1, accept(dispatch.referral_id))

    first = await process_ussd(db_session, DRIVER_1, CONFIRM_ARRIVAL)
    second = await process_ussd(db_session, DRIVER_1, CONFIRM_ARRIVAL)

    assert first.body == b"END Arrival confirmed. Referral complete."
    assert second.body == first.body
    assert len(await queued_sms(db_session, "cho_arrival")) == 1


@pytest.mark.asyncio
async def test_ussd_makes_no_provider_calls(db_session, seeded_db, monkeypatch):
    """Accept and decline answer from the database alone."""

    async def fail(*args, **kwargs):
        raise AssertionError("USSD must not call the SMS provider")

    monkeypatch.setattr("src.services.messaging_gateway.MessagingGateway.send_sms", fail)
    dispatch = await _open(db_session)

    declined = await process_ussd(db_session, DRIVER_1, decline(dispatch.referral_id))
    accepted = await process_ussd(db_session, DRIVER_2, accept(dispatch.referral_id))

    assert declined.body == b"END Referral declined."
    assert accepted.body == ACCEPTED_REPLY.encode()


@pytest.mark.asyncio
async def test_decline_after_accept_has_no_effect(db_session, seeded_db):
    dispatch = await _open(db_session)

    await process_ussd(db_session, DRIVER_1, accept(dispatch.referral_id))
    declined = await process_ussd(db_session, DRIVER_1, decline(dispatch.referral_id))

    # It's this driver's trip now, not an open referral, so there's nothing to decline.
    assert declined.body == ON_TRIP_REPLY.encode()
    await db_session.refresh(dispatch)
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    assert dispatch.driver_id == 1


@pytest.mark.asyncio
async def test_driver_on_a_trip_cannot_claim_another_dispatch(db_session, seeded_db):
    """BUG-9: this used to hand the second referral to a driver already carrying a patient."""
    first = await _open(db_session)
    await process_ussd(db_session, DRIVER_1, accept(first.referral_id))
    second = await _open(db_session)
    second.initiated_at = first.initiated_at
    await db_session.commit()

    reply = await process_ussd(db_session, DRIVER_1, accept(second.referral_id))

    assert reply.body == ON_TRIP_REPLY.encode()
    await db_session.refresh(second)
    assert second.driver_id is None
    assert second.status == "TIER1_NOTIFIED"
    # Arrival is for the trip the driver has, not the newest referral.
    await process_ussd(db_session, DRIVER_1, CONFIRM_ARRIVAL)
    await db_session.refresh(first)
    await db_session.refresh(second)
    assert (first.status, second.status) == ("COMPLETED", "TIER1_NOTIFIED")
