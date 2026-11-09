"""The dispatch status API names the accepted driver's vehicle, for the CHO's driver card."""
from __future__ import annotations

import pytest

from tests.test_diversion import _refer_and_accept


@pytest.mark.asyncio
async def test_no_vehicle_before_a_driver_accepts(client, seeded_db, sample_referral_payload):
    response = await client.post("/api/v1/referral", json=sample_referral_payload)
    dispatch_id = response.json()["dispatch"]["id"]
    body = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert body["driver_vehicle"] is None


@pytest.mark.asyncio
async def test_accepted_driver_vehicle_is_type_and_description(
    client, db_session, seeded_db, sample_referral_payload
):
    dispatch_id = await _refer_and_accept(client, db_session, sample_referral_payload)
    body = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    # Driver 1 in the seed: Motor-King, "Red tricycle".
    assert body["driver_name"]
    assert body["driver_vehicle"] == "Motor-King, Red tricycle"
