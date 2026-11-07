"""
Yoma Triage Emergency Logistics Engine
Single Master Entry Point serving FastAPI Webhooks and the dispatch workers.
"""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.catalog import router as catalog_router
from src.api.cho import router as cho_router
from src.api.driver import router as driver_router
from src.api.errors import install_error_handlers
from src.api.referral import router as referral_router
from src.api.sms_webhook import router as sms_router
from src.api.ussd import router as ussd_router
from src.config import settings
from src.db.database import init_db
from src.services.dispatch_orchestrator import DispatchOrchestrator
from src.services.outbox import OutboxSender
from src.services.referral_expiry import expire_unconfirmed_referrals
from src.services.workers import run_worker_loop


async def run_cascade_work() -> None:
    """One poll of the cascade worker: overdue dispatch steps, then unanswered stale
    referrals past EXPIRE_UNCONFIRMED_HOURS."""
    await DispatchOrchestrator().process_due_dispatches()
    await expire_unconfirmed_referrals()


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.validate_for_startup()
    # Outside development the schema comes only from migrations: alembic upgrade head.
    if settings.is_development:
        await init_db()
    stop_workers = asyncio.Event()
    workers = [
        asyncio.create_task(
            run_worker_loop(
                "cascade",
                run_cascade_work,
                settings.WORKER_POLL_SECONDS,
                stop_workers,
            )
        ),
        asyncio.create_task(
            run_worker_loop(
                "sms-outbox",
                OutboxSender().drain,
                settings.OUTBOX_POLL_SECONDS,
                stop_workers,
            )
        ),
    ]
    yield
    stop_workers.set()
    await asyncio.gather(*workers)
    from src.db.database import engine

    if engine is not None:
        await engine.dispose()


# API docs are served only in development.
_docs_urls: dict[str, Any] = (
    {} if settings.is_development else {"docs_url": None, "redoc_url": None, "openapi_url": None}
)

app = FastAPI(
    title="Yoma Triage Logistics Engine",
    description="Offline-First Emergency Maternal Referral & Transport Broker for Ghana Health Service",
    version="1.0.0",
    lifespan=lifespan,
    **_docs_urls,
)
install_error_handlers(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount USSD & Carrier Webhook API Routers
app.include_router(ussd_router)
app.include_router(referral_router)
app.include_router(sms_router)
app.include_router(driver_router)
app.include_router(catalog_router)
app.include_router(cho_router)


@app.get("/")
def health_check():
    """Health check endpoint for local/server monitoring."""
    env = settings.ENVIRONMENT.strip().lower()
    dev = settings.is_development
    payload: dict[str, Any] = {
        "status": "online",
        "system": "Yoma Triage Emergency Logistics Engine",
        "network_mode": "2G SMS / USSD Enabled",
        "environment": env,
        "at_configured": settings.at_configured,
        "api_auth_required": bool(settings.API_KEY.strip()) or not dev,
    }
    # Avoid advertising webhook URLs on hardened environments.
    if dev:
        payload["public_base_url"] = settings.public_base_url or None
        payload["webhooks"] = {
            "ussd_callback": settings.ussd_callback_url,
            "sms_inbound": settings.sms_inbound_url,
        }
    return payload


if __name__ == "__main__":
    print("--- Starting Yoma Triage Web Gateway on http://0.0.0.0:8000 ---")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
