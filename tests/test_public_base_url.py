"""PUBLIC_BASE_URL drives webhook URLs — never hardcode ngrok hosts."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_health_exposes_webhook_urls_from_public_base(client, monkeypatch):
    monkeypatch.setattr(
        "main.settings.PUBLIC_BASE_URL",
        "https://example-tunnel.ngrok-free.app/",
    )
    res = await client.get("/")
    assert res.status_code == 200
    body = res.json()
    assert body["public_base_url"] == "https://example-tunnel.ngrok-free.app"
    assert body["webhooks"]["ussd_callback"] == (
        "https://example-tunnel.ngrok-free.app/ussd/callback"
    )
    assert body["webhooks"]["sms_inbound"] == (
        "https://example-tunnel.ngrok-free.app/api/v1/sms/inbound"
    )


def test_cors_includes_public_base_url():
    from src.config import Settings

    s = Settings.__new__(Settings)
    s.PUBLIC_BASE_URL = "https://tunnel.example"
    s.CORS_ORIGINS = "http://localhost:8080"
    assert "https://tunnel.example" in s.cors_origins
    assert "http://localhost:8080" in s.cors_origins


def test_webhook_urls_none_without_public_base():
    from src.config import Settings

    s = Settings.__new__(Settings)
    s.PUBLIC_BASE_URL = ""
    assert s.public_base_url == ""
    assert s.ussd_callback_url is None
    assert s.sms_inbound_url is None
