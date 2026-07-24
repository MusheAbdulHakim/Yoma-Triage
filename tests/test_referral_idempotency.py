"""Idempotent referral create via client_request_id + AI screen fields."""
from __future__ import annotations

from unittest.mock import AsyncMock

import pytest


@pytest.mark.asyncio
async def test_create_referral_persists_ai_screen_fields(
    client, seeded_db, sample_referral_payload, monkeypatch
):
    from src.db.models import Dispatch

    async def fake_initiate(*args):
        session = args[-2]
        referral_id = args[-1]
        dispatch = Dispatch(
            referral_id=referral_id,
            facility_id=1,
            status="TIER1_NOTIFIED",
            current_tier=1,
        )
        session.add(dispatch)
        await session.flush()
        return dispatch

    initiate = AsyncMock(side_effect=fake_initiate)
    monkeypatch.setattr(
        "src.api.referral.DispatchOrchestrator.initiate_dispatch",
        initiate,
    )
    monkeypatch.setattr(
        "src.api.referral.relayai_graph.invoke",
        lambda state: {
            "risk_level": "RED",
            "moews_score": 6,
            "clinical_summary": "Critical",
            "compressed_sms_payload": "abc",
        },
    )

    payload = {
        **sample_referral_payload,
        "ai_screen_result": "RED",
        "ai_confidence": 0.82,
    }
    res = await client.post("/api/v1/referral", json=payload)
    assert res.status_code == 201
    body = res.json()
    referral = body["referral"]
    assert referral["client_request_id"] == sample_referral_payload["client_request_id"]
    assert referral["ai_screen_result"] == "RED"
    assert referral["ai_confidence"] == pytest.approx(0.82)
    assert initiate.await_count == 1


@pytest.mark.asyncio
async def test_duplicate_client_request_id_is_idempotent_no_second_cascade(
    client, seeded_db, sample_referral_payload, monkeypatch
):
    from src.db.models import Dispatch

    async def fake_initiate(*args):
        session = args[-2]
        referral_id = args[-1]
        dispatch = Dispatch(
            referral_id=referral_id,
            facility_id=1,
            status="TIER1_NOTIFIED",
            current_tier=1,
        )
        session.add(dispatch)
        await session.flush()
        return dispatch

    initiate = AsyncMock(side_effect=fake_initiate)
    monkeypatch.setattr(
        "src.api.referral.DispatchOrchestrator.initiate_dispatch",
        initiate,
    )
    monkeypatch.setattr(
        "src.api.referral.relayai_graph.invoke",
        lambda state: {
            "risk_level": "RED",
            "moews_score": 6,
            "clinical_summary": "Critical",
            "compressed_sms_payload": "abc",
        },
    )

    payload = {
        **sample_referral_payload,
        "ai_screen_result": "RED",
        "ai_confidence": 0.82,
    }
    first = await client.post("/api/v1/referral", json=payload)
    second = await client.post("/api/v1/referral", json=payload)

    assert first.status_code == 201
    assert second.status_code in (200, 201)
    assert first.json()["referral"]["id"] == second.json()["referral"]["id"]
    assert second.json()["referral"]["client_request_id"] == payload["client_request_id"]
    assert second.json()["dispatch"] is not None
    assert second.json().get("idempotent") is True
    assert initiate.await_count == 1
