"""CORS allowlist for Flutter web demo origins."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_preflight_allowed_origin_gets_acao(client):
    response = await client.options(
        "/api/v1/referral",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:8080"


@pytest.mark.asyncio
async def test_preflight_flutter_chrome_default_port(client):
    response = await client.options(
        "/api/v1/referral",
        headers={
            "Origin": "http://localhost:7357",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:7357"


@pytest.mark.asyncio
async def test_preflight_disallowed_origin_does_not_echo(client):
    response = await client.options(
        "/api/v1/referral",
        headers={
            "Origin": "http://evil.example.com",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert response.headers.get("access-control-allow-origin") != "http://evil.example.com"
