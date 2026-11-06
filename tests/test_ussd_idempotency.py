"""USSD retries are safe, and nothing is sent inside the request."""
from __future__ import annotations

import uuid

import pytest

from src.api.ussd import process_ussd
from src.db.models import Referral
from src.services.dispatch_orchestrator import ACCEPTED_REPLY, DispatchOrchestrator
from tests.conftest import queued_sms


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
    await _open(db_session)

    first = await process_ussd(db_session, "+233240000001", "1")
    second = await process_ussd(db_session, "+233240000001", "1")

    assert first.body == ACCEPTED_REPLY.encode()
    assert second.body == first.body
    assert len(await queued_sms(db_session, "hospital_pre_arrival")) == 1


@pytest.mark.asyncio
async def test_ussd_makes_no_provider_calls(db_session, seeded_db, monkeypatch):
    """Accept and decline answer from the database alone."""

    async def fail(*args, **kwargs):
        raise AssertionError("USSD must not call the SMS provider")

    monkeypatch.setattr("src.services.messaging_gateway.MessagingGateway.send_sms", fail)
    await _open(db_session)

    decline = await process_ussd(db_session, "+233240000001", "2")
    accept = await process_ussd(db_session, "+233240000002", "1")

    assert decline.body == b"END Referral declined."
    assert accept.body == ACCEPTED_REPLY.encode()


@pytest.mark.asyncio
async def test_decline_after_accept_has_no_effect(db_session, seeded_db):
    dispatch = await _open(db_session)

    await process_ussd(db_session, "+233240000001", "1")
    decline = await process_ussd(db_session, "+233240000001", "2")

    assert decline.body == b"END Decline noted."
    await db_session.refresh(dispatch)
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    assert dispatch.driver_id == 1


@pytest.mark.asyncio
async def test_driver_on_a_trip_claims_the_newest_dispatch_even_on_a_timestamp_tie(
    db_session, seeded_db
):
    first = await _open(db_session)
    await process_ussd(db_session, "+233240000001", "1")
    second = await _open(db_session)
    second.initiated_at = first.initiated_at
    await db_session.commit()

    await process_ussd(db_session, "+233240000001", "1")

    await db_session.refresh(second)
    assert second.driver_id == 1
    assert second.status == "HOSPITAL_NOTIFIED"
