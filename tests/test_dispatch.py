"""Cascade decisions on a real session. Concurrency is in test_concurrent_accept_pg.py."""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from src.db.models import DispatchLog, Referral
from src.services.dispatch_orchestrator import (
    ACCEPTED_REPLY,
    CLAIMABLE,
    DispatchOrchestrator,
)
from tests.conftest import queued_sms

MOTOR_KING_1, MOTOR_KING_2, FALLBACK = 1, 2, 3


async def _open(db_session):
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="0123456789abcdef" * 4,
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


def test_claimable_statuses():
    assert {"PENDING", "TIER1_NOTIFIED", "TIER2_NOTIFIED"} == CLAIMABLE


@pytest.mark.asyncio
async def test_initiating_queues_an_offer_for_each_tier_one_driver(db_session, seeded_db):
    await _open(db_session)
    offers = await queued_sms(db_session, "driver_offer")
    assert [message.recipient for message in offers] == ["+233240000001", "+233240000002"]


@pytest.mark.asyncio
async def test_decline_waits_while_same_tier_drivers_remain(db_session, seeded_db):
    dispatch = await _open(db_session)

    reply = await DispatchOrchestrator().handle_decline(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()

    assert reply == "END Referral declined."
    assert dispatch.status == "TIER1_NOTIFIED"
    assert dispatch.current_tier == 1
    assert len(await queued_sms(db_session, "driver_offer")) == 2
    logs = await db_session.scalars(
        select(DispatchLog).where(DispatchLog.action == "decline_tier_remaining")
    )
    assert logs.first() is not None


@pytest.mark.asyncio
async def test_decline_escalates_in_the_same_transaction_once_tier_is_exhausted(
    db_session, seeded_db
):
    dispatch = await _open(db_session)
    orchestrator = DispatchOrchestrator()

    await orchestrator.handle_decline(db_session, dispatch.id, MOTOR_KING_1)
    await orchestrator.handle_decline(db_session, dispatch.id, MOTOR_KING_2)
    await db_session.commit()

    assert dispatch.status == "TIER2_NOTIFIED"
    assert dispatch.current_tier == 2
    assert dispatch.next_action == "tier_timeout"
    offers = await queued_sms(db_session, "driver_offer")
    assert offers[-1].recipient == "+233240000003"


@pytest.mark.asyncio
async def test_repeat_decline_changes_nothing(db_session, seeded_db):
    dispatch = await _open(db_session)
    orchestrator = DispatchOrchestrator()

    await orchestrator.handle_decline(db_session, dispatch.id, MOTOR_KING_1)
    reply = await orchestrator.handle_decline(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()

    assert reply == "END Decline noted."
    assert dispatch.declined_driver_ids == [MOTOR_KING_1]


@pytest.mark.asyncio
async def test_accept_writes_claim_ledger_and_hospital_sms_together(db_session, seeded_db):
    dispatch = await _open(db_session)

    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()

    assert reply == ACCEPTED_REPLY
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    assert dispatch.driver_id == MOTOR_KING_1
    assert dispatch.next_action is None
    logs = {log.action for log in await db_session.scalars(select(DispatchLog))}
    assert {"ussd_accept", "momo_escrow"} <= logs
    assert len(await queued_sms(db_session, "hospital_pre_arrival")) == 1


@pytest.mark.asyncio
async def test_rolled_back_accept_leaves_no_sms(db_session, seeded_db):
    dispatch = await _open(db_session)
    dispatch_id = dispatch.id

    await DispatchOrchestrator().handle_accept(db_session, dispatch_id, MOTOR_KING_1)
    await db_session.rollback()

    assert await queued_sms(db_session, "hospital_pre_arrival") == []


@pytest.mark.asyncio
async def test_repeat_accept_by_same_driver_is_idempotent(db_session, seeded_db):
    dispatch = await _open(db_session)
    orchestrator = DispatchOrchestrator()

    first = await orchestrator.handle_accept(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()
    second = await orchestrator.handle_accept(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()

    assert first == second == ACCEPTED_REPLY
    assert len(await queued_sms(db_session, "hospital_pre_arrival")) == 1


@pytest.mark.asyncio
async def test_second_driver_cannot_accept_claimed_dispatch(db_session, seeded_db):
    dispatch = await _open(db_session)
    orchestrator = DispatchOrchestrator()

    await orchestrator.handle_accept(db_session, dispatch.id, MOTOR_KING_1)
    await db_session.commit()
    reply = await orchestrator.handle_accept(db_session, dispatch.id, MOTOR_KING_2)
    await db_session.commit()

    assert reply == "END Already assigned."
    assert dispatch.driver_id == MOTOR_KING_1


@pytest.mark.asyncio
async def test_tier_two_driver_cannot_accept_while_tier_one_is_active(db_session, seeded_db):
    dispatch = await _open(db_session)

    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch.id, FALLBACK)

    assert reply == "END You are not eligible for this dispatch."
    assert dispatch.status == "TIER1_NOTIFIED"
    assert dispatch.driver_id is None
