"""API and webhook authentication helpers.

CHO OTP is deferred. Until then:
- Set ``API_KEY`` and send ``X-API-Key`` on CHO/API routes.
- Set ``AT_WEBHOOK_SECRET`` and register AT callbacks with ``?secret=...``
  or header ``X-Webhook-Secret``.

Fail-closed in staging/production when secrets are unset.
"""
from __future__ import annotations

import secrets
from typing import Annotated

from fastapi import Header, HTTPException, Query, Request, status

from src.config import settings


def _env_fail_closed() -> bool:
    return settings.ENVIRONMENT.strip().lower() in {"production", "staging"}


async def require_api_key(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> None:
    """Protect CHO-facing and operational JSON APIs."""
    expected = settings.API_KEY.strip()
    if not expected:
        if _env_fail_closed():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="API_KEY is not configured for this environment",
            )
        return
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing X-API-Key",
        )


async def require_webhook_secret(
    request: Request,
    secret: Annotated[str | None, Query()] = None,
    x_webhook_secret: Annotated[str | None, Header(alias="X-Webhook-Secret")] = None,
) -> None:
    """Protect Africa's Talking USSD/SMS callbacks."""
    expected = settings.AT_WEBHOOK_SECRET.strip()
    if not expected:
        if _env_fail_closed():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="AT_WEBHOOK_SECRET is not configured for this environment",
            )
        return

    provided = (x_webhook_secret or secret or "").strip()
    if not provided or not secrets.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing webhook secret",
        )
