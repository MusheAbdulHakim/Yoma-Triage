# Yoma Triage — Production-Close Hackathon Implementation Plan

> **Review changelog (2026-07-26):** Corrected after repository audit: made the patient token unlinkable to names, removed raw names from the mobile outbox/API path, replaced the duplicate demo-timeline endpoint with the existing dispatch-log route, added failing Flutter baseline repair and web CORS/startup smoke tasks, completed the Relay* inventory, corrected the voice-cascade claim, and made arrival side effects/route contracts explicit.
>
> **PO decisions (2026-07-26) — DECIDED; implementation authorized:** See §11. Demo on Android + iPhone + responsive web; Africa’s Talking SMS LIVE with mock fallback; real `yamnet.tflite` (not stub-primary); keep **Yoma Triage** naming; add architecture narrative for judges; proceed with implementation.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Do not git commit** unless the user explicitly asks.

**Goal:** Bring the existing Flutter CHO app + FastAPI backend to a **demo-credible, production-close** quality bar for the UNICEF StartUp Lab hackathon pitch — without claiming unvalidated clinical AI or shipping features that require assets (trained breath model, Dagbani recordings) we do not have.

**Architecture:** Keep the verified backend as the dispatch/SMS/USSD/MoMo authority; harden privacy, observability, and demo reliability. Keep the Flutter app as a thin offline-first CHO client; polish clinical UX, honest screening labeling, offline queue UX, and end-to-end status. Defer true production (auth, SQLCipher, real MoMo, Dagbani TTS, fine-tuned models, hospital dashboard) to an explicit backlog.

**Tech Stack:** Flutter 3.x / Dart 3.5+, FastAPI, SQLAlchemy 2.0 async + PostgreSQL, Africa's Talking (sandbox/mock), MOEWS + SMS codec, optional YAMNet TFLite asset or stub/simulator, pytest + flutter test.

## Global Constraints

- Offline-first: never require 3G/4G for core CHO actions; queue when API unreachable.
- SMS payloads ≤ 140 octets when using compressed telemetry; no raw patient names on SMS/unencrypted channels — SHA-256 patient tokens only.
- Clinical grounding via MOEWS; no unbounded conversational clinical AI in dispatch path.
- Human-in-the-loop: CHO confirms referral; driver accepts; AI never auto-dispatches.
- Mobile never calls Africa's Talking — backend only (`MessagingGateway`).
- Mock MoMo for hackathon; never create duplicate `momo_escrow` `dispatch_log` rows on retries.
- USSD callbacks must return within ~10s (side effects in `BackgroundTasks`).
- Never commit `.env`, API keys, or `docs/superpowers/` contents.
- Test-first: failing test → minimal impl → pass → commit (when implementation is authorized).
- Brand: **Yoma Triage** ("Yoma" = Dagbani for quick/fast). Avoid consumer “AI purple” UI; clinical, high-contrast, low-literacy.

---

## 0. Planning Assumptions (explicit)

These are assumed so the plan can be complete without blocking on product-owner answers. Open questions that could reverse them are in §11.

| ID | Assumption |
|----|------------|
| A1 | Hackathon demo is **live or hybrid**: Flutter web/Android + local FastAPI + `scripts/demo_flow.py` / AT sandbox simulator for USSD. |
| A2 | **No trained pediatric respiratory model** and **no Dagbani audio recordings** before demo day. |
| A3 | Judges value **honest labeling** of demo AI more than fake clinical accuracy claims. |
| A4 | Primary narrative district: **Tamale South CHPS → Tamale Teaching Hospital** (matches `data/demo_data.json` / seed). |
| A5 | On-device SLM (Phi-3/Gemma) is **out of demo scope** — MOEWS + advisory screening is enough for the pitch. |
| A6 | Real MTN MoMo and provisioned USSD shortcode may be **unavailable**; mock + AT sandbox is acceptable if clearly labeled. |
| A7 | English UI for CHO app is acceptable; Dagbani used for **branding cues + SMS/USSD copy samples**, not live TTS. |

---

## 1. Brainstorming Summary — Approaches Considered

### 1.1 Overall productization strategy

| Approach | Pros | Cons |
|----------|------|------|
| **A. Spec-complete Phase 1** (PRODUCT_SPEC §XVI: SLM + YAMNet + live AT + voice) | Matches written vision | Unrealistic before hackathon; invents assets we lack |
| **B. Demo theater only** (scripted UI, no backend hardening) | Fast | Breaks under judge questions; not “production-close” |
| **C. Demo-credible production-close MVP** (recommended) | Hardens real E2E path; honest AI; clear backlog | Requires ruthless scope cuts |

**Recommendation: C.** Harden what already exists (`TASK_BOARD` VERIFIED backend + Flutter shell), fix safety/privacy gaps, polish the pitch path, label stubs honestly.

### 1.2 Audio screening without a trained model

| Approach | Pros | Cons |
|----------|------|------|
| **A. Bundle generic YAMNet + map AudioSet classes** | Looks “real”; on-device story | Not pediatric-validated; easy to overclaim |
| **B. Stub/simulator only + honest UI** | Zero false clinical claims; reliable demo | Weaker “edge AI” visual |
| **C. Hybrid** (recommended): ship path for `yamnet.tflite` if obtained; default stub/simulator; always show `source` + “demo / not clinically validated” banner | Demo-resilient + architecture-ready | Slightly more UI work |

**Recommendation: C.** Keep `YamnetClassifierIo` + stubs; require honest labeling on `ResultScreen`; treat real weights as optional boost, not blocker.

### 1.3 Local language without recordings

| Approach | Pros | Cons |
|----------|------|------|
| **A. Fake Dagbani TTS** | Pitch theater | Credibility risk if judges ask |
| **B. English-only** | Simple | Weak cultural fit for “Yoma” brand |
| **C. Soft localization** (recommended): Dagbani wordmark/tagline, bilingual SMS/USSD **templates in docs + optional string constants**, English CHO UI, Phase-2 recording backlog | Authentic without assets | Not full voice-first Principle 5 |

**Recommendation: C.**

---

## 2. Current State Audit

### 2.1 Backend — what works today

| Area | Status | Evidence |
|------|--------|----------|
| DB models (compound, driver, facility, referral, dispatch, logs, wallet, audit) | Works | `src/db/models.py`, seed via `src/db/seed.py` + `data/demo_data.json` |
| MOEWS calculator | Works | `src/tools/moews_calculator.py`, `tests/test_moews.py` |
| SMS codec (compact Base64) | Works (narrow 6-byte schema vs full PRODUCT_SPEC vector) | `src/tools/sms_codec.py` |
| Clinical + coordinator graph | Works | `src/agents/clinical_agent.py`, `coordinator.py` |
| Dispatch cascade + concurrent accept | Works | `src/services/dispatch_orchestrator.py`, `tests/test_dispatch.py` |
| Messaging gateway (AT or mock) | Works | `src/services/messaging_gateway.py` — mock if no `AT_API_KEY` |
| USSD accept/decline idempotent | Works | `src/api/ussd.py` (note: prefix `/ussd/callback`, not `/api/v1/ussd/callback`) |
| Referral API + `client_request_id` idempotency | Works | `src/api/referral.py` |
| Hospital CONFIRM / DIVERT SMS | Works | `src/api/sms_webhook.py` |
| Mock MoMo on accept | Works | `src/tools/momo_escrow.py` + accept side-effects |
| Driver availability | Works | `src/api/driver.py`, `src/services/driver_pool.py` |
| Demo script | Works | `scripts/demo_flow.py` |
| Backend test suite | Strong | 47 passed on 2026-07-25; current audit re-confirmed the recorded result |
| Flutter test suite | **Failing baseline** | `flutter test` on 2026-07-26 fails because `widget_test.dart` and `simulator_flow_test.dart` still instantiate removed `RelayApp` instead of `YomaApp` |

### 2.2 Backend — stubbed / partial / gaps

| Gap | Severity for demo | Notes |
|-----|-------------------|-------|
| Voice cascade | Medium | Orchestrator never calls `initiate_voice`; the gateway method itself is MOCK without AT and FAILED with AT — product cascade expects voice at T+90s |
| Tier-3 personal emergency contacts | Low–Medium | Tier ≥3 = CHO “coordinate manually” only (`dispatch_orchestrator.py`) |
| Arrival confirmation USSD | Medium | No “Confirm Arrival” → `COMPLETED` path in `ussd.py` |
| Patient name on hospital SMS | **High (safety)** | `hospital_notifier.py` sends `referral.patient_name` — violates privacy rule |
| Patient token quality | **High (privacy)** | Flutter uses `hash-${name.hashCode}`. A bare SHA-256 of a normalized name would still be brute-forceable/linkable; use a per-referral random token, then SHA-256 it |
| Raw name in offline persistence/API | **High (privacy)** | Flutter serializes `patient_name` into SQLite/SharedPreferences and backend stores/returns it, conflicting with PRODUCT_SPEC minimal-storage claims |
| Full SMS clinical vector (PRODUCT_SPEC §10.5) | Low for demo | Codec is intentionally minimal MVP |
| Auth / OTP | Out of scope | Documented MVP non-goal |
| Observability for judges | Medium | Logs only; no demo status board |
| RAG / Gemini optional path | Low | Must not block referral; keep UNKNOWN best-effort |
| USSD route prefix vs PRODUCT_SPEC table | Low | Spec lists `/api/v1/ussd/callback`; code is `/ussd/callback` — document or alias |
| Web demo CORS | **High for stage demo** | `main.py` has no CORS middleware while Flutter web defaults to `http://127.0.0.1:8000`; browser calls from the Flutter dev-server origin will be blocked |
| Demo observability endpoint | None | `GET /api/v1/dispatch/{id}/logs` already exists and is used by `scripts/demo_flow.py`; do not add a duplicate timeline API |

### 2.3 Flutter — what works today

| Area | Status | Evidence |
|------|--------|----------|
| App shell / branding title | Works | `mobile/lib/main.dart`, Android label, web manifest |
| Home: Screen Breathing / Emergency Referral | Works | `home_screen.dart` |
| Screening 15s + Stop early | Works | `screening_screen.dart` |
| Web simulator Normal / Code Red | Works | web path + tests |
| Result GREEN/RED/INCONCLUSIVE | Works | `result_screen.dart`, `screening_result.dart` |
| Referral vitals form + confirm | Works | `referral_screen.dart` (hardcoded compound/facility `1`) |
| Offline outbox + flush | Works | `offline_queue.dart`, `queue_sync_service.dart` |
| Dispatch status polling | Works | `dispatch_status_screen.dart` (2s backoff) |
| API client | Works | `api_client.dart` — referral create + get dispatch |
| Package identity | Mostly done | `yoma_triage`, `gh.yomatriage.yoma_triage` |

### 2.4 Flutter — stubbed / missing / fragile

| Gap | Severity | Notes |
|-----|----------|-------|
| `assets/models/yamnet.tflite` | Expected | Only `.gitkeep`; Android falls back to stub |
| YAMNet score semantics | **High for credibility** | Current `_abnormalScore` averages the top five of 521 AudioSet outputs without class-label selection; even with weights this is not a defensible respiratory anomaly score |
| Honest “not clinically validated” labeling | High for credibility | Result shows `source` but no advisory banner |
| SHA-256 patient hash | High | Privacy |
| go_router / typed routes | Medium | Imperative `Navigator` only |
| Design system / tokens | Medium | Seed color `0xFF1A5F7A` inline; no theme package |
| Accessibility (Semantics, large text, contrast) | Medium | Clinical low-literacy needs larger targets + semantics |
| Error states polish | Medium | Mic deny → partial; offline sync after queue doesn’t re-bind dispatch id elegantly |
| Facility/compound picker | Low–Medium | Hardcoded IDs |
| Refusal documentation journey | Out of demo MVP | PRODUCT_SPEC Journey 5 |
| Auth / SQLCipher / cert pinning | Phase 2 | Per flutter design non-goals |
| Widget test coverage | Partial | `mobile/test/*` exists; no golden/a11y suite |

### 2.5 PRODUCT_SPEC / TASK_BOARD delta (hackathon-relevant)

**Already VERIFIED (do not rebuild):** Tasks 1.1–1.10, 2.x, 3.x, 4.1–4.7, 5.x, 6.x per `TASK_BOARD.md`.

**PRODUCT_SPEC promised but not shipped (defer or thin-slice):**

- On-device SLM triage → **defer**
- Dagbani TTS / voice-first → **defer** (copy templates only)
- Real MoMo escrow → **mock + UI explanation**
- Community contacts / volunteer tiers → **defer** (keep CHO give-up)
- Hospital dashboard / DIVERT UI beyond SMS → **SMS only**
- Arrival confirmation → **thin slice for demo**
- Full 60s recording → keep 15s hackathon default
- OTP auth → **defer**

---

## 3. Rebrand Inventory

### 3.1 Still using old / dual naming

| Location | Current text | Action |
|----------|--------------|--------|
| `PRODUCT_SPEC.md` §Solution | **RelayCare Mobile**, **RelayDispatch** | Rename to **Yoma Care (mobile)** / **Yoma Dispatch (gateway)** or simply “CHO app” / “Dispatch gateway” |
| `docs/yoma-triage-product-spec.md` | Same RelayCare/RelayDispatch | Sync with PRODUCT_SPEC |
| `Yoma Triage Clinical Design Research.md` (and any `RelayAI Clinical Design Research.md` leftover) | RelayCare / RelayDispatch / Kotlin Compose narrative | Update product names; note Flutter is actual stack |
| `mobile/test/widget_test.dart`, `mobile/test/simulator_flow_test.dart` | `RelayApp` (nonexistent) | Rename to `YomaApp`; this currently breaks `flutter test` |
| `src/tools/momo_escrow.py` | `externalId = "RELAY-..."` | Rename the external-id prefix to a Yoma-safe value; real MoMo remains deferred |
| Pitch decks / external one-pagers (if any outside repo) | Audit at demo prep | Replace RelayAI → Yoma Triage |

### 3.2 Already on Yoma Triage (verify only)

- `main.py`, `README.md`, `TASK_BOARD.md`, `.cursorrules`
- `mobile/pubspec.yaml`, `mobile/lib/main.dart`, screens AppBars
- Android `applicationId` / `MainActivity` package `gh.yomatriage.yoma_triage`
- `mobile/web/index.html`, `manifest.json`
- SMS sender default `AT_SENDER_ID=YOMATRIAGE`
- USSD menu “Yoma Triage Emergency Referral”
- MoMo payer message “Yoma Triage Emergency Fuel Stipend”

### 3.3 Visual / voice identity for hackathon

| Element | Guidance |
|---------|----------|
| Wordmark | **Yoma Triage** — primary; optional subtitle “Yoma — quick” (Dagbani gloss) once on home |
| Color | Keep clinical teal/deep cyan (`#1A5F7A`) + alert red (`#C62828`) + safe green (`#2E7D32`); **no purple AI gradients** |
| Typography | Prefer a clear readable family (e.g. `google_fonts` Source Sans 3 / IBM Plex Sans) — avoid Inter-as-default-only if adding fonts; keep high contrast |
| Tone | Direct, calm, clinical; short sentences; no playful emoji |
| AI honesty | Always: “Advisory screening — CHO decides” |

---

## 4. Hackathon Demo Scope vs True Production

### 4.1 In scope — “production-close” demo MVP

1. Rebrand copy cleanup (RelayCare/RelayDispatch → Yoma names).
2. Privacy fix: SHA-256 of a cryptographically random per-referral token; **no names in SMS, mobile outbox, or API payload**.
3. Honest acoustic screening UX (stub/simulator/optional YAMNet) + banners.
4. Flutter polish: theme tokens, a11y basics, clearer offline/error/status, optional compound display names.
5. Backend: arrival USSD → COMPLETED; hospital SMS uses token; existing dispatch-log API/demo script gives observability; demo-only CORS allowlist and startup smoke; optional AT sandbox dry-run docs.
6. End-to-end demo script (human + `demo_flow.py`) covering screen → refer → accept → MoMo mock → hospital notify → confirm/divert → arrival.
7. Regression: `pytest` + `flutter test` green; demo checklist doc.

### 4.2 Explicit later backlog (not before hackathon)

- Fine-tuned / HeAR respiratory model + Ghana validation
- Dagbani TTS recordings + Africa’s Talking Voice production
- On-device SLM (Phi-3/Gemma)
- Real MoMo merchant + 30/70 escrow
- Provisioned USSD shortcode
- CHO OTP auth, SQLCipher, cert pinning
- Personal emergency contacts + full cascade voice tiers
- Hospital web dashboard / LHIMS
- Full PRODUCT_SPEC SMS clinical vector
- Caregiver refusal workflow UI
- Multi-district ops tooling

---

## 5. Audio Screening Strategy (no trained clinical model)

### 5.1 Demo path (must ship)

1. **Web:** Demo Normal / Demo Code Red only (`simulator` source) — already implemented.
2. **Android without `yamnet.tflite`:** stub classifier (`source: stub`) — already implemented.
3. **UI:** On `ResultScreen`, if `source != 'yamnet'` OR always for hackathon:
   - Banner: “Demo screening mode — not clinically validated.”
   - Keep CHO Confirm / Continue monitoring.
4. **Pitch script line:** “Architecture runs on-device TFLite; today we demonstrate the workflow with a transparent demo classifier. Production uses a locally validated respiratory model.”

### 5.2 Optional technical smoke (not a product boost)

- Download official YAMNet TFLite (~4.13 MB) into `mobile/assets/models/yamnet.tflite`.
- Use it only to prove local TFLite loading/inference after checksum and tensor-shape verification.
- Do **not** use the current “mean top-five classes” calculation as a respiratory anomaly proxy. A class-map-based feature with clinically reviewed semantics is separate future work.
- Keep the validation disclaimer for every source, including `yamnet`.

### 5.3 Path to real model (backlog note only)

- Collect Dagbani-region pediatric auscultation with ethics approval → fine-tune / HeAR → replace mapping → clinical validation study → only then remove disclaimer.

### 5.4 What NOT to do

- Do not silently present stub scores as YAMNet.
- Do not upload raw audio.
- Do not auto-refer on RED without CHO confirm.

---

## 6. Local Language / Voice Strategy (no recordings)

| Channel | Hackathon | Later |
|---------|-----------|-------|
| CHO app UI | English + Dagbani brand gloss on home | Full l10n ARB (Dagbani, Gonja, …) |
| Driver SMS | English templates; optional second line Dagbani **placeholder string** in code comments / `message_templates.py` | Real Dagbani copy reviewed by native speakers |
| USSD | English numbered menu (literacy-tolerant) | Bilingual menus if character budget allows |
| Voice / TTS | Show mock voice log in demo_flow (“would call in Dagbani”) | Pre-recorded Dagbani prompts via AT Voice |
| Caregiver | Out of app; CHO speaks locally | IVR education partnerships (Viamo) |

**Requires recordings:** production voice alerts, Whisper fine-tune, any claim of “voice-first in Dagbani.”

---

## 7. End-to-End Demo Workflow — Gaps & Hardening

```
CHO (Flutter)
  → Screen Breathing (sim/stub/optional YAMNet) OR Emergency Referral bypass
  → Result (advisory) → Confirm
  → POST /api/v1/referral (or offline queue → flush)
  → Backend MOEWS + dispatch cascade
  → SMS to drivers (mock or AT)
  → USSD Accept (simulator / demo_flow)
  → Mock MoMo + hospital SMS (hash only)
  → Hospital CONFIRM or DIVERT (SMS webhook)
  → [GAP TODAY] Driver arrival USSD → COMPLETED
  → Flutter dispatch status polling
```

**Canonical implemented routes (do not invent aliases in tests or runbooks):**

| Method | Route | Status |
|--------|-------|--------|
| POST | `/api/v1/referral` | Implemented |
| GET | `/api/v1/referral/{id}` | Implemented |
| GET | `/api/v1/dispatch/{id}` | Implemented |
| GET | `/api/v1/dispatch/{id}/logs` | Implemented; judge-visible audit source |
| POST | `/ussd/callback` | Implemented canonical USSD webhook |
| POST | `/api/v1/sms/inbound` | Implemented |
| POST | `/api/v1/driver/{id}/availability` | Implemented |
| GET | `/api/v1/compound/{id}/drivers` | Implemented |

There is **no** `GET /api/v1/driver/{id}/status`, `/api/v1/ussd/callback`, voice callback, or separate demo timeline route in current code. Add no alias unless the product owner explicitly chooses it in §11.

| Step | Gap | Hardening task |
|------|-----|----------------|
| Screening | Missing model / honesty | §5 + Task M2 |
| Hash / SMS PII | Name on hospital SMS; weak hash | Tasks B1–B2, M3 |
| Offline → live status | After flush, dispatch id not always rebound | Task M5 |
| Voice tier | Not real | Demo script explains mock; optional log action `voice_mock` |
| Arrival | Missing | Task B3 |
| Judge visibility | Existing logs endpoint + script | Task B4 enhances `demo_flow`; no new endpoint |
| AT live | Credentials unknown | Task B5 sandbox runbook |
| Flutter web → API | No CORS middleware | Task B0 CORS allowlist + browser smoke |
| Test baseline | `RelayApp` compile failures | Task W0.0 before all feature work |

---

## 8. File Touch Map (decomposition)

### 8.1 Backend

| File | Responsibility in this plan |
|------|------------------------------|
| `src/services/hospital_notifier.py` | SMS without patient names; use hash token |
| `src/api/referral.py` | Validate `patient_hash` as exactly 64 lowercase hex; do not require or echo patient name |
| `src/api/ussd.py` | Add arrival confirm menu path |
| `src/services/dispatch_orchestrator.py` | `handle_arrival` → COMPLETED + CHO notify |
| `src/api/referral.py` | Reuse existing `GET /api/v1/dispatch/{id}/logs` for judge timeline |
| `main.py`, `src/config.py` | Demo-origin CORS allowlist; no wildcard production policy |
| `src/services/messaging_gateway.py` | Ensure voice mock logs clearly for demo |
| `scripts/demo_flow.py` | Extend arrival step + privacy assertions |
| `tests/test_*.py` | Privacy, arrival, timeline |

### 8.2 Flutter

| File | Responsibility |
|------|----------------|
| `mobile/lib/theme/yoma_theme.dart` (new) | Colors, text theme, button styles |
| `mobile/lib/main.dart` | Apply theme; keep `YomaApp` |
| `mobile/lib/screens/*.dart` | Consume theme; banners; a11y |
| `mobile/lib/services/patient_token.dart` (new) | SHA-256 of cryptographically random per-referral material; never hash a name |
| `mobile/lib/models/referral.dart` | Populate token; remove serialized `patient_name` |
| `mobile/lib/screens/result_screen.dart` | Demo disclaimer |
| `mobile/lib/screens/referral_screen.dart` | Hashing; clearer facility labels |
| `mobile/lib/screens/dispatch_status_screen.dart` | Post-sync dispatch binding; terminal states include arrival |
| `mobile/lib/l10n/brand_copy.dart` (new) | Dagbani gloss + English strings |
| `mobile/test/*` | New tests for hash, disclaimer, theme smoke |

### 8.3 Docs / brand

| File | Responsibility |
|------|----------------|
| `PRODUCT_SPEC.md`, `docs/yoma-triage-product-spec.md` | RelayCare/RelayDispatch rename |
| `README.md` | Demo runbook + honesty notes |
| `docs/plans/yoma-triage-demo-runbook.md` (optional new at impl time) | Minute-by-minute pitch |

---

## 9. Workstreams & Phased Tasks

> Implement in order **W0 → W1 → W2 → W3 → W4 → W5**. Do not mark `TASK_BOARD` items done until tests pass (verifier process).

---

### Workstream W0: Brand & Spec Hygiene

### Task W0.0: Restore a green Flutter baseline

**Files:** `mobile/test/widget_test.dart`, `mobile/test/simulator_flow_test.dart`

- [ ] Run `flutter test` and preserve the observed `RelayApp` compile failure.
- [ ] Replace stale test constructors with the real `YomaApp`.
- [ ] Re-run the full Flutter suite.

**Acceptance:** The pre-existing Flutter suite is green before feature tests are added. Do not hide or skip tests.

### Task W0.1: Eliminate RelayCare / RelayDispatch naming

**Files:**
- Modify: `PRODUCT_SPEC.md` (Solution section ~L37–39 and any architecture labels)
- Modify: `docs/yoma-triage-product-spec.md` (same)
- Modify: `Yoma Triage Clinical Design Research.md` (product component names)
- Modify: `src/tools/momo_escrow.py` (`RELAY-` external-id prefix only; no payment behavior change)
- Verify: case-insensitive repository search for any `relay` branding/symbol

**Interfaces:**
- Produces: Consistent public names — **Yoma Triage** (product), **CHO app** / **Yoma Care**, **Dispatch gateway** / **Yoma Dispatch**

- [ ] **Step 1: Inventory grep**

```bash
rg -ni 'relay' /var/www/html/unicef --glob '!docs/superpowers/**' --glob '!venv/**'
```

Expected before changes: active-doc component names, stale `RelayApp` tests, `RELAY-` MoMo external id, and this plan. Expected after changes: only intentional review/changelog history.

- [ ] **Step 2: Replace component names** in PRODUCT_SPEC Solution block:

```markdown
**Yoma Care (mobile)** — An offline-first Android application …
**Yoma Dispatch** — A multi-channel communication gateway …
```

- [ ] **Step 3: Re-run grep** — zero hits outside intentional historical footnotes (prefer zero).

- [ ] **Step 4: Commit** (when implementation authorized)

```bash
git add PRODUCT_SPEC.md docs/yoma-triage-product-spec.md "*.md"
git commit -m "$(cat <<'EOF'
docs: complete Yoma Triage rebrand naming pass

EOF
)"
```

**Acceptance:** No active RelayAI/RelayCare/RelayDispatch/RelayApp/package/prefix identifiers; Android/web/package names remain Yoma Triage.

**Test:** Grep gate in CI optional; manual grep required.

### Task W0.2: Reconcile active product docs with the honest demo cut

**Files:** `PRODUCT_SPEC.md`, `docs/yoma-triage-product-spec.md`

- [ ] Update the Phase 1 roadmap so it does not claim an on-device SLM or clinically meaningful YAMNet result ships this week.
- [ ] Correct the architecture diagram that visually sends mobile SMS directly to Africa's Talking; backend remains the only gateway.
- [ ] Replace patient-name-in-SMS and “names stored” examples with opaque referral tokens.
- [ ] Mark SQLCipher, certificate pinning, encrypted telemetry, voice/TTS, real MoMo, and production auth as pilot backlog—not current implementation.

**Acceptance:** The two active product specs describe the same hackathon/production boundary as §4 and no longer contradict `.cursorrules` or the actual Flutter/FastAPI architecture.

---

### Workstream W1: Privacy & Clinical Safety (backend + mobile)

### Task B1: Stop sending patient names over SMS

**Files:**
- Modify: `src/services/hospital_notifier.py`
- Test: `tests/test_hospital_privacy.py` (new)

**Interfaces:**
- Consumes: `Referral.patient_hash`, `emergency_type`, `risk_level`
- Produces: Hospital SMS body using `Patient: {hash[:12]}…` (or `token`) — never `patient_name`

- [ ] **Step 1: Write failing test**

```python
# tests/test_hospital_privacy.py
import pytest
from src.services.hospital_notifier import HospitalNotifier

@pytest.mark.asyncio
async def test_hospital_sms_omits_patient_name(db_session, seeded_referral_with_name, driver, facility):
    class SpyGateway:
        def __init__(self):
            self.messages = []
        async def send_sms(self, to, message, dispatch_id, role):
            self.messages.append(message)
            return {"status": "MOCKED"}

    spy = SpyGateway()
    notifier = HospitalNotifier(spy)
    await notifier.notify_pre_arrival(
        db_session, seeded_referral_with_name, driver, facility, dispatch_id=1
    )
    body = spy.messages[0]
    assert seeded_referral_with_name.patient_name not in body
    assert seeded_referral_with_name.patient_hash[:8] in body
```

- [ ] **Step 2: Run test — expect FAIL** (name currently present)

```bash
./venv/bin/python -m pytest tests/test_hospital_privacy.py -v
```

- [ ] **Step 3: Minimal fix**

```python
# hospital_notifier.py — message fragment
token = referral.patient_hash[:12]
message = (
    "YOMA TRIAGE EMERGENCY REFERRAL\n"
    f"From compound #{referral.chps_compound_id}\n"
    f"Patient token: {token}\n"
    f"Condition: {referral.emergency_type}\n"
    f"Severity: {referral.risk_level}\n"
    f"Driver: {driver.name}\n"
    f"Ref: #{referral.id}"
)
```

- [ ] **Step 4: pytest pass + commit** `fix: omit patient names from hospital SMS`

**Acceptance:** No SMS path includes `patient_name`. Driver SMS already omits names (verify in orchestrator).

---

### Task M3 / B1b: Unlinkable SHA-256 patient tokens on mobile and API

**Files:**
- Create: `mobile/lib/services/patient_token.dart`
- Modify: `mobile/lib/screens/referral_screen.dart`
- Modify: `mobile/lib/models/referral.dart`
- Modify: `mobile/lib/services/offline_queue.dart`
- Modify: `src/api/referral.py`
- Test: `mobile/test/patient_token_test.dart`
- Test: `tests/test_referral_privacy.py`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/patient_token.dart';

void main() {
  test('patientToken is unique 64-char lowercase SHA-256 hex', () {
    final a = patientToken();
    final b = patientToken();
    expect(a.length, 64);
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(a, isNot(b));
  });
}
```

- [ ] **Step 2: Implement with `Random.secure()` (or UUID v4 entropy) + `package:crypto`**

```dart
// Generate fresh cryptographically random material per referral, then SHA-256 it.
// Do not derive the token from patient name, phone, DOB, or another low-entropy identifier.
```

Add `crypto` through `flutter pub add crypto` so the lockfile records the resolved current compatible version.

- [ ] **Step 3: Wire referral_screen** — create one token on first confirm and reuse it with the same `client_request_id`. A display name may remain in widget memory for demo readability, but remove `patient_name` from `ReferralRequest.toJson()`, SQLite/SharedPreferences payloads, and backend response. Backend stores `Unknown` until a separately approved encrypted identity design exists.

- [ ] **Step 4: Backend contract test** — reject non-64-hex `patient_hash`, accept valid lowercase SHA-256 token, and assert create/get responses and persisted outbox payloads contain no `patient_name`.
- [ ] **Step 5:** run targeted mobile/backend tests, then both full suites.

**Acceptance:** Outbox/API contain a unique 64-char lowercase hex token and no raw name; no `hash-${hashCode}` or name-derived digest; retries reuse the same token.

---

### Workstream W2: Audio Honesty & Screening UX

### Task M2: Demo disclaimer + source-aware copy

**Files:**
- Modify: `mobile/lib/screens/result_screen.dart`
- Modify: `mobile/lib/services/screening_result.dart` (optional helper `bool get isDemoMode`)
- Test: `mobile/test/result_disclaimer_test.dart` (widget)

- [ ] Always show: “Advisory only — not a diagnosis. Not clinically validated.”
- [ ] When `source` is `stub` or `simulator`, additionally show “Demo screening mode.” Never provide an environment flag that removes the clinical disclaimer.
- [ ] Confirm button label unchanged: CHO remains decision-maker.

**Acceptance:** Widget test finds disclaimer text on simulator RED path; screening still navigates to referral.

### Task M2b: Optional YAMNet asset runbook (docs only unless file obtained)

**Files:**
- Modify: `mobile/README.md`, root `README.md`

Document:

```bash
# Place official YAMNet TFLite at:
# mobile/assets/models/yamnet.tflite
# Asset loading is a technical inference smoke only; demo remains simulator/stub.
```

**Acceptance:** README states missing asset → stub and explains that the current top-five score is not a respiratory classifier; never claim clinical validation.

---

### Workstream W3: Dispatch Completeness for Demo Story

### Task B0: Make the Flutter web stage path reachable

**Files:** `main.py`, `src/config.py`, `.env.example`, `tests/test_cors.py`, `README.md`

- [ ] Write a failing browser-origin preflight test for the configured demo origin.
- [ ] Add explicit configurable demo origins (Flutter dev-server URLs); never use `*` as a production default.
- [ ] Document web, Android-emulator, and physical-device base URLs and run one browser smoke.

**Acceptance:** Flutter web can POST `/api/v1/referral` from its actual origin; unlisted origins receive no CORS grant; API health/seed commands are in a one-command-or-copy-safe startup sequence.

### Task B3: Driver arrival confirmation via USSD

**Files:**
- Modify: `src/api/ussd.py`
- Modify: `src/services/dispatch_orchestrator.py`
- Test: `tests/test_ussd_arrival.py` (new)
- Modify: `scripts/demo_flow.py`

**Interfaces:**
- Produces: `DispatchOrchestrator.handle_arrival(session, dispatch_id, driver_id) -> dict`
- States: from `HOSPITAL_NOTIFIED` / `HOSPITAL_CONFIRMED` → `COMPLETED` (do not allow arrival before hospital notification)
- USSD: resolve the accepting driver's assigned dispatch in those states and offer `3. Confirm arrival`; the current query only searches claimable/`ACCEPTED` and must be covered by route tests

Recommended UX for hackathon (minimal):

```
CON Yoma Triage
1. Accept
2. Decline
3. Confirm arrival
```

- [ ] **Step 1: Failing tests** — assigned `HOSPITAL_NOTIFIED`/`HOSPITAL_CONFIRMED` dispatch + input `3` → status `COMPLETED`; wrong driver and pre-notification arrival rejected; duplicate arrival returns identical success and creates no duplicate logs.
- [ ] **Step 2: Implement `handle_arrival`** as a short locked DB transition; return USSD before external notification. Run CHO notification as an idempotent background side effect, matching accept/decline timeout architecture.
- [ ] **Step 3: Extend `demo_flow.py`** after hospital confirm.
- [ ] **Step 4: Flutter** — treat `COMPLETED` as terminal (already in `_terminalStates`).

**Acceptance:** Integration test covers accept → hospital notify/confirm → arrival → COMPLETED; CHO notification is logged once. Do not claim or implement the production 70% payout in this task.

---

### Task B4: Demo timeline / observability

**Files:**
- Modify: `scripts/demo_flow.py`
- Extend: `tests/test_dispatch_log_api.py`

Reuse `GET /api/v1/dispatch/{dispatch_id}/logs`; it already returns ordered `DispatchLog` rows and `demo_flow.py` already consumes it. Add arrival and privacy assertions plus clearer projector output; do not add a duplicate unauthenticated demo API.

**Acceptance:** After `demo_flow`, the existing logs route shows `sms_send`, `ussd_accept`, `momo_escrow`, `hospital_notify`, `hospital_confirm`, and `arrival_confirm` in order; displayed/logged hospital message contains no patient name.

---

### Task B5: Africa's Talking sandbox runbook (no code required if no credentials)

**Files:**
- Modify: `README.md` or create `docs/plans/at-sandbox-runbook.md` at impl time

Document: env vars (`AT_API_KEY`, `AT_USERNAME`), simulator URL, webhook tunneling (e.g. ngrok) to `/ussd/callback` and SMS inbound, fallback to mock.

**Acceptance:** Operator can choose MOCK vs SANDBOX in ≤5 minutes.

---

### Workstream W4: Flutter Production-Grade Polish

### Task M1: Theme / design tokens

**Files:**
- Create: `mobile/lib/theme/yoma_theme.dart`
- Modify: `mobile/lib/main.dart`

```dart
class YomaColors {
  static const brand = Color(0xFF1A5F7A);
  static const danger = Color(0xFFC62828);
  static const safe = Color(0xFF2E7D32);
  static const caution = Color(0xFFF9A825);
  static const surface = Color(0xFFF7F9FA);
}
```

Apply to all screens; min button height 56–72; high contrast AppBar.

**Test first:** Add a theme/widget smoke test that verifies the branded theme and primary critical-action semantics before changing screen styles.

**Acceptance:** Test-backed visual consistency; no purple seed schemes; no overflow at the demo viewport.

### Task M4: Accessibility & low-literacy

- Write failing widget tests for primary CTA semantics and text labels before adding semantics.
- Semantics labels on primary CTAs (“Screen breathing”, “Confirm emergency referral”).
- Avoid color-only status — include text RED/GREEN/INCONCLUSIVE (already).
- Ensure 18sp+ body on critical instructions.
- Test: `flutter test` + manual TalkBack if device available.

### Task M5: Offline queue → dispatch rebound

**Problem:** `DispatchStatusScreen` with `dispatchId == null` flushes but does not navigate to live dispatch.

**Approach:**
- On successful `createReferral` during flush, parse `dispatch.id` from response; persist mapping `client_request_id → dispatch_id` in outbox row or SharedPreferences; update UI to start polling.

**Files:** `offline_queue.dart`, `dispatch_status_screen.dart`, `api_client.dart` (ensure response parsing), tests in `offline_queue_test.dart`.

**Test first / acceptance:** A failing test must show that a queued request which syncs stores/returns its `dispatch.id` for the same `client_request_id`, transitions the existing status screen to polling, and does not create a second referral.

### Task M6: Compound / facility display (demo)

- Replace silent IDs with labels from constants matching `data/demo_data.json` (“Tamale South CHPS”, “Tamale Teaching Hospital”) — still send ids `1`/`1` unless seed differs.
- Add a widget/contract test asserting displayed labels map to submitted IDs.

### Task M7: Navigation hardening (optional if time)

- **Deferred.** Do not add `go_router` or refactor navigation before the hackathon; current Navigator flow is adequate once tests pass.

---

### Workstream W5: Verification, Demo Script, Backlog Freeze

### Task V1: Full regression

```bash
./venv/bin/python -m pytest -v
cd /var/www/html/unicef/mobile && flutter test
./venv/bin/python scripts/demo_flow.py
```

**Acceptance:** All green; demo_flow prints arrival + timeline. Also run one actual Flutter web browser smoke against FastAPI (tests alone do not prove CORS) and one offline→reconnect sync rehearsal.

### Task V2: Demo day checklist (document)

Minute-by-minute:

1. Seed DB + start API  
2. Flutter web/Android with API_BASE_URL  
3. Screen → Demo Code Red → Confirm vitals → watch status  
4. Run USSD accept via demo_flow or AT simulator  
5. Show hospital SMS content (token, not name)  
6. Arrival confirm → COMPLETED  
7. Airplane mode queue → reconnect flush  

### Task V3: Update TASK_BOARD with **new PENDING** tasks only (do not mark done until verified)

Add section “Hackathon production-close (PENDING)” listing W1–W5 task IDs — **implementation agents** own this; planning agent does not mark complete.

---

## 10. Risks & Constraints

| Risk / constraint | Mitigation |
|-------------------|------------|
| SMS 140-octet limit | Keep codec compact; hospital SMS is short text already; avoid names |
| Unvalidated acoustic AI | Honest banners; CHO confirm; clinical bypass always available |
| No Dagbani audio | Soft localization only; do not claim live Dagbani TTS |
| AT credentials missing | Auto-mock gateway; demo_flow works offline of AT |
| USSD timeout | Keep DB work fast; side effects in BackgroundTasks |
| Duplicate MoMo logs | Existing idempotent check on `momo_escrow` — preserve in arrival work |
| Over-scope (SLM, real MoMo) | §4.2 backlog freeze |
| Privacy Act 843 | Hash tokens; minimize retention narrative in pitch |
| Cleartext HTTP in demo | `usesCleartextTraffic=true` for local demo only — call out as demo config |
| Concurrent accepts | Existing `FOR UPDATE` — do not regress |
| Judges probe “is this diagnostic?” | Scripted answer: screening signal only |

Operational human-readable alerts and compressed clinical telemetry are separate message types. The 6-byte codec satisfies the current telemetry proof, but the plan must not claim that the multi-line hospital message fits one GSM segment without measuring its encoded length. Add a message-length assertion or explicitly label multipart operational SMS as a demo limitation; never place raw clinical identity in either form.

---

## 11. Open Questions for Product Owner

> **Status (2026-07-26):** Product owner answered the blockers. Implementation is **AUTHORIZED**. Remaining items keep the safe defaults noted below.

1. **Demo hardware:** **DECIDED** — Mobile phones: **both Android and iPhone**; **web must work across all devices** (responsive). Emulator/laptop web remain valid for rehearsal.
2. **Africa's Talking:** **DECIDED** — SMS path is **LIVE** (not MOCK-only for demo). Configure real AT SMS via env credentials; keep mock fallback for local tests without keys. Mobile never calls AT directly (backend-mediated).
3. **YAMNet weights:** **DECIDED** — **NOT simulated** as the primary on-device demo path. Vendor/use real `yamnet.tflite` (public model OK). Honest clinical disclaimers still apply (generic AudioSet events ≠ obstetric diagnosis). Stub remains fallback only when the asset is missing.
4. **Narrative geography:** Safe default — **Tamale South CHPS → Tamale Teaching Hospital** (matches seed / `data/demo_data.json`).
5. **Language priority:** Safe default — English CHO UI + Dagbani brand gloss on home; no live TTS.
6. **Patient display names in DB:** Safe default adopted — token-only transport/storage; ephemeral display name in widget memory only.
7. **Arrival confirmation:** Adopted as required for the pitch story.
8. **USSD path alias:** Safe default — document `/ussd/callback` as canonical; do not add an alias.
9. **Hackathon success bar:** **DECIDED** — Working E2E on stage **and** written architecture narrative for judges (`docs/architecture-narrative.md`).
10. **Renaming RelayCare/RelayDispatch:** **DECIDED** — Keep product name **Yoma Triage** everywhere; use “CHO app” / “Dispatch gateway” (or Yoma Care / Yoma Dispatch) for components; eliminate Relay* user-facing leftovers.

---

## 12. Suggested Implementation Order (calendar)

| Phase | Duration (indicative) | Deliverable |
|-------|----------------------|-------------|
| Day 1 | W0 + W1 privacy + B0 | Green baseline; grep-clean brand; token-only privacy; browser/API reachability |
| Day 1–2 | W2 screening honesty | Disclaimer + README |
| Day 2 | W3 arrival + timeline | Complete demo story |
| Day 2–3 | W4 Flutter polish | Theme, offline rebound, labels |
| Day 3 | W5 | Regression + dry-run pitch |

---

## 13. Plan Self-Review

| Check | Result |
|-------|--------|
| Spec coverage (demo MVP) | Tasks map to privacy, screening honesty, E2E arrival, Flutter polish, brand |
| PRODUCT_SPEC full Phase 1 | Explicitly deferred in §4.2 — not pretended |
| Placeholders | None intentional; open questions isolated in §11 |
| Codebase specificity | Real modules cited throughout |
| Test-first | Every implementation task requires a failing test or explicit pre-existing failure before minimal change |
| Constraints | Global Constraints + §10 |

---

## 14. Reviewing Agent Checklist

- [ ] Plan does **not** require trained clinical audio model or Dagbani recordings to succeed
- [ ] Privacy: hospital SMS name leak addressed with concrete file + test
- [ ] Mobile hash scheme upgraded to SHA-256 with test
- [ ] Demo vs backlog cut is explicit and ruthless
- [ ] Audio strategy is honest (source + disclaimer)
- [ ] E2E includes arrival or consciously deferred via open question
- [ ] Flutter tasks reference actual `mobile/lib/...` files
- [ ] Backend tasks reference actual `src/...` files
- [ ] No instruction to call Africa’s Talking from Flutter
- [ ] MoMo remains mock; idempotency preserved
- [ ] Rebrand inventory is file-complete for Relay* strings
- [ ] Assumptions §0 and Open Questions §11 are visible
- [ ] **No implementation started from this planning pass**

---

*Plan authored for Yoma Triage / UNICEF StartUp Lab hackathon preparation. PO decisions locked 2026-07-26 — implementation in progress.*
