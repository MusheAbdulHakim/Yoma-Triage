"""Startup refuses configuration that is unsafe for this environment."""
from __future__ import annotations

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
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(settings, "CASCADE_TIER_SECONDS", 5)
    with pytest.raises(RuntimeError, match="Refusing to start"):
        async with main.lifespan(main.app):
            pass
