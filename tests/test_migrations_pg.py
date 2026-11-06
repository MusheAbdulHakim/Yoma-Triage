"""Alembic baseline matches the models, and startup only creates tables in development."""
from __future__ import annotations

import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

from src.config import settings
from src.db import models  # noqa: F401
from src.db.database import Base
from tests.postgres_support import postgres_url  # noqa: F401 - pytest fixture

REPO = Path(__file__).resolve().parents[1]


def _alembic_config(connection) -> Config:
    config = Config(str(REPO / "alembic.ini"))
    config.set_main_option("script_location", str(REPO / "migrations"))
    config.attributes["connection"] = connection
    return config


async def _in_throwaway_schema(postgres_url, action):  # noqa: F811
    schema = f"yoma_mig_{uuid.uuid4().hex}"
    engine = create_async_engine(
        postgres_url,
        poolclass=NullPool,
        connect_args={"server_settings": {"search_path": schema}},
    )
    try:
        async with engine.begin() as conn:
            await conn.execute(text(f'CREATE SCHEMA "{schema}"'))
        async with engine.begin() as conn:
            return await conn.run_sync(action)
    finally:
        async with engine.begin() as conn:
            await conn.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        await engine.dispose()


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_migrations_produce_exactly_the_models(postgres_url):  # noqa: F811
    def action(connection):
        command.upgrade(_alembic_config(connection), "head")
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        return compare_metadata(context, Base.metadata)

    assert await _in_throwaway_schema(postgres_url, action) == []


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_migrations_can_be_reversed(postgres_url):  # noqa: F811
    def action(connection):
        config = _alembic_config(connection)
        command.upgrade(config, "head")
        command.downgrade(config, "base")
        rows = connection.execute(
            text(
                "select table_name from information_schema.tables "
                "where table_schema = current_schema() and table_name <> 'alembic_version'"
            )
        )
        return [row[0] for row in rows]

    assert await _in_throwaway_schema(postgres_url, action) == []


def test_alembic_needs_a_database_url():
    env = {"PATH": "", "PYTHONPATH": str(REPO), "ENVIRONMENT": "development", "DATABASE_URL": ""}
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        capture_output=True,
        text=True,
        env=env,
        cwd=REPO,
        timeout=60,
    )
    assert result.returncode != 0
    assert "DATABASE_URL must be set" in result.stderr


def test_no_credentials_in_alembic_config():
    assert "postgresql" not in (REPO / "alembic.ini").read_text()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("environment", "expected_calls"),
    [("development", 1), ("production", 0), ("staging", 0), ("anything-else", 0)],
)
async def test_startup_creates_tables_only_in_development(
    monkeypatch, environment, expected_calls
):
    import main

    calls = []

    async def fake_init_db():
        calls.append(1)

    monkeypatch.setattr(main, "init_db", fake_init_db)
    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(settings, "API_KEY", "k")
    monkeypatch.setattr(settings, "AT_WEBHOOK_SECRET", "s")
    monkeypatch.setattr(settings, "AT_API_KEY", "a")
    monkeypatch.setattr(settings, "AT_USERNAME", "yoma")
    monkeypatch.setattr(settings, "AT_USSD_SERVICE_CODE", "*1#")
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 90)

    async with main.lifespan(main.app):
        pass

    assert len(calls) == expected_calls
