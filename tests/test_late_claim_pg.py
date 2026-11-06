"""Notified drivers stay eligible until someone claims the dispatch (audit BUG-4)."""
from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update

from src.db.models import Dispatch, DispatchLog, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator
from tests.postgres_support import (
    CHO_PHONE,
    DRIVER_PHONES,
    FALLBACK_DRIVER_PHONE,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

pytestmark = pytest.mark.postgres

MOTOR_KING = DRIVER_PHONES[1]


@pytest.fixture
def no_wait(monkeypatch):
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")


async def _open(sessions) -> int:
    async with sessions() as session:
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            patient_hash="0" * 64,
            emergency_type="pph",
            severity="RED",
            risk_level="RED",
            status="CONFIRMED",
            client_request_id=str(uuid.uuid4()),
        )
        session.add(referral)
        await session.flush()
        dispatch = await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()
        return dispatch.id


async def _escalate(sessions, dispatch_id: int) -> None:
    async with sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(next_action_at=datetime.now(UTC) - timedelta(seconds=1))
        )
        await session.commit()
    await DispatchOrchestrator().process_due_dispatches()


async def _dial(phone: str, text: str = "1") -> str:
    from main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/ussd/callback",
            data={
                "sessionId": str(uuid.uuid4()),
                "serviceCode": "*384*1#",
                "phoneNumber": phone,
                "text": text,
            },
        )
    assert response.status_code == 200, response.text
    return response.text


async def _dispatch(sessions, dispatch_id: int) -> Dispatch:
    async with sessions() as session:
        return await session.get(Dispatch, dispatch_id)


async def _actions(sessions, dispatch_id: int) -> list[DispatchLog]:
    async with sessions() as session:
        return list(
            await session.scalars(
                select(DispatchLog).where(DispatchLog.dispatch_id == dispatch_id)
            )
        )


@pytest.mark.asyncio
async def test_tier_one_driver_can_accept_after_escalation(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    assert (await _dispatch(pg_sessions, dispatch_id)).current_tier == 2

    assert "Accepted" in await _dial(MOTOR_KING)

    assert (await _dispatch(pg_sessions, dispatch_id)).driver_id == 1
    actions = [log.action for log in await _actions(pg_sessions, dispatch_id)]
    assert "cho_late_accept_notify" not in actions


@pytest.mark.asyncio
async def test_driver_claims_after_failed_and_cho_is_told(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)
    assert (await _dispatch(pg_sessions, dispatch_id)).status == "FAILED"

    assert "Accepted" in await _dial(MOTOR_KING)

    dispatch = await _dispatch(pg_sessions, dispatch_id)
    assert dispatch.driver_id == 1
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    logs = await _actions(pg_sessions, dispatch_id)
    late = [log for log in logs if log.action == "cho_late_accept_notify"]
    assert len(late) == 1
    assert late[0].target_phone == CHO_PHONE
    assert "accepted LATE" in late[0].metadata_json["message"]
    assert "hospital_notify" in {log.action for log in logs}


@pytest.mark.asyncio
async def test_second_late_claim_loses(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)

    assert "Accepted" in await _dial(MOTOR_KING)
    assert "Accepted" not in await _dial(FALLBACK_DRIVER_PHONE)

    assert (await _dispatch(pg_sessions, dispatch_id)).driver_id == 1


@pytest.mark.asyncio
async def test_driver_never_offered_the_dispatch_stays_refused(pg_sessions, no_wait):  # noqa: F811
    await _open(pg_sessions)
    reply = await _dial(FALLBACK_DRIVER_PHONE)
    assert "not eligible" in reply


@pytest.mark.asyncio
async def test_failed_dispatch_past_the_window_cannot_be_claimed(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)
    async with pg_sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(initiated_at=datetime.now(UTC) - timedelta(minutes=46))
        )
        await session.commit()

    assert "Accepted" not in await _dial(MOTOR_KING)

    dispatch = await _dispatch(pg_sessions, dispatch_id)
    assert dispatch.status == "FAILED"
    assert dispatch.driver_id is None


@pytest.mark.asyncio
async def test_decline_after_failed_does_not_restart_the_cascade(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)

    assert "No active dispatch" in await _dial(MOTOR_KING, "2")

    assert (await _dispatch(pg_sessions, dispatch_id)).status == "FAILED"


@pytest.mark.asyncio
async def test_driver_who_declined_can_still_claim_while_unclaimed(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    assert "declined" in await _dial(MOTOR_KING, "2")

    assert "Accepted" in await _dial(MOTOR_KING)

    assert (await _dispatch(pg_sessions, dispatch_id)).driver_id == 1


@pytest.mark.asyncio
async def test_failed_dispatch_inside_the_window_can_be_claimed(pg_sessions, no_wait):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)
    async with pg_sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(initiated_at=datetime.now(UTC) - timedelta(minutes=44))
        )
        await session.commit()

    assert "Accepted" in await _dial(MOTOR_KING)


@pytest.mark.asyncio
async def test_late_claim_window_is_configurable(pg_sessions, no_wait, monkeypatch):  # noqa: F811
    monkeypatch.setattr("src.config.settings.LATE_CLAIM_WINDOW_MINUTES", 120)
    dispatch_id = await _open(pg_sessions)
    await _escalate(pg_sessions, dispatch_id)
    await _escalate(pg_sessions, dispatch_id)
    async with pg_sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(initiated_at=datetime.now(UTC) - timedelta(minutes=46))
        )
        await session.commit()

    assert "Accepted" in await _dial(MOTOR_KING)
