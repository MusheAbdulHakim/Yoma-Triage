from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Driver


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
