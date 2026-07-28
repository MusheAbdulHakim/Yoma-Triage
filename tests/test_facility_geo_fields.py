"""Tests for Facility latitude/longitude fields and seed data round-trip."""
from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.db.database import Base
from src.db.models import Facility

DATA_PATH = Path(__file__).resolve().parents[1] / "data" / "demo_data.json"


@pytest.mark.asyncio
async def test_seed_loads_facility_lat_lon() -> None:
    """Facilities from demo_data.json persist latitude and longitude."""
    raw = json.loads(DATA_PATH.read_text())
    tth = next(f for f in raw["facilities"] if f["id"] == 1)

    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        for f in raw["facilities"]:
            session.add(Facility(**f))
        await session.commit()

        facility = await session.scalar(select(Facility).where(Facility.id == 1))
        assert facility is not None
        assert facility.latitude == pytest.approx(tth["latitude"])
        assert facility.longitude == pytest.approx(tth["longitude"])

    await engine.dispose()
