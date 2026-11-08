from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import AuditLog, Dispatch, Driver

AVAILABLE = "AVAILABLE"
ON_TRIP = "ON_TRIP"
OFF_DUTY = "OFF_DUTY"
VALID_AVAILABILITY = frozenset({AVAILABLE, ON_TRIP, OFF_DUTY})
ACTIVE_DISPATCH_STATUSES = frozenset(
    {
        "ACCEPTED",
        "HOSPITAL_NOTIFIED",
        "HOSPITAL_CONFIRMED",
        "DIVERTED",  # legacy rows only; see LEGACY_DIVERTED
    }
)


class DriverPoolManager:
    async def get_driver(
        self, session: AsyncSession, driver_id: int
    ) -> Driver | None:
        return await session.get(Driver, driver_id)

    async def get_active_dispatch(
        self, session: AsyncSession, driver_id: int, *, exclude: int | None = None
    ) -> Dispatch | None:
        query = select(Dispatch).where(
            Dispatch.driver_id == driver_id,
            Dispatch.status.in_(ACTIVE_DISPATCH_STATUSES),
        )
        if exclude is not None:
            query = query.where(Dispatch.id != exclude)
        return await session.scalar(query.order_by(Dispatch.id.desc()).limit(1))

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
        self, session: AsyncSession, driver_id: int, status: str, *, actor: str = "api"
    ) -> Driver | None:
        if status not in VALID_AVAILABILITY:
            raise ValueError(f"Invalid availability status: {status}")
        driver = await session.get(Driver, driver_id)
        if not driver:
            return None
        set_availability(session, driver, status, actor=actor)
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


def set_availability(
    session: AsyncSession,
    driver: Driver,
    status: str,
    *,
    actor: str,
    dispatch_id: int | None = None,
) -> None:
    """Change a driver's availability, with an audit row, in the caller's transaction.

    actor says who changed it: "dispatch" for the trip itself, "driver" for the driver's
    own USSD menu, "api" for the REST endpoint.
    """
    if status not in VALID_AVAILABILITY:
        raise ValueError(f"Invalid availability status: {status}")
    previous = driver.availability
    if previous == status:
        return
    driver.availability = status
    session.add(
        AuditLog(
            entity_type="driver",
            entity_id=str(driver.id),
            action="driver_availability",
            actor_id=actor,
            metadata_json={"from": previous, "to": status, "dispatch_id": dispatch_id},
        )
    )
