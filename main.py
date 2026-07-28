"""
Yoma Triage Emergency Logistics Engine
Single Master Entry Point serving FastAPI Webhooks and LangGraph Workflows.
"""
from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from src.agents.coordinator import yoma_graph
from src.api.catalog import router as catalog_router
from src.api.driver import router as driver_router
from src.api.referral import router as referral_router
from src.api.sms_webhook import router as sms_router
from src.api.ussd import router as ussd_router
from src.config import settings
from src.db.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield
    from src.db.database import engine

    await engine.dispose()


app = FastAPI(
    title="Yoma Triage Logistics Engine",
    description="Offline-First Emergency Maternal Referral & Transport Broker for Ghana Health Service",
    version="1.0.0",
    lifespan=lifespan,
)

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


@app.get("/")
def health_check():
    """Health check endpoint for local/server monitoring."""
    env = settings.ENVIRONMENT.strip().lower()
    payload: dict[str, Any] = {
        "status": "online",
        "system": "Yoma Triage Emergency Logistics Engine",
        "network_mode": "2G SMS / USSD Enabled",
        "environment": env,
        "at_configured": settings.at_configured,
        "api_auth_required": bool(settings.API_KEY.strip())
        or env in {"production", "staging"},
    }
    # Avoid advertising webhook URLs on hardened environments.
    if env not in {"production", "staging"}:
        payload["public_base_url"] = settings.public_base_url or None
        payload["webhooks"] = {
            "ussd_callback": settings.ussd_callback_url,
            "sms_inbound": settings.sms_inbound_url,
        }
    return payload


@app.post("/test-referral")
def run_test_referral(payload: dict[str, Any]):
    """
    Dev-only graph smoke endpoint. Disabled when ENVIRONMENT=production.
    Prefer POST /api/v1/referral for real referral + dispatch.
    """
    if settings.ENVIRONMENT.lower() == "production":
        raise HTTPException(status_code=404, detail="Not found")
    result = yoma_graph.invoke(payload)
    return result


if __name__ == "__main__":
    print("--- Starting Yoma Triage Web Gateway on http://0.0.0.0:8000 ---")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
