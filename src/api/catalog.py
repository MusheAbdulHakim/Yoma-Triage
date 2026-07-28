"""Versioned offline referral-graph catalog for CHO app sync."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.database import get_db
from src.db.models import CHPSCompound, Facility

router = APIRouter(prefix="/api/v1/catalog", tags=["Catalog"])

CATALOG_VERSION = "2026-07-28.1"


def _compound_payload(compound: CHPSCompound) -> dict[str, Any]:
    return {
        "id": compound.id,
        "name": compound.name,
        "latitude": compound.latitude,
        "longitude": compound.longitude,
        # Catalog uses "district" for CHO UX; DB column is zone.
        "district": compound.zone,
    }


def _facility_payload(facility: Facility) -> dict[str, Any]:
    return {
        "id": facility.id,
        "name": facility.name,
        "latitude": facility.latitude,
        "longitude": facility.longitude,
        "district": facility.district,
        "has_maternity": facility.has_maternity,
        "has_icu": facility.has_icu,
        "type": facility.type,
    }


@router.get("/referral-graph")
async def get_referral_graph(
    district: str | None = Query(default=None),
    region: str = Query(default="northern"),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    """Return a versioned CHPS + facility pack for on-device nearest-facility.

    No patient data and no driver phones — drivers remain server-side after sync.
    """
    compounds = list((await db.execute(select(CHPSCompound))).scalars().all())
    facilities = list((await db.execute(select(Facility))).scalars().all())

    if district:
        compounds = [c for c in compounds if c.zone == district]
        facilities = [f for f in facilities if f.district == district]

    preferred_links: list[dict[str, int]] = []
    facility_ids = {f.id for f in facilities}
    for compound in compounds:
        # Default link: same-id facility when present (demo seed convention).
        if compound.id in facility_ids:
            preferred_links.append(
                {"chps_compound_id": compound.id, "facility_id": compound.id}
            )

    return {
        "version": CATALOG_VERSION,
        "region": region,
        "compounds": [_compound_payload(c) for c in compounds],
        "facilities": [_facility_payload(f) for f in facilities],
        "preferred_links": preferred_links,
    }
