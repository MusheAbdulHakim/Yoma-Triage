"""GET /api/v1/driver/{id}/status — duty status + active trip if any."""
from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Dispatch, Referral

VALID_HASH = "0123456789abcdef" * 4


@pytest.mark.asyncio
async def test_get_driver_status_available(client, seeded_db):
    res = await client.get("/api/v1/driver/1/status")
    assert res.status_code == 200
    body = res.json()
    assert body["id"] == 1
    assert body["availability"] == "AVAILABLE"
    assert body["is_active"] is True
    assert body["active_dispatch"] is None


@pytest.mark.asyncio
async def test_get_driver_status_includes_active_dispatch(
    client, seeded_db, db_session: AsyncSession
):
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash=VALID_HASH,
        patient_name="Unknown",
        emergency_type="Haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id,
        facility_id=1,
        driver_id=1,
        status="ACCEPTED",
        current_tier=1,
    )
    db_session.add(dispatch)
    await db_session.flush()

    # Mirror accept side-effect: driver on trip
    from src.db.models import Driver

    driver = await db_session.get(Driver, 1)
    assert driver is not None
    driver.availability = "ON_TRIP"
    await db_session.flush()

    res = await client.get("/api/v1/driver/1/status")
    assert res.status_code == 200
    body = res.json()
    assert body["availability"] == "ON_TRIP"
    assert body["active_dispatch"] is not None
    assert body["active_dispatch"]["id"] == dispatch.id
    assert body["active_dispatch"]["status"] == "ACCEPTED"
    assert body["active_dispatch"]["referral_id"] == referral.id


@pytest.mark.asyncio
async def test_get_driver_status_missing_404(client, seeded_db):
    res = await client.get("/api/v1/driver/999/status")
    assert res.status_code == 404
    assert res.json()["detail"] == "Driver not found"
