"""Driver availability and compound driver listing APIs."""
from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.database import get_db
from src.db.models import CHPSCompound
from src.services.driver_pool import DriverPoolManager

router = APIRouter(prefix="/api/v1", tags=["Drivers"])

AvailabilityStatus = Literal["AVAILABLE", "ON_TRIP", "OFF_DUTY"]


class AvailabilityUpdate(BaseModel):
    availability: AvailabilityStatus = Field(
        description="Driver duty status: AVAILABLE | ON_TRIP | OFF_DUTY"
    )


def _driver_payload(driver) -> dict[str, Any]:
    return {
        "id": driver.id,
        "name": driver.name,
        "phone": driver.phone,
        "vehicle_type": driver.vehicle_type,
        "vehicle_desc": driver.vehicle_desc,
        "chps_compound_id": driver.chps_compound_id,
        "is_motor_king": driver.is_motor_king,
        "is_active": driver.is_active,
        "availability": driver.availability,
    }


@router.post("/driver/{driver_id}/availability")
async def update_driver_availability(
    driver_id: int,
    payload: AvailabilityUpdate,
    session: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    pool = DriverPoolManager()
    driver = await pool.update_availability(session, driver_id, payload.availability)
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")
    await session.commit()
    return _driver_payload(driver)


@router.get("/compound/{compound_id}/drivers")
async def list_compound_drivers(
    compound_id: int,
    session: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    if not await session.get(CHPSCompound, compound_id):
        raise HTTPException(status_code=404, detail="CHPS compound not found")
    drivers = await DriverPoolManager().list_compound_drivers(session, compound_id)
    return {
        "compound_id": compound_id,
        "drivers": [_driver_payload(driver) for driver in drivers],
    }
