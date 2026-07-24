# RelayAI Flutter CHO App + YAMNet — Design Spec

| Field | Value |
|-------|-------|
| **Date** | 2026-07-24 |
| **Status** | Draft for user review |
| **Approach** | Thin CHO client (Approach 1) |
| **Depends on** | Backend MVP on `main` (`docs/superpowers/specs/2026-07-24-relayai-backend-mvp-design.md`) |
| **Supersedes (scope)** | Flutter Chunk 6 from `docs/superpowers/plans/2026-07-23-relayai-hackathon-mvp.md`, narrowed |

---

## 1. Goal

Build a CHO-facing Flutter app that:

1. Screens breathing with **on-device YAMNet on Android**, or a **web/desktop demo simulator**
2. Lets the CHO confirm an emergency referral (AI advisory only)
3. Supports **manual Emergency Referral** that skips AI entirely (clinical bypass)
4. Queues referrals offline in SQLite and syncs when the API is reachable
5. Polls existing backend dispatch status for the judge-facing end-to-end story

Demo targets: **Android (emulator/device) + Flutter web/desktop fallback**.

---

## 2. Non-Goals

- OTP / CHO authentication
- SQLCipher / certificate pinning (Phase 2 hardening)
- Phone-originated Africa’s Talking or SMS codec dispatch
- Dagbani TTS, real MoMo, hospital dashboard
- On-device SLM / Whisper
- Full 60-second mandatory recording for the hackathon pitch (see §5)

---

## 3. Architecture

```
┌─────────────────────────────────────┐
│  Flutter (Android + Web)            │
│  Home → Screen → Result → Refer     │
│  ┌──────────┐  ┌─────────────────┐  │
│  │ YAMNet   │  │ Web simulator   │  │
│  │ TFLite   │  │ Normal/Code Red │  │
│  │ (Android)│  │                 │  │
│  └────┬─────┘  └────────┬────────┘  │
│       └────────┬────────┘           │
│                ▼                    │
│         Result GREEN/RED            │
│                ▼                    │
│     Vitals form + Confirm           │
│                ▼                    │
│     OfflineQueue (sqflite) ──┐      │
└──────────────────────────────┼──────┘
                               │ HTTPS when online
                               ▼
                    FastAPI backend (existing)
                    POST /api/v1/referral  (+ client_request_id)
                    GET  /api/v1/dispatch/{id}
```

### Boundaries

| Unit | Must | Must not |
|------|------|----------|
| Flutter UI | CHO confirm before any referral | Auto-dispatch without confirm |
| YAMNet (Android) | On-device classify; delete audio after | Upload raw audio; run on web |
| Web simulator | Drive same Result → Refer path | Pretend TFLite is running |
| OfflineQueue | Never silent-drop; retry safely | Call Africa’s Talking |
| Backend | Own SMS/USSD/MoMo; honor `client_request_id` | Depend on Flutter for cascade |

---

## 4. Screens (UX)

Low-literacy: large tap targets, GREEN/RED, short English copy for hackathon.

1. **Home**
   - **Screen Breathing** — AI-assisted path
   - **Emergency Referral** — clinical bypass (no  recording). Required for safety when the CHO already knows the patient is critical.
2. **Screening**
   - Android: record + countdown; **default window 15 seconds** (hackathon); **Stop & Analyze Early** always available
   - Web/desktop: **Demo: Normal** / **Demo: Code Red** only (no mic/TFLite)
3. **Result** — GREEN / RED / Inconclusive + one-line reason; **Confirm Referral** or continue monitoring
4. **Referral form** — vitals (SBP, DBP, HR, RR, Temp, SpO2, AVPU), emergency type, patient name; prefill AI fields if screened
5. **Dispatch status** — poll dispatch; show queued/syncing/accepted/hospital notified

**Demo facility picker:** default Tamale South CHPS → Tamale Teaching Hospital (IDs aligned with `data/demo_data.json`).

---

## 5. Edge ML (YAMNet)

### Android
- `tflite_flutter` + asset `assets/models/yamnet.tflite`
- 16 kHz mono PCM
- Hackathon recording: **15s default**, early stop allowed; product/production may restore 60s later
- Thresholds: confidence **> 0.7** → Code Red candidates; **< 0.5** → Inconclusive (clinical judgment); else GREEN if no abnormal class
- Audio never uploaded; discarded after inference

### Web / desktop
- No TFLite / WASM fight in this slice
- Simulator sets the same `ai_screen_result` / confidence shape the Result screen expects

---

## 6. Offline queue & idempotency

- On Confirm: if offline → SQLite outbox `pending`; UI: “Queued — will send when online”
- `connectivity_plus` → flush pending posts
- Each attempt carries **`client_request_id`** (UUID generated at first Confirm)
- Backend companion change (microscopic): accept optional `client_request_id` on `POST /api/v1/referral`; if a referral with that id already exists, return the existing referral/dispatch (**no second cascade**)
- On 4xx/5xx: keep draft/outbox; never mark sent; never silent-drop
- After successful sync: mark outbox `sent`; navigate/poll dispatch status

---

## 7. API contract

| Endpoint | Use |
|----------|-----|
| `POST /api/v1/referral` | Create referral; body includes vitals, compound/facility ids, optional AI fields, **`client_request_id`** |
| `GET /api/v1/referral/{id}` | Status |
| `GET /api/v1/dispatch/{id}` | Dispatch status for UI |
| `GET /api/v1/dispatch/{id}/logs` | Optional richer status |

**Base URL config:**
- Android emulator → host machine: `http://10.0.2.2:8000`
- Flutter web / desktop: `http://127.0.0.1:8000`
- Physical device: LAN IP of the backend host (documented in README)

---

## 8. Error / degradation matrix

| Failure | Behavior |
|---------|----------|
| Mic permission denied | Prompt; offer Emergency Referral bypass |
| YAMNet load/infer fail | “Screening unavailable — use clinical judgment” + manual referral |
| API unreachable | Queue; show Pending sync |
| Sync / handshake drop | Retry with same `client_request_id` |
| Backend 4xx/5xx | Keep queued/draft; show plain error |
| Web platform | Simulator only |

---

## 9. Testing & demo success

- Unit: outbox enqueue/flush; threshold mapping; `client_request_id` reuse
- Widget: home → simulator RED → confirm smoke (web path)
- Manual: Android 15s / early-stop screen → confirm → backend → USSD accept via existing `demo_flow` or status poll
- **Success:** Judge sees Screen → RED → Confirm → dispatch status without curl; web works without a phone; airplane-mode queue then sync works once

---

## 10. Backend companion work (in this feature’s plan)

1. Add optional `client_request_id` (unique) on referral create; idempotent return
2. Persist optional `ai_screen_result` / `ai_confidence` if not already stored for status UI
3. No cascade/orchestrator redesign

---

## 11. Success criteria checklist

- [ ] Android YAMNet path (or clearly documented stub model if Hub download blocked)
- [ ] Web simulator path
- [ ] Clinical bypass (Emergency Referral)
- [ ] 15s + Stop & Analyze Early
- [ ] Offline outbox + never silent-drop
- [ ] Idempotent sync via `client_request_id`
- [ ] Dispatch status after confirm against live backend
