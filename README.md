# RelayAI Emergency Logistics Engine

Backend-only MVP for the maternal emergency referral flow: CHPS referral, driver SMS/USSD cascade, mock MoMo fuel stipend, and hospital confirmation or diversion.

The implementation follows the [backend MVP design](docs/superpowers/specs/2026-07-24-relayai-backend-mvp-design.md). Flutter is out of scope for this MVP.

## Quick start

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

Create `.env` with a reachable async SQLAlchemy Postgres URL. The local seeded database is expected on port `5433`:

```dotenv
DATABASE_URL=postgresql+asyncpg://postgres:postgres@127.0.0.1:5433/relayai
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

## Tests

```bash
./venv/bin/python -m pytest -q
```
