# Deploy environments (D1)

| Env | `APP_ENV` | Acoustic default | Notes |
|-----|-----------|------------------|-------|
| Local / demo | `development` | `SCREENING_MODEL=yamnet` | Home shows env + model chip |
| Staging | `staging` | `yamnet` or dual-run packs | Point `API_BASE_URL` at staging FastAPI; sync catalog on connect |
| Production pilot | `production` | `yamnet` until HeAR/OPERA cleared | Hide env chip; prefer `MOEWS_ONLY=true` if acoustic pack fails field QA |

## Flutter dart-defines

```bash
--dart-define=APP_ENV=staging
--dart-define=API_BASE_URL=https://api.example.org
--dart-define=SCREENING_DURATION_SEC=15
--dart-define=SCREENING_MODEL=yamnet   # yamnet | hear_event | opera_ce | stub
--dart-define=MOEWS_ONLY=false         # true = kill acoustic path
--dart-define=SCREENING_DUAL_RUN=false # ops compare vs YAMNet
```

Mirror keys also live in repo-root `.env.example` for documentation.

## Auth (OTP deferred)

| Secret | Header / query | When required |
|--------|----------------|---------------|
| `API_KEY` | `X-API-Key` | Always when set; **required** in `staging`/`production` |
| `AT_WEBHOOK_SECRET` | `?secret=` or `X-Webhook-Secret` | Same for `/ussd/callback` and `/api/v1/sms/inbound` |

Flutter: `--dart-define=API_KEY=$API_KEY`. CHO phone OTP login remains deferred.

## Model card

See [`docs/model-cards/yamnet-v0.md`](model-cards/yamnet-v0.md).

## Deferred

- CHO OTP login (explicitly deferred)
- HeAR redistribution until HAI-DEF ToS cleared ([`docs/legal/hai-def-hear-tos-review.md`](legal/hai-def-hear-tos-review.md))
