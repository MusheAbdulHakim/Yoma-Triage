"""Alembic environment. The URL comes from DATABASE_URL; nothing is stored in the repo."""
from __future__ import annotations

import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from src.config import settings
from src.db import models  # noqa: F401 - registers the tables on Base.metadata
from src.db.database import Base

target_metadata = Base.metadata


def _run(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


async def _run_with_new_engine() -> None:
    if not settings.DATABASE_URL.strip():
        raise RuntimeError("DATABASE_URL must be set to run migrations")
    engine = create_async_engine(settings.DATABASE_URL)
    async with engine.connect() as connection:
        await connection.run_sync(_run)
        await connection.commit()
    await engine.dispose()


if context.is_offline_mode():
    raise RuntimeError("Offline migrations are not supported")

# Tests pass in a connection so they can migrate a throwaway schema.
existing = context.config.attributes.get("connection")
if existing is not None:
    _run(existing)
else:
    asyncio.run(_run_with_new_engine())
