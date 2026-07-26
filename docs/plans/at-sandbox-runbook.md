# Africa's Talking Sandbox Runbook

This runbook covers sending **live SMS** through Africa's Talking (AT) from the Yoma Triage backend during hackathon demos. The Flutter mobile app must **never** call AT directly — all SMS/USSD traffic goes through FastAPI.

## Environment variables

| Variable | Purpose | Mock when empty? |
|----------|---------|------------------|
| `AT_API_KEY` | Africa's Talking API key | Yes — `MessagingGateway` returns `MOCKED` |
| `AT_USERNAME` | AT username (use `sandbox` for sandbox) | Required with key for live sends |
| `AT_SENDER_ID` | Sender ID shown on outbound SMS (default `YOMATRIAGE`) | Used only when live |

When `AT_API_KEY` or `AT_USERNAME` is empty, the backend logs mock SMS and does not hit the network. This is the default for local development and CI.

## Enable live sandbox SMS

1. Copy `.env.example` to `.env` (never commit `.env`).
2. Set credentials from your [Africa's Talking sandbox dashboard](https://account.africastalking.com/):
   ```bash
   AT_API_KEY=your_sandbox_api_key
   AT_USERNAME=sandbox
   AT_SENDER_ID=YOMATRIAGE
   ```
3. Start the API: `./venv/bin/python main.py`
4. Confirm mock is off: create a referral and check dispatch logs — `metadata.provider` should be `africas_talking`, not `mock`.

## Webhook setup (inbound hospital SMS)

Hospital `CONFIRM` / `DIVERT` replies hit `POST /api/v1/sms/inbound`.

For local demos, expose the API with ngrok:

```bash
ngrok http 8000
```

Register the ngrok HTTPS URL + path in AT (or simulate with curl):

```bash
curl -X POST "https://YOUR-NGROK.ngrok-free.app/api/v1/sms/inbound" \
  -H "Content-Type: application/json" \
  -d '{"from": "+233240000200", "text": "CONFIRM 1"}'
```

Use the seeded hospital phone (`+233240000200`) as `from` — unauthorized senders are rejected.

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
