# Yoma Triage Emergency Logistics Engine


Backend-only MVP for the maternal emergency referral flow: CHPS referral, driver SMS/USSD cascade, mock MoMo fuel stipend, and hospital confirmation or diversion.


## Executive Summary
Most maternal deaths in the region don't happen because treatment doesn't exist. They happen because the referral takes too long. The CHO sees the problem, but coordinating transport over personal phone calls and paper forms costs hours. Yoma Triage cuts that coordination time by automating what the CHO already does manually.
A CHOs enters vitals into a MOEWS scoring engine, the same risk thresholds Ghana Health Service already uses  and gets a clear GREEN / YELLOW / RED output. There's an optional 15-second acoustic breathing check that runs on the phone itself, no internet needed, but it's advisory only. The CHO decides.
Once the CHO confirms, the system sends SMS alerts to nearby registered drivers. Drivers accept or decline by USSD. If nobody responds, it escalates to the next tier automatically. The receiving hospital gets a pre-arrival notification so they can prepare. Fuel stipend is logged through a Mobile Money escrow path sandbox for now.
When there's no connectivity at all, referrals queue locally on the phone and sync over 2G when the signal returns. No data gets lost.
The core idea is to turn the phones CHPS compounds already have into a coordination system that works on 2G, costs less, and doesn't replace the CHO's judgment — it removes the phone calls and guesswork around it.


## Technologies and methodologies
Yoma Triage uses a modular, offline-first architecture:

- Flutter mobile application for Android and iOS, with a responsive web interface.
- TensorFlow Lite/YAMNet for on-device acoustic respiratory screening.
- A deterministic Modified Obstetric Early Warning Score (MOEWS) engine for physiological risk assessment.
- SQLite for secure local referral queuing during network outages.
- FastAPI, PostgreSQL and SQLAlchemy for backend referral, dispatch and audit services.
- Africa’s Talking SMS and USSD for communicating with drivers and hospitals over basic phones and 2G networks.
- Tiered transport dispatch, hospital pre-arrival alerts and a Mobile Money fuel-stipend pathway.
- Privacy-preserving SHA-256 patient tokens instead of names in SMS traffic.
The solution uses existing smartphones and community transport rather than requiring new IoT sensors or specialist hardware. Future pilots will use community-led co-design with CHOs, drivers and receiving hospitals. GIS routing is also a later enhancement, not a dependency for the current workflow.


## Offline-first and low-connectivity functionality
Clinical screening happens locally. MOEWS requires no internet, while YAMNet executes on the phone using TensorFlow Lite. Referral records are saved to a SQLite outbox and synchronized idempotently when connectivity returns, preventing duplicate submissions or lost records.
After synchronization, the backend coordinates transport through SMS and USSD, which remain available where broadband is unreliable. Clinical telemetry can be encoded as compressed, SMS-safe payloads under the 140-octet constraint. Driver acceptance, hospital confirmation and arrival status are recorded in an auditable PostgreSQL workflow. If clinical AI is unavailable, the referral is not blocked: the CHO can proceed using MOEWS and clinical judgment.


## AI transparency and explainability
Yoma Triage presents simple GREEN, YELLOW or RED guidance, accompanied by the contributing vital signs and the reason a threshold was triggered. MOEWS is deterministic and traceable rather than a black-box prediction.

The acoustic model reports a confidence level and plain-language result, with a persistent warning that it is advisory, not a diagnosis. Inconclusive results explicitly direct the CHO to use clinical judgment. Every critical action—including referral submission is confirmed by the CHO. The system therefore supports faster, more consistent decisions without replacing trained frontline workers.

## Handling incomplete/missing data and safety
Yoma Triage does not depend on complete patient histories, GIS maps or centralized records. It begins with data available during the current encounter: vital signs, symptoms and CHO observations. The deterministic MOEWS engine validates required fields and returns UNKNOWN when essential measurements are missing rather than inventing a risk score. Missing information never blocks an emergency referral—the CHO can escalate based on clinical judgment. Acoustic screening is optional and inconclusive results are explicitly labelled for manual assessment.

No digital system can promise “absolute” security, so Yoma Triage uses layered protection:
1. Data minimization: collect only information required for triage and dispatch.
2. SHA-256 patient tokens replace names in APIs, SMS and hospital alerts.
3. TLS for network traffic and encrypted local storage for production deployment.
4. Role-based access for CHOs, dispatchers and hospitals.
5. Audit logs for referral access and status changes.
6. Defined retention and deletion policies aligned with Ghana’s Data Protection Act.
7. No patient data is used to train models without consent, ethical approval and de-identification.

## Workflow integration and last-mile maintenance
Within each CHPS zone, a trained CHO “super-user” handles basic onboarding, device checks and workflow support. District health information officers provide first-line technical escalation, while the central Yoma Triage team maintains the backend, security updates, clinical thresholds, integrations and model versions.
The tool follows the CHO’s existing workflow instead of creating a parallel reporting burden: enter current vitals once, receive an automatic MOEWS result, confirm the referral, and let the platform coordinate drivers and hospital alerts. Offline queuing removes repeated data entry during outages, while idempotent synchronization prevents duplicates. Drivers use familiar USSD rather than installing another application. Deployment will include short task-based training, low-literacy interfaces, automated diagnostics and a paper/manual fallback so technical failure never prevents care.


## Inclusion of Low-Literacy Caregivers
Yoma Triage’s primary users are CHOs and Motor-King drivers, not families installing an app. Caregivers usually encounter the system through the CHO, so inclusion is designed for that relationship.

For frontline workers with limited literacy, the interface relies on:
- High-contrast GREEN / YELLOW / RED risk cues rather than dense clinical text
- Large touch targets and minimal typing
- Numbered USSD menus (1 Accept, 2 Decline, 3 Confirm arrival) that work on basic phones
- Plain-language reasons for MOEWS alerts (which vitals triggered the score)
For families and caregivers, the current design does not require them to operate complex software. The CHO explains the referral decision face-to-face. Family autonomy is respected: if a household refuses transport, the refusal is documented and care continues without coercion.
Local-language support is part of the product roadmap for Northern Ghana (Dagbani and related languages): voice/IVR notifications, simple graphics, and caregiver updates in spoken language. At hackathon stage, the live demo is English CHO UI plus USSD; Dagbani voice recordings and full caregiver IVR are planned next, not claimed as already shipped. The principle is voice-first and icon-led for households, and CHO-mediated explanation until those channels are validated with communities.


## Affordability & Financial Sustainability
Yoma Triage is built to avoid new capital infrastructure:

- No new ambulances, IoT kits, or specialist hardware — it uses phones already present at CHPS compounds and existing Motor-King fleets
- Core clinical AI runs on-device; dispatch uses SMS/USSD over 2G, which is cheaper and more available than data-heavy telemedicine
- CHOs stop spending personal airtime on ad-hoc calls to drivers and hospitals; messaging is backend-mediated and auditable
- Mobile Money escrow covers emergency fuel stipends so drivers are not unpaid and families are not blocked solely by cash-on-hand delays (sandbox now; production MoMo when merchant keys are live)

## 3-Day Bootcamp Prototype
By Day 3 we will present a live, interactive end-to-end emergency referral loop—not a slide mockup.

What judges will see interactively:

1. CHO app (Flutter on phone): enter maternal vitals → deterministic MOEWS returns GREEN / YELLOW / RED with plain-language reasons → optional 15-second on-device YAMNet acoustic check (advisory only) → CHO confirms referral.
2. Offline proof: with network off, referral saves to the local SQLite outbox; when connectivity returns, it syncs without duplicates.
3. AI + ops loop closes on the backend: referral triggers a tiered Motor-King SMS cascade → driver Accept/Decline/Arrival via USSD → hospital pre-arrival SMS (patient token, not name) → status updates to COMPLETED, with an audit trail of each step.
That closed loop—screen → score → human confirm → dispatch → accept → hospital notify → arrival—is the Day-3 MVP. We will not claim a clinically validated obstetric AI model or live MoMo payouts; MoMo remains sandbox/mock.


## Risk Identification & Strategic Mitigation
Single largest barrier:
Unreliable connectivity and trust in “AI” clinical decisions at the CHPS edge—not model hallucination in the LLM sense. If the tool needs broadband, invents risk scores, or appears to replace the midwife, CHOs and families will reject it and the Second Delay remains unsolved.

Mitigation playbook:

Risk mode	Mitigation
No / weak internet
Clinical path is offline-first: MOEWS + YAMNet on-device; referrals queue in SQLite; dispatch uses SMS/USSD over 2G.
Sparse / missing vitals
Incomplete inputs → UNKNOWN, never a fabricated score; referral is never blocked—CHO escalates by judgment.
AI overconfidence / “hallucination”
No open-ended clinical chatbot in the critical path. MOEWS is deterministic and explainable; YAMNet is advisory with disclaimers; every referral requires CHO confirmation.
Driver non-response
Automatic tier escalation; concurrent accept locking so only one driver wins.
Privacy / social trust
SHA-256 patient tokens on SMS/API; no raw names in alerts; human-in-the-loop at CHO, driver, and hospital.
Demo / ops failure
Rehearsed demo_flow.py + physical-device runbook; Africa’s Talking mock fallback if live SMS fails on stage.


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

## Flutter CHO app (Android · iOS · web)

The CHO client lives in **`mobile/`** — one Flutter codebase for Android phones, iPhones, and responsive web.

```bash
cd /var/www/html/unicef
set -a && source .env && set +a
cd mobile
flutter pub get
# Web simulator (pin port for CORS):
flutter run -d chrome --web-port=8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
# Android emulator:
flutter run -d android \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
# iOS simulator (macOS + Xcode):
flutter run -d ios \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
# Physical Android or iPhone — use LAN IP or PUBLIC_BASE_URL / ngrok:
flutter run -d android \
  --dart-define=API_BASE_URL=https://YOUR-TUNNEL.ngrok-free.app \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
flutter run -d ios \
  --dart-define=API_BASE_URL=https://YOUR-TUNNEL.ngrok-free.app \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
```

Screening countdown is `SCREENING_DURATION_SEC` in `.env` (default 15). YAMNet: place `yamnet.tflite` in `mobile/assets/models/`. If missing, **Android and iOS** use the **stub classifier** automatically. Web uses Demo Normal / Demo Code Red only.

Offline outbox: SQLite on Android/iOS, SharedPreferences on web; `connectivity_plus` flushes on reconnect with the same `client_request_id`.

See `mobile/README.md` and `docs/plans/demo-day-runbook.md` for platform-specific mic permissions and demo SOP.

## Tests

```bash
./venv/bin/python -m pytest -q
cd mobile && flutter test
```
