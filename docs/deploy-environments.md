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
--dart-define=MOEWS_ONLY=true          # default; false = enable acoustic path
--dart-define=SCREENING_DUAL_RUN=false # ops compare vs YAMNet
```

Mirror keys also live in repo-root `.env.example` for documentation.

## Release build (deploy runbook)

A release build fails closed. `mobile/android/app/build.gradle.kts` refuses to build one
unless all of these are given, and the app checks them again when it starts, showing a
"built wrongly" screen instead of running:

- `APP_ENV=production`
- `API_BASE_URL` starting `https://`, and not `localhost`, `127.0.0.1`, `0.0.0.0` or the
  emulator's `10.0.2.2`
- `API_KEY`, the same value the backend has

There are no defaults in a release: without `API_BASE_URL` it has no server at all.

```bash
cd mobile
~/flutter-3.44.8/bin/flutter build apk --release --split-per-abi \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.example.org \
  --dart-define=API_KEY="$API_KEY" \
  --dart-define=MOEWS_ONLY=true
~/flutter-3.44.8/bin/flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.example.org \
  --dart-define=API_KEY="$API_KEY" \
  --dart-define=MOEWS_ONLY=true
```

`--split-per-abi` gives one APK per CPU type, in `build/app/outputs/flutter-apk/`: install
`app-arm64-v8a-release.apk` on almost every current phone, and `app-armeabi-v7a-release.apk`
on older 32-bit ones. The app bundle (`build/app/outputs/bundle/release/app-release.aab`)
is for Google Play, which sends each phone only what it needs.

Without the settings, the build stops with, for example:

```
Refusing to build a release without production settings:
  - APP_ENV must be production (got '')
  - API_BASE_URL must be an https:// address (got '')
  - API_KEY must be set
```

**Test releases.** A release that talks to a test backend, such as the emulator pass's
`http://10.0.2.2:8000`, needs `--dart-define=YOMA_TEST_RELEASE=true`. It shows a red
"TEST BUILD — not for patient use" label on every screen, and can't be combined with
`APP_ENV=production`. Never give one to a CHO.

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
