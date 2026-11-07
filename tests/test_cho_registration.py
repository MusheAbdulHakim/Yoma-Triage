"""CHO identity: provisioning, lookup, and referral checks (BUG-15)."""
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

from src.admin.add_cho import AddChoError, add_cho
from src.db.database import Base
from src.db.models import AuditLog, Cho, CHPSCompound
from tests.conftest import SEEDED_CHO_PHONE

REPO = Path(__file__).resolve().parents[1]
VITALS = {"systolic_bp": 60}


def _referral(**overrides):
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "0123456789abcdef" * 4,
        "cho_phone": SEEDED_CHO_PHONE,
        "emergency_type": "pph",
        "client_request_id": str(uuid.uuid4()),
        "vitals": VITALS,
        **overrides,
    }


# --- Provisioning ----------------------------------------------------------------


@pytest.mark.asyncio
async def test_add_cho_stores_normalized_phone_and_audit_row(db_session, seeded_db):
    cho = await add_cho(
        db_session, name=" Fatima ", phone="024 000 0999", compound_id=1, actor="ops"
    )
    await db_session.commit()

    assert cho.name == "Fatima"
    assert cho.phone == "+233240000999"
    assert cho.active is True
    assert cho.created_at is not None
    audit = await db_session.scalar(select(AuditLog).where(AuditLog.entity_id == str(cho.id)))
    assert audit.entity_type == "cho"
    assert audit.action == "cho_added"
    assert audit.actor_id == "ops"
    assert audit.metadata_json["compound_id"] == 1
    assert "+233240000999" not in str(audit.metadata_json)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"name": "", "phone": "0240000999", "compound_id": 1}, "Name"),
        ({"name": "X", "phone": "12345", "compound_id": 1}, "valid Ghana phone"),
        ({"name": "X", "phone": "0240000999", "compound_id": 999}, "No CHPS compound"),
        ({"name": "X", "phone": SEEDED_CHO_PHONE, "compound_id": 1}, "already registered"),
        ({"name": "X", "phone": "0240000010", "compound_id": 1}, "already registered"),
    ],
)
async def test_add_cho_refuses_bad_input(db_session, seeded_db, kwargs, message):
    with pytest.raises(AddChoError, match=message):
        await add_cho(db_session, actor="ops", **kwargs)


def _run_cli(database_url: str, *args: str, environment: str = "production"):
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in {"API_KEY", "AT_API_KEY", "AT_WEBHOOK_SECRET", "AT_USSD_SERVICE_CODE"}
    }
    env.update(ENVIRONMENT=environment, DATABASE_URL=database_url, PYTHONPATH=str(REPO))
    return subprocess.run(
        [sys.executable, "-m", "src.admin.add_cho", *args],
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
        sessions = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
        async with sessions() as session:
            session.add(CHPSCompound(id=1, name="C", zone="Z", cho_phone="+233240000100"))
            await session.commit()
        await engine.dispose()

    asyncio.run(prepare())
    return url


def _rows(url: str):
    async def read():
        engine = create_async_engine(url)
        sessions = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
        async with sessions() as session:
            chos = (await session.scalars(select(Cho))).all()
            audits = (await session.scalars(select(AuditLog))).all()
        await engine.dispose()
        return chos, audits

    return asyncio.run(read())


@pytest.mark.parametrize("environment", ["production", "staging", "development"])
def test_cli_works_in_every_environment(cli_database, environment):
    result = _run_cli(
        cli_database,
        "--name", "Abiba", "--phone", "0240000555", "--compound-id", "1",
        environment=environment,
    )
    assert result.returncode == 0, result.stderr
    assert "Added CHO" in result.stdout
    assert "0240000555" not in result.stdout, "output must not repeat the phone number"
    chos, audits = _rows(cli_database)
    assert [cho.phone for cho in chos] == ["+233240000555"]
    assert [audit.action for audit in audits] == ["cho_added"]


def test_cli_refusal_writes_nothing_and_exits_nonzero(cli_database):
    result = _run_cli(cli_database, "--name", "A", "--phone", "0240000555", "--compound-id", "9")
    assert result.returncode == 1
    assert "No CHPS compound" in result.stderr
    assert "Traceback" not in result.stderr
    assert _rows(cli_database) == ([], [])


def test_cli_without_database_url_says_so():
    env = {**os.environ, "DATABASE_URL": "", "PYTHONPATH": str(REPO)}
    result = subprocess.run(
        [sys.executable, "-m", "src.admin.add_cho",
         "--name", "A", "--phone", "0240000555", "--compound-id", "1"],
        capture_output=True, text=True, env=env, cwd=REPO, timeout=60,
    )
    assert result.returncode == 1
    assert "DATABASE_URL must be set" in result.stderr


# --- Lookup ----------------------------------------------------------------------


@pytest.mark.asyncio
async def test_lookup_returns_the_compound(client, seeded_db):
    response = await client.post("/api/v1/cho/lookup", json={"phone": "024 000 0010"})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["phone"] == SEEDED_CHO_PHONE
    assert body["compound_id"] == 1
    assert body["compound_name"] == "Tamale South CHPS"
    assert body["latitude"] is not None


@pytest.mark.asyncio
async def test_lookup_of_unknown_phone_is_a_clear_404(client, seeded_db):
    response = await client.post("/api/v1/cho/lookup", json={"phone": "0240000999"})
    assert response.status_code == 404
    assert "not registered" in response.json()["detail"]


@pytest.mark.asyncio
async def test_lookup_of_inactive_cho_is_a_clear_403(client, seeded_db, db_session):
    cho = await db_session.scalar(select(Cho).where(Cho.phone == SEEDED_CHO_PHONE))
    cho.active = False
    await db_session.commit()
    response = await client.post("/api/v1/cho/lookup", json={"phone": SEEDED_CHO_PHONE})
    assert response.status_code == 403
    assert "no longer active" in response.json()["detail"]


@pytest.mark.asyncio
@pytest.mark.parametrize("phone", ["12345", "abc", "+2332400000101", ""])
async def test_lookup_refuses_a_malformed_phone(client, seeded_db, phone):
    response = await client.post("/api/v1/cho/lookup", json={"phone": phone})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_lookup_needs_the_api_key(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "secret")
    response = await client.post("/api/v1/cho/lookup", json={"phone": SEEDED_CHO_PHONE})
    assert response.status_code == 401


# --- Referrals -------------------------------------------------------------------


@pytest.mark.asyncio
async def test_referral_from_the_registered_cho_is_accepted(client, seeded_db):
    response = await client.post("/api/v1/referral", json=_referral())
    assert response.status_code == 201, response.text


@pytest.mark.asyncio
async def test_referral_accepts_any_format_of_the_same_phone(client, seeded_db):
    response = await client.post("/api/v1/referral", json=_referral(cho_phone="0240000010"))
    assert response.status_code == 201, response.text


@pytest.mark.asyncio
async def test_referral_without_cho_phone_is_rejected(client, seeded_db):
    payload = _referral()
    del payload["cho_phone"]
    assert (await client.post("/api/v1/referral", json=payload)).status_code == 422


@pytest.mark.asyncio
async def test_referral_from_unknown_cho_is_rejected_and_sends_nothing(
    client, seeded_db, db_session
):
    from tests.conftest import queued_sms

    response = await client.post("/api/v1/referral", json=_referral(cho_phone="0240000999"))
    assert response.status_code == 403
    assert "not registered" in response.json()["detail"]
    assert await queued_sms(db_session) == []


@pytest.mark.asyncio
async def test_referral_from_inactive_cho_is_rejected(client, seeded_db, db_session):
    cho = await db_session.scalar(select(Cho).where(Cho.phone == SEEDED_CHO_PHONE))
    cho.active = False
    await db_session.commit()
    response = await client.post("/api/v1/referral", json=_referral())
    assert response.status_code == 403
    assert "no longer active" in response.json()["detail"]


@pytest.mark.asyncio
async def test_referral_for_another_compound_is_rejected(client, seeded_db, db_session):
    db_session.add(CHPSCompound(id=2, name="Other", zone="Z", cho_phone="+233240000011"))
    await db_session.commit()
    response = await client.post("/api/v1/referral", json=_referral(chps_compound_id=2))
    assert response.status_code == 403
    assert "does not belong" in response.json()["detail"]


@pytest.mark.asyncio
async def test_skip_vitals_also_needs_a_registered_cho(client, seeded_db):
    payload = _referral(cho_phone="0240000999", vitals_taken=False)
    del payload["vitals"]
    assert (await client.post("/api/v1/referral", json=payload)).status_code == 403


@pytest.mark.asyncio
async def test_retry_of_an_accepted_referral_survives_deactivation(client, seeded_db, db_session):
    payload = _referral()
    first = await client.post("/api/v1/referral", json=payload)
    cho = await db_session.scalar(select(Cho).where(Cho.phone == SEEDED_CHO_PHONE))
    cho.active = False
    await db_session.commit()

    retry = await client.post("/api/v1/referral", json=payload)

    assert retry.status_code == 201
    assert retry.json()["idempotent"] is True
    assert retry.json()["dispatch"]["id"] == first.json()["dispatch"]["id"]


# --- Seed ------------------------------------------------------------------------


def test_demo_seed_registers_a_cho_for_each_compound():
    source = (REPO / "src/db/seed.py").read_text()
    assert "Cho(" in source
