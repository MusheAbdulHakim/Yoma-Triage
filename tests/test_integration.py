"""End-to-end MVP flow: referral → cascade → accept → hospital CONFIRM/DIVERT."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest


@pytest.mark.asyncio
async def test_full_flow_accept_confirm_and_divert(
    client, seeded_db, sample_referral_payload, monkeypatch
):
    monkeypatch.setattr(
        "src.services.dispatch_orchestrator.DispatchOrchestrator.schedule_tier_timeouts",
        lambda self, *a, **k: None,
    )
    monkeypatch.setattr(
        "src.api.referral.yoma_graph.invoke",
        lambda state: {
            "risk_level": "RED",
            "moews_score": 8,
            "clinical_summary": "Critical obstetric emergency",
            "compressed_sms_payload": "ZW5jb2RlZA==",
        },
    )

    # Avoid background MoMo/hospital tasks during accept HTTP path.
    monkeypatch.setattr(
        "src.api.ussd.DispatchOrchestrator.run_accept_side_effects",
        AsyncMock(),
    )
    # Integration uses demo shortcode; ignore sandbox AT_USSD_SERVICE_CODE from .env.
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")

    create = await client.post("/api/v1/referral", json=sample_referral_payload)
    assert create.status_code == 201
    body = create.json()
    referral_id = body["referral"]["id"]
    dispatch_id = body["dispatch"]["id"]
    assert body["referral"]["risk_level"] == "RED"
    assert body["dispatch"]["status"] == "TIER1_NOTIFIED"

    accept = await client.post(
        "/ussd/callback",
        data={
            "session_id": "sess-1",
            "service_code": "*123#",
            "phone_number": "+233240000001",
            "text": "1",
        },
    )
    assert accept.status_code == 200
    assert b"Accepted" in accept.content

    status = await client.get(f"/api/v1/dispatch/{dispatch_id}")
    assert status.status_code == 200
    assert status.json()["status"] == "ACCEPTED"
    assert status.json()["driver_id"] == 1

    confirm = await client.post(
        "/api/v1/sms/inbound",
        json={"from": "+233240000200", "text": f"CONFIRM {dispatch_id}"},
    )
    assert confirm.status_code == 200
    assert confirm.json()["status"] == "CONFIRMED"

    # Re-seed a second accepted dispatch path for DIVERT via unit-level SMS handler
    # after confirming the happy path above. Create another referral + accept.
    payload2 = {
        **sample_referral_payload,
        "client_request_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "patient_hash": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
    }
    create2 = await client.post("/api/v1/referral", json=payload2)
    assert create2.status_code == 201
    dispatch2_id = create2.json()["dispatch"]["id"]

    accept2 = await client.post(
        "/ussd/callback",
        data={
            "session_id": "sess-2",
            "service_code": "*123#",
            "phone_number": "+233240000001",
            "text": "1",
        },
    )
    assert accept2.status_code == 200
    assert b"Accepted" in accept2.content

    divert = await client.post(
        "/api/v1/sms/inbound",
        json={"from": "+233240000200", "text": f"DIVERT {dispatch2_id} 2"},
    )
    assert divert.status_code == 200
    assert divert.json()["status"] == "DIVERTED"
    assert divert.json()["facility_id"] == 2

    diverted = await client.get(f"/api/v1/dispatch/{dispatch2_id}")
    assert diverted.json()["status"] == "DIVERTED"
    assert diverted.json()["facility_id"] == 2

    referral = await client.get(f"/api/v1/referral/{referral_id}")
    assert referral.status_code == 200
    assert referral.json()["id"] == referral_id
