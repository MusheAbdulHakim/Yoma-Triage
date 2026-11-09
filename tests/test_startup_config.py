"""Startup refuses configuration that is unsafe for this environment."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from src import parameters
from src.config import settings

REPO = Path(__file__).resolve().parents[1]


def test_default_tier_wait_matches_spec():
    assert parameters.CASCADE_TIER_SECONDS == 90


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


def test_database_url_is_required_in_every_environment(monkeypatch):
    for environment in ("development", "production"):
        monkeypatch.setattr(settings, "ENVIRONMENT", environment)
        monkeypatch.setattr(settings, "DATABASE_URL", "  ")
        assert "DATABASE_URL must be set" in settings.startup_errors()


def test_no_default_database_credential_in_config():
    source = (Path(__file__).resolve().parents[1] / "src" / "config.py").read_text()
    assert "postgres:postgres" not in source
    assert "postgresql+asyncpg://" not in source


def _clean_env(**extra) -> dict:
    drop = {"ENVIRONMENT", "DATABASE_URL"}
    return {k: v for k, v in os.environ.items() if k not in drop} | extra


def test_app_imports_without_a_database_url_and_refuses_clearly():
    code = (
        "import asyncio, main\n"
        "async def run():\n"
        "    async with main.lifespan(main.app):\n"
        "        pass\n"
        "asyncio.run(run())\n"
    )
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        env=_clean_env(ENVIRONMENT="development"),
        cwd=Path(__file__).resolve().parents[1],
        timeout=120,
    )
    assert result.returncode != 0
    assert "Refusing to start: DATABASE_URL must be set" in result.stderr


@pytest.mark.parametrize("environment", [None, "production", "staging", "dev"])
def test_seed_refuses_outside_development(environment):
    extra = {"DATABASE_URL": "postgresql+asyncpg://nobody@127.0.0.1:1/x"}
    if environment is not None:
        extra["ENVIRONMENT"] = environment
    result = subprocess.run(
        [sys.executable, "-m", "src.db.seed"],
        capture_output=True,
        text=True,
        env=_clean_env(**extra),
        cwd=Path(__file__).resolve().parents[1],
        timeout=60,
    )
    assert result.returncode == 1
    assert "Refusing to seed" in result.stderr
    assert "ENVIRONMENT=development" in result.stderr


def test_seed_refuses_without_a_database_url():
    result = subprocess.run(
        [sys.executable, "-m", "src.db.seed"],
        capture_output=True,
        text=True,
        env=_clean_env(ENVIRONMENT="development"),
        cwd=Path(__file__).resolve().parents[1],
        timeout=60,
    )
    assert result.returncode == 1
    assert "DATABASE_URL must be set" in result.stderr


def test_suite_never_reads_a_developers_dotenv(tmp_path):
    """A .env can't change what the tests check: YOMA_SKIP_DOTENV=1 (set by conftest, and
    inherited by every server and script a test starts) stops it loading. Without the
    switch, the same .env is read, as in normal use."""
    (tmp_path / ".env").write_text("ENVIRONMENT=production\nAT_API_KEY=from-dotenv\n")
    code = (
        f"import json, sys; sys.path.insert(0, {str(REPO)!r}); "
        "from src.config import settings; "
        "print(json.dumps([settings.ENVIRONMENT, settings.AT_API_KEY]))"
    )
    base = {k: v for k, v in os.environ.items() if k not in {"ENVIRONMENT", "AT_API_KEY"}}

    skipped = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, cwd=tmp_path,
        env=base | {"YOMA_SKIP_DOTENV": "1"}, timeout=60, check=True,
    )
    assert json.loads(skipped.stdout.strip().splitlines()[-1]) == ["production", ""], (
        "nothing from .env: the defaults"
    )
    assert "from-dotenv" not in skipped.stdout

    read = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, cwd=tmp_path,
        env={k: v for k, v in base.items() if k != "YOMA_SKIP_DOTENV"}, timeout=60, check=True,
    )
    assert json.loads(read.stdout.strip().splitlines()[-1]) == ["production", "from-dotenv"]


def test_conftest_starts_the_suite_from_a_known_environment():
    assert os.environ["YOMA_SKIP_DOTENV"] == "1"
    assert os.environ["ENVIRONMENT"] == "development"
    assert settings.AT_API_KEY == "" and not settings.at_configured, "no real SMS credentials"
