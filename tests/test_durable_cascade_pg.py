"""The cascade survives restarts: timing lives in the database (B2, BUG-6)."""
from __future__ import annotations

import asyncio
import os
import re
import signal
import socket
import subprocess
import sys
import time
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import pytest
from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

from src.db.models import Dispatch, Referral
from src.services.dispatch_orchestrator import NEXT_ACTION_TIER_TIMEOUT, DispatchOrchestrator
from src.services.workers import run_worker_loop
from tests.postgres_support import (
    DRIVER_PHONES,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

pytestmark = pytest.mark.postgres

REPO = Path(__file__).resolve().parents[1]


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


async def _get(sessions, dispatch_id: int) -> Dispatch:
    async with sessions() as session:
        return await session.get(Dispatch, dispatch_id)


async def _make_due(sessions, dispatch_id: int) -> None:
    async with sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(next_action_at=datetime.now(UTC) - timedelta(seconds=1))
        )
        await session.commit()


def test_no_in_memory_timers_remain():
    source = (REPO / "src/services/dispatch_orchestrator.py").read_text()
    assert "create_task" not in source
    assert "sleep" not in source


@pytest.mark.asyncio
async def test_new_dispatch_stores_when_the_tier_ends(pg_sessions):  # noqa: F811
    before = datetime.now(UTC)
    dispatch = await _get(pg_sessions, await _open(pg_sessions))
    assert dispatch.next_action == NEXT_ACTION_TIER_TIMEOUT
    assert dispatch.next_action_at >= before + timedelta(seconds=85)
    assert dispatch.next_action_at <= datetime.now(UTC) + timedelta(seconds=95)


@pytest.mark.asyncio
async def test_nothing_happens_before_it_is_due(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    assert await DispatchOrchestrator().process_due_dispatches() == 0
    assert (await _get(pg_sessions, dispatch_id)).current_tier == 1


@pytest.mark.asyncio
async def test_each_due_step_advances_one_tier_then_fails(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)

    await _make_due(pg_sessions, dispatch_id)
    await DispatchOrchestrator().process_due_dispatches()
    dispatch = await _get(pg_sessions, dispatch_id)
    assert (dispatch.status, dispatch.current_tier) == ("TIER2_NOTIFIED", 2)
    assert dispatch.next_action_at > datetime.now(UTC)

    await _make_due(pg_sessions, dispatch_id)
    await DispatchOrchestrator().process_due_dispatches()
    dispatch = await _get(pg_sessions, dispatch_id)
    assert dispatch.status == "FAILED"
    assert dispatch.next_action is None
    assert dispatch.next_action_at is None


@pytest.mark.asyncio
async def test_running_workers_at_once_advances_only_one_tier(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _make_due(pg_sessions, dispatch_id)

    await asyncio.gather(*(DispatchOrchestrator().process_due_dispatches() for _ in range(5)))

    dispatch = await _get(pg_sessions, dispatch_id)
    assert (dispatch.status, dispatch.current_tier) == ("TIER2_NOTIFIED", 2)


@pytest.mark.asyncio
async def test_worker_skips_a_row_another_worker_holds(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    await _make_due(pg_sessions, dispatch_id)

    async with pg_sessions() as holder:
        await holder.execute(
            select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
        )
        # SKIP LOCKED returns straight away rather than waiting on the holder.
        processed = await asyncio.wait_for(
            DispatchOrchestrator().process_due_dispatches(), timeout=3
        )
        assert processed == 0
        await holder.rollback()


@pytest.mark.asyncio
async def test_accept_cancels_the_scheduled_step(pg_sessions, monkeypatch):  # noqa: F811
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await DispatchOrchestrator().handle_accept(session, dispatch_id, 1)
        await session.commit()

    dispatch = await _get(pg_sessions, dispatch_id)
    assert dispatch.next_action is None
    assert dispatch.next_action_at is None
    assert await DispatchOrchestrator().process_due_dispatches() == 0


@pytest.mark.asyncio
async def test_stale_schedule_on_a_claimed_dispatch_is_harmless(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await session.execute(
            update(Dispatch)
            .where(Dispatch.id == dispatch_id)
            .values(
                status="HOSPITAL_NOTIFIED",
                driver_id=1,
                next_action=NEXT_ACTION_TIER_TIMEOUT,
                next_action_at=datetime.now(UTC) - timedelta(seconds=1),
            )
        )
        await session.commit()

    await DispatchOrchestrator().process_due_dispatches()

    dispatch = await _get(pg_sessions, dispatch_id)
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    assert dispatch.current_tier == 1
    assert dispatch.next_action_at is None


@pytest.mark.asyncio
async def test_one_bad_dispatch_does_not_block_the_others(pg_sessions, monkeypatch):  # noqa: F811
    bad, good = await _open(pg_sessions), await _open(pg_sessions)
    await _make_due(pg_sessions, bad)
    await _make_due(pg_sessions, good)
    orchestrator = DispatchOrchestrator()
    real = orchestrator._perform_next_action

    async def fail_for_bad(session, dispatch):
        if dispatch.id == bad:
            raise RuntimeError("boom")
        await real(session, dispatch)

    monkeypatch.setattr(orchestrator, "_perform_next_action", fail_for_bad)
    assert await orchestrator.process_due_dispatches() == 1
    assert (await _get(pg_sessions, good)).current_tier == 2
    assert (await _get(pg_sessions, bad)).current_tier == 1


@pytest.mark.asyncio
async def test_loop_runs_immediately_and_survives_a_failed_step():
    calls = []
    stop = asyncio.Event()

    async def step():
        calls.append(time.monotonic())
        if len(calls) == 1:
            raise RuntimeError("first run fails")
        if len(calls) == 3:
            stop.set()

    started = time.monotonic()
    await asyncio.wait_for(run_worker_loop("test", step, 0.01, stop), timeout=3)

    assert len(calls) == 3
    assert calls[0] - started < 0.5


@pytest.mark.asyncio
async def test_overdue_dispatch_is_processed_on_startup(pg_sessions, monkeypatch):  # noqa: F811
    import main

    dispatch_id = await _open(pg_sessions)
    await _make_due(pg_sessions, dispatch_id)

    async def no_init():
        return None

    monkeypatch.setattr(main, "init_db", no_init)
    monkeypatch.setattr("src.config.settings.WORKER_POLL_SECONDS", 3600)
    async with main.lifespan(main.app):
        for _ in range(100):
            if (await _get(pg_sessions, dispatch_id)).current_tier == 2:
                break
            await asyncio.sleep(0.02)

    assert (await _get(pg_sessions, dispatch_id)).current_tier == 2


# --- A real server, really killed -----------------------------------------------


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class _Server:
    def __init__(self, database_url: str):
        self.port = _free_port()
        self.env = {
            **os.environ,
            "ENVIRONMENT": "development",
            "DATABASE_URL": database_url,
            "CASCADE_TIER_SECONDS": "3",
            "WORKER_POLL_SECONDS": "0.2",
            "PYTHONPATH": str(REPO),
            "HF_HUB_OFFLINE": "1",
        }
        self.process: subprocess.Popen | None = None

    def start(self) -> None:
        self.process = subprocess.Popen(
            [
                sys.executable, "-m", "uvicorn", "main:app",
                "--port", str(self.port), "--log-level", "error",
            ],
            cwd=REPO,
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    async def wait_ready(self) -> None:
        async with httpx.AsyncClient() as client:
            for _ in range(300):
                try:
                    await client.get(f"http://127.0.0.1:{self.port}/")
                    return
                except httpx.TransportError:
                    await asyncio.sleep(0.1)
        raise AssertionError("server did not start")

    def kill(self) -> None:
        assert self.process is not None
        self.process.send_signal(signal.SIGKILL)
        self.process.wait(timeout=10)


@pytest.mark.asyncio
async def test_killed_mid_tier_cascade_continues_after_restart(postgres_url):  # noqa: F811
    database = f"yoma_restart_{uuid.uuid4().hex}"
    admin = create_async_engine(postgres_url, poolclass=NullPool, isolation_level="AUTOCOMMIT")
    async with admin.connect() as conn:
        await conn.execute(text(f'CREATE DATABASE "{database}"'))
    url = re.sub(r"/[^/]*$", f"/{database}", postgres_url)
    engine = create_async_engine(url, poolclass=NullPool)
    server = _Server(url)
    try:
        server.start()
        await server.wait_ready()
        async with engine.begin() as conn:
            await conn.execute(
                text(
                    "insert into chps_compounds (id, name, zone, cho_phone) "
                    "values (1, 'CHPS', 'Z', '+233240000100')"
                )
            )
            await conn.execute(
                text(
                    "insert into facilities (id, name, type, phone, district, has_maternity, has_icu) "
                    "values (1, 'H', 't', '+233240000200', 'D', true, false)"
                )
            )
            await conn.execute(
                text(
                    "insert into chos (name, phone, compound_id, active) "
                    "values ('CHO', '+233240000100', 1, true)"
                )
            )
            for driver_id, phone in DRIVER_PHONES.items():
                await conn.execute(
                    text(
                        "insert into drivers (id, name, phone, vehicle_type, vehicle_desc, "
                        "chps_compound_id, is_motor_king, is_active, availability) values "
                        f"({driver_id}, 'D', '{phone}', 'MK', '', 1, true, true, 'AVAILABLE')"
                    )
                )

        async with httpx.AsyncClient(timeout=30) as client:
            created = await client.post(
                f"http://127.0.0.1:{server.port}/api/v1/referral",
                json={
                    "chps_compound_id": 1,
                    "cho_phone": "+233240000100",
                    "facility_id": 1,
                    "patient_hash": "0" * 64,
                    "emergency_type": "pph",
                    "vitals_taken": False,
                    "client_request_id": str(uuid.uuid4()),
                },
            )
        assert created.status_code == 201, created.text
        dispatch_id = created.json()["dispatch"]["id"]

        server.kill()

        # Past the tier deadline with no server running: nothing can have moved it.
        await asyncio.sleep(3.5)
        async with engine.connect() as conn:
            row = (
                await conn.execute(
                    text("select status, current_tier from dispatches where id = :i"),
                    {"i": dispatch_id},
                )
            ).one()
        assert (row.status, row.current_tier) == ("TIER1_NOTIFIED", 1)

        server.start()
        await server.wait_ready()

        status = None
        for _ in range(150):
            async with engine.connect() as conn:
                status = (
                    await conn.execute(
                        text("select status from dispatches where id = :i"), {"i": dispatch_id}
                    )
                ).scalar_one()
            if status == "FAILED":
                break
            await asyncio.sleep(0.1)
        assert status == "FAILED", "cascade did not continue after restart"

        async with engine.connect() as conn:
            for _ in range(50):
                actions = (
                    await conn.execute(
                        text("select action, target_role from dispatch_logs where dispatch_id = :i"),
                        {"i": dispatch_id},
                    )
                ).all()
                if ("cho_give_up", "cho") in {tuple(row) for row in actions}:
                    break
                await asyncio.sleep(0.1)
        assert ("cho_give_up", "cho") in {tuple(row) for row in actions}
    finally:
        if server.process and server.process.poll() is None:
            server.kill()
        await engine.dispose()
        async with admin.connect() as conn:
            await conn.execute(text(f'DROP DATABASE IF EXISTS "{database}" WITH (FORCE)'))
        await admin.dispose()
