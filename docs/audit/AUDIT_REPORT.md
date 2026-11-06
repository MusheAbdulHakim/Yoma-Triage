# Yoma Triage — Codebase Audit Report

**Audited:** commit `d3f2977` (branch `main`, clean tree) · **Audit date:** 2026-11-05
**Spec used as source of truth:** `PRODUCT_SPEC.md` v2.0 (23 July 2026)
**How to read the evidence:** claims marked **[RAN]** were reproduced by executing the code. Claims marked **[READ]** come from reading the code and were not executed. Nothing was run on a physical Android or iOS device, because no Android SDK, iOS toolchain or handset was available.

---

## 1. Executive summary

- **The backend happy path works.** `scripts/demo_flow.py` passes end to end in mock mode: referral → SMS → USSD accept → mock stipend → hospital notice → CONFIRM → arrival, plus the decline and DIVERT paths **[RAN]**.
- **Acoustic screening almost certainly does not work on any real device.** `yamnet_classifier_io.dart` passes a flat `List<double>(521)` as the output buffer for a `[1, 521]` tensor. The pinned `tflite_flutter` 0.11.0 throws on that shape mismatch, the startup probe catches it, and the app silently falls back to a stub returning **GREEN, 90% confidence, every time**. This rests on the plugin source, the real model's shapes and a run of the fallback path. It still needs one device run to confirm, and `todo.md` still lists the physical Android and iPhone runs as open.
- **Even with that bug fixed, the YAMNet approach is not clinically meaningful.** Silence, tones and noise all score GREEN **[RAN]**. "Breathing" counts as an abnormal class, so audible normal breathing can score RED. AudioSet has no stridor class, and its "Crackle" (index 293) isn't a respiratory sound and isn't used.
- **Two drivers can both be told "Accepted".** This happened in **29 of 30** concurrent trials on real Postgres **[RAN]**. The cause is a stale ORM read under `FOR UPDATE`; a one-line fix took it to 0 of 30. The existing "concurrent accept" test is sequential on SQLite, so it can't catch this.
- **The cascade isn't fit for a real emergency.** Its default timeout is **5 s, not 90 s**. A Motor-King driver who responds after one timeout is refused, and every driver is refused once it reaches FAILED **[RAN]**. Timers live in process memory, so a restart strands the referral permanently with no CHO alert **[RAN]**. Voice and personal-contact tiers don't exist.
- **MOEWS is applied to children using adult obstetric thresholds.** Illustrative vitals in a typical range for a healthy 2-year-old score **RED (6)**, and for a newborn **RED (12)** **[RAN]**. The app never collects age. This is a clinical-safety blocker, and the spec itself creates it.
- **The manual referral form opens pre-filled with critical vitals and a real-looking name** (BP 70/50, SpO₂ 85, "Ama Mensah"), and the screening vitals form opens pre-filled with normal values. One unread tap sends fabricated clinical data or false reassurance **[READ]**.
- **Whole spec areas have no code:** CHO auth/OTP, outcome recording, adverse-outcome flow, caregiver refusal, SMS fallback, voice, Dagbani, driver registration, retention jobs, audit-log writes (0 rows after a full flow **[RAN]**), the 70% payout, and real MoMo.
- **Production can silently send nothing.** With `ENVIRONMENT=production` and no AT key, referrals return 201 and SMS is recorded `MOCKED` **[RAN]**. With `ENVIRONMENT` unset, all APIs and webhooks are unauthenticated **[RAN]**.
- **Operations aren't set up:** no CI, Dockerfile, deploy config, migrations, monitoring or backups. Every install dispatches as compound #1 because nothing ever sets the home compound. Release signing uses debug keys. The Flutter web build fails from the committed lockfile, and one Flutter test fails on `main` **[RAN]**.

### Readiness ratings

| Target | Rating | Blunt verdict |
|---|---|---|
| **(a) Hackathon demo** | **6/10 — demoable with care** | The backend path is solid when scripted or tightly rehearsed. Before presenting: set `CASCADE_TIER_SECONDS` to 90, pre-warm the server (first referral blocks about 134 s on a cold cache), and fix or avoid the web build and the acoustic path. Do not present acoustic results from a phone as real. |
| **(b) Production pilot** | **1.5/10 — not safe to pilot** | The cascade, acoustic path, paediatric scoring, authentication and data handling each independently block live patient use. There is also no clinical validation, ethics clearance, or provisioned USSD, voice or MoMo. A realistic estimate is 3–5 months of engineering plus external approvals. |

---

## 2. Repo map

| Component | Path | Language / framework | Versions | Notes |
|---|---|---|---|---|
| Yoma Care (CHO app) | `mobile/` | Dart / Flutter | Flutter 3.44.8 (`mobile/.metadata`), Dart 3.12; `tflite_flutter` 0.11.0, `record` 5.2.1, `sqflite` 2.4.3, `connectivity_plus` 6.1.5 | Android, iOS, web targets. 39 Dart files in `lib/`, 18 test files. |
| Yoma Dispatch (API) | `main.py`, `src/` | Python ≥3.11 / FastAPI, SQLAlchemy async, asyncpg, LangGraph, Chroma, sentence-transformers | **Unpinned (`>=`), no lockfile.** Resolved at audit: FastAPI 0.162.0, SQLAlchemy 2.1.8, LangGraph 1.2.20, torch 2.15.0 | 28 test modules. |
| Database | `src/db/models.py`, `src/db/seed.py` | PostgreSQL | Tables created by `create_all` at startup (`src/db/database.py:18-21`) | **No migrations.** No Supabase config or RLS found. |
| Infra / deploy | — | — | — | **Not found.** Searched for Dockerfile, docker-compose, Procfile, railway, render.yaml, fly.toml, supabase, alembic. |
| CI | — | — | — | **Not found.** No `.github/`. Only `.pre-commit-config.yaml`, whose `detect-secrets` hook references a missing `.secrets.baseline`. |
| Docs | `docs/`, `README.md`, `todo.md`, `TASK_BOARD.md` | Markdown | — | `docs/yoma-triage-product-spec.md` is an older spec copy that differs from `PRODUCT_SPEC.md` (lacks status notes, describes the escrow differently). README and TASK_BOARD link to `docs/superpowers/…`, which is gitignored and absent. |
| Models | `mobile/assets/models/` | TFLite / ONNX | `yamnet.tflite` 4.0 MB, `opera_ce_encoder.tflite` 7.7 MB, `opera_ce_encoder.onnx` 16 MB | The whole folder is bundled (`pubspec.yaml`). **The 16 MB ONNX file is never loaded by app code.** |
| Reference data | `data/` | JSON, PDF, WAV | catalog `2026-07-28.4` | 16 Northern Region MMDAs. Notes say to replace with the GHS master list before pilot. |
| Tooling | `scripts/`, `start_demo.sh` | Python, Bash | — | Demo flow, CORS smoke test, model fetch/export/training. |

### Git history (58 commits on `main`, 2026-07-24 → 2026-11-05)

- 29 of the 58 commits landed on 2026-07-28, and only one is dated after July. The most recent work is OPERA-CE model wiring and demo-flow fixes.
- **Looks abandoned mid-way:**
  - OPERA-CE: encoder shipped, classifier head never trained; `data/lab_set/` holds only synthetic sine-wave clips.
  - HeAR: the legal review decision log is empty.
  - MoMo: `src/tools/momo_escrow.py` is dead code.
  - Voice: `initiate_voice` is a stub that is never called.
  - RAG: `ingest.py` is outside the production flow, and PDFs in `data/ghs_protocols/` are never loaded by `engine.py`, which reads only `.md`/`.txt`.

---

## 3. Commands run & results

All commands ran against an export of `HEAD` in a temporary directory, using a private Postgres cluster on port 55432. The repo's only change is this report. No AT, MoMo or Supabase calls were made and no SMS was sent. Hugging Face was contacted once to fetch the public embedding model the app itself requests.

| # | Command | Result |
|---|---|---|
| 1 | `pip install -r requirements.txt -r requirements-dev.txt` (via `uv`, Python 3.12) | **First attempt failed**: the default resolve pulls CUDA torch (`nvidia-cufft`, several GB) and timed out. **Succeeded** with CPU torch installed first. Environment is still **1.7 GB**. |
| 2 | `pytest -q --cov=src --cov=main` | **104 passed, 1 skipped** (`test_opera_ce_mel`: no `librosa`). **76% coverage** (1359 statements). 0%: `momo_escrow.py`, `rag/ingest.py`, `acoustic/opera_ce_mel.py`, `dispatch_agent.py`. Tests use SQLite and mocks, so row locks are never exercised. |
| 3 | `ruff check .` | **15 errors** (7 N806, 3 I001, 3 F401, 1 UP035, 1 SIM108) |
| 4 | `ruff format --check .` | **55 of 93 files would be reformatted** |
| 5 | `mypy src main.py` | **28 errors in 11 files** |
| 6 | `pip-audit --no-deps --disable-pip -r <frozen>` | **10 rows, 2 packages**: `chromadb` 1.5.9 (PYSEC-2026-311, -3813, -3814, -3815; no fix listed), `setuptools` 78.1.0 (PYSEC-2025-49, PYSEC-2026-3447, GHSA-xmj3-9gf7-h52w; fixed by 84.1.0). Audits a fresh resolve, which may differ from any deployment because nothing is pinned. |
| 7 | `flutter pub get` (3.44.8, committed lockfile) | OK. Lockfile unchanged. |
| 8 | `flutter analyze` | **No issues found** |
| 9 | `flutter test --coverage` | **54 passed, 1 FAILED.** `test/simulator_web_test.dart:42` expects text `RED`; the result hero has shown `MOEWS …` since the fusion commit. **58.7% line coverage.** 0%: `yamnet_classifier_io.dart`, `opera_ce_classifier_io.dart`, `queue_sync_service.dart`, `dispatch_status_screen.dart`. Docs still claim 19 passing. |
| 10 | `flutter build web --dart-define=APP_ENV=production` | **FAILED.** `record_web-1.3.0 mic_recorder_delegate.dart:168: getter 'streamBufferSize' isn't defined for 'RecordConfig'`, caused by the committed `dependency_overrides: record_platform_interface: 1.2.0`. |
| 11 | `flutter pub outdated` | 47 packages behind. `tflite_flutter` 0.11.0 → 0.12.1 (spec asks ^0.12.1), `record` 5.2.1 → 7.1.2, `connectivity_plus` 6.1.5 → 7.3.2. No Dart advisory scanner was run. |
| 12 | `flutter build apk` / `ios` | **Not attempted.** No Android SDK or Xcode on the audit machine. |
| 13 | `uvicorn main:app` + `python -m src.db.seed` | **Starts** in ~4 s. Idle RSS 143 MB → **662 MB** after the first referral. |
| 14 | First `POST /api/v1/referral` timing | **Cold HF cache: 133.9 s, and `GET /` was blocked for 133.7 s.** Warm cache after restart: 8.3 s. HF unreachable: 5.7 s, MOEWS preserved. Later referrals: 0.04 s. |
| 15 | `python scripts/demo_flow.py` | **Passes (exit 0).** Acts on each step within about a second, so it never exercises real driver response times. |
| 16 | Custom concurrency and flow reproductions, YAMNet probe | Results in §7 and §5. |

**Two hypotheses the reproductions refuted, recorded so nobody re-chases them:**
- "The timer fires before commit and kills the cascade" is false. The timer is scheduled after the inline SMS sends.
- "Duplicate POSTs double-send SMS" is false. The loser blocks on the unique index and returns HTTP 500, which the client's retry path recovers from.

---

## 4. Feature status matrix

Paths are relative to the repo root; `m/` = `mobile/lib/`.

### Mobile app

| Area | Feature | Status | Evidence | Notes |
|---|---|---|---|---|
| Acoustic | 16 kHz mono PCM capture | IMPLEMENTED | `m/services/audio_recorder_io.dart:26-33` | Not device-tested. |
| Acoustic | 60 s recording | DIVERGES | `m/config.dart:39` | Default **15 s**; `.env.example` says 30; spec says 60. |
| Acoustic | YAMNet load & inference | **STUBBED/MOCK (effective)** | `m/services/yamnet_classifier_io.dart:51-60,194-204`; plugin `tensor.dart` `_duplicateList` | Output buffer shape mismatch → `ArgumentError` → stub. See BUG-1. Needs device confirmation. |
| Acoustic | Web screening | STUBBED/MOCK | `m/screens/screening_screen.dart:152-194` | "Demo Normal / Demo Code Red" buttons, with no production gate. |
| Acoustic | >0.7 → Code Red | IMPLEMENTED | `m/services/screening_result.dart:19` | Unreachable on device until BUG-1 is fixed. |
| Acoustic | <0.5 → "Inconclusive" | **DIVERGES** | `m/services/screening_result.dart:29-38` | **<0.5 returns GREEN.** Inconclusive is only 0.5–0.7. Spec §7.1.1 says below 0.5 is inconclusive. Locked in by `test/screening_thresholds_test.dart`. |
| Acoustic | Plain-language reasoning | PARTIAL | `m/services/screening_result.dart:23-24` | Generic "Abnormal breathing detected"; never names which sound. The GREEN card shows the *abnormal* score as "Confidence", e.g. 3%. |
| Acoustic | Audio deleted after processing | PARTIAL | `m/services/audio_recorder_io.dart:46-50` vs `:54-61` | Deleted on `stop()`. **`dispose()` (Back during recording) stops without deleting, leaving a WAV in temp.** |
| Acoustic | Fails safe to INCONCLUSIVE | **DIVERGES** | `m/services/yamnet_classifier_io.dart:194-201`; `m/screens/screening_screen.dart:86-87` | Model card says load failure → INCONCLUSIVE. Actually **GREEN 0.9**, also on mic failure **[RAN]**. |
| Models | HeAR | STUBBED/MOCK | `m/services/screening_model_factory.dart:9-24,71-72` | Returns INCONCLUSIVE. ToS review incomplete (`docs/legal/hai-def-hear-tos-review.md`). |
| Models | OPERA-CE (not in spec) | PARTIAL | `m/services/opera_ce_classifier_io.dart:65-67,133-141` | No trained head, same flat-buffer pattern (output `[1,1280]`); ends INCONCLUSIVE on either path, which is safe. |
| Models | On-device SLM | MISSING (as spec backlog) | Searched `mobile/pubspec.yaml`, `m/` | Absent. Spec Part XVI still lists it as Phase 1. Server RAG/Gemini exists instead. |
| Referral | Manual emergency referral | DIVERGES | `m/screens/referral_screen.dart:343-360` | Types are respiratory, PPH, neonatal asphyxia, eclampsia. **No neonatal sepsis, severe malaria or "Other".** Requires full vitals and facility confirmation; spec needs only type and name. |
| Referral | Patient name or "Unknown" | DIVERGES | `m/screens/referral_screen.dart:37,330-339`; `src/api/referral.py:156` | Prefilled "Ama Mensah", required, never sent or stored. DB always stores "Unknown". |
| MOEWS | Parameter scoring (Dart + Python) | IMPLEMENTED, 1 divergence | `m/services/moews_calculator.dart:29-69`; `src/tools/moews_calculator.py:8-61` | Implementations match each other. See table below. |
| MOEWS | Green/Yellow/Red rules | IMPLEMENTED | `m/services/moews_calculator.dart:71-75` | Follows the "any single parameter" reading, so Green means score 0. See §5. |
| MOEWS | Yellow-tier actions | MISSING | Searched `src/`, `m/` | No coordinator notice, 30-min monitoring or soft reservation. Yellow dispatches like Red. Even a GREEN referral POST dispatches **[RAN]**. |
| MOEWS | Acoustic + MOEWS combination | PARTIAL | `m/services/referral_gating.dart:1-20`; `src/api/referral.py:158-160` | Only controls which button shows. Backend severity is MOEWS only. **Acoustic RED + MOEWS ≥3 never becomes Red**: Yellow stays Yellow. Acoustic RED with normal vitals shows a large "MOEWS GREEN" hero. |
| Offline | SQLite outbox + idempotent id | IMPLEMENTED | `m/services/offline_queue.dart:137-190`; `src/api/referral.py:119-130` | Saved before the send attempt. Tested. |
| Offline | Connectivity detection & retry | PARTIAL | `m/services/queue_sync_service.dart:24-43` | Retries only on connectivity *change*, at startup, or manual tap. **Backend outage on steady Wi-Fi never auto-retries.** 0% coverage. |
| Offline | SMS fallback (Base64, CRC-16, layout) | MISSING | Searched `m/`, `pubspec.yaml`; no SMS plugin | The app can't send SMS at all. |
| Offline | Backend SMS codec | PARTIAL | `src/tools/sms_codec.py:30-34` | **6 bytes** (compound, score, risk, HR, SBP). No CRC, no 140-octet layout. Stored, never transmitted, inbound never decodes it. |
| Offline | AES-256-GCM on SMS | MISSING | Searched `src/`, `m/` | Confirms the spec status note. |
| Journey 5 | Caregiver refusal documentation | MISSING | Searched `src/`, `m/` for refus*/caregiver | "Continue Monitoring" records nothing. README claims refusals are documented. |
| Outcomes | Arrived alive / deceased / unknown | MISSING | Searched `src/`, `m/`; no `outcome` column in `src/db/models.py` | |
| Auth | CHO phone + OTP | MISSING | `src/api/deps.py:3`; `docs/deploy-environments.md:37` | Explicitly deferred. One shared API key compiled into the app. |
| Backend-mediated | App never calls AT | IMPLEMENTED | No AT references in `m/`; `m/services/api_client.dart` | Confirmed. |
| i18n | Dagbani / English | MISSING | Searched `m/`, `pubspec.yaml` for l10n/intl/Dagbani | English hardcoded. |
| Setup | Home CHPS selection | **MISSING** | `m/services/catalog_store.dart:24-31`; `m/screens/referral_screen.dart:93` | The setter is **never called**. Every install is compound #1. |

**MOEWS parameter-by-parameter**

| Parameter | Spec | Code | Verdict |
|---|---|---|---|
| Systolic | <80 R; 80–90 Y; 90–140 N; 140–150 Y; >150 R | Same; 90, 140 and 150 score 1 | Match. Spec boundaries overlap; code picks the higher score. |
| Diastolic | 60–90 N; 90–100 Y; >100 R; **nothing below 60** | Same, **plus <60 = 3 (RED)**; 90 scores 1 | **DIVERGES**: code adds a rule. Clinically defensible, but undocumented in the spec table. |
| Heart rate | <50/>130 R; 50–60, 110–130 Y | Same | Match |
| Resp. rate | <10/>30 R; 10–14, 24–30 Y | Same | Match |
| Temperature | <35/>39 R; 35–36, 38–39 Y | Same; 36.0 and 38.0 score 1 | Match. **Temp 36.0 alone → YELLOW → referral CTA [RAN].** |
| SpO₂ | <90 R; 90–94 Y; ≥95 N | Same; optional | Match. Backend treats missing as 0. |
| Consciousness | V/P/U = 3 | Same | Match |
| Missing required vital | Not specified | Returns UNKNOWN | Sensible addition. |

### Backend

| Area | Feature | Status | Evidence | Validated / Auth / Tested |
|---|---|---|---|---|
| API | `POST /api/v1/referral` | IMPLEMENTED | `src/api/referral.py:109-177` | Validation **weak** (below) / API key / yes |
| API | `GET /api/v1/dispatch/{id}` | IMPLEMENTED | `src/api/referral.py:188-193` | ETA **hardcoded 30** (`:96`) / API key / yes |
| API | `POST /api/v1/ussd/callback` | DIVERGES (path) | `src/api/ussd.py:30,175` | Actual path is `/ussd/callback` / secret / yes |
| API | `POST /api/v1/voice/callback` | **MISSING** | Searched `src/api/` | |
| API | `POST /api/v1/sms/inbound` | IMPLEMENTED | `src/api/sms_webhook.py:328-373` | Sender check / secret / yes |
| API | `GET /api/v1/driver/{id}/status` | IMPLEMENTED | `src/api/driver.py:56-69` | API key / yes |
| API | `POST /api/v1/driver/{id}/availability` | IMPLEMENTED | `src/api/driver.py:72-83` | Enum validated / API key / yes. Any key holder can change any driver. |
| API | `GET /api/v1/compound/{id}/drivers` | IMPLEMENTED | `src/api/driver.py:86-97` | API key / yes. Returns driver phones. |
| API | Input validation | PARTIAL | `src/api/referral.py:32-59` | SBP 1200 and HR −5 accepted; MOEWS discarded. `emergency_type` >64 chars → HTTP 500 **[RAN]**. |
| Cascade | Tier 1 Motor-King SMS | IMPLEMENTED | `src/services/dispatch_orchestrator.py:122-142` | |
| Cascade | Tier 1 voice, tier 2 voice | **MISSING** | `src/services/messaging_gateway.py:189-206`; never called | `initiate_voice` always returns FAILED when AT is configured. |
| Cascade | Fallback SMS | IMPLEMENTED | `src/services/driver_pool.py:48-52` | Non-Motor-King in the same compound. |
| Cascade | Personal contacts | **MISSING** | `src/services/dispatch_orchestrator.py:98-99`; no model | Comment states it's deliberately excluded. |
| Cascade | CHO manual notice | IMPLEMENTED | `src/services/dispatch_orchestrator.py:100-120` | Tells the CHO to escalate to NAS. |
| Cascade | 90 s per tier | **DIVERGES** | `src/config.py:34`; `.env.example` | **Default 5 s.** Full cascade ends in about 10 s. |
| Cascade | Durable timing | **MISSING** | `src/services/dispatch_orchestrator.py:82-83,421-422` | `asyncio.create_task` + `sleep`. No scheduler, queue or worker. Task reference isn't retained. Single-process only. |
| Cascade | Survives restart | **MISSING** | `main.py:24-30` **[RAN]** | Referral stays `TIER1_NOTIFIED` forever; CHO gets no notice. |
| Cascade | Idempotent side effects | PARTIAL | `src/services/dispatch_orchestrator.py:330-339,288-295` | Guarded by log checks. A crash between accept commit and side effects strands the dispatch at `ACCEPTED`. |
| Cascade | Single-driver claim | **DIVERGES** | `src/services/dispatch_orchestrator.py:148-150` **[RAN]** | Two drivers both "Accepted", 29/30. |
| USSD | Accept / Decline | IMPLEMENTED (buggy) | `src/api/ussd.py:32-37,157-172` | See BUG-3, BUG-9, BUG-10. |
| USSD | Delay option | **MISSING** | `src/api/ussd.py:32-37` | Option 3 is arrival. |
| USSD | Availability menu | **MISSING** | `src/api/ussd.py` | REST only; a feature phone can't use it. |
| USSD | Confirm arrival | IMPLEMENTED | `src/api/ussd.py:117-140` | Blocked after a diversion (BUG-5). |
| USSD | CHO accept-delay | **MISSING** | Searched `src/` | |
| Hospital | Pre-arrival SMS | PARTIAL | `src/services/hospital_notifier.py:19-30` | No age/gender, ETA or AI screen; 227 chars = 2 segments. |
| Hospital | CONFIRM | IMPLEMENTED | `src/api/sms_webhook.py:212-267` | Also accepts `YES`/`OK`/`Y`, and from the **driver's** phone. |
| Hospital | DIVERT | PARTIAL | `src/api/sms_webhook.py:269-325` | Numeric facility ID only; staff are never told IDs. No reason. Driver's phone can divert **[RAN]**. Rejected after CONFIRM. |
| Hospital | Diversion re-notification | PARTIAL | `src/api/sms_webhook.py:298-319` **[RAN]** | Driver and CHO notified; **new hospital is not**. No new ETA. |
| Hospital | Arrival notice to hospital | MISSING | `src/services/dispatch_orchestrator.py:275-315` | CHO only. |
| Notify | CHO SMS on accept | **MISSING** | `src/services/dispatch_orchestrator.py:317-373` **[RAN]** | Only visible by app polling. Patient SMS also absent. |
| Voice | TTS English / Dagbani | MISSING | `src/services/messaging_gateway.py:189-206` | Principle 5 calls voice primary. |
| MoMo | Mock ledger `MOCK_RECORDED` | STUBBED/MOCK | `src/services/dispatch_orchestrator.py:341-364` | **Confirmed.** Wallet row status reads `INITIAL_DISBURSED` though nothing moved. |
| MoMo | 30/70 split, fare calculation | **MISSING** | `src/services/dispatch_orchestrator.py:23` | Constant GHS 22.50. No fare, no 70% release. `momo_escrow.py` is dead code with wrong auth and environment headers. |
| Priority | Referral prioritisation | **MISSING** | Searched `src/`, `m/` | Mentioned only in RAG text. |
| Drivers | Registration, add/remove | **MISSING** | Searched `src/api/` | Seed file only. |
| Drivers | Availability respected | PARTIAL | `src/services/driver_pool.py:43-47` | Filter works, but **accept doesn't set ON_TRIP** and nothing can via USSD **[RAN]**. |
| Security | `AT_WEBHOOK_SECRET` | IMPLEMENTED | `src/api/deps.py:43-63` | Fail-closed only in staging/production. Query-string form leaks into logs. |
| Security | `API_KEY` | IMPLEMENTED | `src/api/deps.py:24-40` | Same. Single shared key. |
| Security | Rate limiting | **MISSING** | Searched `src/`, `main.py`, requirements | |
| Audit | Audit log writes | **MISSING** | `src/db/models.py:119`, no writers **[RAN]** | 0 rows. `dispatch_logs` is a partial substitute. README claims audit logs. |
| Adverse | Clinical review flag, district notice | **MISSING** | Searched `src/`, `m/` | |

### Data

| Item | Status | Evidence | Notes |
|---|---|---|---|
| Tables | PARTIAL | `src/db/models.py` | Present: `chps_compounds`, `drivers`, `facilities`, `referrals`, `dispatches`, `dispatch_logs`, `wallets`, `audit_logs`. |
| **Missing tables** | MISSING | — | `emergency_contact`. Part X also lists Patient, Journey and Notification entities that §11.1 omits. |
| **Missing fields** | MISSING | — | `referral.outcome`, `facility.blood_bank_status`. `driver` lacks the license plate required by §7.2.3. |
| **Extra fields** | — | `src/db/models.py` | `referral`: `facility_id`, `patient_hash`, `moews_score`, `risk_level`, `clinical_summary`, `compressed_sms_payload`, `vitals_json`, `client_request_id`, `ai_model_version`. `dispatch`: `facility_id`, `current_tier`, `declined_driver_ids`. `driver.availability`, `facility` lat/long, `wallet.dispatch_id`/`transaction_id`. |
| Unpopulated | PARTIAL | `src/api/referral.py:152-169` | `patient_age`, `patient_gender` never set; the API has no such inputs. |
| Types | Risk | `src/db/models.py:111` | Money stored as `Float`. |
| Patient name vs hash | IMPLEMENTED (token) | `src/api/referral.py:155-156`; `m/services/patient_token.dart:8-12` | Name column always "Unknown". The "hash" is SHA-256 of random bytes, new per referral, so it's unlinkable but also useless for hospital matching. |
| 90-day retention | **MISSING** | Searched `src/`, `scripts/` | No job, scheduler or anonymisation. |
| Encryption at rest | Not determinable | No app-level encryption; `vitals_json` plain JSON | Depends on host. No host configured. |
| RLS | **MISSING** | No Supabase/SQL files | Single DB role assumed. |
| Seed data | STUBBED/MOCK | `data/demo_data.json` | Fake phones. **Only 5 drivers, in compounds 1 and 2**; 14 of 16 compounds have none, so they fail immediately to CHO manual. |
| Geography | **DIVERGES** | `data/northern_referral_graph.json`; `src/api/catalog.py:46-50` | Northern Region only. **Kassena-Nankana East (Upper East), a named pilot district, is absent and other regions return 404.** Coordinates come from OSM geocoding of MMDA seats, with invented "CHPS" per MMDA. |

### Security & Ops

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| SQLCipher | MISSING (confirmed) | `mobile/pubspec.yaml` (`sqflite`); `m/services/offline_queue.dart:115` | Plaintext vitals. |
| Certificate pinning | MISSING (confirmed) | `m/services/api_client.dart:24` | |
| TLS | PARTIAL | `mobile/android/app/src/main/AndroidManifest.xml:8` | **`usesCleartextTraffic="true"` in the main manifest.** Default URLs are `http://`. |
| Tests | PARTIAL | §3 | No real-DB, device or integration tests. |
| CI/CD, Docker, deploy config | MISSING | §2 | |
| Env separation | PARTIAL | `src/config.py:9`; `docs/deploy-environments.md` | `ENVIRONMENT` flag only, defaults to the open `development`. |
| Logging | PARTIAL | Only `src/rag/ingest.py:59` configures logging | `LOG_LEVEL` is read and never applied. No structure, no request IDs. |
| Monitoring, alerting, error tracking | MISSING | Searched requirements, `pubspec.yaml`, `src/` | No Sentry or metrics. |
| Health check | PARTIAL | `main.py:56-76` | Static; doesn't touch the DB. Exposes `at_configured`. |
| Migrations, backups | MISSING | `src/db/database.py:18-21` | `create_all` can't alter existing tables. |
| AT sandbox vs production | IMPLEMENTED | `src/config.py:79-85`; `src/services/messaging_gateway.py:23-27` | Clean switch. Live path untested at audit. **Missing key silently mocks.** |
| USSD code | PARTIAL | `src/config.py:25`; `src/api/ussd.py:65-73` | Configurable; docs use sandbox `*384*99193#`. Production code not provisioned. Empty code → SMS says "Dial USSD". |
| App signing | **STUBBED/MOCK** | `mobile/android/app/build.gradle.kts:33-37` | Release signed with **debug keys**. |
| Bundle IDs | IMPLEMENTED | `build.gradle.kts:23`; `project.pbxproj:385` | `gh.yomatriage.yoma_triage` / `gh.yomatriage.yomaTriage`; inconsistent but valid. |
| Mic permissions | IMPLEMENTED | `AndroidManifest.xml:3`; `ios/Runner/Info.plist:69` | |
| Privacy policy, store metadata | MISSING | Searched `docs/`, `mobile/` | No policy document found. Default launcher icons per `todo.md`. |
| Low-end device support | PARTIAL | `mobile/android/app/build.gradle.kts:26` | minSdk from Flutter default (24). About 28 MB of model assets, 16 MB unused. Never tested on a device. |

---

## 5. Spec divergences & spec issues

### Code diverges from spec (most important first)

1. **Thresholds:** <0.5 is GREEN, not inconclusive.
2. **Cascade:** 5 s vs 90 s; SMS-only, two tiers vs six steps.
3. **Hospital SMS:** token instead of name; no age, ETA or AI screen. Arguably the right privacy choice, but staff can't match the patient to the message.
4. **Emergency types** don't match §7.1.2.
5. **CHO isn't SMS-notified on accept**, which also fails Principle 6 (the flow should not depend on data).
6. **Fusion rule** isn't implemented as written.
7. **Recording** is 15 s vs 60 s.
8. **USSD path:** `/ussd/callback` vs `/api/v1/ussd/callback`.
9. **Service names** differ from §10.3. `voice_service.py` and others don't exist.
10. **`tflite_flutter`** is 0.11.0; the spec asks for ^0.12.1.
11. **Unspecified additions:** OPERA-CE, advisory HR entry, server RAG/Gemini, facility picker.
12. **RAG demo text contradicts the implemented thresholds.** `src/rag/engine.py:26-41` says MOEWS ≥6, SBP ≥160, HR ≥120, SpO₂ <92. The first 180 characters of a retrieved snippet go into the stored `clinical_summary`: a RED referral was saved with "MOEWS score >= 6 or Systolic BP >= 160" **[RAN]**. The same corpus advises an IV magnesium sulfate loading dose and is passed to Gemini when enabled, against §9.1's ban on recommending treatment protocols.

### Issues in the spec itself

| # | Issue | Finding | Decision needed |
|---|---|---|---|
| S1 | **MOEWS applied to children** | Part VII targets under-5 respiratory distress, yet §9.3 combines it with an *obstetric, adult* score. Illustrative healthy-range vitals score: 2-year-old **RED (6)**, newborn **RED (12)** **[RAN]**. | **Most serious spec problem.** Use WHO IMCI / paediatric thresholds with an age input, or restrict the pilot to obstetric cases. |
| S2 | **MOEWS boundaries overlap** | SBP 90, 140, 150; DBP 90, 100; HR 50, 60, 110, 130; RR 10, 14, 24, 30; Temp 35, 36, 38, 39; all are in two bands. | Code uses the higher band. Make this explicit. |
| S3 | **Triage categories contradict** | "Green 0–2" vs "Yellow any parameter scoring 1". Every non-zero parameter is 1 or 3, so Green can only be 0, and a total of 1–2 is always Yellow. A temp of exactly 36.0 °C triggers Yellow. | Clinical lead to decide. Likely over-triage and alert fatigue. |
| S4 | **Spec thresholds not validated** | Local PDFs exist in `data/ghs_protocols/`, but nothing shows the table was reconciled against them. | Clinical sign-off. |
| S5 | **Score range** | §10.5 says MOEWS 0–15, but the maximum is **21** (7 × 3) **[RAN]**. | Fix text. |
| S6 | **140-octet payload doesn't add up** | Header 112 ✓. Clinical is labelled 320, fields sum to **312**. Transit is labelled 128, fields sum to **160**. Labelled total with 272 padding is **832**; actual field total is **856**. **Neither equals 1,120.** Correct padding would be 536. | Redesign the layout. |
| S7 | **Payload doesn't fit one Base64 SMS** | 140 bytes as Base64 is **188 chars**; GSM-7 allows 160, so one SMS carries **120 binary bytes**. AES-GCM adds about 28 more (nonce + tag), leaving roughly 92. | Choose: 2-part SMS, or a much smaller payload. |
| S8 | **Example payload is wrong** | §10.5's "binary" sample decodes to `RLAI-256{"age":28,"bp":120/80,...,"moews":4}`: plaintext, invalid JSON, old brand. Its vitals don't support a score of 4 without an RR or other parameters. | Replace. |
| S9 | **Other payload errors** | BP in "millibar" (should be mmHg). Parity and gravidity appear twice. Lat/long field conflicts with "GPS location of patients: never stored". | Fix. |
| S10 | **Patient name contradictions** | "Never stored" (§11.3) vs `patient_name` in §11.1, `emergency_contact.patient_name/phone`, Principle 7, §7.1.2, and §7.3.1. Code follows "never stored". | Decide. Hospitals probably need *something* identifying. |
| S11 | **"No data on device beyond the session"** | §10.7 directly conflicts with the offline queue (§10.2), SQLCipher (§11.4) and the personal contacts stored per patient (§7.7). | Replace with: queue retained until sent, encrypted, with a hard TTL. |
| S12 | **YAMNet classes** | Spec says "normal breathing, wheeze, crackle, stridor". Model's embedded label file **[RAN]**: `Breathing`(36), `Wheeze`(37), `Crackle`(293, a general sound), **no stridor, and no normal/abnormal concept**. It's a general sound-event detector trained on web audio. | **YAMNet can't deliver the claim.** Needs a validated respiratory model, probably with a chest-contact sensor. |
| S13 | **Offline-first vs. reality** | Principle 1 says no internet needed. Dispatch can't begin until the phone syncs or an SMS is sent, and the SMS path isn't built. Journey 3 shows no SMS attempt at all, conflicting with §10.5. iOS can't send SMS silently from an app. | Decide if SMS fallback is Android-only or uses the composer. |
| S14 | **Language** | Spec assumes Dagbani across pilot sites. Kassena-Nankana East is mainly Kasem/Nankam-speaking, not Dagbani. AT TTS Dagbani support is doubtful, so assume recordings. | Confirm with district teams. |
| S15 | **Human-in-the-loop vs. automation** | §9.3 "automatically classified as Red" / "triggers immediate transport" vs Principle 3. Code requires CHO confirm, which is right. | Update text. |
| S16 | **Architecture diagram** | §10.1 shows the mobile app calling AT; §10.2 forbids it. Journey 1 says "App sends SMS to backend". | Fix text. |
| S17 | **Cost** | §14.1 assumes Supabase free tier and about USD 1.20 hosting per compound. The current stack needs about 660 MB RAM per process. | Remove RAG from the request path, then re-cost. |
| S18 | **Phase 1 SLM** | Part XVI lists it as a deliverable; Part I says backlog. | Fix text. |
| S19 | **Stale escrow text** | `docs/yoma-triage-product-spec.md` says different things from `PRODUCT_SPEC.md`. | Delete one. |

---

## 6. Security & compliance findings

Ghana Data Protection Act, 2012 (Act 843) mapping is an engineering reading and needs a legal review.

| Sev | Finding | Location | Recommended fix |
|---|---|---|---|
| **Critical** | **No user-level authentication.** One static key in every APK gives full read/write across all compounds, including dispatch logs, driver phone numbers and availability. It can be extracted from a binary and can't be revoked per user. | `src/api/deps.py:24-40`; `m/config.dart:27-30` | CHO OTP with per-user tokens; scope queries by compound; drop the embedded key. |
| **Critical** | **Fail-open default.** `ENVIRONMENT` unset → `development` → no API auth, no webhook auth, `/test-referral` open **[RAN]**. Anyone can then fake a driver acceptance. | `src/config.py:9`; `src/api/deps.py:20-21` | Default to fail-closed; require explicit opt-in for insecure dev mode; refuse to start without secrets. |
| **High** | **Production silently mocks SMS.** No AT key → 201 response, status `MOCKED`, nobody contacted, and a CHO may wait on it **[RAN]**. | `src/services/messaging_gateway.py:30-45` | Refuse startup in staging/production without AT config. |
| **High** | **Cleartext traffic allowed** in the release manifest; default base URLs are HTTP. Health data and the API key can travel unencrypted. | `AndroidManifest.xml:8`; `m/config.dart:15-22` | Move the flag to the debug manifest only; reject non-HTTPS URLs in release. |
| **High** | **Release build signed with the debug key.** Anyone could produce a matching update. | `build.gradle.kts:33-37` | Real keystore in a secret store. |
| **High** | **Driver identity is caller ID only.** Spec requires phone + PIN. Accept, decline and arrival drive payments in the design. | `src/api/ussd.py:85-92` | Add PIN (hashed) before real money moves. |
| **High** | **Driver can DIVERT a patient**, logged as `hospital` **[RAN]**. | `src/api/sms_webhook.py:88-98,290-292` | Facility phone only for CONFIRM/DIVERT; fix audit role. SMS sender IDs can be spoofed, so prefer a per-dispatch code. |
| **High** | **Plaintext health data on device**: vitals, compound, AI result in SQLite, retained indefinitely if never sent. No app lock on shared devices. | `m/services/offline_queue.dart:115-133,178-189`; `m/models/referral.dart:36-50` | SQLCipher + Keystore, TTL, app PIN. Web localStorage should not be used in production. |
| **High** | **No retention or anonymisation** despite the spec's 90-day commitment. `vitals_json` and phone numbers kept forever. | Searched `src/`, `scripts/` | Scheduled job; keep logs per policy. |
| **High** | **No audit trail** despite spec and README claims. | `src/db/models.py:119-127` | Write on every state change; make append-only; restrict access. |
| **High** | **Compliance posture undocumented.** No privacy policy, consent flow, DPIA, or evidence of Data Protection Commission registration. | Searched `docs/`, `mobile/` | Legal workstream. |
| **Medium** | **Vitals may be sent to Google Gemini** if the key and package are present: a cross-border processor and an un-consented purpose. Gestational age and vitals, no name. | `src/agents/clinical_agent.py:104-117` | Remove from the path, or get an agreement and a legal basis. |
| **Medium** | **Webhook secret in query string**, so it lands in access and proxy logs. | `src/api/deps.py:45,58`; `.env.example` | Prefer header or AT IP allowlist plus rotation. |
| **Medium** | **No rate limiting** on any endpoint. Unauthenticated `/test-referral` in staging loads ML **[RAN]**. | `main.py:79-88` | Add limits; delete `/test-referral`. |
| **Medium** | **`/docs` and `/openapi.json` public in production** **[RAN]**. | `main.py:33-38` | Disable in production. |
| **Medium** | **PII in storage and logs.** Full provider responses and, in mock mode, message bodies go to `dispatch_logs.metadata`. Mock log lines include phone numbers. | `src/services/messaging_gateway.py:31-37`; `src/services/dispatch_orchestrator.py:134-141` | Redact; apply log policy. |
| **Medium** | **Weak input validation** enables 500s and data loss **[RAN]**. | `src/api/referral.py:32-59` | Pydantic ranges and enums. |
| **Medium** | **Known vulnerable dependencies; nothing pinned** (§3 row 6). `requests` is imported but undeclared. | `requirements.txt` | Lockfile, automated scanning, drop chromadb from production. |
| **Medium** | **Runtime model download** from Hugging Face, unpinned, with no integrity check. | `src/rag/engine.py:101-103` | Remove, or vendor with a hash. |
| **Low** | **Default DB credential literal** in code (type: Postgres password for local dev). Sample placeholder in `.env.example`. | `src/config.py:16-19` | Require explicit config. |
| **Low** | **Certificate pinning absent.** | `m/services/api_client.dart` | Add once hosting is stable, with a rotation plan. |
| **Low** | **Secret-scan hook is broken** (missing baseline). | `.pre-commit-config.yaml` | Add baseline. |
| **Low** | **Health endpoint** reveals config state. | `main.py:60-68` | Minimise. |
| **Info** | **CORS is properly configured**: allowlist, no wildcard. **Patient tokens** are soundly generated. Webhook comparison is constant-time. | `src/config.py:64-73`; `m/services/patient_token.dart` | Keep. |
| **Info** | **Committed secrets: none found.** Regex scan of the tree and full git history for AT, Google and OpenAI key formats, JWTs, private keys and `*_KEY=` values. The only two hits are documentation placeholders (`docs/plans/at-sandbox-runbook.md`, an old `docs/superpowers/plans` file). `.env`, keystores, `.pem` and `google-services` files were never tracked. Regex scanning isn't exhaustive. Tracked-then-removed `.superpowers/` reports remain in history. | `git log --all` | Run `gitleaks` in CI. |

---

## 7. Bugs & code-quality risks

### Critical: can directly harm a patient

**BUG-1: YAMNet likely never runs on device; every screening returns GREEN 90%.**
`yamnet_classifier_io.dart:53-54,85` passes `List<double>.filled(521)`. The real model's output is `[1, 521]` **[RAN]**. Plugin `Tensor._duplicateList` throws on shape mismatch, confirmed with the plugin's own conversion code: `obj.shape=[1, 521] dst.shape=[521]` **[RAN]**. The `catch` at `:55-60` returns `_StubWithFlag`, which returns `GREEN conf=0.9 src=stub` **[RAN for the fallback]**. On a device the result card shows "Demo screening mode", but the CHO can't act on that.
*Fix:* use nested `[List<double>.filled(521, 0)]`, read `[0]`; **change all fallbacks to INCONCLUSIVE**; add an integration test on a device. *Limit of evidence:* no native TFLite library was available on the audit machine, so the full call chain ran only in parts.

**BUG-2: Fallback and failure paths report GREEN.**
`screening_screen.dart:86-87`: mic failure + "Stop & Analyze" → `stubClassify(forceRed: false)` → GREEN 90%. Contradicts the model card. A permission denial becomes reassurance. *Fix:* delete stubs from release builds.

**BUG-3: Two drivers can both accept.**
`ussd.py:142` loads the dispatch without a lock into the session identity map. `handle_accept` then runs `SELECT … FOR UPDATE` (`dispatch_orchestrator.py:148-150`) and blocks while the other driver commits, but SQLAlchemy returns the **stale cached object**, so `status` still looks claimable. Both drivers hear "Accepted", the driver is overwritten, and two `ussd_accept` logs are written. **29/30** **[RAN]**. Adding `.execution_options(populate_existing=True)` gave **0/30** **[RAN]**.
The same pattern affects `handle_decline` and `handle_arrival`. The window widens whenever a lock is held across SMS calls (BUG-8). Test `test_two_drivers_accept_only_one_wins` can't detect it (sequential, SQLite, no real locks).
*Consequence:* a second driver sets off for a patient already taken, and is told "not assigned" on arrival.

**BUG-4: The cascade rejects responding drivers.**
`handle_accept` checks eligibility against `current_tier` only (`dispatch_orchestrator.py:167-177`). After one timeout: `'END You are not eligible for this dispatch.'` After FAILED: `'END No active dispatch.'` **[RAN]**. At the default 5 s nobody can realistically dial USSD in time. At 90 s, a Motor-King driver who answers at 91 s while the patient has no transport is still refused.
*Fix:* keep all notified drivers eligible while unclaimed; allow claim after FAILED and notify the CHO.

**BUG-5: After a diversion the trip can't finish.**
`DIVERTED` isn't in `ARRIVAL_ELIGIBLE`, so arrival returns `END No active dispatch.` **[RAN]**. The new hospital is never told, and the app treats DIVERTED as terminal and stops polling (`dispatch_status_screen.dart:36`).
*Fix:* treat diversion as a destination change, not a status; notify the new facility.

**BUG-6: Restart silently strands referrals.**
Timers are in memory (`dispatch_orchestrator.py:82-83`); lifespan only runs `init_db` (`main.py:24-30`). Result: `TIER1_NOTIFIED` indefinitely **[RAN]**. Any deploy, crash or host restart does this, and the CHO's screen spins forever. Likewise, `BackgroundTasks` lost mid-accept leave `ACCEPTED`, which can't confirm arrival.
*Fix:* persist `next_action_at`, run a DB-polling worker with `SKIP LOCKED`, and sweep on startup.

**BUG-7: Pre-filled vitals.**
`referral_screen.dart:68-86` defaults to 70/50, HR 140, RR 35, 39.5 °C, SpO₂ 85, AVPU V. `vitals_screen.dart:20-25` defaults to normal 120/80. Unread submission either fabricates a critical patient or creates false reassurance at the exact moment a CHO is under stress.
*Fix:* empty fields, and an explicit "not measured" option (the backend's UNKNOWN already supports this).

**BUG-8: The server stalls during clinical work and SMS.**
- `yoma_graph.invoke` is **synchronous inside an async handler** (`referral.py:140`), blocking the whole event loop: **133.7 s on cold cache**, 8.3 s warm, 5.7 s with HF unreachable **[RAN]**. USSD (10 s budget), webhooks and timers all freeze. If the RAG engine fails, it retries on **every** referral (`clinical_agent.py:31-41`), as nothing caches the failure **[READ]**.
- `run_accept_side_effects`, `_tier_timeout` and `run_decline_side_effects` hold **`FOR UPDATE` across AT HTTP calls** (8 s timeout each, sequential) **[READ]**, so a driver's accept can wait past AT's USSD deadline.
- `POST /referral` sends SMS before commit: slow for many drivers, and a failed commit means SMS for a referral that doesn't exist.
*Fix:* remove RAG from the request path; use a transactional outbox for sends.

**BUG-9: A driver on one trip gets assigned others; arrival closes the wrong one.**
Accept doesn't set `ON_TRIP`. The same driver accepted a second referral, then "Confirm arrival" completed the newest while the first stayed `HOSPITAL_NOTIFIED` forever **[RAN]**. The menu shows no referral details, and `ussd.py:142-153` always picks the newest open dispatch, so older referrals in a compound can't be accepted while a newer one is open.
*Fix:* show referral context; session-based selection; auto `ON_TRIP`, restored on completion.

### High

| ID | Bug | Evidence | Fix |
|---|---|---|---|
| BUG-10 | **USSD input takes the last character only.** `21` was read as **accept** **[RAN]**; `99*1`, `13`, `3*2` also pass the parser. A typo can claim a dispatch. | `src/api/ussd.py:76-82` | Exact match per menu level. |
| BUG-11 | **Invalid vitals destroy a valid score.** SBP 1200 or HR −5: `struct.error` in the codec → whole graph fails → **RED patient recorded UNKNOWN** **[RAN]**. | `src/agents/coordinator.py:19-25`; `src/tools/sms_codec.py:30`; `src/api/referral.py:141-150` | Range validation; codec failure mustn't discard MOEWS. |
| BUG-12 | **Stale queued referrals dispatch live.** A referral queued during an outage flushes hours later and sends real drivers to a patient who has left. Journey 3 expects "historical". No `created_at` sent, no TTL, no cancel. | `m/services/offline_queue.dart:263-322`; `src/api/referral.py` | Send capture time; prompt the CHO on stale items; add cancel. |
| BUG-13 | **No auto-retry during backend outage** on steady connectivity. Queue screen retries by button only. | `m/services/queue_sync_service.dart:40-43` | Periodic timer with backoff. |
| BUG-14 | **Permanent errors retried forever**; 4xx stays `pending`. There's no queue screen for a CHO to see. | `m/services/offline_queue.dart:313-318` | Separate `failed`; add UI. |
| BUG-15 | **Every install is compound #1** (Tamale South); drivers and CHO alerts go there regardless of location. | `m/services/catalog_store.dart:24-31` | Tie to CHO account. |
| BUG-16 | **Catalog and seed may disagree; failure is opaque.** IDs need manual sync across three files. Compound 1's coordinates differ between catalog (9.3934) and seed (9.403). | `data/*.json`; `src/api/catalog.py:18` | One source of truth in the DB. |
| BUG-17 | **FAILED gives the CHO no action.** The screen shows "FAILED" with no call button or driver list. Principle 9 requires a manual path. | `m/screens/dispatch_status_screen.dart:156-215` | Add call actions and cached contacts. |
| BUG-18 | **All-SMS-failed looks fine.** Status still `TIER1_NOTIFIED`; no earlier CHO alert. Zero candidates also waits a full timeout. | `src/services/dispatch_orchestrator.py:122-143` | Skip tier immediately; alert. |
| BUG-19 | **Web build broken** by the `record_platform_interface` override. The same override may affect Android (unverified). | `mobile/pubspec.yaml`; §3 row 10 | Upgrade `record`, remove override. |
| BUG-20 | **Audio file left on Back**, and Android cache cleanup isn't guaranteed. | `m/services/audio_recorder_io.dart:54-61` | Delete in `dispose()` and purge on startup. |
| BUG-21 | **Stream-based recording isn't used**; a full clip loads to memory and inference runs on the UI isolate. Dart float lists run per window with 50% overlap, so jank is likely on low-end phones. **[READ]** | `m/services/yamnet_classifier_io.dart:87-98` | Run in an isolate; test on target devices. |

### Medium / Low

- Concurrent duplicate POST returns unhandled **HTTP 500** instead of the idempotent response **[RAN]** (`src/api/referral.py:170-173`). A client retry recovers.
- `eta_minutes` is hardcoded 30, shown to the CHO as fact (`src/api/referral.py:96`). Spec needs a real estimate.
- `handle_decline` accepts any compound driver, including those never notified, and can affect tier logic (`src/services/dispatch_orchestrator.py:209-229`).
- `asyncio.create_task` result isn't retained, so tasks may be garbage-collected (`src/services/dispatch_orchestrator.py:83`).
- `_latest_dispatch_for_sender` scans the 50 newest dispatches with N+1 queries, and misses older ones (`src/api/sms_webhook.py:107-118`).
- `clinical_summary` always says "Maternal referral" even for a child (`src/agents/clinical_agent.py:85-89`).
- `protocol_assist` is computed and then dropped; Gemini cost with no output.
- Failing test and docs drift: TASK_BOARD says verified, and "61/19 passing" no longer matches.
- `/test-referral` is reachable in staging without auth **[RAN]**.
- README Quick Start references `/var/www/html/unicef`, ports differ (5432 vs 5433), and `todo.md` credits working "Mock MoMo" to the dead `momo_escrow.py`.
- Code style: 15 ruff errors, 55 unformatted files, 28 mypy errors; `requirements-dev.txt` duplicates `pyproject.toml`.

---

## 8. Production gap list

**Effort:** S ≤ 2 days · M ≤ 2 weeks · L > 2 weeks (one engineer).

### P0: Launch blockers

| # | Item | Effort | External dependency |
|---|---|---|---|
| 1 | Clinical scope decision and paediatric scoring (or restrict to obstetric). Age input. | M | **Clinical lead, GHS** |
| 2 | Clinical sign-off of thresholds and triage rules; resolve S2/S3 | S | **GHS protocol owner** |
| 3 | Ethics/IRB clearance for the pilot and any audio collection | L | **Ethics board, GHS approval** |
| 4 | **Disable acoustic screening** in the pilot (`MOEWS_ONLY=true`) until validated; make every fallback INCONCLUSIVE | S | None |
| 5 | Acoustic path decision: fix BUG-1, then validate; sensor/stethoscope question | L | **Labelled Ghana data, study** |
| 6 | Remove all pre-filled patient data (BUG-7) | S | None |
| 7 | Fix double accept (BUG-3), plus a real-Postgres concurrency test | S | None |
| 8 | Fix late-driver rejection (BUG-4), and 90 s default with config guard | S | None |
| 9 | Durable cascade: persisted timers, worker, restart recovery (BUG-6) | M | None |
| 10 | Transactional outbox; no locks across HTTP; no RAG in request path (BUG-8) | M | None |
| 11 | Fix diversion lifecycle + notify new hospital (BUG-5) | S | None |
| 12 | Driver trip state: ON_TRIP, referral context in USSD (BUG-9, BUG-10) | M | None |
| 13 | CHO SMS on accept and on all status changes | S | None |
| 14 | CHO manual path on FAILED (call buttons, contact list) | S | None |
| 15 | Personal-contact tier + voice decision (build or formally cut) | M–L | **AT voice number**; recordings if voice |
| 16 | CHO auth (OTP), per-user sessions, compound scoping, home compound | M | **AT SMS** for OTP |
| 17 | Fail-closed config; refuse start without AT/secrets; remove mock in prod | S | None |
| 18 | Stale-referral handling and cancel (BUG-12) | M | Clinical input |
| 19 | Input validation (BUG-11) | S | None |
| 20 | Encrypted outbox + TTL + app lock; resolve S11 | M | None |
| 21 | Act 843: privacy policy, consent basis, DPIA, DPC registration, data-processing terms, retention job | L (mostly non-eng) | **Legal counsel, Data Protection Commission** |
| 22 | Audit log writes | S–M | None |
| 23 | Hosting: HTTPS, Docker, staging/prod, CI, Alembic, backups with restore test | M | **Host contract** |
| 24 | Monitoring and on-call: DB health, stuck-dispatch alert, error tracking, delivery reports | M | **Named on-call owner** |
| 25 | Signed release, disable cleartext, device QA on target low-end phones | M | **Play account / MDM; test devices** |
| 26 | Production AT: USSD code, sender ID, SMS float, live-network tests on MTN, Telecel, AirtelTigo | M | **AT production account; USSD code (spec: ~USD 100 + GHS 900/mo); sender ID approval** |
| 27 | Real data: facility master list, CHPS list, drivers, **Upper East** coverage | M | **GHS / District Directorates** |
| 28 | Driver registration + phone verification + CHO add/remove | M | Field team |
| 29 | Paper/manual fallback SOP and training for failure modes | M | **GHS trainers** |
| 30 | Decide transport payment for the pilot: real MoMo, or manual reimbursement with drivers told clearly | S decision | **Funder** |

### P1: Needed for the pilot

| # | Item | Effort | External dependency |
|---|---|---|---|
| 31 | Outcome recording; adverse flow with review flag, anonymised notice | M | **District Health Directorate** process |
| 32 | Caregiver refusal documentation (Journey 5) | S | None |
| 33 | Real MoMo: escrow, 30/70, fare table, idempotency, reconciliation | L | **MTN MoMo merchant/KYC, fund setup, AT Payments or MTN** |
| 34 | Delay option + CHO accept-delay flow | M | None |
| 35 | USSD availability menu; driver PIN | S–M | None |
| 36 | SMS-based offline fallback: redesign payload, Android send, inbound decode, CRC, dedupe | L | **Inbound number**; iOS limitation |
| 37 | Localisation: Dagbani, Kasem/Nankam as confirmed; SMS, USSD and voice copy | L | **Translators; voice recordings; clinical reviewers** |
| 38 | Hospital pre-arrival content, patient matching, DIVERT by code/name | M | Hospital staff input |
| 39 | Referral prioritisation (if relevant at pilot volume) | S | Clinical rules |
| 40 | Pilot metrics (§13.3) export and dashboard | M | Evaluation partner |
| 41 | Yellow-tier workflow | M | Coordinator role defined |
| 42 | Retry logic, queue screen, error states | S | None |
| 43 | AT delivery receipts; failed-SMS retry and alternate routes | M | None |
| 44 | Reduce app size (drop ONNX); update `record`, `tflite_flutter`; fix web build or drop web | S | None |
| 45 | Clean up: fix failing test, lockfile, lint, docs reconciliation, one spec | S | None |
| 46 | Training material, super-user guide | M | **GHS, UNICEF** |
| 47 | Certificate pinning; rate limiting; disable `/docs`; pen test | M | Security vendor |

### P2: Post-pilot / nice to have

| # | Item | Effort | External dependency |
|---|---|---|---|
| 48 | On-device SLM | L | Clinical validation |
| 49 | Hospital dashboard, LHIMS | L | **GHS, LHIMS** |
| 50 | DHIS2 sync | L | **GHS** data agreement |
| 51 | RAG on official guidance (as out-of-band staff help, not the request path) | M | Clinical review |
| 52 | Voice dictation | L | Dagbani data |
| 53 | Community fund tooling, NHIS/LEAP | L | **NHIA, LEAP** |
| 54 | Route- and distance-based ETA and fare; driver distance ranking | M | Road data |
| 55 | Viamo/Agoo IVR refreshers | M | **Viamo** |
| 56 | ISO 27001 prep, multi-tenant scaling | L | Auditor |

---

## 9. Suggested next 2 weeks

Goal: **make the MOEWS-and-dispatch core safe and durable, and remove anything that gives false reassurance.** Acoustic stays off. No new features.

**Week 1: safety and correctness**

| Day | Task |
|---|---|
| 1 | **Hold the clinical scope meeting.** Decide paediatric vs obstetric-only (S1), and thresholds (S2/S3). Send the ethics/GHS approval enquiry. These decisions shape everything else. |
| 1 | Change all acoustic fallbacks to INCONCLUSIVE. Set `MOEWS_ONLY=true` as the default. Empty all pre-filled forms. |
| 2 | Add `populate_existing=True` to all lock queries. Add a Postgres service to tests, with a real concurrent-accept test (port the audit harness). |
| 2 | Fix late accept: all notified drivers stay eligible; claim allowed after FAILED, with CHO notice. Set 90 s default. |
| 3 | Fail-closed config: required env at startup, AT mandatory outside dev, remove `/test-referral`, disable `/docs` in prod. |
| 3 | Pydantic ranges and enums on vitals; codec failure mustn't discard MOEWS. Exact USSD parsing. |
| 4–5 | Durable cascade: add Alembic first, then `next_action_at` on dispatch, a DB-polling worker, startup recovery. Restart test. |

**Week 2: dispatch completeness and operability**

| Day | Task |
|---|---|
| 6 | Transactional outbox for SMS; no locks across HTTP. Remove RAG/LLM from the request path, and drop torch/chromadb from the production image. |
| 7 | Fix diversion lifecycle and new-hospital notice. Facility-only CONFIRM/DIVERT. CHO SMS on accept and arrival. Hospital arrival SMS. |
| 8 | Driver trip state: auto `ON_TRIP`, referral context in USSD, correct arrival targeting. Write audit log on all transitions. |
| 9 | App: FAILED screen with call actions; periodic queue retry; stale-referral prompt; home compound setup (interim, until OTP). Fix cleartext; real signing key; update `record`, remove the override. |
| 10 | CI (pytest on Postgres, `flutter analyze/test`, `pip-audit`, `gitleaks`); fix the failing test; pin dependencies with a lockfile. Dockerfile and staging deploy with health check and stuck-dispatch alert. |
| 10 | **Run BUG-1 on a real low-end Android phone and record the result.** Then run a full rehearsal on staging: real sandbox SMS, a real USSD dial, a server restart mid-cascade, and a driver answering at 100 s. |

**In parallel (non-engineering, start now because of lead times):** ethics submission · AT production account and USSD code · DPC/legal review · GHS facility list · confirm pilot languages · pilot transport payment decision.

---

## 10. Open questions

**Clinical**
1. Is the pilot obstetric, paediatric, or both? If children are in scope, what replaces MOEWS?
2. Who is the accountable clinical lead who signs off thresholds, and has GHS reviewed the table against the protocols in `data/ghs_protocols/`?
3. Should Yellow actually dispatch transport, or only reserve it? Is Yellow-on-any-single-1 acceptable, given over-triage?
4. Should acoustic screening exist in the pilot at all, given it needs a validated model and possibly hardware?
5. How long may a queued referral stay valid before it must be reconfirmed?

**Field and operational**
6. Did anyone run YAMNet successfully on a physical phone? `todo.md` shows that as open. Any such evidence would be important against BUG-1.
7. Which languages are actually needed in each pilot district? Is Dagbani right for Kassena-Nankana East?
8. What devices do CHOs really have? Are they shared? Is iOS or web actually needed in the pilot? Dropping them would remove real work.
9. Do drivers truly have USSD access on all three networks, and who pays for session costs?
10. Who covers on-call for a life-critical service, at what hours?
11. Are real driver-response times compatible with 90 s tiers?

**Data, legal, funding**
12. What may the hospital receive to identify a patient? Name, token, or age + compound?
13. Who is the Act 843 data controller (GHS, UNICEF, the company), and has Data Protection Commission registration begun?
14. Which money flow runs at pilot start, who funds it, and who holds the merchant account?
15. Is the HeAR ToS review proceeding, or is OPERA-CE the chosen path? Decision log is empty.
16. Is Supabase still the database choice? No code depends on it, and RLS would need a different auth model.

**Couldn't determine from the code**
17. Whether a deployed environment exists and how it's configured (secrets, TLS, encryption at rest, backups).
18. Whether Android and iOS release builds succeed, and app size and performance on low-end devices.
19. Live AT behaviour under this code on Ghanaian networks. `todo.md` records sandbox success, not verified here.
20. Which `.env` values were used in earlier demos, and whether those sandbox keys should be rotated (`todo.md` lists rotation as open).
