# Yoma Triage Emergency Logistics Engine

Backend-only MVP for the maternal emergency referral flow: CHPS referral, driver SMS/USSD cascade, mock MoMo fuel stipend, and hospital confirmation or diversion.

The implementation follows the [backend MVP design](docs/superpowers/specs/2026-07-24-yoma-triage-backend-mvp-design.md). The CHO Flutter client lives in `mobile/` ([Flutter + YAMNet design](docs/superpowers/specs/2026-07-24-yoma-triage-flutter-yamnet-design.md)).

## Quick start

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

Create `.env` with a reachable async SQLAlchemy Postgres URL. The local seeded database is expected on port `5433`:

```dotenv
DATABASE_URL=postgresql+asyncpg://postgres:postgres@127.0.0.1:5433/yoma_triage
```

Seed the demo data, then start the API in one terminal:

```bash
./venv/bin/python -m src.db.seed
./venv/bin/python main.py
```

In a second terminal, run the end-to-end judge timeline:

```bash
./venv/bin/python scripts/demo_flow.py
```

The demo drives `http://127.0.0.1:8000`, creates critical referrals, simulates Ibrahim accepting and declining via USSD, verifies mock MoMo and hospital notification audit logs, then demonstrates hospital `CONFIRM` and `DIVERT` commands.

## Flutter CHO app

The CHO client lives in **`mobile/`**.

```bash
cd mobile
flutter pub get
# Web simulator:
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
# Android emulator:
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

YAMNet: place `yamnet.tflite` in `mobile/assets/models/`. If missing, the Android path uses the **stub classifier** automatically. Web uses Demo Normal / Demo Code Red only.

Offline outbox: SQLite on mobile, SharedPreferences on web; `connectivity_plus` flushes on reconnect with the same `client_request_id`.

## Tests

```bash
./venv/bin/python -m pytest -q
cd mobile && flutter test
```
