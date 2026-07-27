# Demo Day Runbook (Yoma Triage)

Quick path for judge rehearsal. Details for AT: `docs/plans/at-sandbox-runbook.md`.

## Prerequisites

1. Postgres on `127.0.0.1:5433` (`DATABASE_URL` in `.env`).
2. `.env` has `AT_API_KEY`, `AT_USERNAME=sandbox`, `AT_SENDER_ID=99193`, `AT_USSD_SERVICE_CODE=*384*99193#`.
3. API: `./venv/bin/python main.py` (port 8000).
4. Public tunnel for live phone USSD/SMS callbacks — set **only** in `.env` (never hardcode in source):

   ```bash
   # After: ngrok http 8000
   PUBLIC_BASE_URL=https://YOUR-CURRENT-TUNNEL.ngrok-free.app
   ```

   Then register in Africa’s Talking (copy from `GET /`):
   - SMS: `{PUBLIC_BASE_URL}/api/v1/sms/inbound`
   - USSD: `{PUBLIC_BASE_URL}/ussd/callback`

   Confirm locally:

   ```bash
   curl -sS http://127.0.0.1:8000/ | python3 -m json.tool
   # webhooks.ussd_callback / webhooks.sms_inbound should match AT dashboard
   ```

   When the ngrok URL changes, update `PUBLIC_BASE_URL` and re-register AT callbacks — no code change.

## Flutter web (CORS)

Always pin the web port so it matches `CORS_ORIGINS`:

```bash
cd mobile
flutter run -d chrome --web-port=8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

If the browser Origin differs (random port), add it to `CORS_ORIGINS` in `.env` and reload the API. Verify:

```bash
./venv/bin/python scripts/cors_smoke.py
```

`PUBLIC_BASE_URL` (ngrok) is auto-appended to the CORS allowlist for device demos that call the API through the tunnel — it is **not** a Flutter web Origin unless you host the web build there.


```bash
cd /var/www/html/unicef
./venv/bin/python scripts/demo_flow.py
# optional: DEMO_API_BASE_URL=http://127.0.0.1:8000
```

Expects: referral → USSD accept → hospital SMS (`SENT`) → CONFIRM → arrival `COMPLETED`, then decline → divert.

Uses **live seed phones** (resolves Ibrahim/Musah/Abdul from `GET /api/v1/compound/1/drivers`).

## Manual phone path (judge room)

1. Flutter referral (or POST `/api/v1/referral`) for compound 1 → facility 1.
2. Driver dials `*384*99193#` → `1` Accept.
3. Facility receives hospital SMS with **Driver phone** line; reply `CONFIRM <id>` or `confirmed`.
4. Driver dials again → `3` Arrival → status `COMPLETED`.

## If AT is down

Unset `AT_API_KEY` / leave empty → mock SMS; demo_flow still works; say “telecom mocked for offline demo”.

## Pitch honesty

- MOEWS is the risk spine; YAMNet is advisory AudioSet only — not obstetric diagnosis.
- MoMo fuel stipend is mocked unless live MoMo keys are set.
