# Africa's Talking Sandbox Runbook

This runbook covers sending **live SMS** through Africa's Talking (AT) from the Yoma Triage backend during hackathon demos. The Flutter mobile app must **never** call AT directly — all SMS/USSD traffic goes through FastAPI.

## Environment variables

| Variable | Purpose | Mock when empty? |
|----------|---------|------------------|
| `AT_API_KEY` | Africa's Talking API key | Yes — `MessagingGateway` returns `MOCKED` |
| `AT_USERNAME` | AT username (use `sandbox` for sandbox) | Required with key for live sends |
| `AT_SENDER_ID` | Sender ID shown on outbound SMS (default `YOMATRIAGE`) | Used only when live |
| `AT_USSD_SERVICE_CODE` | Registered USSD shortcode (e.g. `*384*99193#`) | Empty = accept any inbound `serviceCode`; when set, SMS offers include the code and callbacks must match |
| `AT_API_BASE_URL` | SMS API host override | Empty → `api.sandbox…` if username is `sandbox`, else `api.africastalking.com`. Bulk path: `/version1/messaging/bulk` |

When `AT_API_KEY` or `AT_USERNAME` is empty, the backend logs mock SMS and does not hit the network. This is the default for local development and CI.

## Enable live sandbox SMS

1. Copy `.env.example` to `.env` (never commit `.env`).
2. Set credentials from your [Africa's Talking sandbox dashboard](https://account.africastalking.com/):
   ```bash
   AT_API_KEY=your_sandbox_api_key
   AT_USERNAME=sandbox
   AT_SENDER_ID=YOMATRIAGE
   AT_USSD_SERVICE_CODE=*384*99193#
   ```
3. Start the API: `./venv/bin/python main.py`
4. Confirm mock is off: create a referral and check dispatch logs — `metadata.provider` should be `africas_talking`, not `mock`.

## USSD callback (driver accept / decline)

Follows [Africa’s Talking USSD session handling](https://developers.africastalking.com/docs/ussd/handle_sessions):

1. Register a service code and set the callback to `https://YOUR-HOST/ussd/callback`.
2. AT sends `POST` with `Content-Type: application/x-www-form-urlencoded`.
3. Your app must reply within **10 seconds** with a **plain string** starting with `CON` (keep session open) or `END` (close session). Use `Content-Type: text/plain` — never JSON.

### Fields AT posts

| Field | Meaning |
|-------|---------|
| `sessionId` | Unique session id for this dial |
| `serviceCode` | Short code the user dialed |
| `phoneNumber` | Driver MSISDN (often `+233…`) |
| `text` | `""` on first dial; then `1`, `2`, or accumulated `1*2` |

Yoma Triage also accepts snake_case aliases for local demos.

### Session flow in this app

| `text` | Response |
|--------|----------|
| `""` (first dial) | `CON` menu: Accept / Decline / Confirm arrival |
| `1` or `…*1` | Accept active dispatch → `END …` |
| `2` or `…*2` | Decline → `END …` (escalate in background) |
| `3` or `…*3` | Confirm arrival → `END …` |

Heavy work (MoMo mock, hospital SMS) runs in FastAPI `BackgroundTasks` so the USSD reply stays under the 10s budget.

### Smoke test

```bash
# First dial — menu
curl -X POST "https://YOUR-NGROK.ngrok-free.app/ussd/callback" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "sessionId=ATUid_test&serviceCode=%2A384%2A99193%23&phoneNumber=%2B233240000001&text="

# Accept
curl -X POST "https://YOUR-NGROK.ngrok-free.app/ussd/callback" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "sessionId=ATUid_test&serviceCode=%2A384%2A99193%23&phoneNumber=%2B233240000001&text=1"
```

Set `AT_USSD_SERVICE_CODE` in `.env` to the same shortcode registered in AT (sandbox or production). Change production codes there — do not hardcode them in Python.

## Outbound SMS

Africa’s Talking exposes **two** SMS send APIs; sandbox and live do not behave the same:

| Environment | Endpoint | Body | Notes |
|-------------|----------|------|-------|
| Sandbox (`AT_USERNAME=sandbox`) | `POST /version1/messaging` | form-urlencoded (`to`, `message`, `from`) | `/messaging/bulk` returns **404** today |
| Live production app | `POST /version1/messaging/bulk` | JSON (`phoneNumbers`, `senderId`, `enqueue: true`) | Needs **live** API key + app username (sandbox keys → 401 on live host) |

`MessagingGateway` picks sandbox form vs live bulk from `AT_API_BASE_URL` / username. Set `AT_SENDER_ID` to your registered shortcode (e.g. `99193`) — used as `from` (sandbox) or `senderId` (live).

## Privacy rules (non-negotiable)

- Hospital SMS uses `Patient token: {hash[:12]}` — never raw patient names.
- Referral API accepts only 64-character lowercase hex `patient_hash` tokens.
- Mobile computes SHA-256 client-side; backend stores `patient_name` as `"Unknown"`.

## Flutter / mobile

- Do **not** add AT SDK or direct HTTP calls to `api.africastalking.com` in `mobile/`.
- Mobile posts referrals to `POST /api/v1/referral` and polls dispatch status.
- CORS for Flutter web is configured via `CORS_ORIGINS` in `.env`.

## MoMo (separate from AT)

MTN MoMo uses `MOMO_PRIMARY_KEY`. When empty, fuel stipends are mocked in dispatch logs (`momo_escrow`). External IDs use the `YOMA-` prefix in production disbursement payloads.

## Quick verification checklist

- [ ] Empty AT vars → dispatch logs show `MOCKED` SMS
- [ ] AT vars set → outbound SMS reaches sandbox test numbers
- [ ] Hospital inbound webhook reachable via ngrok (if testing live replies)
- [ ] No patient names in hospital SMS body or API responses
- [ ] Flutter app uses backend API only (no AT keys in mobile)
