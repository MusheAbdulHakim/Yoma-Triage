"""CLI commands to deactivate and move a CHO, each with an audit row (item 4)."""
from __future__ import annotations

import asyncio
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.admin.add_cho import AddChoError
from src.admin.deactivate_cho import deactivate_cho
from src.admin.move_cho import move_cho
from src.db.database import Base
from src.db.models import AuditLog, Cho, CHPSCompound
from tests.conftest import SEEDED_CHO_PHONE

REPO = Path(__file__).resolve().parents[1]


@pytest.mark.asyncio
async def test_deactivate_writes_the_change_and_audit_row(db_session, seeded_db):
    cho = await deactivate_cho(db_session, phone="0240000010", actor="ops")
    await db_session.commit()

    assert cho.active is False
    audit = await db_session.scalar(select(AuditLog).where(AuditLog.action == "cho_deactivated"))
    assert audit.entity_type == "cho"
    assert audit.entity_id == str(cho.id)
    assert audit.actor_id == "ops"
    assert SEEDED_CHO_PHONE not in str(audit.metadata_json)


@pytest.mark.asyncio
async def test_deactivating_twice_is_refused_and_writes_no_second_row(db_session, seeded_db):
    await deactivate_cho(db_session, phone=SEEDED_CHO_PHONE, actor="ops")
    with pytest.raises(AddChoError, match="already inactive"):
        await deactivate_cho(db_session, phone=SEEDED_CHO_PHONE, actor="ops")
    await db_session.commit()
    rows = await db_session.scalars(select(AuditLog))
    assert len(rows.all()) == 1


@pytest.mark.asyncio
async def test_move_writes_the_change_and_audit_row(db_session, seed_second_compound):
    cho = await move_cho(db_session, phone=SEEDED_CHO_PHONE, compound_id=2, actor="ops")
    await db_session.commit()

    assert cho.compound_id == 2
    audit = await db_session.scalar(select(AuditLog).where(AuditLog.action == "cho_moved"))
    assert audit.entity_id == str(cho.id)
    assert audit.actor_id == "ops"
    assert audit.metadata_json["from_compound_id"] == 1
    assert audit.metadata_json["to_compound_id"] == 2
    assert SEEDED_CHO_PHONE not in str(audit.metadata_json)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("phone", "compound_id", "message"),
    [
        ("12345", 2, "valid Ghana phone"),
        ("+233249999999", 2, "No CHO"),
        (SEEDED_CHO_PHONE, 999, "No CHPS compound"),
        (SEEDED_CHO_PHONE, 1, "already at compound"),
    ],
)
async def test_move_refuses_bad_input(db_session, seed_second_compound, phone, compound_id, message):
    with pytest.raises(AddChoError, match=message):
        await move_cho(db_session, phone=phone, compound_id=compound_id, actor="ops")
    assert (await db_session.scalars(select(AuditLog))).all() == []


@pytest.mark.asyncio
async def test_an_inactive_cho_cannot_be_moved(db_session, seed_second_compound):
    await deactivate_cho(db_session, phone=SEEDED_CHO_PHONE, actor="ops")
    with pytest.raises(AddChoError, match="inactive"):
        await move_cho(db_session, phone=SEEDED_CHO_PHONE, compound_id=2, actor="ops")


# --- What the app and API see afterwards ------------------------------------------


@pytest.mark.asyncio
async def test_after_deactivating_lookup_and_referrals_are_refused(client, seeded_db, db_session):
    await deactivate_cho(db_session, phone=SEEDED_CHO_PHONE, actor="ops")
    await db_session.commit()

    lookup = await client.post("/api/v1/cho/lookup", json={"phone": SEEDED_CHO_PHONE})
    assert (lookup.status_code, lookup.json()["code"]) == (403, "CHO_NOT_ACTIVE")
    referral = await client.post(
        "/api/v1/referral",
        json={
            "chps_compound_id": 1,
            "facility_id": 1,
            "patient_hash": "a" * 64,
            "cho_phone": SEEDED_CHO_PHONE,
            "emergency_type": "pph",
            "client_request_id": str(uuid.uuid4()),
        },
    )
    assert (referral.status_code, referral.json()["code"]) == (403, "CHO_NOT_ACTIVE")


@pytest.mark.asyncio
async def test_after_moving_lookup_gives_the_new_compound(client, seed_second_compound, db_session):
    await move_cho(db_session, phone=SEEDED_CHO_PHONE, compound_id=2, actor="ops")
    await db_session.commit()

    lookup = await client.post("/api/v1/cho/lookup", json={"phone": SEEDED_CHO_PHONE})
    assert lookup.json()["compound_id"] == 2
    assert lookup.json()["compound_name"] == "Other CHPS"


# --- The real commands ------------------------------------------------------------


def _run(module: str, url: str, *args: str, environment: str = "production"):
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in {"API_KEY", "AT_API_KEY", "AT_WEBHOOK_SECRET", "AT_USSD_SERVICE_CODE"}
    }
    env.update(ENVIRONMENT=environment, DATABASE_URL=url, PYTHONPATH=str(REPO))
    return subprocess.run(
        [sys.executable, "-m", module, *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO,
        timeout=60,
    )


@pytest.fixture
def cli_database(tmp_path):
    url = f"sqlite+aiosqlite:///{tmp_path}/cli.db"

    async def prepare():
        engine = create_async_engine(url)
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        sessions = async_sessionmaker(engine, class_=AsyncSession)
        async with sessions() as session:
            session.add(CHPSCompound(id=1, name="A", zone="Z", cho_phone="+233240000010"))
            session.add(CHPSCompound(id=2, name="B", zone="Z", cho_phone="+233240000011"))
            await session.flush()
            session.add(Cho(id=1, name="Abiba", phone=SEEDED_CHO_PHONE, compound_id=1))
            await session.commit()
        await engine.dispose()

    asyncio.run(prepare())
    return url


def _state(url: str) -> tuple[Cho, list[str]]:
    async def read():
        engine = create_async_engine(url)
        async with async_sessionmaker(engine, class_=AsyncSession)() as session:
            cho = await session.get(Cho, 1)
            actions = list(await session.scalars(select(AuditLog.action)))
        await engine.dispose()
        return cho, actions

    return asyncio.run(read())


@pytest.mark.parametrize("environment", ["production", "staging", "development"])
def test_deactivate_command_works_in_every_environment(cli_database, environment):
    result = _run(
        "src.admin.deactivate_cho",
        cli_database,
        "--phone",
        "0240000010",
        environment=environment,
    )
    assert result.returncode == 0, result.stderr
    cho, actions = _state(cli_database)
    assert cho.active is False
    assert actions == ["cho_deactivated"]


@pytest.mark.parametrize("environment", ["production", "staging", "development"])
def test_move_command_works_in_every_environment(cli_database, environment):
    result = _run(
        "src.admin.move_cho",
        cli_database,
        "--phone",
        "0240000010",
        "--compound-id",
        "2",
        environment=environment,
    )
    assert result.returncode == 0, result.stderr
    cho, actions = _state(cli_database)
    assert cho.compound_id == 2
    assert actions == ["cho_moved"]


@pytest.mark.parametrize(
    ("module", "args"),
    [
        ("src.admin.deactivate_cho", ["--phone", "0249999999"]),
        ("src.admin.move_cho", ["--phone", "0240000010", "--compound-id", "999"]),
    ],
)
def test_a_refused_command_writes_nothing_and_exits_nonzero(cli_database, module, args):
    result = _run(module, cli_database, *args)
    assert result.returncode == 1
    assert "Traceback" not in result.stderr
    cho, actions = _state(cli_database)
    assert (cho.active, cho.compound_id, actions) == (True, 1, [])


@pytest.mark.parametrize(
    ("module", "args"),
    [
        ("src.admin.deactivate_cho", ["--phone", "0240000010"]),
        ("src.admin.move_cho", ["--phone", "0240000010", "--compound-id", "2"]),
    ],
)
def test_commands_without_a_database_url_say_so(module, args):
    result = _run(module, "", *args)
    assert result.returncode == 1
    assert "DATABASE_URL must be set" in result.stderr
    assert "Traceback" not in result.stderr
