"""Single-driver claim under real Postgres row locks (audit BUG-3)."""
from __future__ import annotations

import asyncio
import uuid

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.db.database import Base, get_db
from src.db.models import CHPSCompound, Dispatch, DispatchLog, Driver, Facility, Referral
from tests.postgres_support import postgres_url  # noqa: F401 - pytest fixture

pytestmark = pytest.mark.postgres

ROUNDS = 30
DRIVER_PHONES = {1: "+233240000001", 2: "+233240000002"}


@pytest_asyncio.fixture
async def pg_sessions(postgres_url, monkeypatch):  # noqa: F811
    """Session factory bound to a throwaway schema, wired into the app."""
    from main import app
    from src.services import dispatch_orchestrator

    schema = f"yoma_test_{uuid.uuid4().hex}"
    engine = create_async_engine(
        postgres_url,
        poolclass=NullPool,
        connect_args={"server_settings": {"search_path": schema}},
    )
    async with engine.begin() as conn:
        await conn.execute(text(f'CREATE SCHEMA "{schema}"'))
        await conn.run_sync(Base.metadata.create_all)

    sessions = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with sessions() as session:
        session.add(CHPSCompound(id=1, name="CHPS", zone="Z", cho_phone="+233240000100"))
        session.add(Facility(id=1, name="Hospital", phone="+233240000200", district="D"))
        await session.flush()
        for driver_id, phone in DRIVER_PHONES.items():
            session.add(
                Driver(
                    id=driver_id,
                    name=f"Driver {driver_id}",
                    phone=phone,
                    vehicle_type="Motor-King",
                    chps_compound_id=1,
                    is_motor_king=True,
                )
            )
        await session.commit()

    async def override_get_db():
        async with sessions() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    monkeypatch.setattr(dispatch_orchestrator, "async_session", sessions)
    monkeypatch.setattr(
        dispatch_orchestrator.DispatchOrchestrator,
        "schedule_tier_timeouts",
        lambda self, *a, **k: None,
    )
    yield sessions

    app.dependency_overrides.clear()
    async with engine.begin() as conn:
        await conn.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
    await engine.dispose()


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
        return dispatch.id


async def _dial_accept(client: AsyncClient, phone: str) -> str:
    response = await client.post(
        "/ussd/callback",
        data={
            "sessionId": str(uuid.uuid4()),
            "serviceCode": "*384*1#",
            "phoneNumber": phone,
            "text": "1",
        },
    )
    assert response.status_code == 200, response.text
    return response.text


@pytest.mark.asyncio
async def test_parallel_accepts_have_exactly_one_winner(pg_sessions, monkeypatch):
    from main import app

    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for round_number in range(ROUNDS):
            dispatch_id = await _open_dispatch(pg_sessions)

            replies = await asyncio.gather(
                *(_dial_accept(client, phone) for phone in DRIVER_PHONES.values())
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
