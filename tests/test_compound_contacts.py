"""What the CHO app saves for the offline manual fallback (item 2, BUG-17)."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import Driver


@pytest.mark.asyncio
async def test_contacts_lists_the_compounds_drivers_and_all_facility_phones(client, seeded_db):
    response = await client.get("/api/v1/compound/1/contacts")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["drivers"] == [
        {"name": "Ibrahim", "phone": "+233240000001", "is_motor_king": True},
        {"name": "Musah", "phone": "+233240000002", "is_motor_king": True},
        {"name": "Abdul", "phone": "+233240000003", "is_motor_king": False},
    ]
    assert {facility["phone"] for facility in body["facilities"]} == {
        "+233240000200",
        "+233240000201",
    }
    assert {"id", "name", "phone"} == set(body["facilities"][0])


@pytest.mark.asyncio
async def test_inactive_drivers_are_left_out(client, seeded_db, db_session):
    driver = await db_session.scalar(select(Driver).where(Driver.phone == "+233240000002"))
    driver.is_active = False
    await db_session.commit()
    response = await client.get("/api/v1/compound/1/contacts")
    assert "+233240000002" not in {d["phone"] for d in response.json()["drivers"]}


@pytest.mark.asyncio
async def test_off_duty_drivers_stay_listed(client, seeded_db, db_session):
    """A CHO calling by hand may still reach a driver the cascade wouldn't offer to."""
    driver = await db_session.scalar(select(Driver).where(Driver.phone == "+233240000002"))
    driver.availability = "OFF_DUTY"
    await db_session.commit()
    response = await client.get("/api/v1/compound/1/contacts")
    assert "+233240000002" in {d["phone"] for d in response.json()["drivers"]}


@pytest.mark.asyncio
async def test_unknown_compound_is_404(client, seeded_db):
    assert (await client.get("/api/v1/compound/999/contacts")).status_code == 404


@pytest.mark.asyncio
async def test_contacts_need_the_api_key(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "secret")
    assert (await client.get("/api/v1/compound/1/contacts")).status_code == 401
