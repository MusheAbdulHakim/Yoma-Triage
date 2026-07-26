# Yoma Triage — Architecture Narrative (Hackathon Demo)

This document explains the end-to-end flow for judges evaluating the Yoma Triage MVP: an offline-first emergency maternal referral and transport broker for Northern Ghana.

## Problem

Community Health Planning and Services (CHPS) compounds face obstetric emergencies with unreliable connectivity. Midwives need to screen risk, confirm referrals, dispatch Motor-King drivers, and alert district hospitals — often over 2G SMS and USSD, not broadband.

## High-level flow

```mermaid
sequenceDiagram
    participant CHO as CHPS Midwife (Flutter)
    participant App as Yoma Triage Mobile
    participant API as FastAPI Backend
    participant AT as Africa's Talking
    participant Driver as Motor-King Driver
    participant Hospital as District Hospital

    CHO->>App: Voice screening + vitals entry
    App->>App: YAMNet advisory (on-device TFLite; web uses demo simulator)
    CHO->>App: Confirm referral
    App->>API: POST /api/v1/referral (SHA-256 patient token)
    API->>API: MOEWS scoring (LangGraph clinical path)
    API->>AT: Tier-1 driver SMS cascade
    Driver->>API: USSD *123# → Accept (1)
    API->>API: Mock MoMo fuel stipend (30%)
    API->>AT: Hospital pre-arrival SMS (patient token only)
    Hospital->>API: SMS CONFIRM {dispatch_id}
    Driver->>API: USSD → Confirm arrival (3)
    API->>AT: CHO arrival notification
    API->>App: Dispatch status COMPLETED
```

## Components

### 1. CHPS screening (Flutter mobile)

- Midwife records vitals and optional cough audio.
- **YAMNet** (TensorFlow Lite) provides an **advisory** screen only — it does not override clinical judgment or MOEWS.
- Referrals queue offline when there is no connectivity; sync uses `client_request_id` for idempotency.

### 2. Clinical assessment (backend)

- LangGraph coordinator invokes deterministic MOEWS scoring aligned with Ghana Health Service referral guidelines.
- Output is structured JSON (risk level, score, compressed SMS payload) — not open-ended chat.
- If clinical assessment fails, referral still proceeds with `UNKNOWN` risk (spec §10).

### 3. Referral API

- Accepts a 64-character lowercase hex **patient token** (SHA-256 hash computed on device).
- Does not expose real patient names in API responses.
- Triggers dispatch cascade immediately after CHO confirmation.

### 4. Dispatch orchestrator

- **Tier 1**: Motor-King drivers at the compound (SMS + USSD accept/decline).
- **Tier 2**: Personal vehicles if tier 1 declines or times out.
- **Tier 3**: CHO manual coordination if no driver accepts.
- Concurrent accept uses database row locking — one winner only.

### 5. Driver USSD menu

```
Yoma Triage Emergency Referral
1. Accept
2. Decline
3. Confirm arrival
```

- Accept triggers mock **MoMo** fuel stipend logging (real MTN integration deferred; `MOMO_PRIMARY_KEY` empty = mock).
- Decline escalates to the next tier after USSD response returns (non-blocking).
- Arrival confirmation moves dispatch to `COMPLETED` and notifies the CHO.

### 6. Hospital SMS

- Pre-arrival alert includes compound, condition, severity, driver name, and **patient token prefix** — never the patient's name.
- Hospital replies `CONFIRM {dispatch_id}` or `DIVERT {dispatch_id} {facility_id}` via inbound SMS webhook.

### 7. Messaging gateway

- **Mock mode** (default): no AT credentials → SMS logged as `MOCKED`.
- **Live mode**: when `AT_API_KEY` and `AT_USERNAME` are set, outbound SMS uses Africa's Talking sandbox/production API.
- Mobile never holds AT keys; all carrier I/O is backend-mediated.

## Offline-first design

| Channel | Constraint | Approach |
|---------|------------|----------|
| SMS telemetry | ≤140 octets | Compressed Base64 vitals vector |
| Mobile sync | Intermittent 2G | Local outbox + idempotent API |
| USSD | 10s gateway timeout | DB commit first; side effects in background |
| Clinical AI | No unbounded LLM in dispatch | Deterministic MOEWS + structured JSON |

## Honest hackathon scope

| Feature | Demo status |
|---------|-------------|
| MOEWS clinical scoring | Implemented |
| YAMNet cough advisory | On-device; advisory only |
| Driver cascade + USSD | Implemented |
| MoMo fuel stipend | **Mocked** unless `MOMO_PRIMARY_KEY` set |
| Africa's Talking SMS | **Mocked** unless AT env vars set |
| Hospital confirm/divert SMS | Implemented (webhook + demo script) |
| Arrival USSD → COMPLETED | Implemented |
| 70% final MoMo payout | **Deferred** (not in hackathon scope) |
| RAG / GHS protocol lookup | Partial / demo data |

## Observability

- `GET /api/v1/dispatch/{id}/logs` — ordered audit trail: `sms_send`, `ussd_accept`, `momo_escrow`, `hospital_notify`, `hospital_confirm`, `arrival_confirm`.
- `scripts/demo_flow.py` — judge-visible local demo against a running API on port 8000.

## Security & privacy

- Patient identity on the wire is a one-way SHA-256 token.
- SMS payloads never contain raw names.
- Hospital commands validated against registered facility phone numbers.

## Running the demo

1. Seed data: `python -m src.db.seed`
2. Start API: `./venv/bin/python main.py`
3. Run flow: `./venv/bin/python scripts/demo_flow.py`
4. Optional live AT: see [at-sandbox-runbook.md](./plans/at-sandbox-runbook.md)
