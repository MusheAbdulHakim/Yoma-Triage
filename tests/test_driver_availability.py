"""Driver availability + compound driver listing endpoints."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_update_driver_availability(client, seeded_db):
    res = await client.post(
        "/api/v1/driver/1/availability",
        json={"availability": "OFF_DUTY"},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["id"] == 1
    assert body["availability"] == "OFF_DUTY"


@pytest.mark.asyncio
async def test_update_driver_availability_rejects_invalid_status(client, seeded_db):
    res = await client.post(
        "/api/v1/driver/1/availability",
        json={"availability": "BUSY"},
    )
    assert res.status_code == 422


@pytest.mark.asyncio
async def test_update_missing_driver_returns_404(client, seeded_db):
    res = await client.post(
        "/api/v1/driver/999/availability",
        json={"availability": "AVAILABLE"},
    )
    assert res.status_code == 404


@pytest.mark.asyncio
async def test_list_compound_drivers(client, seeded_db):
    res = await client.get("/api/v1/compound/1/drivers")
    assert res.status_code == 200
    body = res.json()
    assert body["compound_id"] == 1
    assert len(body["drivers"]) == 3
    names = {d["name"] for d in body["drivers"]}
    assert names == {"Ibrahim", "Musah", "Abdul"}
    assert all("availability" in d for d in body["drivers"])


@pytest.mark.asyncio
async def test_list_compound_drivers_missing_compound_404(client, seeded_db):
    res = await client.get("/api/v1/compound/999/drivers")
    assert res.status_code == 404
