"""Seed demo CHPS compounds, drivers, and hospitals.

Idempotent upsert: aligns DB rows with `data/demo_data.json` so the 16-MMDA
Northern catalog IDs always resolve for `POST /api/v1/referral`.
"""
from __future__ import annotations

import asyncio
import json
from pathlib import Path

from sqlalchemy import select

from src.db.database import async_session, init_db
from src.db.models import CHPSCompound, Driver, Facility

DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "demo_data.json"


def _merge_compound(row: CHPSCompound, data: dict) -> None:
    row.name = data["name"]
    row.zone = data["zone"]
    row.latitude = data.get("latitude")
    row.longitude = data.get("longitude")
    row.cho_phone = data["cho_phone"]


def _merge_facility(row: Facility, data: dict) -> None:
    row.name = data["name"]
    row.type = data.get("type", "district_hospital")
    row.phone = data["phone"]
    row.district = data["district"]
    row.latitude = data.get("latitude")
    row.longitude = data.get("longitude")
    row.has_maternity = bool(data.get("has_maternity", True))
    row.has_icu = bool(data.get("has_icu", False))


async def seed() -> None:
    await init_db()
    raw = json.loads(DATA_PATH.read_text())
    async with async_session() as session:
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

        await session.flush()

        existing_phones = {
            phone
            for phone in (
                await session.scalars(select(Driver.phone))
            ).all()
        }
        added_drivers = 0
        for d in raw["drivers"]:
            if d["phone"] in existing_phones:
                continue
            session.add(Driver(**d, availability="AVAILABLE", is_active=True))
            added_drivers += 1
            existing_phones.add(d["phone"])

        await session.commit()
        print(
            f"Seed upserted {len(raw['compounds'])} compounds, "
            f"{len(raw['facilities'])} facilities; "
            f"added {added_drivers} new drivers"
        )


if __name__ == "__main__":
    asyncio.run(seed())
