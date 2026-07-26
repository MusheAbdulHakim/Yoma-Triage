# Yoma Triage Agent Task & Verification Board

## Status Legend
- `[PENDING]`: Needs implementation
- `[IN_PROGRESS @agent_name]`: Currently being worked on
- `[TESTING @test-agent]`: Awaiting test suite generation and execution
- `[AUDITING @verifier-agent]`: Awaiting spec compliance check
- `[VERIFIED]`: Tested, audited, and ready for deployment
- `[BLOCKED]`: Waiting on dependency

---

## Completed (Backend MVP)

- [VERIFIED] **Task 1.1: Database Models & Schema**
  - Files: `src/db/models.py`, `src/db/database.py`
  - Verified: 2026-07-24
  - Tables: CHPSCompound, Driver, Facility, Referral, Dispatch, DispatchLog, Wallet, AuditLog

- [VERIFIED] **Task 1.2: MOEWS Calculator**
  - Files: `src/tools/moews_calculator.py`
  - Verified: 2026-07-24
  - All 7 parameters: SBP, DBP, HR, RR, Temp, SpO2, AVPU

- [VERIFIED] **Task 1.3: SMS Codec**
  - Files: `src/tools/sms_codec.py`
  - Verified: 2026-07-24
  - Binary compression: 5 fields → 6 bytes → Base64

- [VERIFIED] **Task 1.4: LangGraph Coordinator**
  - Files: `src/agents/coordinator.py`, `src/agents/clinical_agent.py`
  - Verified: 2026-07-24
  - Clinical assessment → prepare_dispatch flow

- [VERIFIED] **Task 1.5: Dispatch Orchestrator**
  - Files: `src/services/dispatch_orchestrator.py`
  - Verified: 2026-07-24
  - Cascade tiers, timeouts, idempotent accept/decline

- [VERIFIED] **Task 1.6: Messaging Gateway**
  - Files: `src/services/messaging_gateway.py`
  - Verified: 2026-07-24
  - AT SMS mock/sandbox, Voice stub

- [VERIFIED] **Task 1.7: USSD Handler**
  - Files: `src/api/ussd.py`
  - Verified: 2026-07-24
  - Fast USSD callback, idempotent, background tasks

- [VERIFIED] **Task 1.8: Referral API**
  - Files: `src/api/referral.py`
  - Verified: 2026-07-24
  - POST /api/v1/referral, GET /referral/{id}, GET /dispatch/{id}, GET /dispatch/{id}/logs

- [VERIFIED] **Task 1.9: Demo Data Seeder**
  - Files: `src/db/seed.py`
  - Verified: 2026-07-24
  - Compounds, drivers, facilities seeded

- [VERIFIED] **Task 1.10: Demo Flow Script**
  - Files: `scripts/demo_flow.py`
  - Verified: 2026-07-24
  - Happy path, decline path, hospital CONFIRM/DIVERT

- [VERIFIED] **Task 2.1: Add client_request_id to Referral API**
  - Files: `src/api/referral.py`
  - Verified: 2026-07-24

- [VERIFIED] **Task 2.2: Persist ai_screen_result/ai_confidence**
  - Files: `src/db/models.py`, `src/api/referral.py`
  - Verified: 2026-07-24

- [VERIFIED] **Task 3.1: Hospital DIVERT handler**
  - Files: `src/api/sms_webhook.py`
  - Verified: 2026-07-25
  - Parse `DIVERT {dispatch_id} {facility_id}`; notify driver + CHO; log

- [VERIFIED] **Task 3.2: Driver availability endpoint**
  - Files: `src/api/driver.py`, `src/services/driver_pool.py`
  - Verified: 2026-07-25
  - `POST /api/v1/driver/{id}/availability`
  - `GET /api/v1/compound/{id}/drivers`

- [VERIFIED] **Task 3.3: Add python-multipart dependency**
  - Files: `requirements.txt`, `pyproject.toml`
  - Verified: 2026-07-25

---

## Completed (Mobile/Flutter)

- [VERIFIED] **Tasks 4.1–4.7** — Flutter CHO app in `mobile/`
  - Setup, YAMNet/stub, web simulator, screens, offline queue, API client
  - Note: real `yamnet.tflite` asset still missing (stub fallback on Android)

---

## Completed (Testing)

- [VERIFIED] **Task 5.1: MOEWS Threshold Tests** — `tests/test_moews.py`
- [VERIFIED] **Task 5.2: SMS Codec Round-trip Tests** — `tests/test_sms_codec.py`
- [VERIFIED] **Task 5.3: USSD Idempotency Tests** — `tests/test_ussd_idempotency.py`
- [VERIFIED] **Task 5.4: Concurrent Accept Tests** — `tests/test_dispatch.py`
- [VERIFIED] **Task 5.5: Integration Test (Full Flow)** — `tests/test_integration.py`
- [VERIFIED] **Task 5.6: Flutter Widget Tests** — `mobile/test/widget_test.dart`

---

## Completed (Verification)

- [VERIFIED] **Task 6.1: Backend Spec Compliance Audit**
  - Report: `docs/superpowers/specs/2026-07-25-yoma-triage-compliance-audit.md`
  - Verified: 2026-07-25

- [VERIFIED] **Task 6.2: Mobile Spec Compliance Audit**
  - Report: `docs/superpowers/specs/2026-07-25-yoma-triage-compliance-audit.md`
  - Verified: 2026-07-25
  - PARTIAL: Android YAMNet requires model asset

---

## Hackathon production-close (2026-07-26)

PO decisions locked: Android+iPhone+responsive web; live AT SMS with mock fallback; real YAMNet TFLite; Yoma Triage naming; architecture narrative. **No git commits** in this pass unless requested.

| ID | Item | Status |
|----|------|--------|
| W0.0 | Flutter baseline `YomaApp` tests | [VERIFIED] `flutter test` green |
| W0.1 | Relay* → Yoma rebrand (docs + MoMo prefix) | [VERIFIED] grep-clean on active surfaces |
| B1 | Hospital SMS patient-token privacy | [VERIFIED] `tests/test_hospital_privacy.py` |
| B1b | Unlinkable SHA-256 tokens + API | [VERIFIED] `tests/test_referral_privacy.py` + Flutter `patient_token` |
| B0 | CORS allowlist for Flutter web | [VERIFIED] `tests/test_cors.py` |
| B3 | USSD arrival → COMPLETED | [VERIFIED] `tests/test_ussd_arrival.py` |
| B5 | AT live/mock runbook | [VERIFIED] `docs/plans/at-sandbox-runbook.md` |
| Arch | Judge architecture narrative | [VERIFIED] `docs/architecture-narrative.md` |
| M2 | Advisory / demo disclaimer UI | [VERIFIED] `mobile/test/result_disclaimer_test.dart` |
| M2b | Vendored `yamnet.tflite` + class-map scoring | [VERIFIED] asset present; stub fallback remains |
| M1/M4/M5/M6 | Theme, a11y, offline rebound, facility labels | [VERIFIED] implemented; covered by suite |
| iOS | Flutter iOS target + mic permission | [VERIFIED] `mobile/ios/` present |

Regression (lead verify): **pytest 61 passed**; **flutter test 19 passed** (2026-07-26).

---

## Blockers

- Live Africa’s Talking SMS to a real phone requires operator-provided `AT_API_KEY` / `AT_USERNAME` in `.env` (mock works without keys). See `docs/plans/at-sandbox-runbook.md`.

---

## Notes

- Backend suite: `python -m pytest -v` (**61 passed** as of 2026-07-26)
- CHO Flutter app lives in `mobile/` (Android, iOS, responsive web)
- Demo flow script covers happy path, decline, hospital CONFIRM/DIVERT, and arrival
- YAMNet is advisory AudioSet detection only — never claim obstetric diagnosis
- Explicit backlog: real MoMo, Dagbani TTS, on-device SLM, SQLCipher/auth, hospital dashboard, validated respiratory model
