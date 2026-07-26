# Verification — Yoma Triage Hackathon Implementation

**Date:** 2026-07-26  
**Verifier:** independent spot-check + fresh test rerun (no new feature work)  
**Verdict:** **PASS WITH GAPS**

## Evidence (fresh runs)

| Suite | Command | Result |
|-------|---------|--------|
| Backend | `PYTHONPATH=. ./venv/bin/pytest -q` | **61 passed** (~23s) |
| Flutter | `cd mobile && flutter test` | **19 passed** |

No commits made. No code changes applied (nothing was a demo-blocking quick fix).

## Claim spot-check

| Claim | Status | Evidence |
|-------|--------|----------|
| Privacy: token-only SMS/API | **Pass** | `hospital_notifier.py` sends `Patient token: {hash[:12]}`; API response has `patient_hash` only (`referral.py`); DB stores `patient_name="Unknown"` |
| SHA-256 patient tokens | **Pass** | API validates `^[0-9a-f]{64}$`; Flutter `patient_token.dart` uses `Random.secure()` + SHA-256 (not name-derived) |
| Flutter outbox excludes name | **Pass** | `ReferralRequest.toJson()` omits `patientName`; `offline_queue_test` asserts no `patient_name` |
| CORS configurable | **Pass** | `CORSMiddleware` in `main.py`; `CORS_ORIGINS` in `config.py`; `tests/test_cors.py` allow + deny |
| AT live path + mock fallback | **Pass (code)** | `MessagingGateway` posts to AT when `settings.at_configured`; otherwise `MOCKED`. Unit tests cover mock/sent/fail |
| USSD arrival → COMPLETED | **Pass** | USSD option `3` → `handle_arrival`; status `COMPLETED`; `tests/test_ussd_arrival.py` (7) |
| Real `yamnet.tflite` | **Pass** | Asset present (~4.1 MB), magic `TFL3`; `yamnet_classifier_io.dart` loads asset, maps AudioSet respiratory indices, stub only on load/probe failure |
| Flutter rebrand / iOS+mic / theme / disclaimers | **Pass** | No Relay* in `mobile/lib`; `ios/` present; `NSMicrophoneUsageDescription` set; result disclaimer mandatory + demo-mode label |
| pytest 61 / flutter 19 | **Pass** | Reconfirmed this run |
| No commits | **Pass** | Uncommitted worktree (as claimed) |

## PO decision compliance

| Decision | Compliance |
|----------|------------|
| Android + iOS + responsive web | **Met with caveats** — Android/iOS folders present; web titled Yoma Triage; referral form scrolls (`ListView`). Home/result/screening are simple columns (no overflow tests on small viewports). |
| LIVE Africa’s Talking SMS | **Code ready; runtime not live yet** — live path exists; current `Settings.at_configured == False` → mock SMS until real `AT_API_KEY` (+ username) are set in `.env`. |
| Real YAMNet (not stub-primary) | **Met on IO** — asset + live interpreter path; stub is fallback only. Web still uses simulator (expected). Disclaimers present. |
| Keep Yoma Triage name | **Met** |

## Top gaps / demo blockers

1. **AT credentials required for LIVE SMS** — User must set real `AT_API_KEY` / `AT_USERNAME` (and sender if needed) per `docs/plans/at-sandbox-runbook.md`. Until then, demo SMS is mocked (fine for local rehearsal, not for live AT stage).
2. **No fresh browser CORS smoke in this verification** — unit preflight tests pass; stage still needs one real Flutter-web → FastAPI POST from the actual origin (add origin to `CORS_ORIGINS` if using a non-default port).
3. **Patient name UI still present locally** — collected for display only; not sent/serialized. Acceptable for hackathon; not encrypted-identity design.
4. **Voice cascade not live** — when AT is configured, `initiate_voice` still returns FAILED (“Voice not configured for MVP”). SMS path is what PO locked; voice is backlog.
5. **YAMNet is advisory technical smoke** — respiratory AudioSet mapping is honest but not obstetric-validated; keep disclaimer language in the pitch.

## Ready to commit?

**Yes, if the user asks** — implementation claims match code + both suites green. Prefer excluding secrets (`.env`), IDE junk (`.idea/`), and any accidental keys. Large `yamnet.tflite` (~4 MB) should be intentional if included.

## Next ops for demo

1. Set AT credentials → confirm `settings.at_configured` is true → send one sandbox SMS.  
2. Seed DB + run `scripts/demo_flow.py` including USSD arrival.  
3. One Flutter web browser smoke against FastAPI with matching CORS origin.
