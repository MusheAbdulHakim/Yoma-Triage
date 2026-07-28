# Driver assignment policy (offline-first)

## Normative rules

1. **No usable IP data path** (airplane mode, MTN “No service”, tower outage, DNS/route failure, captive portal) ⇒ the CHO app **must not** claim a driver is assigned, en route, or notified.
2. Offline success state is **queued clinical intent**: destination facility chosen locally, referral in SQLite outbox with stable `client_request_id`.
3. **Driver SMS/USSD cascade runs only on the backend** after a successful `POST /api/v1/referral` (or outbox flush). Africa’s Talking stays server-mediated.
4. Cascade remains **compound-scoped** (Motor-King → personal → CHO escalate) as implemented in `src/services/dispatch_orchestrator.py` / `driver_pool.py`.
5. **Optional later:** rank notify order by driver base / compound distance to patient origin once driver coords exist — still not live GPS tracking.

## UX contract

| Screen | When | Driver name shown? |
|--------|------|--------------------|
| `QueuedReferralScreen` | `dispatchId == null` | **Never** |
| `DispatchStatusScreen` | After sync returns `dispatch_id` | Only after cascade assigns |

Honesty copy (queued): referral saved on device; drivers have **not** been notified yet; they are contacted when the phone has coverage.

## Non-goals

- On-device Africa’s Talking SMS
- Pretend ETA / “en route” while offline
- Live driver GPS chase in v1
