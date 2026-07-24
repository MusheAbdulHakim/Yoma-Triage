# RelayAI Hackathon MVP Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working end-to-end hackathon demo: Flutter app (acoustic screening + clinical triage) → FastAPI backend (dispatch cascade) → Africa's Talking SMS/USSD → driver accepts → hospital notified → confirmation.

**Architecture:** Offline-first Flutter mobile app runs YAMNet TFLite for respiratory screening and MOEWS scoring locally. On referral trigger, app sends JSON to FastAPI backend. Backend orchestrates cascading dispatch via Africa's Talking SMS/Voice/USSD to Motor-King drivers, notifies receiving hospital, and tracks dispatch lifecycle in PostgreSQL. Driver responds via USSD. Hospital confirms via SMS. MoMo escrow is simulated for hackathon.

**Tech Stack:** Flutter 3.x, Dart, TFLite (YAMNet), FastAPI, Python 3.11+, PostgreSQL (Supabase), Africa's Talking SDK (SMS, Voice, USSD), LangGraph, ChromaDB (RAG), Pydantic

---

## File Structure

```
/var/www/html/unicef/
├── main.py                          # FastAPI entry point (EXISTS - update)
├── requirements.txt                 # Python deps (EXISTS - update)
├── pyproject.toml                   # (EXISTS)
├── README.md                        # (EXISTS - write)
├── .env.example                     # NEW - environment variables template
├── src/
│   ├── __init__.py                  # NEW
│   ├── config.py                    # (EXISTS - update)
│   ├── api/
│   │   ├── __init__.py              # NEW
│   │   ├── ussd.py                  # (EXISTS - update)
│   │   ├── sms_webhook.py           # NEW - inbound SMS handler
│   │   └── referral.py              # NEW - referral CRUD endpoints
│   ├── agents/
│   │   ├── __init__.py              # NEW
│   │   ├── state.py                 # (EXISTS - keep)
│   │   ├── coordinator.py           # (EXISTS - update to use full agents)
│   │   ├── clinical_agent.py        # (EXISTS - update)
│   │   └── dispatch_agent.py        # (EXISTS - update)
│   ├── db/
│   │   ├── __init__.py              # NEW
│   │   ├── database.py              # (EXISTS - implement)
│   │   ├── models.py                # (EXISTS - implement)
│   │   └── seed.py                  # NEW - demo data seeder
│   ├── rag/
│   │   ├── __init__.py              # NEW
│   │   ├── engine.py                # (EXISTS - keep)
│   │   └── ingest.py                # (EXISTS - keep)
│   ├── services/
│   │   ├── __init__.py              # NEW
│   │   ├── africastalking_sms.py    # NEW - AT SMS integration
│   │   ├── africastalking_voice.py  # NEW - AT Voice integration
│   │   ├── africastalking_ussd.py   # NEW - AT USSD integration
│   │   ├── dispatch_orchestrator.py # NEW - cascade dispatch logic
│   │   ├── hospital_notifier.py     # NEW - pre-arrival notification
│   │   └── driver_pool.py           # NEW - driver registration/availability
│   └── tools/
│       ├── __init__.py              # NEW
│       ├── moews_calculator.py      # (EXISTS - update scoring)
│       ├── sms_codec.py             # (EXISTS - keep)
│       └── momo_escrow.py           # (EXISTS - keep)
├── data/
│   ├── ghs_protocols/               # (EXISTS)
│   ├── vector_store/                # (EXISTS)
│   └── demo_data.json               # NEW - seed data
├── flutter_app/                     # NEW - Flutter mobile app
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   ├── screening_screen.dart
│   │   │   ├── referral_screen.dart
│   │   │   └── result_screen.dart
│   │   ├── services/
│   │   │   ├── audio_recorder.dart
│   │   │   ├── tflite_classifier.dart
│   │   │   ├── api_client.dart
│   │   │   └── offline_queue.dart
│   │   ├── models/
│   │   │   └── referral.dart
│   │   └── widgets/
│   │       ├── vital_input.dart
│   │       └── status_indicator.dart
│   └── assets/
│       └── models/
│           └── yamnet.tflite
└── tests/
    ├── test_moews.py
    ├── test_sms_codec.py
    └── test_dispatch.py
```

---

## Chunk 1: Backend Foundation (Database + Models + Config)

### Task 1: Environment Configuration

**Files:**
- Create: `.env.example`
- Modify: `src/config.py`

- [ ] **Step 1: Create .env.example**

```
# Africa's Talking
AT_API_KEY=sandbox_xxxxx
AT_USERNAME=sandbox
AT_SENDER_ID=RELAYAI

# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/relayai

# Gemini (optional - for enhanced clinical agent)
GEMINI_API_KEY=

# MoMo (simulated for hackathon)
MOMO_API_URL=https://sandbox.momodeveloper.mtn.com
MOMO_PRIMARY_KEY=

# App
ENVIRONMENT=development
LOG_LEVEL=INFO
```

- [ ] **Step 2: Update config.py with missing settings**

Add `DATABASE_URL`, `AT_API_KEY`, `AT_USERNAME`, `AT_SENDER_ID` to the Settings class.

- [ ] **Step 3: Verify config loads**

Run: `cd /var/www/html/unicef && python -c "from src.config import settings; print(settings.ENVIRONMENT)"`
Expected: `development`

### Task 2: Database Models

**Files:**
- Modify: `src/db/models.py`
- Modify: `src/db/database.py`

- [ ] **Step 4: Implement database.py with async engine**

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from src.config import settings

engine = create_async_engine(settings.DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

async def get_db():
    async with async_session() as session:
        yield session

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
```

- [ ] **Step 5: Implement models.py with all tables**

Create models: `CHPSCompound`, `Driver`, `Facility`, `EmergencyContact`, `Referral`, `Dispatch`, `DispatchLog`, `Wallet`, `AuditLog`. Follow the ERD from spec Part XI.

- [ ] **Step 6: Verify models load**

Run: `cd /var/www/html/unicef && python -c "from src.db.models import Base; print(Base.metadata.tables.keys())"`
Expected: Table names printed

### Task 3: Demo Data Seeder

**Files:**
- Create: `data/demo_data.json`
- Create: `src/db/seed.py`

- [ ] **Step 7: Create demo_data.json**

Include 3 CHPS compounds, 5 drivers (3 Motor-King + 2 fallback), 3 hospitals, 2 emergency contacts. Use real Tamale/Kassena-Nankana area names.

- [ ] **Step 8: Create seed.py script**

Async script that reads demo_data.json and inserts all records using SQLAlchemy async sessions.

- [ ] **Step 9: Run seeder**

Run: `cd /var/www/html/unicef && python -m src.db.seed`
Expected: "Seeded 3 compounds, 5 drivers, 3 facilities"

---

## Chunk 2: Africa's Talking Integration Services

### Task 4: SMS Service

**Files:**
- Create: `src/services/__init__.py`
- Create: `src/services/africastalking_sms.py`

- [ ] **Step 10: Implement SMS service**

```python
import requests
from src.config import settings

class AfricasTalkingSMS:
    BASE_URL = "https://api.africastalking.com/version1/messaging"
    
    def __init__(self):
        self.api_key = settings.AT_API_KEY
        self.username = settings.AT_USERNAME
    
    def send(self, to: str, message: str) -> dict:
        headers = {"apiKey": self.api_key, "Content-Type": "application/x-www-form-urlencoded"}
        data = {"username": self.username, "to": to, "message": message}
        response = requests.post(self.BASE_URL, headers=headers, data=data)
        return response.json()
```

- [ ] **Step 11: Add sandbox test mode**

When `ENVIRONMENT == "development"`, log messages instead of sending. Return mock success response.

- [ ] **Step 12: Verify SMS service**

Run: `cd /var/www/html/unicef && python -c "from src.services.africastalking_sms import AfricasTalkingSMS; s = AfricasTalkingSMS(); print(s.send('+233240000000', 'Test'))"`
Expected: Mock success response (or real if sandbox key configured)

### Task 5: Voice Service

**Files:**
- Create: `src/services/africastalking_voice.py`

- [ ] **Step 13: Implement Voice service**

Implement `AfricasTalkingVoice` class with `initiate_call(to, message)` method. Use AT Voice API for automated calls to drivers when SMS not responded to.

- [ ] **Step 14: Add sandbox mock**

Same pattern as SMS - log in development, send in production.

### Task 6: USSD Handler

**Files:**
- Modify: `src/api/ussd.py`

- [ ] **Step 15: Update USSD handler to integrate with dispatch**

When driver accepts (option 1), call `disburse_fuel_stipend` and update dispatch status in database. When driver declines (option 2), trigger next tier in cascade.

- [ ] **Step 16: Test USSD flow**

Run: `cd /var/www/html/unicef && python -c "from src.api.ussd import handle_ussd; print(handle_ussd('session1', '*123#', '+233240000000', ''))"`
Expected: USSD menu text returned

---

## Chunk 3: Dispatch Cascade Logic

### Task 7: Driver Pool Manager

**Files:**
- Create: `src/services/driver_pool.py`

- [ ] **Step 17: Implement driver pool manager**

```python
class DriverPoolManager:
    def __init__(self, db):
        self.db = db
    
    async def get_available_drivers(self, chps_compound_id: int) -> list[Driver]:
        """Get available drivers for a CHPS compound, ordered by type (Motor-King first)."""
        
    async def update_availability(self, driver_id: int, status: str):
        """Update driver availability status."""
        
    async def register_driver(self, driver_data: dict) -> Driver:
        """Register a new driver."""
```

- [ ] **Step 18: Implement fallback tier logic**

Add methods: `get_fallback_drivers()`, `get_personal_contacts(patient_hash)`.

### Task 8: Dispatch Orchestrator

**Files:**
- Create: `src/services/dispatch_orchestrator.py`

- [ ] **Step 19: Implement cascade dispatch**

```python
class DispatchOrchestrator:
    CASCADE_TIMERS = {
        "tier1_sms": 0,        # Immediate
        "tier1_voice": 90,     # 90 seconds
        "tier2_sms": 180,      # 3 minutes
        "tier2_voice": 270,    # 4.5 minutes
        "tier3_sms": 360,      # 6 minutes
        "tier3_voice": 450,    # 7.5 minutes
        "give_up": 540,        # 9 minutes
    }
    
    async def initiate_dispatch(self, referral_id: int) -> Dispatch:
        """Start cascade dispatch for a referral."""
        
    async def handle_driver_response(self, driver_id: int, response: str):
        """Process driver accept/decline/delay."""
        
    async def escalate_to_next_tier(self, dispatch_id: int):
        """Move to next tier in cascade."""
```

- [ ] **Step 20: Implement SMS sending in cascade**

At each tier, send SMS via `AfricasTalkingSMS.send()`. At voice tiers, initiate call via `AfricasTalkingVoice.initiate_call()`.

- [ ] **Step 21: Implement timeout handling**

Use `asyncio.create_task` with delays for cascade timers. If no response after 9 minutes, notify CHO.

### Task 9: Hospital Notifier

**Files:**
- Create: `src/services/hospital_notifier.py`

- [ ] **Step 22: Implement hospital notification**

```python
class HospitalNotifier:
    async def notify_pre_arrival(self, referral: Referral, driver: Driver, facility: Facility):
        """Send pre-arrival SMS to hospital."""
        message = f"""RELAYAI EMERGENCY REFERRAL
From: {referral.chps_compound.name}
Patient: {referral.patient_name}
Age: {referral.patient_age}
Condition: {referral.emergency_type}
Severity: {referral.severity}
Driver: {driver.name}
ETA: {self.calculate_eta(referral, facility)}"""
        
        await self.sms_service.send(facility.phone, message)
```

---

## Chunk 4: Backend API Endpoints

### Task 10: Referral API

**Files:**
- Create: `src/api/referral.py`

- [ ] **Step 23: Implement referral endpoints**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `POST /api/v1/referral` | POST | Create referral from mobile app |
| `GET /api/v1/referral/{id}` | GET | Get referral status |
| `GET /api/v1/dispatch/{id}` | GET | Get dispatch status |
| `POST /api/v1/driver/{id}/availability` | POST | Update driver availability |
| `GET /api/v1/compound/{id}/drivers` | GET | List drivers for compound |

- [ ] **Step 24: Wire referral creation to dispatch cascade**

When `POST /api/v1/referral` receives a referral, create Referral record, create Dispatch record, and trigger `DispatchOrchestrator.initiate_dispatch()`.

- [ ] **Step 25: Add SMS webhook endpoint**

`POST /api/v1/sms/inbound` — Handle inbound SMS from hospital (CONFIRM/DIVERT).

### Task 11: Update Main Entry Point

**Files:**
- Modify: `main.py`

- [ ] **Step 26: Add database init on startup**

```python
@app.on_event("startup")
async def startup():
    await init_db()
```

- [ ] **Step 27: Mount new routers**

Add `referral_router` to app.

- [ ] **Step 28: Verify backend starts**

Run: `cd /var/www/html/unicef && python main.py`
Expected: Server starts on port 8000

---

## Chunk 5: MOEWS Calculator Fix + Dispatch Agent Integration

### Task 12: Fix MOEWS Calculator

**Files:**
- Modify: `src/tools/moews_calculator.py`

- [ ] **Step 29: Add diastolic BP and temperature scoring**

Update `calculate_moews` to include:
- DBP scoring: <60 = +3, 60-90 = 0, 90-100 = +1, >100 = +3
- Temperature scoring: <35.0 = +3, 35-36 = +1, 36-38 = 0, 38-39 = +1, >39 = +3
- SpO2 scoring: <90 = +3, 90-94 = +1, ≥95 = 0
- AVPU scoring: Alert = 0, Voice/Pain/Unresponsive = +3

- [ ] **Step 30: Update risk thresholds to match spec**

Green: 0-2, Yellow: 3-4 (or any single param = 1), Red: ≥5 (or any single param = 3)

- [ ] **Step 31: Write tests**

```python
# tests/test_moews.py
def test_normal_vitals():
    result = calculate_moews(120, 80, 80, 18, 37.0, 98, "A")
    assert result["moews_score"] == 0
    assert result["risk_level"] == "GREEN"

def test_critical_vitals():
    result = calculate_moews(70, 50, 140, 35, 39.5, 85, "V")
    assert result["moews_score"] >= 5
    assert result["risk_level"] == "RED"
```

- [ ] **Step 32: Run tests**

Run: `cd /var/www/html/unicef && python -m pytest tests/test_moews.py -v`
Expected: All tests pass

### Task 13: Wire Full Agents into Coordinator

**Files:**
- Modify: `src/agents/coordinator.py`

- [ ] **Step 33: Replace simple clinical_node with full clinical_agent**

Import `run_clinical_assessment` from `clinical_agent.py` and use it as the clinical node.

- [ ] **Step 34: Replace simple dispatch_node with full dispatch_agent**

Import `run_dispatch_coordination` from `dispatch_agent.py` and use it as the dispatch node.

- [ ] **Step 35: Test the full graph**

Run: `cd /var/www/html/unicef && python -c "from src.agents.coordinator import relayai_graph; result = relayai_graph.invoke({'chps_id': '1', 'patient_hash': 'test123', 'vitals': {'systolic_bp': 160, 'diastolic_bp': 95, 'heart_rate': 120, 'respiratory_rate': 28, 'temperature': 38.5, 'consciousness_level': 'A'}, 'next_node': 'clinical'}); print(result)"`
Expected: MOEWS score, risk level, compressed SMS payload returned

---

## Chunk 6: Flutter Mobile App

### Task 14: Flutter Project Setup

**Files:**
- Create: `flutter_app/pubspec.yaml`
- Create: `flutter_app/lib/main.dart`

- [ ] **Step 36: Create Flutter project structure**

```yaml
# pubspec.yaml
name: relayai_app
description: RelayAI - Emergency Referral Platform
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  tflite_flutter: ^0.12.1
  record: ^5.0.0
  http: ^1.1.0
  sqflite: ^2.3.0
  connectivity_plus: ^5.0.0
  shared_preferences: ^2.2.0
  path_provider: ^2.1.0
```

- [ ] **Step 37: Create main.dart with MaterialApp**

Basic app shell with routing to home screen.

### Task 15: Audio Recording + TFLite Classification

**Files:**
- Create: `flutter_app/lib/services/audio_recorder.dart`
- Create: `flutter_app/lib/services/tflite_classifier.dart`
- Create: `flutter_app/assets/models/yamnet.tflite` (download)

- [ ] **Step 38: Implement audio_recorder.dart**

```dart
class AudioRecorder {
  final recorder = Record();
  
  Future<void> startRecording() async {
    await recorder.start(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ), path: 'recording.wav');
  }
  
  Future<String?> stopRecording() async {
    return await recorder.stop();
  }
}
```

- [ ] **Step 39: Implement tflite_classifier.dart**

```dart
class TFLiteClassifier {
  late Interpreter _interpreter;
  
  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/models/yamnet.tflite');
  }
  
  Map<String, double> classify(List<double> audioData) {
    // Run inference, return {"normal": 0.92, "wheeze": 0.05, "crackle": 0.03}
  }
}
```

- [ ] **Step 40: Download YAMNet model**

Download `yamnet.tflite` (4.13 MB) from TensorFlow Hub and place in `flutter_app/assets/models/`.

- [ ] **Step 41: Test on-device classification**

Verify model loads and classifies a test audio sample.

### Task 16: Screens and Navigation

**Files:**
- Create: `flutter_app/lib/screens/home_screen.dart`
- Create: `flutter_app/lib/screens/screening_screen.dart`
- Create: `flutter_app/lib/screens/referral_screen.dart`
- Create: `flutter_app/lib/screens/result_screen.dart`
- Create: `flutter_app/lib/models/referral.dart`
- Create: `flutter_app/lib/services/api_client.dart`

- [ ] **Step 42: Create home_screen.dart**

Two buttons: "Screen Breathing" and "Emergency Referral". Simple, large text for low-literacy users.

- [ ] **Step 43: Create screening_screen.dart**

60-second audio recording UI with countdown timer. Shows "Recording..." with progress indicator.

- [ ] **Step 44: Create referral_screen.dart**

Vital signs input form (BP, HR, RR, Temp, SpO2, AVPU). Emergency type dropdown. Patient name field. "Refer Now" button.

- [ ] **Step 45: Create result_screen.dart**

GREEN/RED result display with AI reasoning. "Confirm Referral" button. Shows dispatch status updates.

- [ ] **Step 46: Implement api_client.dart**

```dart
class ApiClient {
  final String baseUrl;
  
  Future<Referral> createReferral(Referral referral) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/referral'),
      body: jsonEncode(referral.toJson()),
    );
    return Referral.fromJson(jsonDecode(response.body));
  }
  
  Future<DispatchStatus> getDispatchStatus(String dispatchId) async {
    // Poll dispatch status
  }
}
```

- [ ] **Step 47: Implement offline_queue.dart**

Queue referrals in SQLite when offline. Sync when network returns.

### Task 17: Referral Model + Integration

**Files:**
- Create: `flutter_app/lib/models/referral.dart`

- [ ] **Step 48: Create Referral model**

```dart
class Referral {
  final String id;
  final String chpsCompoundId;
  final String patientName;
  final int patientAge;
  final String emergencyType;
  final String severity;
  final Vitals vitals;
  final String? aiScreenResult;
  final double? aiConfidence;
  final DateTime initiatedAt;
  
  Map<String, dynamic> toJson() => { ... };
  factory Referral.fromJson(Map<String, dynamic> json) => Referral(...);
}
```

- [ ] **Step 49: Wire screening result to referral creation**

After acoustic screening shows RED, automatically populate referral form with screening result.

- [ ] **Step 50: Wire referral submission to backend**

"Confirm Referral" button calls `ApiClient.createReferral()`.

---

## Chunk 7: Integration Testing + Demo Script

### Task 18: End-to-End Integration Test

**Files:**
- Create: `tests/test_dispatch.py`

- [ ] **Step 51: Write integration test**

```python
async def test_full_dispatch_flow():
    # 1. Seed demo data
    # 2. Create referral via API
    # 3. Verify dispatch cascade starts
    # 4. Simulate driver USSD response
    # 5. Verify hospital notification sent
    # 6. Verify dispatch status = COMPLETED
```

- [ ] **Step 52: Run integration test**

Run: `cd /var/www/html/unicef && python -m pytest tests/test_dispatch.py -v`
Expected: Full flow completes

### Task 19: Demo Data + Script

**Files:**
- Create: `docs/demo_script.md`
- Modify: `data/demo_data.json`

- [ ] **Step 53: Create demo_script.md**

Step-by-step script for hackathon presentation:
1. Show CHPS compound problem (map, stats)
2. Open RelayAI app → "Screen Breathing"
3. Hold phone near child → 60-second recording
4. AI returns RED → "Wheezing detected"
5. CHO confirms referral → backend receives
6. Cascade dispatch starts → SMS to drivers
7. Driver receives SMS on feature phone
8. Driver dials USSD → Accepts
9. Hospital receives pre-arrival notification
10. Driver confirms arrival → Dispatch complete

- [ ] **Step 54: Populate demo_data.json with realistic data**

Use real place names: Navrongo (Kassena-Nankana East), Savelugu, Tamale Teaching Hospital.

### Task 20: README + Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 55: Write README.md**

```markdown
# RelayAI

Offline-first emergency maternal referral and transport broker for Northern Ghana.

## Quick Start

### Backend
pip install -r requirements.txt
cp .env.example .env  # Add your Africa's Talking sandbox key
python main.py

### Flutter App
cd flutter_app
flutter pub get
flutter run

## Architecture
[Diagram from spec]

## API Endpoints
[Table from spec]

## Demo
See docs/demo_script.md
```

- [ ] **Step 56: Verify full system works**

1. Start backend: `python main.py`
2. Run seeder: `python -m src.db.seed`
3. Test referral endpoint: `curl -X POST http://localhost:8000/api/v1/referral -H "Content-Type: application/json" -d '{...}'`
4. Verify dispatch cascade runs
5. Verify SMS logged (sandbox mode)

---

## Chunk Summary

| Chunk | Tasks | Est. Time | Dependency |
|-------|-------|-----------|------------|
| 1: Backend Foundation | 1-3 | 30 min | None |
| 2: AT Integration | 4-6 | 45 min | Chunk 1 |
| 3: Dispatch Cascade | 7-9 | 60 min | Chunk 2 |
| 4: API Endpoints | 10-11 | 30 min | Chunk 3 |
| 5: MOEWS Fix + Agent Integration | 12-13 | 30 min | Chunk 1 |
| 6: Flutter App | 14-17 | 120 min | Chunk 4 |
| 7: Integration + Demo | 18-20 | 45 min | All |

**Total estimated time: ~6 hours** (with parallel work on backend + Flutter)

---

## Critical Path

1. Database models → Demo data → Seed script
2. Africa's Talking SMS service → Dispatch orchestrator → Hospital notifier
3. Referral API → Main.py update → Backend running
4. Flutter TFLite integration → Screening screen → Referral creation
5. End-to-end test → Demo script → Presentation ready

## Hackathon MVP Scope (What We Build)

- [x] MOEWS calculator (exists, needs fix)
- [x] SMS codec (exists)
- [x] RAG engine (exists)
- [ ] Database layer + models
- [ ] Demo data seeder
- [ ] Africa's Talking SMS service
- [ ] Africa's Talking Voice service
- [ ] Dispatch cascade orchestrator
- [ ] Hospital notifier
- [ ] Referral API endpoints
- [ ] Flutter acoustic screening (YAMNet)
- [ ] Flutter clinical triage (vitals input)
- [ ] Flutter referral creation
- [ ] Offline queue
- [ ] Integration test
- [ ] Demo script

## What We Explicitly Skip (Phase 2)

- Hospital Dashboard with LHIMS
- MoMo real payments (simulated only)
- Dagbani TTS (English only for hackathon)
- Provisioned USSD code (use sandbox)
- NHIS transport voucher integration
- LEAP program integration
- Voice-to-Text clinical dictation
- SLM (Phi-3 Mini/Gemma 2B) on-device
- DHIS2 data sync
- ISO 27001 compliance
