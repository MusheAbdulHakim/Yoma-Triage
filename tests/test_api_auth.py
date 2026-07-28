"""API key and webhook secret enforcement."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_referral_requires_api_key_when_configured(client, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "test-secret-key")
    monkeypatch.setattr("src.config.settings.API_KEY", "test-secret-key")

    denied = await client.get("/api/v1/catalog/referral-graph")
    assert denied.status_code == 401

    ok = await client.get(
        "/api/v1/catalog/referral-graph",
        headers={"X-API-Key": "test-secret-key"},
    )
    assert ok.status_code == 200


@pytest.mark.asyncio
async def test_production_without_api_key_is_unavailable(client, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "")
    monkeypatch.setattr("src.api.deps.settings.ENVIRONMENT", "production")

    res = await client.get("/api/v1/catalog/referral-graph")
    assert res.status_code == 503


@pytest.mark.asyncio
async def test_ussd_webhook_requires_secret_when_configured(client, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.AT_WEBHOOK_SECRET", "hook-secret")
    monkeypatch.setattr("src.config.settings.AT_WEBHOOK_SECRET", "hook-secret")

    denied = await client.post(
        "/ussd/callback",
        data={
            "sessionId": "s1",
            "serviceCode": "*384*99193#",
            "phoneNumber": "+233240000001",
            "text": "",
        },
    )
    assert denied.status_code == 401

    # Unknown driver still returns plain END (auth passed)
    ok = await client.post(
        "/ussd/callback?secret=hook-secret",
        data={
            "sessionId": "s1",
            "serviceCode": "*384*99193#",
            "phoneNumber": "+233240000001",
            "text": "",
        },
    )
    assert ok.status_code == 200
    assert ok.headers["content-type"].startswith("text/plain")


@pytest.mark.asyncio
async def test_health_hides_webhooks_in_production(client, monkeypatch):
    monkeypatch.setattr("main.settings.ENVIRONMENT", "production")
    res = await client.get("/")
    assert res.status_code == 200
    body = res.json()
    assert "webhooks" not in body
    assert body["api_auth_required"] is True
