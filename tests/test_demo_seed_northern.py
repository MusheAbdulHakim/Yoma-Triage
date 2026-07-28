"""Northern catalog IDs must exist in demo seed for referral FK checks."""
from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.db.database import Base
from src.db.models import CHPSCompound, Facility
from src.db.seed import _merge_compound, _merge_facility

DEMO = Path(__file__).resolve().parents[1] / "data" / "demo_data.json"
GRAPH = Path(__file__).resolve().parents[1] / "data" / "northern_referral_graph.json"


@pytest.mark.asyncio
async def test_demo_data_covers_northern_catalog_ids() -> None:
    demo = json.loads(DEMO.read_text())
    graph = json.loads(GRAPH.read_text())
    assert {c["id"] for c in demo["compounds"]} == {c["id"] for c in graph["compounds"]}
    assert {f["id"] for f in demo["facilities"]} == {f["id"] for f in graph["facilities"]}
    assert len(demo["compounds"]) == 16
    # ID 2 must not be Navrongo (Upper East) — Northern catalog uses Sagnarigu.
    assert demo["facilities"][1]["name"] == graph["facilities"][1]["name"]
    assert "Navrongo" not in demo["facilities"][1]["name"]


@pytest.mark.asyncio
async def test_seed_upsert_inserts_sixteen_facilities() -> None:
    raw = json.loads(DEMO.read_text())
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        for c in raw["compounds"]:
            row = await session.get(CHPSCompound, c["id"])
            if row is None:
                session.add(CHPSCompound(**c))
            else:
                _merge_compound(row, c)
        for f in raw["facilities"]:
            row = await session.get(Facility, f["id"])
            if row is None:
                session.add(Facility(**f))
            else:
                _merge_facility(row, f)
        await session.commit()
        n_fac = len((await session.scalars(select(Facility))).all())
        n_chps = len((await session.scalars(select(CHPSCompound))).all())
        assert n_fac == 16
        assert n_chps == 16
        f16 = await session.get(Facility, 16)
        assert f16 is not None
        assert f16.name.startswith("Zabzugu")
    await engine.dispose()
