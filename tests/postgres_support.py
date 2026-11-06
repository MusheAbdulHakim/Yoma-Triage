"""Real-Postgres support for tests that depend on row locks.

SQLite ignores ``FOR UPDATE``, so lock behaviour can only be tested on Postgres.

Server selection:
- ``TEST_POSTGRES_URL``: use that server (asyncpg URL). Tests only ever touch a
  uniquely named throwaway schema, never existing tables.
- otherwise: start a temporary local cluster if ``initdb`` is available.
- otherwise: skip, or fail if ``REQUIRE_POSTGRES_TESTS=1`` (set this in CI so the
  race tests cannot silently stop running).
"""
from __future__ import annotations

import glob
import os
import shutil
import socket
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.db.database import Base, get_db
from src.db.models import CHPSCompound, Driver, Facility

DRIVER_PHONES = {1: "+233240000001", 2: "+233240000002"}
FALLBACK_DRIVER_ID = 3
FALLBACK_DRIVER_PHONE = "+233240000003"
CHO_PHONE = "+233240000100"


def _find_pg_binary(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    candidates = sorted(glob.glob(f"/usr/lib/postgresql/*/bin/{name}"))
    return candidates[-1] if candidates else None


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _unavailable(reason: str) -> None:
    if os.environ.get("REQUIRE_POSTGRES_TESTS") == "1":
        pytest.fail(f"Postgres tests are required but cannot run: {reason}")
    pytest.skip(f"Postgres unavailable: {reason}")


@pytest.fixture(scope="session")
def postgres_url():
    configured = os.environ.get("TEST_POSTGRES_URL", "").strip()
    if configured:
        yield configured
        return

    initdb, pg_ctl = _find_pg_binary("initdb"), _find_pg_binary("pg_ctl")
    if not initdb or not pg_ctl:
        _unavailable("set TEST_POSTGRES_URL or install Postgres server binaries")

    base = Path(tempfile.mkdtemp(prefix="yoma-pg-"))
    data_dir, port = base / "data", _free_port()
    try:
        subprocess.run(
            [initdb, "-D", str(data_dir), "-U", "postgres", "--auth=trust", "-E", "UTF8"],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                pg_ctl, "-D", str(data_dir), "-w", "-l", str(base / "log"),
                "-o", f"-p {port} -k {base} -c listen_addresses=127.0.0.1 -c fsync=off",
                "start",
            ],
            check=True,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        shutil.rmtree(base, ignore_errors=True)
        _unavailable(f"could not start a temporary cluster: {exc}")

    try:
        yield f"postgresql+asyncpg://postgres@127.0.0.1:{port}/postgres"
    finally:
        subprocess.run(
            [pg_ctl, "-D", str(data_dir), "-m", "immediate", "stop"],
            check=False,
            capture_output=True,
        )
        shutil.rmtree(base, ignore_errors=True)


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
        session.add(CHPSCompound(id=1, name="CHPS", zone="Z", cho_phone=CHO_PHONE))
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
        session.add(
            Driver(
                id=FALLBACK_DRIVER_ID,
                name="Fallback",
                phone=FALLBACK_DRIVER_PHONE,
                vehicle_type="Personal vehicle",
                chps_compound_id=1,
                is_motor_king=False,
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
