"""Startup refuses configuration that is unsafe for this environment."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from src.config import DEFAULT_CASCADE_TIER_SECONDS, settings


def test_default_tier_wait_matches_spec():
    assert DEFAULT_CASCADE_TIER_SECONDS == 90


@pytest.mark.parametrize("environment", ["production", "staging", "PRODUCTION "])
def test_short_cascade_refused_outside_development(monkeypatch, environment):
    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 59)
    assert any("CASCADE_TIER_SECONDS" in error for error in settings.startup_errors())


@pytest.mark.parametrize("environment", ["production", "staging"])
def test_sixty_second_cascade_is_allowed(monkeypatch, environment):
    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 60)
    assert not any("CASCADE_TIER_SECONDS" in error for error in settings.startup_errors())


def test_short_cascade_allowed_in_development(monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 5)
    assert not any("CASCADE_TIER_SECONDS" in error for error in settings.startup_errors())


@pytest.mark.asyncio
async def test_lifespan_refuses_before_touching_the_database(monkeypatch):
    import main

    async def fail_if_called():
        raise AssertionError("init_db must not run on a refused start")

    monkeypatch.setattr(main, "init_db", fail_if_called)
    _configure_production(monkeypatch)
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 5)
    with pytest.raises(RuntimeError, match="Refusing to start"):
        async with main.lifespan(main.app):
            pass


def _configure_production(monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(settings, "API_KEY", "key")
    monkeypatch.setattr(settings, "AT_WEBHOOK_SECRET", "secret")
    monkeypatch.setattr(settings, "AT_API_KEY", "at-key")
    monkeypatch.setattr(settings, "AT_USERNAME", "yoma")
    monkeypatch.setattr(settings, "AT_USSD_SERVICE_CODE", "*384*1#")
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 90)


def test_complete_production_config_starts(monkeypatch):
    _configure_production(monkeypatch)
    assert settings.startup_errors() == []


@pytest.mark.parametrize(
    "missing",
    ["API_KEY", "AT_WEBHOOK_SECRET", "AT_API_KEY", "AT_USERNAME", "AT_USSD_SERVICE_CODE"],
)
@pytest.mark.parametrize("value", ["", "   "])
def test_each_required_secret_is_enforced(monkeypatch, missing, value):
    _configure_production(monkeypatch)
    monkeypatch.setattr(settings, missing, value)
    assert any(missing in error for error in settings.startup_errors())


def test_sandbox_refused_in_production_allowed_in_staging(monkeypatch):
    _configure_production(monkeypatch)
    monkeypatch.setattr(settings, "AT_USERNAME", "sandbox")
    assert any("sandbox" in error for error in settings.startup_errors())
    monkeypatch.setattr(settings, "ENVIRONMENT", "staging")
    assert settings.startup_errors() == []


@pytest.mark.parametrize("environment", ["", "dev", "develop", "prod", "test", "Staging2"])
def test_unrecognised_environment_gets_production_behaviour(monkeypatch, environment):
    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(settings, "API_KEY", "")
    assert settings.is_development is False
    assert any("API_KEY" in error for error in settings.startup_errors())


def test_explicit_development_needs_no_secrets(monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", " Development ")
    monkeypatch.setattr(settings, "API_KEY", "")
    assert settings.is_development is True
    assert settings.startup_errors() == []


def _import_main_in_subprocess(environment: str | None) -> dict:
    env = {k: v for k, v in os.environ.items() if k != "ENVIRONMENT"}
    if environment is not None:
        env["ENVIRONMENT"] = environment
    code = (
        "import json, main; from fastapi.testclient import TestClient; "
        "from src.config import settings; c = TestClient(main.app); "
        "print(json.dumps({'env': settings.ENVIRONMENT, "
        "'docs': c.get('/docs').status_code, 'redoc': c.get('/redoc').status_code, "
        "'openapi': c.get('/openapi.json').status_code}))"
    )
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        env=env,
        cwd=Path(__file__).resolve().parents[1],
        timeout=120,
        check=True,
    )
    return json.loads(result.stdout.strip().splitlines()[-1])


@pytest.mark.parametrize("environment", [None, "production", "staging", "dev"])
def test_docs_disabled_unless_development(environment):
    app_info = _import_main_in_subprocess(environment)
    assert app_info["docs"] == 404
    assert app_info["redoc"] == 404
    assert app_info["openapi"] == 404
    if environment is None:
        assert app_info["env"] == "production"


def test_docs_enabled_in_development():
    app_info = _import_main_in_subprocess("development")
    assert app_info["docs"] == 200
    assert app_info["openapi"] == 200


@pytest.mark.asyncio
async def test_test_referral_is_gone(client):
    response = await client.post("/test-referral", json={"vitals": {}})
    assert response.status_code == 404


@pytest.mark.asyncio
@pytest.mark.parametrize("environment", ["production", "staging", "typo"])
async def test_no_silent_mock_sends_outside_development(monkeypatch, environment):
    from src.services.messaging_gateway import MessagingGateway

    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(settings, "AT_API_KEY", "")

    sms = await MessagingGateway().send_sms("+233240000001", "hello", 1, "driver")
    voice = await MessagingGateway().initiate_voice("+233240000001", "hello", 1, "driver")

    assert sms["status"] == "FAILED"
    assert voice["status"] == "FAILED"


@pytest.mark.asyncio
async def test_mock_sends_remain_in_development(monkeypatch):
    from src.services.messaging_gateway import MessagingGateway

    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "AT_API_KEY", "")

    sms = await MessagingGateway().send_sms("+233240000001", "hello", 1, "driver")

    assert sms["status"] == "MOCKED"


@pytest.mark.asyncio
async def test_unrecognised_environment_keeps_auth_on(client, monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", "typo")
    monkeypatch.setattr(settings, "API_KEY", "")
    monkeypatch.setattr(settings, "AT_WEBHOOK_SECRET", "")

    assert (await client.get("/api/v1/catalog/referral-graph")).status_code == 503
    assert (await client.post("/ussd/callback", data={"phoneNumber": "1"})).status_code == 503


def test_late_claim_window_defaults_to_45_minutes(monkeypatch):
    monkeypatch.delenv("LATE_CLAIM_WINDOW_MINUTES", raising=False)
    env = {k: v for k, v in os.environ.items() if k != "LATE_CLAIM_WINDOW_MINUTES"}
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            "from src.config import settings; print(settings.LATE_CLAIM_WINDOW_MINUTES)",
        ],
        capture_output=True,
        text=True,
        env=env,
        cwd=Path(__file__).resolve().parents[1],
        timeout=60,
        check=True,
    )
    assert result.stdout.strip().splitlines()[-1] == "45"
