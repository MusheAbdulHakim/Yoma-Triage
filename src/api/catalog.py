"""Versioned offline referral-graph catalog for CHO app sync."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query

router = APIRouter(prefix="/api/v1/catalog", tags=["Catalog"])

# Keep in sync with mobile/assets/catalog/northern_bootstrap.json
CATALOG_VERSION = "2026-07-28.2"
_NORTHERN_PATH = (
    Path(__file__).resolve().parents[2] / "data" / "northern_referral_graph.json"
)


def _load_northern() -> dict[str, Any]:
    if not _NORTHERN_PATH.is_file():
        raise HTTPException(
            status_code=500,
            detail="Northern referral graph pack missing on server",
        )
    body = json.loads(_NORTHERN_PATH.read_text())
    body["version"] = body.get("version") or CATALOG_VERSION
    return body


@router.get("/referral-graph")
async def get_referral_graph(
    district: str | None = Query(default=None),
    region: str = Query(default="northern"),
) -> dict[str, Any]:
    """Return a versioned CHPS + facility pack for on-device nearest-facility.

    No patient data and no driver phones — drivers remain server-side after sync.
    Northern Region uses the 16-MMDA static pack (same asset as mobile bootstrap).
    """
    if region.lower() != "northern":
        raise HTTPException(
            status_code=404,
            detail=f"Region '{region}' not published yet (pilot: northern)",
        )

    body = _load_northern()
    compounds = list(body.get("compounds") or [])
    facilities = list(body.get("facilities") or [])
    preferred_links = list(body.get("preferred_links") or [])

    if district:
        compounds = [c for c in compounds if c.get("district") == district]
        facilities = [f for f in facilities if f.get("district") == district]
        compound_ids = {c["id"] for c in compounds}
        facility_ids = {f["id"] for f in facilities}
        preferred_links = [
            link
            for link in preferred_links
            if link.get("chps_compound_id") in compound_ids
            and link.get("facility_id") in facility_ids
        ]

    return {
        "version": body.get("version", CATALOG_VERSION),
        "region": "northern",
        "notes": body.get("notes"),
        "compounds": compounds,
        "facilities": facilities,
        "preferred_links": preferred_links,
    }
