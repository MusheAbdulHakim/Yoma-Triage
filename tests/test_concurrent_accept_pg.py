"""Single-driver claim under real Postgres row locks (audit BUG-3)."""
from __future__ import annotations

import asyncio
import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from src.db.models import Dispatch, DispatchLog, Referral
from tests.postgres_support import (
    DRIVER_PHONES,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

pytestmark = pytest.mark.postgres

ROUNDS = 30


async def _open_dispatch(sessions) -> int:
    from src.services.dispatch_orchestrator import DispatchOrchestrator

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
        return dispatch.id, referral.id


async def _finish(sessions, dispatch_id: int, driver_id: int) -> None:
    """The winner arrives, so both drivers are AVAILABLE for the next round."""
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    async with sessions() as session:
        await DispatchOrchestrator().handle_arrival(session, dispatch_id, driver_id)
        await session.commit()


async def _dial_accept(client: AsyncClient, phone: str, ref: int) -> str:
    response = await client.post(
        "/ussd/callback",
        data={
            "sessionId": str(uuid.uuid4()),
            "serviceCode": "*384*1#",
            "phoneNumber": phone,
            "text": f"1*{ref}*1",
        },
    )
    assert response.status_code == 200, response.text
    return response.text


@pytest.mark.asyncio
async def test_parallel_accepts_have_exactly_one_winner(pg_sessions, monkeypatch):  # noqa: F811
    from main import app

    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for round_number in range(ROUNDS):
            dispatch_id, ref = await _open_dispatch(pg_sessions)

            replies = await asyncio.gather(
                *(_dial_accept(client, phone, ref) for phone in DRIVER_PHONES.values())
            )

            winners = [
                driver_id
                for driver_id, reply in zip(DRIVER_PHONES, replies, strict=True)
                if "Accepted" in reply
            ]
            context = f"round {round_number}: replies={replies}"
            assert len(winners) == 1, context
            async with pg_sessions() as session:
                dispatch = await session.get(Dispatch, dispatch_id)
                accept_logs = (
                    await session.scalars(
                        select(DispatchLog).where(
                            DispatchLog.dispatch_id == dispatch_id,
                            DispatchLog.action == "ussd_accept",
                        )
                    )
                ).all()
            assert dispatch.driver_id == winners[0], context
            assert len(accept_logs) == 1, context
            await _finish(pg_sessions, dispatch_id, winners[0])
