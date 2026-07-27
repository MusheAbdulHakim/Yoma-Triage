"""Gate /test-referral to non-production environments."""
from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.mark.asyncio
async def test_test_referral_allowed_in_development(monkeypatch):
    from main import app
    from src.config import settings

    monkeypatch.setattr(settings, "ENVIRONMENT", "development")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/test-referral",
            json={
                "chps_id": "1",
                "patient_hash": "0123456789abcdef" * 4,
                "gestational_weeks": 36,
                "vitals": {
                    "systolic_bp": 120,
                    "diastolic_bp": 80,
                    "heart_rate": 80,
                    "respiratory_rate": 18,
                    "temperature": 37.0,
                    "spo2": 98,
                    "consciousness_level": "A",
                },
                "errors": [],
            },
        )
    assert res.status_code == 200
    body = res.json()
    assert "risk_level" in body
    assert "moews_score" in body


@pytest.mark.asyncio
async def test_test_referral_blocked_in_production(monkeypatch):
    from main import app
    from src.config import settings

    monkeypatch.setattr(settings, "ENVIRONMENT", "production")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/test-referral", json={"vitals": {}})
    assert res.status_code == 404
    assert "detail" in res.json()
