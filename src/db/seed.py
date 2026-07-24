"""Seed demo CHPS compounds, drivers, and hospitals."""
import asyncio
import json
from pathlib import Path
from sqlalchemy import select
from src.db.database import async_session, init_db
from src.db.models import CHPSCompound, Driver, Facility

DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "demo_data.json"

async def seed() -> None:
    await init_db()
    raw = json.loads(DATA_PATH.read_text())
    async with async_session() as session:
        existing = await session.scalar(select(CHPSCompound).limit(1))
        if existing:
            print("Seed skipped: data already present")
            return
        for c in raw["compounds"]:
            session.add(CHPSCompound(**c))
        for f in raw["facilities"]:
            session.add(Facility(**f))
        await session.flush()
        for d in raw["drivers"]:
            session.add(Driver(**d, availability="AVAILABLE", is_active=True))
        await session.commit()
        print(
            f"Seeded {len(raw['compounds'])} compounds, "
            f"{len(raw['drivers'])} drivers, {len(raw['facilities'])} facilities"
        )

if __name__ == "__main__":
    asyncio.run(seed())
