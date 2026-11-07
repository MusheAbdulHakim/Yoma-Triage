"""B4: stale referrals the CHO never answers are closed by the cascade worker."""
from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update

from src import parameters
from src.api import errors
from src.config import settings
from src.db.models import AuditLog, Dispatch, Referral
from src.services.referral_expiry import EXPIRED_UNCONFIRMED, expire_unconfirmed_referrals
from tests.postgres_support import (
    CHO_PHONE,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)
from tests.test_stale_referrals import _resolve, _stale

NOW = datetime(2026, 11, 7, 12, 0, tzinfo=UTC)
HOURS = parameters.EXPIRE_UNCONFIRMED_HOURS


async def _referral(sessions, *, status="AWAITING_CONFIRMATION", age=timedelta(hours=HOURS + 1)):
    async with sessions() as session:
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            patient_hash="0" * 64,
            emergency_type="pph",
            status=status,
            client_request_id=str(uuid.uuid4()),
            queue_age_seconds=1500,
            initiated_at=NOW - age,
        )
        session.add(referral)
        await session.commit()
        return referral.id


async def _status(sessions, referral_id) -> str:
    async with sessions() as session:
        return (await session.get(Referral, referral_id)).status


async def _audit(sessions) -> list[AuditLog]:
    async with sessions() as session:
        return list(await session.scalars(select(AuditLog).order_by(AuditLog.id)))


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_an_unanswered_referral_past_the_limit_expires_with_an_audit_row(pg_sessions):  # noqa: F811
    referral_id = await _referral(pg_sessions)

    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 1

    assert await _status(pg_sessions, referral_id) == EXPIRED_UNCONFIRMED
    [audit] = await _audit(pg_sessions)
    assert (audit.entity_type, audit.entity_id) == ("referral", str(referral_id))
    assert audit.action == "referral_expired_unconfirmed"
    assert audit.actor_id == "worker"
    assert audit.metadata_json == {"queue_age_seconds": 1500, "expire_after_hours": HOURS}
    async with pg_sessions() as session:
        assert (await session.scalars(select(Dispatch))).all() == [], "nobody is told"


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_one_still_inside_the_limit_is_left(pg_sessions):  # noqa: F811
    referral_id = await _referral(pg_sessions, age=timedelta(hours=HOURS) - timedelta(minutes=1))
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 0
    assert await _status(pg_sessions, referral_id) == "AWAITING_CONFIRMATION"


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_exactly_at_the_limit_expires(pg_sessions):  # noqa: F811
    referral_id = await _referral(pg_sessions, age=timedelta(hours=HOURS))
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 1
    assert await _status(pg_sessions, referral_id) == EXPIRED_UNCONFIRMED


@pytest.mark.postgres
@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["CONFIRMED", "MANUALLY_HANDLED", "CANCELLED"])
async def test_only_unanswered_referrals_expire(pg_sessions, status):  # noqa: F811
    referral_id = await _referral(pg_sessions, status=status, age=timedelta(days=30))
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 0
    assert await _status(pg_sessions, referral_id) == status


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_a_second_run_changes_nothing(pg_sessions):  # noqa: F811
    await _referral(pg_sessions)
    await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions)
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 0
    assert len(await _audit(pg_sessions)) == 1


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_the_limit_can_be_overridden(pg_sessions, monkeypatch):  # noqa: F811
    monkeypatch.setattr(settings, "EXPIRE_UNCONFIRMED_HOURS", 2)
    referral_id = await _referral(pg_sessions, age=timedelta(hours=3))
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 1
    assert await _status(pg_sessions, referral_id) == EXPIRED_UNCONFIRMED


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_a_run_handles_at_most_its_limit(pg_sessions):  # noqa: F811
    for _ in range(3):
        await _referral(pg_sessions)
    assert await expire_unconfirmed_referrals(now=NOW, limit=2, sessions=pg_sessions) == 2
    assert await expire_unconfirmed_referrals(now=NOW, limit=2, sessions=pg_sessions) == 1


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_a_referral_being_answered_is_left_for_the_next_run(pg_sessions):  # noqa: F811
    """The answer holds the row lock; the expiry skips it rather than wait or overwrite."""
    referral_id = await _referral(pg_sessions)
    async with pg_sessions() as answering:
        await answering.execute(
            select(Referral).where(Referral.id == referral_id).with_for_update()
        )
        assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 0
        await answering.execute(
            update(Referral).where(Referral.id == referral_id).values(status="MANUALLY_HANDLED")
        )
        await answering.commit()
    assert await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions) == 0
    assert await _status(pg_sessions, referral_id) == "MANUALLY_HANDLED"


@pytest.mark.postgres
@pytest.mark.asyncio
@pytest.mark.parametrize("action", ["send_now", "already_handled", "cancel"])
async def test_answering_an_expired_referral_says_it_expired(pg_sessions, action):  # noqa: F811
    from main import app

    referral_id = await _referral(pg_sessions)
    await expire_unconfirmed_referrals(now=NOW, sessions=pg_sessions)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post(
            f"/api/v1/referral/{referral_id}/resolve",
            json={"action": action, "cho_phone": CHO_PHONE},
        )
    assert response.status_code == 409
    assert response.json()["code"] == errors.REFERRAL_EXPIRED
    assert "Drivers were not told" in response.json()["detail"]
    assert await _status(pg_sessions, referral_id) == EXPIRED_UNCONFIRMED
    async with pg_sessions() as session:
        assert (await session.scalars(select(Dispatch))).all() == []


@pytest.mark.asyncio
async def test_the_api_refuses_an_answer_once_expired(client, seeded_db, db_session):
    body = await _stale(client)
    referral_id = body["referral"]["id"]
    await db_session.execute(
        update(Referral).where(Referral.id == referral_id).values(status=EXPIRED_UNCONFIRMED)
    )
    await db_session.commit()

    response = await _resolve(client, referral_id, "send_now")
    assert (response.status_code, response.json()["code"]) == (409, errors.REFERRAL_EXPIRED)


@pytest.mark.asyncio
async def test_the_cascade_worker_runs_the_expiry(monkeypatch):
    import main

    calls = []

    async def dispatches(self, limit=100):
        calls.append("dispatches")
        return 0

    async def expiry(**_):
        calls.append("expiry")
        return 0

    monkeypatch.setattr(main.DispatchOrchestrator, "process_due_dispatches", dispatches)
    monkeypatch.setattr(main, "expire_unconfirmed_referrals", expiry)
    await main.run_cascade_work()
    assert calls == ["dispatches", "expiry"]


def test_startup_refuses_a_zero_limit(monkeypatch):
    monkeypatch.setattr(settings, "EXPIRE_UNCONFIRMED_HOURS", 0)
    assert "EXPIRE_UNCONFIRMED_HOURS must be above 0" in settings.startup_errors()


def test_the_default_is_the_sheet_value():
    assert settings.EXPIRE_UNCONFIRMED_HOURS == HOURS == 24

