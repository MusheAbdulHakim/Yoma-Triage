"""Referral API must enforce token privacy and hash validation."""
from __future__ import annotations

from unittest.mock import AsyncMock

import pytest

VALID_PATIENT_HASH = "0123456789abcdef" * 4


@pytest.mark.asyncio
async def test_rejects_invalid_patient_hash(client, seeded_db, sample_referral_payload):
    payload = {**sample_referral_payload, "patient_hash": "not-a-valid-hash"}
    response = await client.post("/api/v1/referral", json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_rejects_uppercase_patient_hash(client, seeded_db, sample_referral_payload):
    payload = {**sample_referral_payload, "patient_hash": VALID_PATIENT_HASH.upper()}
    response = await client.post("/api/v1/referral", json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_accepts_valid_hash_and_omits_patient_name(
    client, seeded_db, sample_referral_payload, monkeypatch
):
    from src.db.models import Dispatch

    async def fake_initiate(session, referral_id):
        dispatch = Dispatch(
            referral_id=referral_id,
            facility_id=1,
            status="TIER1_NOTIFIED",
            current_tier=1,
        )
        session.add(dispatch)
        await session.flush()
        return dispatch

    monkeypatch.setattr(
        "src.api.referral.DispatchOrchestrator.initiate_dispatch",
        AsyncMock(side_effect=fake_initiate),
    )
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke",
        lambda state: {
            "risk_level": "RED",
            "moews_score": 6,
            "clinical_summary": "Critical",
            "compressed_sms_payload": "abc",
        },
    )

    payload = {
        **sample_referral_payload,
        "patient_hash": VALID_PATIENT_HASH,
        "patient_name": "Secret Patient Name",
    }
    create = await client.post("/api/v1/referral", json=payload)
    assert create.status_code == 201
    referral = create.json()["referral"]
    assert referral["patient_hash"] == VALID_PATIENT_HASH
    assert "patient_name" not in referral
    assert "Secret Patient Name" not in str(create.json())

    get_response = await client.get(f"/api/v1/referral/{referral['id']}")
    assert get_response.status_code == 200
    body = get_response.json()
    assert "patient_name" not in body
    assert "Secret Patient Name" not in str(body)
