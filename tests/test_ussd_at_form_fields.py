"""USSD callback accepts Africa's Talking camelCase form fields."""
from __future__ import annotations

from unittest.mock import AsyncMock

import pytest


async def _seed_open_referral(client, monkeypatch, request_id: str):
    monkeypatch.setattr(
        "src.services.dispatch_orchestrator.DispatchOrchestrator.schedule_tier_timeouts",
        lambda self, *a, **k: None,
    )
    monkeypatch.setattr(
        "src.api.ussd.DispatchOrchestrator.run_accept_side_effects",
        AsyncMock(),
    )
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke",
        lambda state: {
            "risk_level": "RED",
            "moews_score": 8,
            "clinical_summary": "Critical",
            "compressed_sms_payload": "x",
        },
    )
    create = await client.post(
        "/api/v1/referral",
        json={
            "chps_compound_id": 1,
            "facility_id": 1,
            "patient_hash": "0123456789abcdef" * 4,
            "emergency_type": "Obstetric haemorrhage",
            "gestational_weeks": 38,
            "client_request_id": request_id,
            "vitals": {
                "systolic_bp": 70,
                "diastolic_bp": 50,
                "heart_rate": 140,
                "respiratory_rate": 35,
                "temperature": 37.0,
                "spo2": 92,
                "consciousness_level": "V",
            },
        },
    )
    assert create.status_code == 201
    return create.json()


@pytest.mark.asyncio
async def test_ussd_callback_accepts_africastalking_field_names(
    client, seeded_db, monkeypatch
):
    monkeypatch.setattr(
        "src.api.ussd.settings.AT_USSD_SERVICE_CODE", "*384*99193#"
    )
    await _seed_open_referral(
        client, monkeypatch, "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
    )

    res = await client.post(
        "/ussd/callback",
        data={
            "sessionId": "ATUid_test",
            "serviceCode": "*384*99193#",
            "phoneNumber": "+233240000001",
            "text": "1",
            "networkCode": "62002",
        },
    )
    assert res.status_code == 200, res.text
    assert res.headers["content-type"].startswith("text/plain")
    assert res.text.startswith("END ")
    assert "Accepted" in res.text


@pytest.mark.asyncio
async def test_ussd_first_dial_empty_text_returns_con_menu(client, seeded_db, monkeypatch):
    monkeypatch.setattr(
        "src.api.ussd.settings.AT_USSD_SERVICE_CODE", "*384*99193#"
    )
    res = await client.post(
        "/ussd/callback",
        data={
            "sessionId": "ATUid_menu",
            "serviceCode": "*384*99193#",
            "phoneNumber": "+233240000001",
            "text": "",
        },
    )
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/plain")
    assert res.text.startswith("CON ")
    assert "1. Accept" in res.text


@pytest.mark.asyncio
async def test_ussd_accepts_local_ghana_phone_without_plus(
    client, seeded_db, monkeypatch
):
    monkeypatch.setattr(
        "src.api.ussd.settings.AT_USSD_SERVICE_CODE", "*384*99193#"
    )
    await _seed_open_referral(
        client, monkeypatch, "ffffffff-ffff-ffff-ffff-ffffffffffff"
    )
    res = await client.post(
        "/ussd/callback",
        data={
            "sessionId": "ATUid_local",
            "serviceCode": "*384*99193#",
            "phoneNumber": "0240000001",
            "text": "1",
        },
    )
    assert res.status_code == 200, res.text
    assert "Accepted" in res.text


@pytest.mark.asyncio
async def test_ussd_rejects_unexpected_service_code(client, monkeypatch):
    monkeypatch.setattr(
        "src.api.ussd.settings.AT_USSD_SERVICE_CODE", "*384*99193#"
    )
    res = await client.post(
        "/ussd/callback",
        data={
            "sessionId": "ATUid_bad",
            "serviceCode": "*384*00000#",
            "phoneNumber": "+233240000001",
            "text": "",
        },
    )
    assert res.status_code == 200
    assert res.text.startswith("END ")
    assert "service code" in res.text.lower()


@pytest.mark.asyncio
async def test_ussd_missing_phone_returns_end_not_json(client, monkeypatch):
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    res = await client.post(
        "/ussd/callback",
        data={"sessionId": "x", "serviceCode": "*123#", "text": "1"},
    )
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/plain")
    assert res.text.startswith("END ")
    assert "phoneNumber" in res.text
