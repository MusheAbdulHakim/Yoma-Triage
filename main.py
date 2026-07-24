"""
RelayAI Emergency Logistics Engine
Single Master Entry Point serving FastAPI Webhooks and LangGraph Workflows.
"""
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from src.api.referral import router as referral_router
from src.api.sms_webhook import router as sms_router
from src.api.ussd import router as ussd_router
from src.agents.coordinator import relayai_graph
from src.db.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="RelayAI Logistics Engine",
    description="Offline-First Emergency Maternal Referral & Transport Broker for Ghana Health Service",
    version="1.0.0",
    lifespan=lifespan,
)

# Mount USSD & Carrier Webhook API Routers
app.include_router(ussd_router)
app.include_router(referral_router)
app.include_router(sms_router)

@app.get("/")
def health_check():
    """Health check endpoint for local/server monitoring."""
    return {
        "status": "online",
        "system": "RelayAI Emergency Logistics Engine",
        "network_mode": "2G SMS / USSD Enabled"
    }

@app.post("/test-referral")
def run_test_referral(payload: dict):
    """
    HTTP endpoint to trigger a test run of the multi-agent graph.
    Pass JSON with vitals to test clinical reasoning and 2G SMS encoding.
    """
    result = relayai_graph.invoke(payload)
    return result

if __name__ == "__main__":
    # Start the FastAPI server on port 8000
    print("--- Starting RelayAI Web Gateway on http://0.0.0.0:8000 ---")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)