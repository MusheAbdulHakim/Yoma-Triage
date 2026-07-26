from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Driver

VALID_AVAILABILITY = frozenset({"AVAILABLE", "ON_TRIP", "OFF_DUTY"})


class DriverPoolManager:
    async def get_candidates(
        self,
        session: AsyncSession,
        compound_id: int,
        tier: int,
        declined_ids: list[int],
    ) -> list[Driver]:
        query = select(Driver).where(
            Driver.chps_compound_id == compound_id,
            Driver.is_active.is_(True),
            Driver.availability == "AVAILABLE",
        )
        if tier == 1:
            query = query.where(Driver.is_motor_king.is_(True))
        elif tier == 2:
            query = query.where(Driver.is_motor_king.is_(False))
        else:
            return []

        rows = (await session.execute(query)).scalars().all()
        declined = set(declined_ids or [])
        return [driver for driver in rows if driver.id not in declined]

    async def update_availability(
        self, session: AsyncSession, driver_id: int, status: str
    ) -> Driver | None:
        if status not in VALID_AVAILABILITY:
            raise ValueError(f"Invalid availability status: {status}")
        driver = await session.get(Driver, driver_id)
        if not driver:
            return None
        driver.availability = status
        await session.flush()
        return driver

    async def list_compound_drivers(
        self, session: AsyncSession, compound_id: int
    ) -> list[Driver]:
        rows = await session.scalars(
            select(Driver)
            .where(
                Driver.chps_compound_id == compound_id,
                Driver.is_active.is_(True),
            )
            .order_by(Driver.id)
        )
        return list(rows)
