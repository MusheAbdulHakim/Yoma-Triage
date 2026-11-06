"""CHO identity lookup for first-run setup in the app. OTP will verify this later."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.deps import require_api_key
from src.db.database import get_db
from src.db.models import Cho, CHPSCompound
from src.utils.phones import is_valid_ghana_phone, normalize_ghana_phone

router = APIRouter(prefix="/api/v1", tags=["CHO"], dependencies=[Depends(require_api_key)])

NOT_REGISTERED = (
    "This phone number is not registered as a CHO. Ask your district coordinator to register it."
)
NOT_ACTIVE = "This CHO is no longer active. Ask your district coordinator to reactivate it."


class ChoLookup(BaseModel):
    # In the body rather than the URL, so the number stays out of access logs.
    phone: str = Field(min_length=1, max_length=32)


async def find_cho(session: AsyncSession, phone: str) -> Cho | None:
    return await session.scalar(select(Cho).where(Cho.phone == normalize_ghana_phone(phone)))


@router.post("/cho/lookup")
async def lookup_cho(payload: ChoLookup, session: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    if not is_valid_ghana_phone(normalize_ghana_phone(payload.phone)):
        raise HTTPException(
            status_code=422,
            detail="Enter a valid Ghana phone number, for example 0240000100.",
        )
    cho = await find_cho(session, payload.phone)
    if cho is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=NOT_REGISTERED)
    if not cho.active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=NOT_ACTIVE)
    compound = await session.get(CHPSCompound, cho.compound_id)
    return {
        "name": cho.name,
        "phone": cho.phone,
        "compound_id": cho.compound_id,
        "compound_name": compound.name if compound else None,
        "latitude": compound.latitude if compound else None,
        "longitude": compound.longitude if compound else None,
    }
