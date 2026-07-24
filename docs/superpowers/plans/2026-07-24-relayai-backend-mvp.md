# RelayAI Backend Hackathon MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend-only hackathon demo: referral → MOEWS/RAG → cascade dispatch → USSD accept/decline → mock MoMo log → hospital SMS (mock or AT sandbox), driven by `scripts/demo_flow.py`.

**Architecture:** FastAPI + LangGraph clinical path (MOEWS + RAG; Gemini optional) + deterministic `DispatchOrchestrator` + `MessagingGateway` (AT sandbox or mock) + Supabase PostgreSQL. Flutter deferred.

**Tech Stack:** Python 3.11+, FastAPI, SQLAlchemy asyncio + asyncpg, LangGraph, ChromaDB, Pydantic, Africa's Talking (optional), pytest, httpx

**Spec:** `docs/superpowers/specs/2026-07-24-relayai-backend-mvp-design.md`

## Global Constraints

- No Flutter / YAMNet / `emergency_contact` table in this plan
- USSD `/ussd/callback` must return within ~10s: no LangGraph, no await AT HTTP, no long locks inside the request
- Idempotency key for USSD accept: `(dispatch_id, driver_id)`
- Claim jobs with `SELECT … FOR UPDATE`; escalate on decline only if status still `TIER*_NOTIFIED`
- MoMo always mocked; first accept only logs `momo_escrow` to `dispatch_log`
- MOEWS null vitals → `risk_level=UNKNOWN`, never crash referral
- LLM failure must not fail referral
- DB: `create_all` on startup; no Alembic
- Cascade timers: `CASCADE_TIER_SECONDS` default 5–10 (demo)
- Requires `python-multipart` for USSD form posts

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `.env.example` | Env template |
| `src/config.py` | Settings |
| `src/db/database.py` | Async engine, session, `init_db` |
| `src/db/models.py` | SQLAlchemy models |
| `src/db/seed.py` | Demo seeder |
| `data/demo_data.json` | Seed payload |
| `src/tools/moews_calculator.py` | Spec-aligned MOEWS + null guard |
| `src/services/messaging_gateway.py` | AT or mock SMS/Voice + log |
| `src/services/driver_pool.py` | Available drivers by tier |
| `src/services/hospital_notifier.py` | Pre-arrival / divert messages |
| `src/services/dispatch_orchestrator.py` | Cascade, accept, decline, timeouts |
| `src/api/referral.py` | Referral + dispatch GET/POST |
| `src/api/ussd.py` | Fast USSD callback |
| `src/api/sms_webhook.py` | Hospital CONFIRM/DIVERT |
| `src/agents/coordinator.py` | Wire clinical → prepare_dispatch |
| `src/agents/clinical_agent.py` | MOEWS + RAG + optional Gemini |
| `main.py` | App, routers, startup `init_db` |
| `scripts/demo_flow.py` | Judge timeline demo |
| `tests/test_moews.py` | MOEWS unit tests |
| `tests/test_sms_codec.py` | Codec round-trip |
| `tests/test_ussd_idempotency.py` | Idempotency + claim races |
| `tests/test_dispatch.py` | Cascade / decline / hospital |
| `requirements.txt` | Deps including multipart, asyncpg |

---

### Task 1: Dependencies and configuration

**Files:**
- Modify: `requirements.txt`
- Create: `.env.example`
- Modify: `src/config.py`
- Create: `src/__init__.py` (empty if missing)
- Create: `src/api/__init__.py`, `src/services/__init__.py`, `src/db/__init__.py`, `src/agents/__init__.py`, `src/tools/__init__.py`, `src/rag/__init__.py` as needed

**Interfaces:**
- Produces: `settings.DATABASE_URL`, `settings.AT_API_KEY`, `settings.AT_USERNAME`, `settings.AT_SENDER_ID`, `settings.CASCADE_TIER_SECONDS`, `settings.ENVIRONMENT`

- [ ] **Step 1: Update `requirements.txt`**

Append (keep existing packages; do not remove LangGraph stack):

```
python-multipart>=0.0.9
sqlalchemy[asyncio]>=2.0.30
asyncpg>=0.29.0
httpx>=0.27.0
pytest>=8.0.0
pytest-asyncio>=0.23.0
```

- [ ] **Step 2: Create `.env.example`**

```
ENVIRONMENT=development
LOG_LEVEL=INFO
DATABASE_URL=postgresql+asyncpg://postgres:postgres@db.example.supabase.co:5432/postgres
AT_API_KEY=
AT_USERNAME=sandbox
AT_SENDER_ID=RELAYAI
GEMINI_API_KEY=
MOMO_API_URL=https://sandbox.momodeveloper.mtn.com
MOMO_PRIMARY_KEY=
CASCADE_TIER_SECONDS=5
VECTOR_STORE_DIR=./data/vector_store
```

- [ ] **Step 3: Update `src/config.py`**

```python
"""Central configuration management loading from environment variables."""
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEFAULT_GEMINI_MODEL: str = "gemini-1.5-flash"
    VECTOR_STORE_DIR: str = os.getenv("VECTOR_STORE_DIR", "./data/vector_store")
    MOMO_API_URL: str = os.getenv("MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MOMO_PRIMARY_KEY: str = os.getenv("MOMO_PRIMARY_KEY", "")
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/relayai",
    )
    AT_API_KEY: str = os.getenv("AT_API_KEY", "")
    AT_USERNAME: str = os.getenv("AT_USERNAME", "sandbox")
    AT_SENDER_ID: str = os.getenv("AT_SENDER_ID", "RELAYAI")
    CASCADE_TIER_SECONDS: int = int(os.getenv("CASCADE_TIER_SECONDS", "5"))

    @property
    def at_configured(self) -> bool:
        return bool(self.AT_API_KEY and self.AT_USERNAME)

settings = Settings()
```

- [ ] **Step 4: Verify config loads**

Run: `cd /var/www/html/unicef && ./venv/bin/python -c "from src.config import settings; print(settings.ENVIRONMENT, settings.CASCADE_TIER_SECONDS)"`

Expected: `development 5`

- [ ] **Step 5: Commit**

```bash
git add requirements.txt .env.example src/config.py src/__init__.py src/*/__init__.py
git commit -m "chore: add backend MVP config and multipart/asyncpg deps"
```

---

### Task 2: Database layer and models

**Files:**
- Modify: `src/db/database.py`
- Modify: `src/db/models.py`
- Test: `tests/test_models_import.py`

**Interfaces:**
- Produces: `Base`, `get_db`, `init_db`, models `CHPSCompound`, `Driver`, `Facility`, `Referral`, `Dispatch`, `DispatchLog`, `Wallet`, `AuditLog`
- Consumes: `settings.DATABASE_URL`

- [ ] **Step 1: Write failing import test**

Create `tests/test_models_import.py`:

```python
def test_models_register_tables():
    from src.db.models import Base
    names = set(Base.metadata.tables.keys())
    for required in {
        "chps_compounds", "drivers", "facilities", "referrals",
        "dispatches", "dispatch_logs", "wallets", "audit_logs",
    }:
        assert required in names
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m pytest tests/test_models_import.py -v`

Expected: FAIL (empty or incomplete models)

- [ ] **Step 3: Implement `src/db/database.py`**

```python
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from src.config import settings

engine = create_async_engine(settings.DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session

async def init_db() -> None:
    from src.db import models  # noqa: F401 — register models
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
```

Note: If `Base` lives in `database.py`, models must import `Base` from there. Prefer single `Base` in `database.py` and have models import it (update test to import models after).

- [ ] **Step 4: Implement `src/db/models.py`**

```python
from datetime import datetime
from typing import Optional
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, JSON, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from src.db.database import Base

class CHPSCompound(Base):
    __tablename__ = "chps_compounds"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    zone: Mapped[str] = mapped_column(String(120))
    latitude: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    longitude: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    cho_phone: Mapped[str] = mapped_column(String(32))
    drivers: Mapped[list["Driver"]] = relationship(back_populates="compound")

class Driver(Base):
    __tablename__ = "drivers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(32), unique=True)
    vehicle_type: Mapped[str] = mapped_column(String(64))
    vehicle_desc: Mapped[str] = mapped_column(String(120), default="")
    chps_compound_id: Mapped[int] = mapped_column(ForeignKey("chps_compounds.id"))
    is_motor_king: Mapped[bool] = mapped_column(Boolean, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    availability: Mapped[str] = mapped_column(String(32), default="AVAILABLE")  # AVAILABLE|ON_TRIP|OFF_DUTY
    compound: Mapped["CHPSCompound"] = relationship(back_populates="drivers")

class Facility(Base):
    __tablename__ = "facilities"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(160))
    type: Mapped[str] = mapped_column(String(64), default="district_hospital")
    phone: Mapped[str] = mapped_column(String(32))
    district: Mapped[str] = mapped_column(String(120))
    has_maternity: Mapped[bool] = mapped_column(Boolean, default=True)
    has_icu: Mapped[bool] = mapped_column(Boolean, default=False)

class Referral(Base):
    __tablename__ = "referrals"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    chps_compound_id: Mapped[int] = mapped_column(ForeignKey("chps_compounds.id"))
    facility_id: Mapped[int] = mapped_column(ForeignKey("facilities.id"))
    patient_hash: Mapped[str] = mapped_column(String(64))
    patient_name: Mapped[str] = mapped_column(String(120), default="Unknown")
    patient_age: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    patient_gender: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    emergency_type: Mapped[str] = mapped_column(String(64))
    severity: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    moews_score: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    risk_level: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    clinical_summary: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    compressed_sms_payload: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="CREATED")
    vitals_json: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    initiated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

class Dispatch(Base):
    __tablename__ = "dispatches"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referral_id: Mapped[int] = mapped_column(ForeignKey("referrals.id"), unique=True)
    driver_id: Mapped[Optional[int]] = mapped_column(ForeignKey("drivers.id"), nullable=True)
    facility_id: Mapped[int] = mapped_column(ForeignKey("facilities.id"))
    status: Mapped[str] = mapped_column(String(32), default="PENDING")
    # PENDING|TIER1_NOTIFIED|TIER2_NOTIFIED|ACCEPTED|HOSPITAL_NOTIFIED|COMPLETED|DIVERTED|FAILED
    current_tier: Mapped[int] = mapped_column(Integer, default=0)
    declined_driver_ids: Mapped[list] = mapped_column(JSON, default=list)
    initiated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    driver_assigned_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

class DispatchLog(Base):
    __tablename__ = "dispatch_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"))
    action: Mapped[str] = mapped_column(String(64))
    target_phone: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    target_role: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    response: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    metadata_json: Mapped[Optional[dict]] = mapped_column("metadata", JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

class Wallet(Base):
    __tablename__ = "wallets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referral_id: Mapped[int] = mapped_column(ForeignKey("referrals.id"))
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"))
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(8), default="GHS")
    source: Mapped[str] = mapped_column(String(64), default="community_fund_mock")
    status: Mapped[str] = mapped_column(String(32), default="INITIAL_DISBURSED")
    transaction_id: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entity_type: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(64))
    actor_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    metadata_json: Mapped[Optional[dict]] = mapped_column("metadata", JSON, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

If `database.py` also defined `Base`, remove duplicate — models import `Base` from `database.py` only. Update `init_db` accordingly.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m pytest tests/test_models_import.py -v`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/db/database.py src/db/models.py tests/test_models_import.py
git commit -m "feat: add async SQLAlchemy models for RelayAI backend MVP"
```

---

### Task 3: Demo seed data

**Files:**
- Create: `data/demo_data.json`
- Create: `src/db/seed.py`

**Interfaces:**
- Produces: seed script inserting 3 compounds, ≥5 drivers (Motor-King + fallback), ≥2 facilities
- Consumes: models + `async_session`

- [ ] **Step 1: Create `data/demo_data.json`**

```json
{
  "compounds": [
    {"id": 1, "name": "Tamale South CHPS", "zone": "Tamale Metro", "latitude": 9.403, "longitude": -0.842, "cho_phone": "+233240000100"},
    {"id": 2, "name": "Navrongo Central CHPS", "zone": "Kassena-Nankana East", "latitude": 10.895, "longitude": -1.092, "cho_phone": "+233240000101"},
    {"id": 3, "name": "Savelugu CHPS", "zone": "Savelugu Municipal", "latitude": 9.624, "longitude": -0.825, "cho_phone": "+233240000102"}
  ],
  "facilities": [
    {"id": 1, "name": "Tamale Teaching Hospital", "type": "teaching_hospital", "phone": "+233240000200", "district": "Tamale", "has_maternity": true, "has_icu": true},
    {"id": 2, "name": "Navrongo War Memorial Hospital", "type": "district_hospital", "phone": "+233240000201", "district": "Kassena-Nankana East", "has_maternity": true, "has_icu": false},
    {"id": 3, "name": "Savelugu Municipal Hospital", "type": "municipal_hospital", "phone": "+233240000202", "district": "Savelugu", "has_maternity": true, "has_icu": false}
  ],
  "drivers": [
    {"name": "Ibrahim", "phone": "+233240000001", "vehicle_type": "Motor-King", "vehicle_desc": "Red tricycle", "chps_compound_id": 1, "is_motor_king": true},
    {"name": "Musah", "phone": "+233240000002", "vehicle_type": "Motor-King", "vehicle_desc": "Blue tricycle", "chps_compound_id": 1, "is_motor_king": true},
    {"name": "Abdul", "phone": "+233240000003", "vehicle_type": "motorcycle", "vehicle_desc": "Black Honda", "chps_compound_id": 1, "is_motor_king": false},
    {"name": "Kwame", "phone": "+233240000004", "vehicle_type": "Motor-King", "vehicle_desc": "Yellow tricycle", "chps_compound_id": 2, "is_motor_king": true},
    {"name": "Yakubu", "phone": "+233240000005", "vehicle_type": "pickup", "vehicle_desc": "White Toyota", "chps_compound_id": 2, "is_motor_king": false}
  ]
}
```

- [ ] **Step 2: Implement `src/db/seed.py`**

```python
"""Seed demo CHPS compounds, drivers, and hospitals."""
import asyncio
import json
from pathlib import Path
from sqlalchemy import select
from src.db.database import async_session, init_db
from src.db.models import CHPSCompound, Driver, Facility

DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "demo_data.json"

async def seed() -> None:
    await init_db()
    raw = json.loads(DATA_PATH.read_text())
    async with async_session() as session:
        existing = await session.scalar(select(CHPSCompound).limit(1))
        if existing:
            print("Seed skipped: data already present")
            return
        for c in raw["compounds"]:
            session.add(CHPSCompound(**c))
        for f in raw["facilities"]:
            session.add(Facility(**f))
        await session.flush()
        for d in raw["drivers"]:
            session.add(Driver(**d, availability="AVAILABLE", is_active=True))
        await session.commit()
        print(
            f"Seeded {len(raw['compounds'])} compounds, "
            f"{len(raw['drivers'])} drivers, {len(raw['facilities'])} facilities"
        )

if __name__ == "__main__":
    asyncio.run(seed())
```

- [ ] **Step 3: Run seeder (requires valid `DATABASE_URL` in `.env`)**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m src.db.seed`

Expected: `Seeded 3 compounds, 5 drivers, 3 facilities` (or skip message)

- [ ] **Step 4: Commit**

```bash
git add data/demo_data.json src/db/seed.py
git commit -m "feat: add Northern Ghana demo seed data"
```

---

### Task 4: MOEWS calculator (spec-aligned) + tests

**Files:**
- Modify: `src/tools/moews_calculator.py`
- Create: `tests/test_moews.py`
- Modify: `src/agents/state.py` (add optional spo2 if needed)

**Interfaces:**
- Produces: `calculate_moews(sbp, dbp, hr, rr, temp, spo2=None, consciousness="A") -> {moews_score, risk_level}` where risk_level ∈ {GREEN, YELLOW, RED, UNKNOWN}
- Consumes: none

- [ ] **Step 1: Write failing tests**

Create `tests/test_moews.py`:

```python
from src.tools.moews_calculator import calculate_moews

def test_normal_vitals_green():
    result = calculate_moews.invoke({
        "sbp": 120, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["moews_score"] == 0
    assert result["risk_level"] == "GREEN"

def test_critical_vitals_red():
    result = calculate_moews.invoke({
        "sbp": 70, "dbp": 50, "hr": 140, "rr": 35, "temp": 39.5, "spo2": 85, "consciousness": "V"
    })
    assert result["moews_score"] >= 5
    assert result["risk_level"] == "RED"

def test_null_vitals_unknown():
    result = calculate_moews.invoke({
        "sbp": None, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m pytest tests/test_moews.py -v`

Expected: FAIL (old thresholds / no null guard / wrong labels)

- [ ] **Step 3: Rewrite `calculate_moews`**

Implement scoring per design/product:

- SBP: `<80 or >150` → 3; `80–90 or 140–150` → 1; else 0 (align to product table; document chosen bands in docstring)
- DBP: `>100` → 3; `90–100` → 1; `<60` → treat as elevated risk per clinical judgment → 1 or 3 as product table
- HR: `<50 or >130` → 3; `50–60 or 110–130` → 1
- RR: `<10 or >30` → 3; `10–14 or 24–30` → 1
- Temp: `<35 or >39` → 3; `35–36 or 38–39` → 1
- SpO2: `<90` → 3; `90–94` → 1; else 0 if provided
- Consciousness: not Alert → 3

Risk: any single param score == 3 → at least RED; total ≥5 → RED; 3–4 or any param == 1 with total <5 → YELLOW; 0–2 → GREEN.

If any of `sbp, dbp, hr, rr, temp` is `None`, return `{"moews_score": None, "risk_level": "UNKNOWN"}` without raising.

Keep `@tool` decorator for LangChain compatibility; allow None via Optional types.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m pytest tests/test_moews.py -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/tools/moews_calculator.py tests/test_moews.py
git commit -m "fix: align MOEWS scoring with product thresholds and null guard"
```

---

### Task 5: MessagingGateway

**Files:**
- Create: `src/services/messaging_gateway.py`
- Create: `tests/test_messaging_gateway.py`

**Interfaces:**
- Produces: `MessagingGateway.send_sms(to, message, dispatch_id, role) -> dict` with keys `status` (`SENT`|`MOCKED`|`FAILED`), `provider_response`
- Consumes: `settings.at_configured`, `DispatchLog` writes via injected session or returned payload for caller to persist

- [ ] **Step 1: Write failing test**

```python
import pytest
from src.services.messaging_gateway import MessagingGateway

@pytest.mark.asyncio
async def test_mock_when_no_at_keys(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "")
    gw = MessagingGateway()
    result = await gw.send_sms("+233240000001", "test", dispatch_id=1, role="driver")
    assert result["status"] == "MOCKED"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `./venv/bin/python -m pytest tests/test_messaging_gateway.py -v`

- [ ] **Step 3: Implement gateway**

```python
"""Africa's Talking SMS/Voice with auto-mock fallback."""
import logging
import httpx
from src.config import settings

logger = logging.getLogger(__name__)

class MessagingGateway:
    SMS_URL = "https://api.africastalking.com/version1/messaging"

    async def send_sms(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        if not settings.at_configured:
            logger.info("MOCK SMS dispatch=%s role=%s to=%s msg=%s", dispatch_id, role, to, message)
            return {"status": "MOCKED", "to": to, "message": message, "role": role, "dispatch_id": dispatch_id}
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(
                    self.SMS_URL,
                    headers={"apiKey": settings.AT_API_KEY, "Accept": "application/json"},
                    data={"username": settings.AT_USERNAME, "to": to, "message": message, "from": settings.AT_SENDER_ID},
                )
            if resp.status_code >= 400:
                return {"status": "FAILED", "error": resp.text, "to": to, "dispatch_id": dispatch_id, "role": role}
            return {"status": "SENT", "provider_response": resp.json(), "to": to, "dispatch_id": dispatch_id, "role": role}
        except Exception as exc:
            logger.exception("AT SMS failed")
            return {"status": "FAILED", "error": str(exc), "to": to, "dispatch_id": dispatch_id, "role": role}

    async def initiate_voice(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        # Same mock/sandbox pattern; Voice optional for MVP cascade SMS-first
        if not settings.at_configured:
            logger.info("MOCK VOICE dispatch=%s to=%s", dispatch_id, to)
            return {"status": "MOCKED", "to": to, "message": message, "dispatch_id": dispatch_id, "role": role}
        return {"status": "FAILED", "error": "Voice not configured for MVP", "to": to, "dispatch_id": dispatch_id, "role": role}
```

Caller persists `dispatch_log` with `action=sms_send` / `sms_failed` from returned status. On `FAILED`, cascade continues (spec §10).

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add src/services/messaging_gateway.py tests/test_messaging_gateway.py
git commit -m "feat: add MessagingGateway with AT sandbox or mock"
```

---

### Task 6: Driver pool + hospital notifier + dispatch orchestrator

**Files:**
- Create: `src/services/driver_pool.py`
- Create: `src/services/hospital_notifier.py`
- Create: `src/services/dispatch_orchestrator.py`
- Create: `tests/test_dispatch.py`

**Interfaces:**
- `DriverPoolManager.get_candidates(session, compound_id, tier, declined_ids) -> list[Driver]`
- `HospitalNotifier.notify_pre_arrival(session, referral, driver, facility, dispatch_id)`
- `DispatchOrchestrator.initiate_dispatch(session, referral_id) -> Dispatch`
- `DispatchOrchestrator.handle_accept(session, dispatch_id, driver_id) -> dict` (claim under FOR UPDATE)
- `DispatchOrchestrator.handle_decline(session, dispatch_id, driver_id) -> dict`
- `DispatchOrchestrator.schedule_tier_timeouts(dispatch_id)` using `asyncio.create_task` + `CASCADE_TIER_SECONDS`

- [ ] **Step 1: Write failing tests for decline escalate and double-accept**

In `tests/test_dispatch.py` use pytest-asyncio + optionally SQLite is **not** the design DB — prefer testing against Supabase or use a test `DATABASE_URL`. If Supabase unavailable in CI, document that integration tests require `.env`. Minimal unit test can mock session; prefer real async PG.

At minimum, pure logic test:

```python
def test_claimable_statuses():
    from src.services.dispatch_orchestrator import CLAIMABLE
    assert "TIER1_NOTIFIED" in CLAIMABLE
    assert "ACCEPTED" not in CLAIMABLE
```

Expand with DB-backed tests once seed works.

- [ ] **Step 2: Implement `driver_pool.py`**

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from src.db.models import Driver

class DriverPoolManager:
    async def get_candidates(self, session: AsyncSession, compound_id: int, tier: int, declined_ids: list[int]) -> list[Driver]:
        q = select(Driver).where(
            Driver.chps_compound_id == compound_id,
            Driver.is_active.is_(True),
            Driver.availability == "AVAILABLE",
        )
        if tier == 1:
            q = q.where(Driver.is_motor_king.is_(True))
        elif tier == 2:
            q = q.where(Driver.is_motor_king.is_(False))
        else:
            return []
        rows = (await session.execute(q)).scalars().all()
        return [d for d in rows if d.id not in set(declined_ids or [])]
```

- [ ] **Step 3: Implement `hospital_notifier.py`**

```python
from sqlalchemy.ext.asyncio import AsyncSession
from src.db.models import DispatchLog, Referral, Driver, Facility
from src.services.messaging_gateway import MessagingGateway

class HospitalNotifier:
    def __init__(self, gateway: MessagingGateway):
        self.gateway = gateway

    async def notify_pre_arrival(
        self,
        session: AsyncSession,
        referral: Referral,
        driver: Driver,
        facility: Facility,
        dispatch_id: int,
    ) -> None:
        message = (
            f"RELAYAI EMERGENCY REFERRAL\n"
            f"From compound #{referral.chps_compound_id}\n"
            f"Patient: {referral.patient_name}\n"
            f"Condition: {referral.emergency_type}\n"
            f"Severity: {referral.risk_level}\n"
            f"Driver: {driver.name}\n"
            f"Ref: #{referral.id}"
        )
        result = await self.gateway.send_sms(facility.phone, message, dispatch_id, "hospital")
        session.add(DispatchLog(
            dispatch_id=dispatch_id,
            action="hospital_notify" if result["status"] != "FAILED" else "hospital_notify_failed",
            target_phone=facility.phone,
            target_role="hospital",
            response=result["status"],
            metadata_json=result,
        ))
```

- [ ] **Step 4: Implement `dispatch_orchestrator.py`**

Create `src/services/dispatch_orchestrator.py` with this behavior (full file OK to adapt slightly for imports):

```python
"""Deterministic cascade dispatch — no LLM."""
from __future__ import annotations
import asyncio
import logging
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from src.config import settings
from src.db.database import async_session
from src.db.models import Dispatch, DispatchLog, Driver, Referral, Wallet, CHPSCompound, Facility
from src.services.messaging_gateway import MessagingGateway
from src.services.driver_pool import DriverPoolManager
from src.services.hospital_notifier import HospitalNotifier

logger = logging.getLogger(__name__)
CLAIMABLE = {"TIER1_NOTIFIED", "TIER2_NOTIFIED", "PENDING"}
FUEL_STIPEND_GHS = 22.5

class DispatchOrchestrator:
    def __init__(self, gateway: MessagingGateway | None = None):
        self.gateway = gateway or MessagingGateway()
        self.pool = DriverPoolManager()
        self.hospital = HospitalNotifier(self.gateway)

    async def initiate_dispatch(self, session: AsyncSession, referral_id: int) -> Dispatch:
        referral = await session.get(Referral, referral_id)
        if not referral:
            raise ValueError(f"referral {referral_id} not found")
        dispatch = Dispatch(
            referral_id=referral.id,
            facility_id=referral.facility_id,
            status="PENDING",
            current_tier=0,
            declined_driver_ids=[],
        )
        session.add(dispatch)
        await session.flush()
        await self._notify_tier(session, dispatch, referral, tier=1)
        await session.flush()
        asyncio.create_task(self._tier_timeout(dispatch.id, tier=1))
        return dispatch

    async def _notify_tier(self, session: AsyncSession, dispatch: Dispatch, referral: Referral, tier: int) -> None:
        declined = list(dispatch.declined_driver_ids or [])
        candidates = await self.pool.get_candidates(session, referral.chps_compound_id, tier, declined)
        status = f"TIER{tier}_NOTIFIED" if tier in (1, 2) else "FAILED"
        dispatch.current_tier = tier
        dispatch.status = status if candidates or tier < 3 else "FAILED"
        if tier >= 3 or (tier == 2 and not candidates):
            compound = await session.get(CHPSCompound, referral.chps_compound_id)
            msg = f"RelayAI: No driver for referral #{referral.id}. Coordinate manually."
            result = await self.gateway.send_sms(compound.cho_phone, msg, dispatch.id, "cho")
            session.add(DispatchLog(
                dispatch_id=dispatch.id, action="cho_give_up", target_phone=compound.cho_phone,
                target_role="cho", response=result["status"], metadata_json=result,
            ))
            dispatch.status = "FAILED"
            return
        for driver in candidates:
            msg = (
                f"EMERGENCY: Patient at compound #{referral.chps_compound_id}. "
                f"Dial USSD to accept. Ref #{referral.id}"
            )
            result = await self.gateway.send_sms(driver.phone, msg, dispatch.id, "driver")
            session.add(DispatchLog(
                dispatch_id=dispatch.id, action="sms_send" if result["status"] != "FAILED" else "sms_failed",
                target_phone=driver.phone, target_role="driver", response=result["status"], metadata_json=result,
            ))
            # On FAILED SMS, still continue to next candidate (spec §10)

    async def handle_accept(self, session: AsyncSession, dispatch_id: int, driver_id: int) -> dict:
        dispatch = await session.scalar(
            select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
        )
        if not dispatch:
            return {"ussd": "END No active dispatch.", "run_side_effects": False}
        if dispatch.status == "ACCEPTED" and dispatch.driver_id == driver_id:
            return {"ussd": "END Accepted! Fuel stipend queued. Proceed to CHPS.", "run_side_effects": False}
        if dispatch.status == "ACCEPTED" and dispatch.driver_id != driver_id:
            return {"ussd": "END Already assigned.", "run_side_effects": False}
        if dispatch.status not in CLAIMABLE:
            return {"ussd": "END Dispatch not available.", "run_side_effects": False}
        dispatch.status = "ACCEPTED"
        dispatch.driver_id = driver_id
        dispatch.driver_assigned_at = datetime.now(timezone.utc)
        session.add(DispatchLog(
            dispatch_id=dispatch.id, action="ussd_accept", target_role="driver",
            response="ACCEPTED", metadata_json={"driver_id": driver_id},
        ))
        return {"ussd": "END Accepted! Fuel stipend queued. Proceed to CHPS.", "run_side_effects": True}

    async def handle_decline(self, session: AsyncSession, dispatch_id: int, driver_id: int) -> dict:
        dispatch = await session.scalar(
            select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
        )
        if not dispatch:
            return {"ussd": "END No active dispatch."}
        declined = list(dispatch.declined_driver_ids or [])
        if driver_id not in declined:
            declined.append(driver_id)
        dispatch.declined_driver_ids = declined
        session.add(DispatchLog(
            dispatch_id=dispatch.id, action="ussd_decline", target_role="driver",
            response="DECLINED", metadata_json={"driver_id": driver_id},
        ))
        if dispatch.status == "ACCEPTED":
            return {"ussd": "END Decline noted."}
        if dispatch.status not in CLAIMABLE:
            return {"ussd": "END Decline noted."}
        referral = await session.get(Referral, dispatch.referral_id)
        next_tier = 2 if dispatch.current_tier <= 1 else 3
        await self._notify_tier(session, dispatch, referral, tier=next_tier)
        if dispatch.status.startswith("TIER"):
            asyncio.create_task(self._tier_timeout(dispatch.id, tier=dispatch.current_tier))
        return {"ussd": "END Referral declined."}

    async def run_accept_side_effects(self, dispatch_id: int, driver_id: int) -> None:
        async with async_session() as session:
            dispatch = await session.get(Dispatch, dispatch_id)
            if not dispatch or dispatch.status not in {"ACCEPTED", "HOSPITAL_NOTIFIED"}:
                return
            existing = await session.scalar(
                select(DispatchLog).where(
                    DispatchLog.dispatch_id == dispatch_id,
                    DispatchLog.action == "momo_escrow",
                )
            )
            if not existing:
                tx = str(uuid.uuid4())
                session.add(DispatchLog(
                    dispatch_id=dispatch_id, action="momo_escrow", target_role="driver",
                    response="INITIAL_DISBURSED",
                    metadata_json={"transaction_id": tx, "amount_ghs": FUEL_STIPEND_GHS, "stage": "INITIAL_30PCT"},
                ))
                session.add(Wallet(
                    referral_id=dispatch.referral_id, dispatch_id=dispatch_id,
                    amount=FUEL_STIPEND_GHS, transaction_id=tx, status="INITIAL_DISBURSED",
                ))
            referral = await session.get(Referral, dispatch.referral_id)
            driver = await session.get(Driver, driver_id)
            facility = await session.get(Facility, dispatch.facility_id)
            await self.hospital.notify_pre_arrival(session, referral, driver, facility, dispatch_id)
            dispatch.status = "HOSPITAL_NOTIFIED"
            await session.commit()

    async def _tier_timeout(self, dispatch_id: int, tier: int) -> None:
        await asyncio.sleep(settings.CASCADE_TIER_SECONDS)
        async with async_session() as session:
            dispatch = await session.scalar(
                select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
            )
            if not dispatch:
                return
            if dispatch.status == "ACCEPTED" or dispatch.current_tier != tier:
                return
            if dispatch.status not in CLAIMABLE:
                return
            referral = await session.get(Referral, dispatch.referral_id)
            next_tier = tier + 1
            await self._notify_tier(session, dispatch, referral, tier=next_tier)
            await session.commit()
            if dispatch.status.startswith("TIER"):
                asyncio.create_task(self._tier_timeout(dispatch.id, tier=dispatch.current_tier))
```

Ensure USSD layer uses `BackgroundTasks.add_task(orchestrator.run_accept_side_effects, ...)` — not inline await of AT/MoMo.

- [ ] **Step 5: Run unit tests**

Run: `./venv/bin/python -m pytest tests/test_dispatch.py -v`

Expected: PASS for claimable + any DB tests configured

- [ ] **Step 6: Commit**

```bash
git add src/services/driver_pool.py src/services/hospital_notifier.py src/services/dispatch_orchestrator.py tests/test_dispatch.py
git commit -m "feat: add cascade dispatch orchestrator with FOR UPDATE claims"
```

---

### Task 7: USSD callback (fast, idempotent)

**Files:**
- Modify: `src/api/ussd.py`
- Create: `tests/test_ussd_idempotency.py`

**Interfaces:**
- Consumes: `DispatchOrchestrator.handle_accept/handle_decline`
- Produces: plain text `CON`/`END` responses

- [ ] **Step 1: Write failing idempotency test**

Use `httpx.AsyncClient` + FastAPI `app` with overridden DB if possible; or call handler logic function extracted as `process_ussd(session, phone, text) -> str`.

```python
@pytest.mark.asyncio
async def test_double_accept_same_end_body():
    # arrange: open dispatch TIER1_NOTIFIED for driver phone +233240000001
    first = await process_ussd(...)
    second = await process_ussd(...)  # same accept
    assert first.startswith("END")
    assert first == second
```

- [ ] **Step 2: Implement `src/api/ussd.py`**

```python
from fastapi import APIRouter, Form, Response, BackgroundTasks
from src.db.database import async_session
from src.db.models import Driver
from src.services.dispatch_orchestrator import DispatchOrchestrator
from sqlalchemy import select

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])
orchestrator = DispatchOrchestrator()

@router.post("/callback")
async def handle_ussd(
    background_tasks: BackgroundTasks,
    session_id: str = Form(...),
    service_code: str = Form(...),
    phone_number: str = Form(...),
    text: str = Form(""),
):
    user_input = text.strip()
    if user_input == "":
        return Response(content="CON RelayAI Emergency Referral\n1. Accept\n2. Decline", media_type="text/plain")

    async with async_session() as session:
        driver = await session.scalar(select(Driver).where(Driver.phone == phone_number))
        if not driver:
            return Response(content="END Unknown driver.", media_type="text/plain")
        # Resolve open dispatch for driver's compound (latest CLAIMABLE or ACCEPTED by this driver)
        ...
        if user_input.endswith("1") or user_input == "1":
            result = await orchestrator.handle_accept(session, dispatch.id, driver.id)
            await session.commit()
            if result.get("run_side_effects"):
                background_tasks.add_task(orchestrator.run_accept_side_effects, dispatch.id, driver.id)
            return Response(content=result["ussd"], media_type="text/plain")
        if user_input.endswith("2") or user_input == "2":
            result = await orchestrator.handle_decline(session, dispatch.id, driver.id)
            await session.commit()
            return Response(content=result["ussd"], media_type="text/plain")
        return Response(content="END Invalid option selected.", media_type="text/plain")
```

Do not await MoMo or AT inside this handler.

- [ ] **Step 3: Run tests**

Run: `./venv/bin/python -m pytest tests/test_ussd_idempotency.py -v`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/api/ussd.py tests/test_ussd_idempotency.py
git commit -m "feat: fast idempotent USSD accept/decline with background side effects"
```

---

### Task 8: Referral API + SMS inbound + main wiring

**Files:**
- Create: `src/api/referral.py`
- Create: `src/api/sms_webhook.py`
- Modify: `main.py`
- Modify: `src/agents/coordinator.py`
- Modify: `src/agents/clinical_agent.py`
- Modify: `src/agents/dispatch_agent.py` (thin wrapper or deprecate inline)

**Interfaces:**
- `POST /api/v1/referral` body: `{chps_compound_id, facility_id, patient_hash, patient_name, emergency_type, vitals: {...}}`
- Runs clinical graph → persists Referral → `initiate_dispatch`
- `POST /api/v1/sms/inbound` body: `{from, text}` parsing CONFIRM/DIVERT

- [ ] **Step 1: Harden clinical agent for missing Gemini**

In `clinical_agent.py`: if no `GEMINI_API_KEY`, set template summary; wrap LLM in try/except. Use updated MOEWS with spo2/consciousness from vitals. Null vitals → UNKNOWN.

- [ ] **Step 2: Update coordinator**

```python
from src.agents.clinical_agent import run_clinical_assessment
# prepare_dispatch node: compress via sms_codec, then END
# Do NOT call MoMo/AT inside graph
workflow.add_node("clinical_assessment", run_clinical_assessment)
workflow.add_node("prepare_dispatch", prepare_dispatch_node)
```

Update `ReferralState` risk labels to GREEN/YELLOW/RED/UNKNOWN if needed for consistency with MOEWS (map in API when persisting).

- [ ] **Step 3: Implement `src/api/referral.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from src.db.database import get_db
from src.agents.coordinator import relayai_graph
from src.services.dispatch_orchestrator import DispatchOrchestrator
# POST creates Referral from graph output, starts orchestrator
```

- [ ] **Step 4: Implement `src/api/sms_webhook.py`**

Parse uppercase `CONFIRM` / `DIVERT`; update dispatch/facility; log; mock SMS to driver+CHO on divert.

- [ ] **Step 5: Update `main.py`**

```python
from contextlib import asynccontextmanager
from src.db.database import init_db
from src.api.ussd import router as ussd_router
from src.api.referral import router as referral_router
from src.api.sms_webhook import router as sms_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield

app = FastAPI(..., lifespan=lifespan)
app.include_router(ussd_router)
app.include_router(referral_router)
app.include_router(sms_router)
```

- [ ] **Step 6: Smoke start**

Run: `cd /var/www/html/unicef && ./venv/bin/python -c "from main import app; print(app.title)"`

Expected: `RelayAI Logistics Engine` (or updated title)

- [ ] **Step 7: Commit**

```bash
git add main.py src/api/referral.py src/api/sms_webhook.py src/agents/
git commit -m "feat: referral and hospital SMS APIs wired to orchestrator"
```

---

### Task 9: SMS codec test + demo flow script

**Files:**
- Create: `tests/test_sms_codec.py`
- Create: `scripts/demo_flow.py`
- Modify: `README.md`

**Interfaces:**
- `demo_flow.py` prints judge timeline for happy path, decline path, hospital path

- [ ] **Step 1: Codec round-trip test**

```python
from src.tools.sms_codec import compress_referral_payload, decompress_referral_payload

def test_round_trip():
    encoded = compress_referral_payload.invoke({
        "chps_id_int": 1, "moews_score": 6, "risk_code": 3, "hr": 140, "sbp": 70
    })
    decoded = decompress_referral_payload.invoke({"encoded_str": encoded})
    assert decoded["moews_score"] == 6
    assert decoded["heart_rate"] == 140
```

- [ ] **Step 2: Implement `scripts/demo_flow.py`**

Use httpx against `http://127.0.0.1:8000`:

1. Ensure seed
2. POST referral with critical vitals for compound 1
3. Print `[00:00] Referral created...` style lines using elapsed seconds
4. POST USSD accept as Ibrahim → print MoMo + hospital lines from GET dispatch logs
5. Second scenario: decline as Ibrahim → assert Musah/Abdul notified
6. Third: hospital CONFIRM

Sample prints must match design §11 style.

- [ ] **Step 3: Write README quick start**

Backend-only instructions: venv, `.env`, seed, `python main.py`, `python scripts/demo_flow.py`. Link design spec. State Flutter is out of scope for this MVP.

- [ ] **Step 4: Manual E2E**

```
./venv/bin/python -m src.db.seed
./venv/bin/python main.py   # separate terminal
./venv/bin/python scripts/demo_flow.py
```

Expected: timeline with `HOSPITAL_NOTIFIED ✓` and decline escalation visible.

- [ ] **Step 5: Commit**

```bash
git add tests/test_sms_codec.py scripts/demo_flow.py README.md
git commit -m "feat: add judge demo_flow script and codec tests"
```

---

## Chunk Summary

| Task | Focus | Depends on |
|------|--------|------------|
| 1 | Config + deps | — |
| 2 | DB models | 1 |
| 3 | Seed | 2 |
| 4 | MOEWS | 1 |
| 5 | MessagingGateway | 1 |
| 6 | Orchestrator | 2, 5 |
| 7 | USSD | 6 |
| 8 | Referral API + main | 4, 6, 7 |
| 9 | Demo + README | 8 |

**Out of scope:** Flutter Chunk 6 from `2026-07-23-relayai-hackathon-mvp.md` (separate plan later).

---

## Self-Review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Backend-only demo / no Flutter | Global + Task 9 |
| Supabase Postgres + create_all | Tasks 2, 8 |
| AT sandbox or mock | Task 5 |
| Cascade + accelerated timers | Task 6 |
| Decline escalate only if not ACCEPTED | Task 6 |
| Idempotency `(dispatch_id, driver_id)` | Tasks 6–7 |
| FOR UPDATE claim | Task 6 |
| Fast USSD + BackgroundTasks | Task 7 |
| Mock MoMo on dispatch_log | Task 6 |
| Hospital CONFIRM/DIVERT | Task 8 |
| Null vitals UNKNOWN | Task 4 |
| LLM optional | Task 8 |
| AT send failure continues cascade | Task 5–6 |
| python-multipart | Task 1 |
| demo_flow judge timeline | Task 9 |
| No emergency_contact | Global / seed |
