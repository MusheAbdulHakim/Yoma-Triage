# RelayAI Flutter CHO App + YAMNet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter CHO app (Android + web) with YAMNet/stub screening, clinical bypass, offline SQLite outbox, and integration to the existing RelayAI backend via `client_request_id` idempotent referrals.

**Architecture:** Thin Flutter UI talks only to FastAPI. Android runs bundled YAMNet TFLite (stub fallback); web uses a Normal/Code Red simulator. Offline outbox flushes `POST /api/v1/referral` with stable `client_request_id`. Dispatch status polls every 2s. Backend companion adds idempotency + AI screen fields only—no cascade redesign.

**Tech Stack:** Flutter 3.x / Dart 3, `tflite_flutter`, `record`, `sqflite` / `sqflite_common_ffi_web` or conditional imports, `connectivity_plus`, `http`, FastAPI/SQLAlchemy (existing), pytest

**Spec:** `docs/superpowers/specs/2026-07-24-relayai-flutter-yamnet-design.md`

## Global Constraints

- AI advisory only — CHO must Confirm Referral before POST
- Clinical bypass: Home → Emergency Referral skips screening
- Recording: **15s default** + **Stop & Analyze Early**; not mandatory 60s
- YAMNet: **bundle** `assets/models/yamnet.tflite`; **stub fallback** if missing/fail
- Web: simulator only — no TFLite/WASM
- Offline outbox: **never silent-drop**; retry with same `client_request_id`
- Poll interval: **`Duration(seconds: 2)`** on dispatch status
- Base URL: Android emulator `http://10.0.2.2:8000`; web `http://127.0.0.1:8000`
- No OTP/auth this slice; no `/logs` UI; no Africa’s Talking from the phone
- Reuse existing MOEWS/clinical/coordinator — do not rewrite

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `src/db/models.py` | Add `client_request_id`, `ai_screen_result`, `ai_confidence` |
| `src/api/referral.py` | Accept those fields; idempotent create |
| `tests/test_referral_idempotency.py` | Backend duplicate `client_request_id` test |
| `flutter_app/pubspec.yaml` | Flutter deps + assets |
| `flutter_app/lib/main.dart` | App entry + routing |
| `flutter_app/lib/config.dart` | `apiBaseUrl` by platform |
| `flutter_app/lib/models/referral.dart` | DTOs |
| `flutter_app/lib/services/api_client.dart` | HTTP to backend |
| `flutter_app/lib/services/offline_queue.dart` | SQLite outbox |
| `flutter_app/lib/services/screening_service.dart` | Platform facade |
| `flutter_app/lib/services/yamnet_classifier.dart` | TFLite + stub |
| `flutter_app/lib/services/audio_recorder.dart` | 16kHz PCM record |
| `flutter_app/lib/screens/*.dart` | Home, screening, result, referral, status |
| `flutter_app/assets/models/yamnet.tflite` | Bundled or placeholder + stub |
| `flutter_app/test/*.dart` | Unit + widget tests |
| `README.md` | Flutter quick start + model/stub notes |

---

### Task 1: Backend companion — `client_request_id` + AI screen fields

**Files:**
- Modify: `src/db/models.py`
- Modify: `src/api/referral.py`
- Create: `tests/test_referral_idempotency.py`

**Interfaces:**
- Consumes: existing `create_referral`, `Referral`, `DispatchOrchestrator`
- Produces: `ReferralCreate.client_request_id: str | None`, `ai_screen_result: str | None`, `ai_confidence: float | None`; unique DB column; idempotent POST

- [ ] **Step 1: Write failing idempotency test**

```python
# tests/test_referral_idempotency.py
import pytest
from httpx import ASGITransport, AsyncClient
from main import app

@pytest.mark.asyncio
async def test_duplicate_client_request_id_does_not_second_cascade(monkeypatch):
    calls = {"n": 0}
    async def fake_initiate(self, session, referral_id):
        calls["n"] += 1
        class D: id = 1
        return D()
    monkeypatch.setattr(
        "src.api.referral.DispatchOrchestrator.initiate_dispatch",
        fake_initiate,
    )
    # Prefer DB-backed test if DATABASE_URL available; else use TestClient + overridden get_db.
    # Assert: two POSTs with same client_request_id → calls["n"] == 1 and same referral id.
```

Implement a concrete version that uses the real async session against seeded Postgres (same as other integration tests), e.g.:

```python
@pytest.mark.asyncio
async def test_duplicate_client_request_id_returns_same_referral():
    from httpx import ASGITransport, AsyncClient
    from main import app
    body = {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "hash-idem-1",
        "patient_name": "Test",
        "emergency_type": "respiratory_distress",
        "client_request_id": "11111111-1111-1111-1111-111111111111",
        "ai_screen_result": "RED",
        "ai_confidence": 0.82,
        "vitals": {
            "systolic_bp": 70, "diastolic_bp": 50, "heart_rate": 140,
            "respiratory_rate": 35, "temperature": 39.5, "spo2": 85,
            "consciousness_level": "V",
        },
    }
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        r1 = await client.post("/api/v1/referral", json=body)
        r2 = await client.post("/api/v1/referral", json=body)
    assert r1.status_code == 201
    assert r2.status_code in (200, 201)
    assert r1.json()["id"] == r2.json()["id"]
    assert r1.json().get("ai_screen_result") == "RED"
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd /var/www/html/unicef && ./venv/bin/python -m pytest tests/test_referral_idempotency.py -v`

Expected: FAIL (field/column missing or second cascade)

- [ ] **Step 3: Extend `Referral` model**

Add columns (nullable for existing rows):

```python
client_request_id: Mapped[Optional[str]] = mapped_column(String(64), unique=True, nullable=True)
ai_screen_result: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
ai_confidence: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
```

`create_all` on startup will add columns on fresh DBs; for existing Postgres, document `ALTER TABLE` or drop/recreate demo DB if needed for hackathon.

- [ ] **Step 4: Update `ReferralCreate` and `create_referral`**

```python
class ReferralCreate(BaseModel):
    # ...existing fields...
    client_request_id: Optional[str] = Field(default=None, max_length=64)
    ai_screen_result: Optional[str] = None
    ai_confidence: Optional[float] = None
```

At start of `create_referral`:

```python
if payload.client_request_id:
    existing = await session.scalar(
        select(Referral).where(Referral.client_request_id == payload.client_request_id)
    )
    if existing:
        dispatch = await session.scalar(
            select(Dispatch).where(Dispatch.referral_id == existing.id)
        )
        return {
            **_referral_response(existing),
            "dispatch": _dispatch_response(dispatch) if dispatch else None,
            "idempotent": True,
        }
```

When creating new referral, set `client_request_id`, `ai_screen_result`, `ai_confidence` on the model. Include AI fields in `_referral_response`.

- [ ] **Step 5: Run test — expect PASS**

Run: `./venv/bin/python -m pytest tests/test_referral_idempotency.py -v`

- [ ] **Step 6: Commit**

```bash
git add src/db/models.py src/api/referral.py tests/test_referral_idempotency.py
git commit -m "feat: idempotent referral create with client_request_id and AI screen fields"
```

---

### Task 2: Flutter project scaffold + config

**Files:**
- Create: `flutter_app/` via `flutter create`
- Create/Modify: `flutter_app/pubspec.yaml`, `lib/main.dart`, `lib/config.dart`

**Interfaces:**
- Produces: runnable `flutter_app` with deps declared; `ApiConfig.baseUrl`

- [ ] **Step 1: Ensure Flutter SDK**

Run: `flutter --version`

If missing, install Flutter 3.x per https://docs.flutter.dev/get-started/install/linux and ensure `flutter` is on PATH.

- [ ] **Step 2: Create project**

```bash
cd /var/www/html/unicef
flutter create --org gh.relayai --project-name relayai_app flutter_app
```

- [ ] **Step 3: Update `pubspec.yaml` dependencies**

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  sqflite: ^2.3.0
  path: ^1.9.0
  connectivity_plus: ^5.0.0
  uuid: ^4.0.0
  record: ^5.0.0
  tflite_flutter: ^0.11.0
  path_provider: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/models/
```

Create `flutter_app/assets/models/.gitkeep`. Note: `tflite_flutter` is Android/iOS oriented — gate imports with conditional/`kIsWeb`.

- [ ] **Step 4: Add `lib/config.dart`**

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // Android emulator loopback to host
    return 'http://10.0.2.2:8000';
  }
}
```

- [ ] **Step 5: Smoke run**

```bash
cd flutter_app && flutter pub get && flutter analyze
```

Expected: no blocking errors (warnings OK if noted).

- [ ] **Step 6: Commit**

```bash
git add flutter_app
git commit -m "chore: scaffold Flutter CHO app with deps and API config"
```

---

### Task 3: Models + API client

**Files:**
- Create: `flutter_app/lib/models/referral.dart`
- Create: `flutter_app/lib/services/api_client.dart`
- Create: `flutter_app/test/api_client_test.dart` (optional mock)

**Interfaces:**
- Produces: `ApiClient.createReferral(...)`, `getDispatch(id)` matching backend JSON

- [ ] **Step 1: Define `ReferralRequest` / responses**

```dart
class ReferralRequest {
  final String clientRequestId;
  final int chpsCompoundId;
  final int facilityId;
  final String patientHash;
  final String patientName;
  final String emergencyType;
  final Map<String, dynamic> vitals;
  final String? aiScreenResult;
  final double? aiConfidence;

  Map<String, dynamic> toJson() => {
    'client_request_id': clientRequestId,
    'chps_compound_id': chpsCompoundId,
    'facility_id': facilityId,
    'patient_hash': patientHash,
    'patient_name': patientName,
    'emergency_type': emergencyType,
    'vitals': vitals,
    if (aiScreenResult != null) 'ai_screen_result': aiScreenResult,
    if (aiConfidence != null) 'ai_confidence': aiConfidence,
  };
}
```

- [ ] **Step 2: Implement `ApiClient`**

```dart
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.baseUrl;
  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> createReferral(ReferralRequest req) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/referral'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(req.toJson()),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDispatch(int id) async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/dispatch/$id'));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/models flutter_app/lib/services/api_client.dart
git commit -m "feat: add Flutter referral DTOs and API client"
```

---

### Task 4: Offline outbox (never silent-drop)

**Files:**
- Create: `flutter_app/lib/services/offline_queue.dart`
- Create: `flutter_app/test/offline_queue_test.dart`

**Interfaces:**
- Produces: `enqueue(ReferralRequest)`, `flush(ApiClient)`, statuses `pending|sent|failed`

- [ ] **Step 1: Write failing unit test** (use `sqflite_common_ffi` for VM tests)

```dart
test('enqueue then flush marks sent and keeps client_request_id', () async {
  // enqueue one request; mock ApiClient success; flush; expect status sent
});

test('flush failure keeps pending — never silent-drop', () async {
  // mock ApiClient throw; expect still pending
});
```

- [ ] **Step 2: Run — expect FAIL**

`cd flutter_app && flutter test test/offline_queue_test.dart`

- [ ] **Step 3: Implement SQLite outbox**

Table: `id, client_request_id UNIQUE, payload_json, status, last_error, created_at, updated_at`

```dart
class OfflineQueue {
  Future<void> enqueue(ReferralRequest req);
  Future<List<QueuedReferral>> pending();
  Future<void> flush(ApiClient api); // retry pending; on success mark sent; on error keep pending + last_error
}
```

On web: use conditional implementation — `sqflite` may need `sqflite_common_ffi_web` or an in-memory/`shared_preferences` JSON queue for web MVP. Prefer: **mobile uses sqflite; web uses `shared_preferences` list** behind the same `OfflineQueue` interface so tests and UI stay unified.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/offline_queue.dart flutter_app/test/offline_queue_test.dart
git commit -m "feat: add offline referral outbox with safe retry"
```

---

### Task 5: Screening service — YAMNet, stub, web simulator

**Files:**
- Create: `flutter_app/lib/services/screening_result.dart`
- Create: `flutter_app/lib/services/yamnet_classifier.dart`
- Create: `flutter_app/lib/services/audio_recorder.dart`
- Create: `flutter_app/lib/services/screening_service.dart`
- Create: `flutter_app/test/screening_thresholds_test.dart`
- Asset: `flutter_app/assets/models/yamnet.tflite` OR document stub-only until downloaded

**Interfaces:**
- Produces: `ScreeningResult { label: GREEN|RED|INCONCLUSIVE, confidence, reason, source: yamnet|stub|simulator }`

- [ ] **Step 1: Threshold unit test**

```dart
test('confidence above 0.7 maps abnormal to RED', () {
  expect(mapYamnetToResult(abnormalScore: 0.82), isRed);
});
test('confidence below 0.5 is INCONCLUSIVE', () {
  expect(mapYamnetToResult(abnormalScore: 0.4), isInconclusive);
});
```

- [ ] **Step 2: Implement mapper + stub classifier**

```dart
ScreeningResult stubClassify({required bool forceRed}) => ScreeningResult(
  label: forceRed ? 'RED' : 'GREEN',
  confidence: forceRed ? 0.85 : 0.9,
  reason: forceRed ? 'Stub: Code Red (demo)' : 'Stub: Normal (demo)',
  source: 'stub',
);
```

- [ ] **Step 3: YAMNet loader with fallback**

```dart
Future<YamnetClassifier> YamnetClassifier.create() async {
  try {
    final interp = await Interpreter.fromAsset('assets/models/yamnet.tflite');
    return YamnetClassifier._live(interp);
  } catch (_) {
    return YamnetClassifier._stub();
  }
}
```

Do not import `tflite_flutter` on web — use `screening_service_io.dart` / `screening_service_web.dart` with `export` conditional.

- [ ] **Step 4: Audio recorder (IO only)**

15s default timer; expose `stopEarly()`; 16 kHz mono.

- [ ] **Step 5: Obtain model asset**

Download YAMNet TFLite from TensorFlow Hub into `assets/models/yamnet.tflite` when network allows. If blocked, leave README note and rely on stub — success criteria still met.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/services/screening* flutter_app/lib/services/yamnet* flutter_app/lib/services/audio* flutter_app/test/screening_thresholds_test.dart flutter_app/assets
git commit -m "feat: add YAMNet screening with stub and web simulator facades"
```

---

### Task 6: Screens + navigation

**Files:**
- Create: `lib/screens/home_screen.dart`
- Create: `lib/screens/screening_screen.dart`
- Create: `lib/screens/result_screen.dart`
- Create: `lib/screens/referral_screen.dart`
- Create: `lib/screens/dispatch_status_screen.dart`
- Modify: `lib/main.dart`
- Create: `test/bypass_flow_test.dart`
- Create: `test/simulator_flow_test.dart`

**Interfaces:**
- Home routes to Screening or Referral (bypass)
- Result → Referral with AI prefill
- Referral Confirm → OfflineQueue + navigate Status
- Status polls every 2s

- [ ] **Step 1: Widget test — bypass path (failing)**

```dart
testWidgets('Emergency Referral opens vitals without screening', (tester) async {
  await tester.pumpWidget(const RelayApp());
  await tester.tap(find.text('Emergency Referral'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Vitals'), findsOneWidget); // or form field keys
});
```

- [ ] **Step 2: Implement Home + Referral + wiring until bypass test passes**

Large buttons; default compound/facility ids `1` / `1` from seed.

- [ ] **Step 3: Widget test — simulator RED path (web-friendly)**

Pump screening in simulator mode; tap Demo Code Red; Confirm Referral visible.

- [ ] **Step 4: Screening screen**

Android: countdown 15s + Stop & Analyze Early. Web: Demo Normal / Demo Code Red.

- [ ] **Step 5: Result + Dispatch status**

Status: `Timer.periodic(const Duration(seconds: 2), ...)` calling `getDispatch`; cancel on dispose; show status text.

- [ ] **Step 6: Connectivity listener**

On reconnect, `offlineQueue.flush(api)`.

- [ ] **Step 7: Run widget tests**

`cd flutter_app && flutter test`

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib flutter_app/test
git commit -m "feat: add CHO screens with bypass, screening, and 2s status poll"
```

---

### Task 7: README + manual E2E checklist

**Files:**
- Modify: `/var/www/html/unicef/README.md`
- Optional: `flutter_app/README.md`

- [ ] **Step 1: Document Flutter quick start**

```markdown
## Flutter CHO app

cd flutter_app
flutter pub get
# Web (simulator):
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
# Android emulator:
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000

YAMNet: place yamnet.tflite in assets/models/ (bundled). If missing, stub classifier is used automatically.
```

- [ ] **Step 2: Manual E2E**

1. Start backend + seed  
2. Web: simulator RED → confirm → see dispatch status  
3. Toggle offline (devtools) → confirm queues → online flush with same id  
4. Android if available: 15s or early-stop → result → confirm  

- [ ] **Step 3: Commit**

```bash
git add README.md flutter_app/README.md
git commit -m "docs: Flutter CHO app quick start and YAMNet stub notes"
```

---

## Chunk Summary

| Task | Focus | Depends |
|------|--------|---------|
| 1 | Backend `client_request_id` + AI fields | — |
| 2 | Flutter scaffold | — (parallel with 1 OK) |
| 3 | API client | 2 |
| 4 | Offline queue | 3 |
| 5 | Screening / YAMNet / stub | 2 |
| 6 | Screens + tests | 3, 4, 5 |
| 7 | README + E2E | 6 |

---

## Self-Review (plan vs spec)

| Spec item | Task |
|-----------|------|
| Android YAMNet + stub fallback | 5 |
| Web simulator | 5, 6 |
| Clinical bypass | 6 |
| 15s + Stop early | 5, 6 |
| Offline never silent-drop | 4 |
| `client_request_id` idempotency | 1, 3, 4 |
| Persist AI screen fields | 1 |
| Poll 2s | 6 |
| No `/logs` UI | Global |
| Auth Phase 2 | Global / README |
| Bypass widget test | 6 |
| Emulator `10.0.2.2` | 2, 7 |
