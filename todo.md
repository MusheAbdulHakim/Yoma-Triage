# Yoma Triage — Remaining Work (`todo.md`)

**Generated:** 2026-07-26  
**Last updated:** 2026-07-27  
**Scope:** Everything still needed for a credible hackathon demo **and** a true production / pilot-ready system.  
**Sources:** `TASK_BOARD.md`, `PRODUCT_SPEC.md`, `docs/yoma-triage-product-spec.md`, `docs/architecture-narrative.md`, `docs/plans/yoma-triage-production-hackathon-plan.md` (+ REVIEW / VERIFY), `docs/plans/at-sandbox-runbook.md`, `README.md`, `Yoma Triage Clinical Design Research.md`, `.cursorrules`, `src/`, `main.py`, `tests/`, `scripts/`, `mobile/`.  
**Do not treat this as a commit plan** — tracking only.

Evidence baseline (VERIFY 2026-07-26): **pytest 61 passed**, **flutter test 19 passed**; hackathon production-close table in `TASK_BOARD.md` largely `[VERIFIED]`; live AT / real MoMo / clinical models / Dagbani voice still open.
**Session update (2026-07-26):** backend suite **74 passed** after 3.3/3.4 API + clinical/RAG work.
**Session update (2026-07-27):** Live AT sandbox SMS + USSD shortcode `*384*99193#` working; inbound form webhook + status auto-replies; hospital notify includes driver phone; related inbound/hospital/accept tests green (19 in focused run).

---

## 1. Executive status

### What already works (demo-credible)

| Area | Evidence |
|------|----------|
| MOEWS clinical scoring | `src/tools/moews_calculator.py`, `tests/test_moews.py` |
| Referral API + idempotency | `src/api/referral.py`, `tests/test_referral_idempotency.py` |
| Privacy tokens (unlinkable SHA-256) | `mobile/lib/services/patient_token.dart`, `tests/test_referral_privacy.py`, `tests/test_hospital_privacy.py` |
| Dispatch cascade + concurrent accept | `src/services/dispatch_orchestrator.py`, `tests/test_dispatch.py` |
| USSD accept / decline / arrival → `COMPLETED` | `src/api/ussd.py`, `tests/test_ussd_arrival.py` |
| Hospital CONFIRM / DIVERT SMS | `src/api/sms_webhook.py` (AT form + JSON; sender status replies) |
| Hospital pre-arrival SMS (driver name + phone) | `src/services/hospital_notifier.py` after USSD accept |
| Live AT sandbox SMS (form) + USSD callback | `MessagingGateway`, `ussd.py`, shortcode `*384*99193#` / sender `99193` |
| Mock MoMo fuel stipend (30%) | `src/tools/momo_escrow.py` (`YOMA-` prefix) |
| CORS allowlist for Flutter web | `main.py`, `src/config.py`, `tests/test_cors.py` |
| CHO Flutter app (Android / iOS / web) | `mobile/lib/screens/*`, `mobile/ios/`, `mobile/android/`, `mobile/web/` |
| Offline outbox + sync | `mobile/lib/services/offline_queue.dart`, `queue_sync_service.dart` |
| YAMNet TFLite asset + class-map scoring | `mobile/assets/models/yamnet.tflite` (~4.1 MB), `yamnet_classifier_io.dart` |
| Advisory / demo disclaimers | `mobile/lib/screens/result_screen.dart`, `result_disclaimer_test.dart` |
| Judge narrative + AT runbook | `docs/architecture-narrative.md`, `docs/plans/at-sandbox-runbook.md` |
| Demo script | `scripts/demo_flow.py` |

### Remaining gap — hackathon vs true production

| Bar | Status |
|-----|--------|
| **Hackathon demo (mock SMS OK)** | Near-ready: seed DB → `main.py` → `demo_flow.py` + Flutter web/emulator. Live phone SMS still needs AT credentials. |
| **Hackathon demo (LIVE AT SMS)** | **Unblocked for sandbox:** keys + shortcode in `.env`; outbound SMS + USSD + inbound form verified on test handset. Still need stable public URL (ngrok) for AT callbacks in judge room + full E2E rehearsal. |
| **True production / field pilot** | Large gap: real MoMo 30/70, provisioned USSD shortcode, voice cascade, CHO auth + encryption, hospital dashboard, Dagbani voice/l10n, validated respiratory model, GHS protocol RAG with real PDFs, observability/hosting, clinical governance. |

Specs still over-claim Phase 1 SLM / SQLCipher / encrypted SMS in places (`PRODUCT_SPEC.md` §8.2, §XVI Phase 1, security sections) even after partial W0.2 reconciliation — treat those as **backlog**, not shipped.

---

## 2. Critical blockers / demo day

- [x] Obtain Africa’s Talking sandbox (or production) `AT_API_KEY` + `AT_USERNAME`; set in local `.env` (never commit). Confirm `settings.at_configured is True`.
- [x] Send one live sandbox SMS to a registered test handset; verify dispatch log `provider` ≠ `mock` (`docs/plans/at-sandbox-runbook.md`). — sandbox form path + `AT_SENDER_ID=99193`.
- [x] Inbound SMS webhook accepts AT **form-urlencoded**; bare `confirmed` + status auto-reply to sender; hospital notify includes driver phone. — code + tests; keep ngrok URL registered for judge day.
- [x] Keep **stable public URL** for AT callbacks via `PUBLIC_BASE_URL` in `.env` (no hardcoded ngrok hosts). `GET /` exposes `webhooks.ussd_callback` + `webhooks.sms_inbound`. Re-register in AT when the tunnel URL changes.
- [x] Provision / document USSD shortcode callback (`*384*99193#` → `POST /ussd/callback` in `src/api/ussd.py` — **not** `/api/v1/ussd/callback`). AT camelCase form fields handled.
- [x] Run fresh browser CORS smoke: Flutter web origins in `CORS_ORIGINS`; `scripts/cors_smoke.py` PASS; Chromium fetch from `http://127.0.0.1:8765` → API succeeded (pin Flutter with `--web-port=8080`).
- [ ] Build and install **physical Android** APK with mic permission; confirm YAMNet loads (stub only on failure — see `YamnetClassifierIo.create`).
- [ ] Build and run **physical iPhone** (`mobile/ios/`); confirm `NSMicrophoneUsageDescription` and TFLite path (or documented stub fallback).
- [x] Rehearse full judge path once (API): `scripts/demo_flow.py` → accept → hospital SMS `SENT` → CONFIRM → arrival `COMPLETED` (+ decline/divert) — 2026-07-27. Still optional: Flutter UI + physical-phone USSD via ngrok.
- [ ] Projector checklist: architecture narrative open; disclaimer language rehearsed (“advisory AudioSet / not obstetric diagnosis”).
- [x] Confirm Postgres is up on expected port — local `.env` uses `127.0.0.1:5433/yoma_triage`; still align README vs `config.py` default `5432` in docs.

---

## 3. Backend remaining work

Grounded in `src/`, `main.py`, `tests/`, `scripts/`.

### 3.1 Messaging / Africa’s Talking

- [x] Complete live AT dry-run per runbook; document sender-ID / sandbox quirks for Ghana numbers. — sandbox uses form `POST /version1/messaging` (bulk 404); live bulk needs live keys; see `docs/plans/at-sandbox-runbook.md`.
- [x] Inbound AT form + `GOOD`/`BAD`; sender-only status SMS when no open / already confirmed / en route; successful CONFIRM ack SMS.
- [x] Hospital pre-arrival SMS after accept includes **driver phone** (`HospitalNotifier.notify_pre_arrival`); verified in tests.
- [ ] Implement **Voice** path: `MessagingGateway.initiate_voice` currently returns `FAILED` / `"Voice not configured for MVP"` when AT is configured (`src/services/messaging_gateway.py`); orchestrator **never calls** `initiate_voice` (SMS-only cascade).
- [ ] Wire voice into cascade tiers only after AT Voice credentials + IVR/TTS strategy exist (pilot).
- [ ] Measure GSM-7/UCS-2 **segment count** for hospital operational SMS (`HospitalNotifier` multi-line body in `src/services/hospital_notifier.py`) — plan REVIEW required this; telemetry codec (`sms_codec.py`) already fits ≤140 octets, operational SMS may be multipart.
- [ ] Add `message_templates.py` (or equivalent) for driver/hospital/CHO SMS with optional Dagbani second-line placeholders (plan §6).
- [ ] Harden AT error taxonomy in logs (rate limit, invalid sender, unreachable MSISDN) beyond generic `FAILED`.

### 3.2 MoMo escrow

- [ ] Replace mock path with MTN MoMo sandbox end-to-end when `MOMO_PRIMARY_KEY` is set; verify 202 Accepted + callback handling.
- [ ] Implement **70% completion payout** on arrival/hospital handshake (explicitly deferred; do not claim in demo — VERIFY / architecture narrative).
- [ ] Convert `momo_escrow.py` from sync `requests` to **async** HTTP (`.cursorrules`: async for all HTTP).
- [ ] Idempotent disbursement: never duplicate `dispatch_log` / MoMo external IDs on USSD retries (rule already stated; add regression tests for live path).
- [ ] Escrow / community emergency fund accounting model (PRODUCT_SPEC transport financing) — pilot design.

### 3.3 APIs & dispatch

- [x] Decide and optionally add `GET /api/v1/driver/{id}/status` (listed as not implemented in plan REVIEW).
- [x] Decide whether to alias `POST /api/v1/ussd/callback` (safe default: keep only `/ussd/callback`).
- [ ] Voice callback webhook (AT) — not implemented.
- [x] Tier timeout values for production (`CASCADE_TIER_SECONDS` default `5` is demo-short; field may need minutes). — documented in `.env.example` / config comment; still env-tuned.
- [x] Personal-vehicle / NAS escalation messaging content polish for tier 2–3 (logic exists; copy/ops incomplete).
- [ ] Caregiver refusal / cancel workflow API (plan §4.2 backlog).

### 3.4 Clinical path / RAG / LLM

- [x] Ingest real GHS MNCH / referral PDFs into RAG (`src/rag/engine.py` currently seeds **two hard-coded sample** `Document`s; `src/rag/ingest.py` unused in production flow). — demo corpus expanded + `data/ghs_protocols/` file seed; real official PDFs still backlog.
- [x] Make Gemini summarization optional and **never** authoritative: risk must remain MOEWS-deterministic (today: `_template_summary` fallback if no `GEMINI_API_KEY` — good; still avoid open-ended clinical claims).
- [x] Ensure clinical assessment errors always return `UNKNOWN` risk without blocking referral (spec §10 / `.cursorrules`) — add explicit failure-injection tests if missing.
- [x] Remove or gate `/test-referral` in non-dev environments (`main.py`).

### 3.5 Privacy & auth (post-hackathon)

- [ ] Encrypted patient identity design (current: display-name local only; API/DB `patient_name="Unknown"`; token-only on wire).
- [ ] CHO authentication (OTP) — PRODUCT_SPEC § security; not in FastAPI.
- [ ] API authn/authz (signed CHO sessions, hospital roles, driver identity binding beyond phone match).
- [ ] Rate-limit and authenticate AT/USSD webhooks (shared secret / signature verification).
- [ ] Audit log export / retention policy for GHS.

### 3.6 Hospital dashboard & observability

- [ ] Hospital web dashboard (PRODUCT_SPEC Phase 3): intake queue, confirm/divert UI replacing SMS-only.
- [ ] LHIMS / DHIS2 integration hooks (Phase 3–4).
- [ ] Structured metrics (referral latency, accept rate, divert rate) — beyond `GET /api/v1/dispatch/{id}/logs`.
- [ ] Centralized logging (JSON), request IDs, alerting for cascade failures.
- [ ] Health check beyond `GET /` (DB ping, AT config status without leaking secrets).

### 3.7 Code quality leftovers

- [x] Replace bare/broad `except Exception` patterns in clinical/RAG init (`clinical_agent.py`) with specific exceptions + logging.
- [ ] Ensure `from __future__ import annotations` consistency across all `src/` modules (`.cursorrules`).
- [ ] Align `DATABASE_URL` defaults in README vs `config.py` vs docker/compose if added.

---

## 4. Flutter / mobile remaining work

Grounded in `mobile/lib/`, `mobile/test/`, `mobile/ios/`, `mobile/android/`, `mobile/web/`.

### 4.1 Platforms & packaging

- [ ] Signed Android release build + Play Internal testing track (or sideload SOP for CHO devices).
- [ ] Signed iOS build + TestFlight; microphone privacy strings verified on device.
- [ ] Responsive web polish: overflow tests on small viewports (VERIFY: home/result/screening are simple columns; referral scrolls).
- [ ] Document `API_BASE_URL` dart-defines per target (emulator `10.0.2.2`, device LAN IP, production HTTPS).
- [ ] App icons / splash consistent with Yoma brand (default Flutter icons still present under `ios/` / `android/` mipmaps).

### 4.2 Offline, sync, UX

- [ ] Offline reconnect rehearsal checklist (airplane mode → queue → reconnect → same `client_request_id`) documented for judges.
- [ ] Clearer offline badge / queued-count on home (partially done; harden empty/error states).
- [ ] Facility / compound **display names** from seed (IDs alone are weak for CHO UX — plan M6 noted; verify completeness).
- [ ] Dispatch status rebound when a previously queued referral syncs to a real dispatch ID (REVIEW noted historical gap; re-verify `dispatch_status_screen.dart`).
- [ ] Caregiver refusal / “continue monitoring” analytics (local only).

### 4.3 Auth, encryption, security

- [ ] CHO OTP login (deferred — PRODUCT_SPEC).
- [ ] SQLCipher (or equivalent) for SQLite outbox — today: plain `sqflite` / SharedPreferences on web.
- [ ] Certificate pinning for API HTTPS.
- [ ] Remove or encrypt on-device patient display name (`referral_screen.dart` still collects `_patientName` for local display; not serialized — acceptable for hackathon, not for PHI-at-rest).
- [ ] Biometric / PIN unlock for app (PRODUCT_SPEC Keystore narrative).

### 4.4 Screening UX honesty

- [ ] Keep mandatory advisory disclaimer for **all** sources including live YAMNet (already required; never add env flag to remove — plan §5).
- [ ] Ensure web simulator always labeled demo-mode.
- [ ] Do not upload raw audio to backend (current design); keep that invariant under any future model swap.
- [ ] Never auto-refer on RED without CHO confirm (HITL).

### 4.5 Localization & a11y

- [ ] Add Dagbani brand gloss on home (“Yoma — quick”) — plan §6 / brand_copy; **missing** on `home_screen.dart` today.
- [ ] Flutter `l10n` ARB for English + Dagbani (+ Gonja later).
- [ ] Large tap targets / high contrast audit on low-end Android (partial theme in `yoma_theme.dart`).
- [ ] Screen-reader labels for all primary actions (partial `Semantics` on home).

### 4.6 Tests & CI

- [ ] Integration test driving API + offline flush on IO (beyond widget/simulator tests).
- [ ] Golden / overflow tests for 320px-wide layouts.
- [ ] CI job: `flutter test` + `flutter analyze` on PR.
- [ ] Device lab smoke (Android emulator + Chrome) in CI if feasible.

---

## 5. Clinical / audio / ML

### 5.1 Current state (honest)

| Item | State |
|------|-------|
| Asset | `mobile/assets/models/yamnet.tflite` present (~4.1 MB), fetched via `scripts/fetch_yamnet.sh` |
| Runtime | `yamnet_classifier_io.dart` loads TFLite; maps AudioSet indices `{36,37,39,40,41,42}` (Breathing, Wheeze, Gasp, Pant, Snort, Cough); stub on load/probe failure |
| Web | Demo Normal / Demo Code Red simulator only (`yamnet_classifier_stub.dart` path) |
| Clinical validity | **None.** Generic AudioSet event detection ≠ obstetric / neonatal diagnosis. Disclaimers required. |
| Backend audio | No audio upload / server inference in referral path |
| PRODUCT_SPEC HeAR mention | Aspiration for Phase 2+; not integrated |

**Never claim:** YAMNet alone is a clinical diagnostic, pneumonia detector, or eclampsia screen. MOEWS + CHO judgment remain the clinical spine.

### 5.2 Do we need to train our own model?

**Short answer:** Not for hackathon. **Yes, eventually** for any claim of maternal/neonatal respiratory (or fetal) screening in Northern Ghana CHPS — but start from open foundation models + local fine-tune, not from scratch.

**Rationale**

1. Yoma Triage’s primary life-saving path is **MOEWS + referral/dispatch**, not acoustic AI (`.cursorrules`, architecture narrative).
2. No public model is validated on **Northern Ghana CHPS phone-mic** maternal/neonatal acoustic conditions under field noise.
3. Training from scratch needs ethics IRB, consented recordings, clinician labels, device diversity, and GHS partnership — multi-month.
4. Best path: **reuse OSS health-acoustic encoders** (HeAR event detectors / OPERA / DeepBreath-class approaches) → fine-tune on Ghana data → clinical validation → then replace YAMNet advisory head.

### 5.3 Open-source / public models (researched 2025–2026)

| Model | Detects | License | Format / on-device | Fit for Yoma Triage | Source | Integration effort |
|-------|---------|---------|--------------------|---------------------|--------|--------------------|
| **YAMNet** (in repo) | 521 AudioSet events (incl. cough, breathing, wheeze, baby cry) | Apache-2.0 | TFLite (~4 MB); Flutter `tflite_flutter` | **Partial** — good for demo technical smoke; **poor** as clinical screen | [TF models audioset/yamnet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet), TF Hub | **Done** for advisory path |
| **HeAR** foundation + **health event detectors** | Embeddings for cough/breath/etc.; MobileNet-V3 event detectors (cough, breathing, …) | **Gated:** [Health AI Developer Foundations ToS](https://developers.google.com/health-ai-developer-foundations/terms) (not plain OSS; clinical-use / redistribution constraints). Repo code Apache-2.0 | TF / PyTorch on HF; event detectors convertible to **TFLite** (official notebook) | **Good** (pilot) as encoder + event gate; still **not** obstetric-validated; accept ToS before ship | [developers.google.com/hear](https://developers.google.com/health-ai-developer-foundations/hear), [github.com/Google-Health/hear](https://github.com/Google-Health/hear), HF `google/hear` | **M–L** (2–6 wks): ToS review, TFLite export, Flutter swap, thresholds, disclaimer |
| **OPERA** (CT/CE/GT) | Respiratory foundation embeddings; 19 downstream resp. tasks in benchmark | MIT (code); checkpoints on HF/Zenodo | PyTorch `.ckpt` — needs export to ONNX/TFLite for phone | **Good** (pilot research); superior to general audio on many resp. tasks; **backend or offline export** first | [github.com/evelyn0414/OPERA](https://github.com/evelyn0414/OPERA), [HF evelyn0414/OPERA](https://huggingface.co/evelyn0414/OPERA) | **L** (4–10 wks): export + head training + mobile runtime |
| **DeepBreath** | Pediatric lung auscultation → healthy vs pathology (pneumonia / wheeze / bronchiolitis) | Apache-2.0 (code); dataset access via project process | TF/Python; **no stock TFLite** — convert yourself; designed for **multi-site digital stethoscope**, not phone cough clip | **Partial** — clinically relevant pediatric LMICs evidence (npj Digit Med); poor drop-in for current single phone-mic UX | [github.com/epfl-iglobalhealth/DeepBreath-NatMed23](https://github.com/epfl-iglobalhealth/DeepBreath-NatMed23) | **L** (hardware + protocol change) |
| **ResoNet** | Cough → bronchitis / normal / pertussis / pneumonia (demo app) | Check repo license before prod use | **ONNX** + Flutter `onnxruntime`; pure-Dart DSP | **Partial** — closest Flutter cough-disease UX; **not** maternal-validated; disease labels may mislead CHOs | [github.com/shahriar-ahmed-seam/ResoNet](https://github.com/shahriar-ahmed-seam/ResoNet) | **M** (1–3 wks) if license OK; keep advisory UI |
| **CoughVID-trained classifiers / Cough-E** | Cough detection / COVID-era cough apps; edge cough detect | CoughVID dataset **CC BY 4.0**; model licenses vary | Often ONNX/TFLite/micro | **Partial** — cough presence useful as gate; disease claims weak | [zenodo CoughVID](https://zenodo.org/records/4048312), [Cough-E](https://github.com/esl-epfl/Cough-E) | **M** |
| **Fetal PCG models / GarbhSurakhsha-style** | Fetal heart sound normal/abnormal research | Datasets: PhysioNet ODC-By / credentialed; app code varies | Research TF; rarely production TFLite | **Poor** for current MVP (needs dedicated PCG hardware/protocol); **future** antenatal module only | [PhysioNet SUFHSDB](https://physionet.org/content/sufhsdb/1.0.1/), [fpcgdb](https://www.physionet.org/content/fpcgdb/1.0.0/), [GarbhSurakhsha](https://github.com/IntegrationGOAT/garbhsuraksha) | **XL** |
| **Whisper Tiny Dagbani** (`waxal-benchmarking/whisper-tiny-waxal-dag`) | Dagbani ASR (WER ~39.5% reported) | Apache-2.0 | Transformers; heavy for low-end phones — better **backend** or larger devices | **Poor** for emergency screening audio; **partial** for Phase-2 voice dictation / IVR analytics | [HF waxal-benchmarking/whisper-tiny-waxal-dag](https://huggingface.co/waxal-benchmarking/whisper-tiny-waxal-dag) | **M–L** for dictation; not for YAMNet replacement |

**Distinction to keep in pitch decks:** generic AudioSet AED (YAMNet) ≠ clinically validated obstetric/respiratory screening.

### 5.4 Recommendation timeline

| Horizon | Action |
|---------|--------|
| **Short-term (hackathon)** | Keep **YAMNet + disclaimers** (or web simulator). Do not train. Do not claim diagnosis. Lead with MOEWS + dispatch. |
| **Medium-term (pilot)** | Accept HeAR ToS **or** OPERA MIT path → on-device TFLite/ONNX event detector + linear head; ethics-approved Ghana cough/breath pilot set; CHO-in-the-loop only. |
| **Long-term** | Train/fine-tune **custom** head (or full model) on Northern Ghana CHPS data; stethoscope protocol if targeting DeepBreath-class claims; clinical study before removing disclaimer; optional fetal PCG as separate product line. |

### 5.5 Actionable ML backlog

- [ ] Document model card in-repo: YAMNet advisory limits, AudioSet class indices used, failure → stub behavior.
- [ ] Legal review of HeAR HAI-DEF ToS before any integration or redistribution.
- [ ] Spike: export HeAR MobileNet event detector to TFLite; A/B against YAMNet on 20 labeled clips (non-clinical lab set).
- [ ] Spike: OPERA embedding + logistic head on public cough dataset; measure phone-mic domain gap.
- [ ] Ethics package for Ghana acoustic data collection (consent, storage, retention, GHS approval).
- [ ] Decide stethoscope vs phone-mic product requirement before DeepBreath-class work.
- [ ] Explicitly defer fetal PCG until antenatal hardware partnership exists.

---

## 6. Local language / voice / recordings

**Brand:** “Yoma” = Dagbani for quick/fast (`docs/plans/...-plan.md`). UI remains English.

### What’s missing

- [ ] Home-screen Dagbani gloss (not in `home_screen.dart`).
- [ ] Reviewed Dagbani SMS/USSD copy (native-speaker + clinical accuracy).
- [ ] Pre-recorded Dagbani IVR / AT Voice prompts for drivers and caregivers.
- [ ] Full app l10n (Dagbani, Gonja, Likpakpaanl, etc. as needed by district).
- [ ] Caregiver-facing voice education (Viamo-style) — PRODUCT_SPEC / clinical research personas.
- [ ] ASR for clinical dictation (Whisper-Dagbani exists but high WER; not emergency-ready).

### Resource checklist (to add)

- [ ] Speaker recruitment plan (gender-balanced, multiple Northern dialects).
- [ ] Consent forms (recording + model training + redistribution).
- [ ] Script pack: emergency dispatch, decline, arrival, hospital divert, caregiver updates.
- [ ] Quiet + realistic CHPS noise recording environments.
- [ ] Secure storage (encrypted object store; access audit); no raw PHI in filenames.
- [ ] QA by bilingual CHO / midwife reviewers.
- [ ] Budget for AT Voice minutes + TTS or human voice talent.

**Hackathon:** soft localization only (brand + English). **Do not claim live Dagbani TTS.**

---

## 7. Integrations & infrastructure

- [ ] Host API on reachable HTTPS host (not only `127.0.0.1`) for device demos.
- [ ] Secrets management (`.env` / vault); rotate AT and MoMo keys post-hackathon.
- [ ] Postgres backups + migration strategy (Alembic or equivalent — confirm current `init_db` only).
- [ ] Staging vs production environments (`ENVIRONMENT` in config).
- [ ] CORS: stage network origins allowlist; **never** `*` in production (`tests/test_cors.py` pattern).
- [ ] Africa’s Talking production account + Ghana shortcode procurement.
- [ ] MTN MoMo merchant / disbursement KYC.
- [ ] Monitoring uptime (UptimeRobot / Cloud Run health).
- [ ] Optional: Gemini key only if summarization desired; system must work without it.
- [ ] Vector store persistence volume for RAG (`VECTOR_STORE_DIR`).

---

## 8. Rebrand / docs leftovers

Active mobile/backend surfaces are largely Yoma-clean (`TASK_BOARD` W0.1). Remaining:

- [ ] Reconcile `PRODUCT_SPEC.md` / `docs/yoma-triage-product-spec.md` **Phase 1** roadmap: still lists on-device SLM as this-week deliverable (§XVI) — mark as pilot backlog (W0.2 incomplete).
- [ ] Mark SQLCipher, cert pinning, encrypted SMS telemetry, OTP auth as **not implemented** in security sections (still read as present tense in PRODUCT_SPEC ~§1472).
- [ ] Align architecture diagrams that historically implied mobile→AT direct SMS with backend-mediated rule.
- [ ] Update `Yoma Triage Clinical Design Research.md` Kotlin/Compose narrative remnants if any remain vs Flutter stack.
- [ ] Pitch decks / external one-pagers: audit RelayAI / RelayCare / RelayDispatch naming.
- [ ] README still says “Backend-only MVP” while Flutter exists — refresh quick-start to dual-stack.
- [ ] Keep intentional “relay” English verbs; avoid product-name regressions (`rg -ni 'relay'` gate excluding review changelogs).

---

## 9. Testing & quality

### Coverage gaps

- [ ] Live AT integration test (opt-in, credential-gated; not CI-default).
- [ ] MoMo sandbox integration test (credential-gated).
- [ ] Hospital SMS GSM segment-length unit test.
- [ ] Voice cascade tests (once implemented).
- [ ] RAG ingest + retrieval tests with fixture PDFs.
- [ ] Load / concurrent referral stress beyond single accept race.
- [ ] Flutter golden/overflow + offline reconnect automated test.
- [ ] E2E Playwright/Appium optional for web/Android.

### Demo runbook holes

- [x] Single **Demo Day Runbook** — `docs/plans/demo-day-runbook.md` (seed, API, AT, ngrok, failure fallback).
- [x] Explicit “what to say if AT is down” (mock fallback is OK) — in demo-day runbook.
- [ ] Explicit “what YAMNet is / isn’t” slide or scripted line.
- [ ] Port mismatch fix (5432 vs 5433) in all docs.
- [ ] Post-demo teardown (revoke ngrok, rotate keys).

### Quality gates

- [ ] Never mark TASK_BOARD DONE without pytest + flutter test (existing rule).
- [ ] Pre-commit / CI already partially present (`.pre-commit-config.yaml`) — ensure team runs it.
- [ ] Exclude `.env`, `.idea/`, secrets from any future commit.

---

## 10. Resources to add

### Binary / model assets

- [ ] Keep `yamnet.tflite` intentional in git LFS or fetch script (size ~4 MB).
- [ ] Future: HeAR/OPERA TFLite/ONNX artifact + class map JSON + model card.
- [ ] Optional INT8 YAMNet variant only if targeting microcontrollers (not current CHO phones).

### Datasets (pilot)

- [ ] Ethics-approved Ghana cough/breath set (phone mic).
- [ ] Optional: CoughVID / OPERA public sets for pretrain probes (license compliance).
- [ ] PhysioNet fetal PCG only if antenatal track funded.
- [ ] Real GHS protocol PDFs for RAG (not sample strings).

### Credentials & telecom

- [x] AT API key, username, sender ID (`99193`), USSD shortcode (`*384*99193#`) — sandbox working locally; keep out of git.
- [ ] MoMo primary/secondary keys, target environment, callback URL.
- [ ] Gemini key (optional).
- [ ] TLS certs for public API.

### Hardware

- [ ] Demo Android + iPhone devices with offline airplane-mode rehearsal.
- [ ] Optional digital stethoscope if pursuing DeepBreath-class path.
- [ ] Projector / hotspot for judge room.

### Seed / ops data

- [ ] Expand `data/demo_data.json` with real pilot compounds/drivers/hospitals (replace sandbox `+23324000…` when authorized).
- [ ] Hospital contact verification process.
- [ ] Driver MoMo MSISDN verification list.

### People

- [ ] Dagbani copy reviewers; clinical advisor for MOEWS UX; GHS liaison for pilot ethics.

---

## 11. Prioritized backlog

### P0 — Demo day / this week

1. [x] **Live AT credentials + one real SMS** (sandbox form path verified).
2. [x] **End-to-end rehearsal** seed → USSD accept → hospital SMS → CONFIRM → arrival → COMPLETED (+ decline/divert) via `scripts/demo_flow.py` (2026-07-27).
3. [x] **Stable ngrok (or host) + AT callback URLs** — `PUBLIC_BASE_URL` in `.env`; verified tunnel reaches USSD + SMS inbound (2026-07-27).
4. [x] **CORS browser smoke** — `scripts/cors_smoke.py` + Chromium cross-origin fetch (2026-07-27).
5. [ ] **Physical device build** (Android minimum; iPhone if claimed on stage) — **next best task**.
6. [ ] **Pitch honesty**: YAMNet advisory + MOEWS spine; no clinical AI overclaim; MoMo mocked unless keys set.
7. [x] **Single Demo Day Runbook** — `docs/plans/demo-day-runbook.md`.

### P1 — Next 2–4 sprints (pilot prep)

- [ ] Spec reconciliation (Phase 1 SLM/security language).
- [ ] Dagbani gloss + bilingual SMS templates + l10n scaffolding.
- [ ] HeAR or OPERA spike + legal review; model card.
- [ ] MoMo sandbox real disbursement + async client.
- [ ] USSD shortcode production provisioning.
- [ ] CHO OTP + encrypted local storage design.
- [ ] Hosted staging API + secrets + monitoring.
- [ ] Hospital SMS segment measurement + template module.
- [ ] Expand seed data toward Kassena-Nankana / Savelugu pilot geography (PRODUCT_SPEC Phase 2).

### P2 — Later (production / scale)

- [ ] Voice cascade + Dagbani IVR recordings.
- [ ] 70% MoMo completion payout + escrow fund.
- [ ] Hospital dashboard + LHIMS/DHIS2.
- [ ] On-device SLM triage (Phi-3/Gemma) if still desired — secondary to MOEWS.
- [ ] Custom fine-tuned respiratory model + clinical validation; remove disclaimer only after study.
- [ ] Fetal PCG track; NAS integration; multi-district ops; ISO 27001 / broader compliance.

### Suggested sprint order

1. Demo blockers (P0) → 2. Docs honesty + staging host → 3. MoMo sandbox + AT production path → 4. Language soft→hard → 5. ML spike (HeAR/OPERA) → 6. Auth/SQLCipher → 7. Hospital dashboard → 8. Custom model study.

---

## Appendix — Canonical routes (do not invent)

| Method | Route | Status |
|--------|-------|--------|
| POST | `/api/v1/referral` | Implemented |
| GET | `/api/v1/referral/{id}` | Implemented |
| GET | `/api/v1/dispatch/{id}` | Implemented |
| GET | `/api/v1/dispatch/{id}/logs` | Implemented |
| POST | `/ussd/callback` | Implemented |
| POST | `/api/v1/sms/inbound` | Implemented |
| POST | `/api/v1/driver/{id}/availability` | Implemented |
| GET | `/api/v1/compound/{id}/drivers` | Implemented |
| GET | `/api/v1/driver/{id}/status` | Implemented |
| POST | `/api/v1/ussd/callback` | **Not implemented** (alias) — decided: keep only `/ussd/callback` |
| Voice callback | — | **Not implemented** |

---

*End of remaining-work document. Update this file as items close; keep checkboxes honest.*
