# RelayAI Backend Hackathon MVP — Design Spec

| Field | Value |
|-------|-------|
| **Date** | 2026-07-24 |
| **Status** | Approved for implementation planning |
| **Approach** | Thin vertical slice (Approach 2) |
| **Supersedes (scope)** | Narrows `docs/superpowers/plans/2026-07-23-relayai-hackathon-mvp.md` Chunks 1–5 + 7; Flutter Chunk 6 deferred |
| **Related** | `docs/relayai-product-spec.md` (product vision); existing FastAPI/LangGraph skeleton in `src/` |

---

## 1. Goal

Build a **backend-only** hackathon demo that proves end-to-end emergency referral coordination for Northern Ghana CHPS compounds:

1. **Happy path:** Create referral → MOEWS + RAG clinical assessment → cascade SMS to driver → USSD accept → mock MoMo escrow logged → hospital pre-arrival SMS
2. **Failure path:** Driver declines (or times out) → escalate to next driver/tier
3. **Hospital path:** Pre-arrival notification; inbound SMS `CONFIRM` or `DIVERT`

Demo is driven by `scripts/demo_flow.py` and/or `curl` + simulated USSD/SMS webhooks. **No Flutter app in this slice.**

---

## 2. Non-Goals (Follow-on Plan)

- Flutter mobile app, YAMNet/HeAR acoustic screening, on-device offline SQLite queue
- Personal `emergency_contact` tier (patient/family network) — Phase 2; MVP tier-3 = CHO give-up only
- Real MTN MoMo disbursement (hackathon uses mock only)
- Dagbani TTS / provisioned production USSD shortcode
- Hospital web dashboard, DHIS2/LHIMS, NHIS/LEAP integrations
- On-device SLM (Phi-3 / Gemma)
- Alembic/migration tooling (use `create_all` for hackathon)

Offline-first remains a **product principle**: this backend is the online coordination layer. Edge offline queue arrives with the Flutter plan. PostgreSQL/Supabase does **not** conflict with offline-first.

---

## 3. Architecture

```
Demo client (curl / scripts/demo_flow.py)
        │ HTTPS JSON
        ▼
┌─────────────────────────────────────────┐
│ FastAPI (main.py)                       │
│  POST /api/v1/referral                  │
│  GET  /api/v1/referral/{id}             │
│  GET  /api/v1/dispatch/{id}             │
│  POST /ussd/callback                    │
│  POST /api/v1/sms/inbound               │
└────────────┬────────────────────────────┘
             │
     ┌───────┴────────┐
     ▼                ▼
 Clinical path     Dispatch path
 (LangGraph)       (deterministic)
 MOEWS + RAG       Orchestrator +
 [Gemini optional] DriverPool +
                   MessagingGateway
             │
             ▼
     PostgreSQL (Supabase)
     MessagingGateway → AT sandbox OR console/DB mock
     MoMo escrow → always mock in hackathon
```

### Boundaries

| Unit | Responsibility | Must not |
|------|----------------|----------|
| **Clinical LangGraph** | MOEWS score, RAG citations, optional Gemini summary, SMS codec payload | Auto-refer without API call; call Africa's Talking; hold USSD request |
| **DispatchOrchestrator** | Cascade tiers, timeouts, escalate, status machine | Use an LLM; wait on USSD HTTP |
| **MessagingGateway** | Send SMS/Voice via AT sandbox or mock; persist attempts to `dispatch_log` | Block USSD callback on network I/O |
| **USSD handler** | Parse input, claim dispatch under lock, return `CON`/`END` fast | Run LangGraph, call MoMo HTTP, await AT SMS |
| **MoMo tool** | Return mock transaction; log to `dispatch_log` | Double-pay on idempotent retries |

**CHO confirmation:** For this MVP, `POST /api/v1/referral` *is* the CHO confirm action (no separate confirm step).

---

## 4. Data Model (Supabase PostgreSQL)

### Tables (MVP)

| Table | Purpose |
|-------|---------|
| `chps_compound` | Facility origin (name, zone, lat/lon, cho_phone) |
| `driver` | Pool member (phone, vehicle, compound_id, is_motor_king, availability) |
| `facility` | Receiving hospital (name, phone, district, capabilities) |
| `referral` | Clinical + patient hash, emergency type, severity, moews, status |
| `dispatch` | One active transport job per referral (status, driver_id, tier, timestamps) |
| `dispatch_log` | Append-only audit: SMS/Voice/USSD, MoMo mock IDs, hospital replies |
| `wallet` | Mock escrow row linked to referral/dispatch |
| `audit_log` | Optional generic entity actions |

**Personal emergency contacts:** The product spec’s `emergency_contact` table and patient-network tier are **Phase 2**. For this hackathon MVP, cascade tier-3 is **give-up / notify CHO only**. Tier-2 covers seeded fallback/volunteer drivers. Do not add `emergency_contact` in this slice.

### Dispatch status machine

```
PENDING
  → TIER1_NOTIFIED
       ├─ ACCEPTED (claimable while status ∈ {TIER*_NOTIFIED})
       ├─ driver DECLINED recorded → escalate only if still not ACCEPTED
       │     → TIER2_NOTIFIED → (same accept/decline rules)
       └─ tier timeout → escalate if still not ACCEPTED
  → ACCEPTED
  → HOSPITAL_NOTIFIED
  → COMPLETED | DIVERTED | FAILED
```

Store `current_tier` (int) + `status` enum. Per-driver outcomes live in `dispatch_log` (and optionally a `declined_driver_ids` list on `dispatch`) so a late decline from Driver A cannot undo an accept by Driver B.

### `dispatch_log` (judge-facing audit)

Every side-effect row includes at least: `dispatch_id`, `action`, `target_phone`, `target_role`, `response` / `metadata` (JSON), `created_at`.

Mock MoMo on first successful accept: `action=momo_escrow`, metadata `{transaction_id, amount_ghs, stage: "INITIAL_30PCT"}`, tied to the same `dispatch_id` as the medical job.

---

## 5. Cascade Dispatch

Deterministic orchestrator with **accelerated demo timers** (configurable; default ~5–10 seconds per tier, not production 90s).

| Tier | Targets | Channel sequence |
|------|---------|------------------|
| 1 | Motor-King drivers for compound | SMS then (optional) Voice |
| 2 | Fallback / volunteer drivers only | SMS then Voice |
| 3 | Give-up (no personal contacts in MVP) | Notify CHO phone; `status=FAILED` |

**Accept:** under `SELECT … FOR UPDATE`, if status is still claimable (`TIER*_NOTIFIED`) → set `ACCEPTED` + `driver_id` → enqueue mock MoMo log (once) + hospital pre-arrival SMS + CHO notify → return USSD `END` immediately.

**Decline:** under the same lock:
1. Append `dispatch_log` with `action=ussd_decline` for that driver (mark driver declined for this dispatch).
2. Escalate **only if** status is still `TIER*_NOTIFIED` (not already `ACCEPTED`).
3. Transition: record decline → notify next driver → `TIER{n+1}_NOTIFIED` (or `FAILED` at give-up).

**Late decline race:** If Driver A’s decline arrives after Driver B already accepted, ignore escalation; log decline as informational; leave `ACCEPTED` intact.

**Tier timeout:** same guard — escalate only if not yet `ACCEPTED`.

**Hospital inbound:** `CONFIRM` or `DIVERT <alt facility>`; on divert, SMS driver + CHO and set `DIVERTED`.

---

## 6. MessagingGateway

```
if AT_API_KEY and AT_USERNAME configured:
    send via Africa's Talking sandbox
else:
    mock: log to console + insert dispatch_log; return success envelope
```

Voice follows the same sandbox-or-mock rule. USSD is **inbound webhook only** (no outbound USSD API required for MVP).

---

## 7. API Surface

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/referral` | POST | Create referral, run clinical graph, start cascade |
| `/api/v1/referral/{id}` | GET | Referral status for demo polling |
| `/api/v1/dispatch/{id}` | GET | Dispatch + recent logs |
| `/ussd/callback` | POST | Driver accept/decline (Africa's Talking / form-compatible) |
| `/api/v1/sms/inbound` | POST | Hospital CONFIRM / DIVERT |
| `/` | GET | Health check (existing) |

Optional keep: `POST /test-referral` for graph-only smoke tests without persistence.

---

## 8. Clinical Path (LangGraph)

1. **`clinical_assessment`**
   - Deterministic MOEWS aligned to product spec: Green 0–2, Yellow 3–4 (or any single parameter score = 1), Red ≥5 (or any single parameter score = 3). Include SBP, DBP, HR, RR, temp, SpO2, AVPU as available.
   - **Null-vitals guard:** If any required vital is `None`/missing, **do not** call the scorer; set `moews_score=null`, `risk_level=UNKNOWN`, log a validation note, and continue the referral. The calculator is deterministic and should not crash on valid ints/floats; treat bad input as UNKNOWN, not a 500.
   - Chroma RAG citations from GHS protocols.
   - Gemini summary **optional**: if `GEMINI_API_KEY` missing or call fails, use a template one-liner from MOEWS + citations. Never fail the referral solely because the LLM failed.
2. **`prepare_dispatch`**
   - Compress telemetry via existing `sms_codec`; attach to state / referral record.
   - Hand off to `DispatchOrchestrator` (outside graph).

Reuse/fix: `src/tools/moews_calculator.py`, `src/agents/clinical_agent.py`, `src/agents/coordinator.py`, `src/rag/engine.py`.

---

## 9. Engineering Constraints (Hard Requirements)

### 9.1 USSD timeout (~10 seconds)

Telco gateways drop slow USSD sessions. `/ussd/callback` must:

- Parse form fields → short DB transaction with `SELECT … FOR UPDATE` → update status → **enqueue** MoMo log / hospital notify (background task or after-response) → return `CON`/`END` immediately.
- **Must not** invoke LangGraph, await Africa's Talking HTTP, or hold long locks.

### 9.2 Idempotent callbacks

Low-bandwidth retries may POST the same accept twice, possibly with a **new** `session_id`. Idempotency key is **`(dispatch_id, driver_id)`**, not session:

- Resolve driver by `phone_number`; resolve active dispatch for that driver’s compound / open job.
- If `dispatch.status == ACCEPTED` and `dispatch.driver_id` is this driver → return the **identical** success `END` body; do not re-log MoMo or re-SMS hospital.
- If `dispatch.status == ACCEPTED` and `driver_id` is a **different** driver → return `END Already assigned.`
- Do not create a second MoMo `dispatch_log` or second hospital SMS on retry.

### 9.3 Concurrency (cascade claim)

When assigning a driver on accept:

- `SELECT … FOR UPDATE` on the `dispatch` (or owning `referral`) row inside a transaction.
- Only one concurrent accept wins; loser receives `END Already assigned.` (or equivalent).
- Winner = first committed accept while status is still claimable (`TIER*_NOTIFIED`).
- Decline-then-escalate must re-check status under the same lock before moving to `TIER2_NOTIFIED` (see §5).

### 9.4 Mock MoMo escrow

- Always mock in hackathon (`ENVIRONMENT=development` or missing MoMo keys).
- On **first** successful accept only, write `dispatch_log` with mock `transaction_id` linked to `dispatch_id` for judge-visible audit in `demo_flow.py`.

### 9.5 Database init

No Alembic/migrations for the hackathon. On FastAPI startup:

```python
async with engine.begin() as conn:
    await conn.run_sync(Base.metadata.create_all)
```

Seed demo rows via `python -m src.db.seed` (or `demo_flow.py` invoking the seeder).

---

## 10. Error Handling & Degradation

| Failure | Behavior |
|---------|----------|
| Missing/null vitals | Skip MOEWS; `risk_level=UNKNOWN`; referral still created |
| MOEWS/RAG unexpected error | Create referral with best-effort / `UNKNOWN` risk; log error; dispatch may still start |
| No AT keys | MessagingGateway mocks; cascade and USSD simulation still work |
| AT sandbox error (rate limit, timeout, invalid number) | Log error; mark that `dispatch_log` send as `FAILED`; **continue cascade** (next tier/driver may succeed) |
| No drivers / full timeout | `dispatch.status=FAILED`; notify CHO (mock/SMS) to coordinate manually |
| Duplicate USSD accept | Idempotent identical `END` via `(dispatch_id, driver_id)` |
| Concurrent accept | One wins via `FOR UPDATE` |
| Late decline after accept | Log decline; do not escalate; keep `ACCEPTED` |
| Hospital DIVERT | Update destination; notify driver + CHO; log |
| MoMo mock | Always succeeds; never blocks accept response path |

---

## 11. Testing & Demo

### Unit

- MOEWS thresholds vs product spec
- SMS codec compress/decompress round-trip
- USSD idempotency (double accept)
- Concurrent claim (second accept loses)

### Integration / demo script

`scripts/demo_flow.py`:

1. Seed (or assume seeded) compounds, drivers, hospitals
2. Happy path: referral → USSD accept → assert MoMo log + hospital notify log
3. Decline path: USSD decline → assert escalation to next driver
4. Hospital path: inbound CONFIRM and/or DIVERT

Print a **sequential, judge-visible timeline** (timestamps relative to start), for example:

```
[00:00] Referral created: #REF-001
[00:01] MOEWS: 6 (RED) — Critical: BP 70/50, HR 140, RR 35
[00:02] Cascade: SMS → Driver Ibrahim (+233240000001)
[00:07] Ibrahim: ACCEPTED via USSD
[00:08] Mock MoMo: GHS 22.50 fuel stipend logged (tx=…)
[00:09] Hospital SMS: Tamale Teaching Hospital notified
[00:10] Status: HOSPITAL_NOTIFIED ✓
```

Decline-path demo should show an analogous timeline with `DECLINED` → next driver SMS → accept.

### Manual

- `curl` POST referral
- Form POST to `/ussd/callback` mimicking gateway fields (`application/x-www-form-urlencoded`; requires `python-multipart`)

---

## 12. Config & Dependencies

`.env.example` includes:

- `DATABASE_URL` (Supabase Postgres; async SQLAlchemy URL, e.g. `postgresql+asyncpg://…`)
- `AT_API_KEY`, `AT_USERNAME`, `AT_SENDER_ID` (optional → mock)
- `GEMINI_API_KEY` (optional)
- `MOMO_*` (unused for live pay in MVP; mock always)
- `ENVIRONMENT`, `LOG_LEVEL`
- `CASCADE_TIER_SECONDS` (demo default 5–10)

**Required dependency additions** (beyond current `requirements.txt`):

- `python-multipart>=0.0.9` — FastAPI form parsing for `/ussd/callback`
- `sqlalchemy[asyncio]`, `asyncpg` — async Postgres access
- `httpx` or keep `requests` for AT HTTP (implementation plan picks one)

Database tables: created via §9.5 `create_all` on startup (no Alembic).

---

## 13. Relationship to Existing Plan Doc

`docs/superpowers/plans/2026-07-23-relayai-hackathon-mvp.md` remains historical reference. The **implementation plan** produced after this design will:

- Cover backend Chunks equivalent to 1–5 + 7 only
- Incorporate accelerated cascade, MessagingGateway, and §9 constraints
- Explicitly exclude Flutter Chunk 6 (separate future plan)
- Prefer executable steps over placeholders

---

## 14. Success Criteria

- [ ] End-to-end happy path runnable via `demo_flow.py` against local FastAPI + Supabase
- [ ] Decline → escalate visible in `dispatch_log`
- [ ] Hospital pre-arrival + CONFIRM/DIVERT logged (mock or AT sandbox)
- [ ] Mock MoMo `transaction_id` on `dispatch_log` for accepted dispatch
- [ ] USSD handler returns within timeout budget; idempotent; safe under concurrent accept
- [ ] Judges can understand problem → triage → dispatch → money audit → hospital notify without a Flutter UI
