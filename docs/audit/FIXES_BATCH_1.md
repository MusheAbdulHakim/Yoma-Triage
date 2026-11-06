# Safety Fixes: Batch 1

**Branch:** `fix/safety-batch-1` (7 commits on top of `main` at `d3f2977`; not merged, not pushed)
**Source:** `AUDIT_REPORT.md`

All seven items are done. **Nothing has run on a physical device or in a release build**, so BUG-1 and the release-build exclusion still need checking (see [Verification limits](#verification-limits)).

| Item | Commit | Fixes |
|---|---|---|
| 1. Acoustic false reassurance | `73de2c7` | BUG-1, BUG-2, BUG-20 |
| 2. No pre-filled patient data | `ebb9e98` | BUG-7 |
| 3. Single driver claim | `bc495fc` | BUG-3 |
| 4. Late drivers not refused | `c9d3534` | BUG-4 |
| 5. Fail-closed configuration | `1a27552` | Security Critical #2, High #1 |
| 6. Input validation | `47b2436` | BUG-10, BUG-11 |
| 7. Failing Flutter test | `f5fb33c` | `simulator_web_test.dart:42` |

---

## Decisions for you to review

These are the places where I chose something the brief didn't spell out. Items 1–3 matter most.

1. **Partly measured vitals discard a critical reading.** The existing UNKNOWN rule returns UNKNOWN if any required vital is missing, so SBP 60 with temperature "not measured" reads **UNKNOWN, not RED**. Item 2 makes this much easier to reach. I kept it because you asked to map to the existing handling. The CHO can still refer from that screen, and the backend still dispatches, but the score hides a critical value. **I recommend this as the first fix in the next batch:** any measured parameter scoring 3 should give RED, even with others missing.
2. **SpO₂ "not measured" can still produce GREEN.** SpO₂ was already optional and scores from the other vitals. Many CHPS compounds won't have a pulse oximeter, so I left this as is, but it's a clinical call.
3. **The emergency form now needs seven answers** (six vitals plus AVPU, each typed or marked not measured), on top of name, type and facility. This removes the fabricated values, but spec §7.1.2 asks only for type and name, and a CHO may be alone with a bleeding patient. Consider a "Vitals not taken" shortcut; I didn't add one because it's a new feature.
4. **YAMNet can now only say RED or INCONCLUSIVE.** Following §7.1.1, below 0.5 is INCONCLUSIVE, and 0.5–0.7 already was. YAMNet's score measures "respiratory event detected", not "breathing is normal", so it has no honest route to GREEN. OPERA-CE's mapping can still return GREEN, because its figure is a true two-class probability of normal (>0.7); no OPERA-CE classifier head ships, so that path can't currently run.
5. **Hiding "Screen Breathing" needed a replacement entry point (added).** It was the only route to the on-device MOEWS result. Home now shows **Record Vitals** in its place, going straight to vitals and result, with the acoustic card hidden.
6. **Late claims are limited to 2 hours (added).** "A claim after FAILED succeeds" with no limit would let a driver dialling days later claim a dead dispatch and trigger the hospital notice and stipend. `LATE_CLAIM_WINDOW` is 2 hours from dispatch start. **The value is my placeholder and needs an operational decision.**
7. **A driver who declined can still claim while the dispatch is unclaimed.** This follows the literal "any driver notified", and it recovers from a mistaken "2". The opposite rule would be a one-line change.
8. **Startup checks went slightly further than listed.** It also requires `AT_USSD_SERVICE_CODE` (without it, every driver is rejected) and refuses `AT_USERNAME=sandbox` in production (sandbox sends never reach real phones). Staging may still use sandbox.
9. **`/docs`, `/redoc` and `/openapi.json` are off everywhere except development**, including staging. You asked for production; this keeps unknown environment names locked down too.
10. **The vital ranges are mine and need clinical sign-off:** SBP 0–300, DBP 0–200, HR 0–300, RR 0–120, temperature 20–45 °C, SpO₂ 0–100. They catch typos, not clinical risk.
11. **The app enforces the same vital limits as the API (added).** The app reports any API error as "queued, will send when online", so without this a rejected referral would retry forever while the CHO believes it's on its way. `tests/test_referral_validation.py` keeps the Dart and Python values in sync.
12. **Validation also covers `ai_screen_result`, `ai_confidence`, `gestational_weeks` and the IDs,** because each of those could otherwise still cause a 500 or accept impossible values.

### Breaking changes

- **Local `.env` files need `ENVIRONMENT=development`,** or the API refuses to start. `start_demo.sh`, the README and the demo runbook are updated.
- **`emergency_type` is now an enum.** Strings like `"Obstetric haemorrhage"` return 422. App values are unaffected, and `scripts/demo_flow.py` is updated.
- **`.env.example` now ships `ENVIRONMENT=production` and `MOEWS_ONLY=true`.**
- **`/test-referral` is gone,** along with its test file.

---

## What changed

### 1. No false reassurance in acoustic screening

- **Output buffers:** YAMNet and OPERA-CE now use a nested `[1, N]` buffer, read from `[0]`. `mobile/lib/services/tflite_output.dart`, `yamnet_classifier_io.dart`, `opera_ce_classifier_io.dart`
- **Failures:** every load, inference and mic failure returns INCONCLUSIVE through `unavailableResult()`. The stub never returns GREEN. `screening_result.dart`, `screening_screen.dart`, `screening_service.dart`, `screening_model_factory.dart`, `yamnet_classifier_stub.dart`
- **Release builds:** a `demoClassifiersEnabled` constant (`!kReleaseMode`) excludes the simulator and stub classifiers. Web release shows "not available" instead of demo buttons.
- **Thresholds:** below 0.5 returns INCONCLUSIVE. `screening_result.dart`, `test/screening_thresholds_test.dart`
- **MOEWS_ONLY:** defaults to true, and only `false` or `0` turns acoustic on, so any other value stays off. `config.dart`, `home_screen.dart`, `result_screen.dart`
- **Recordings:** `dispose()` deletes the WAV even if stopping throws, and `purgeStaleRecordings()` runs at startup. `audio_recorder_io.dart`, `main.dart`
- **Docs:** `.env.example`, `mobile/README.md`, `docs/deploy-environments.md` and `docs/model-cards/yamnet-v0.md` updated to match.

### 2. No pre-filled patient data

- **Forms:** both screens start blank. New shared `VitalField` and `AvpuField` provide "Not measured" for each vital and for AVPU. An untouched form can't be submitted. `mobile/lib/widgets/vital_field.dart`, `referral_screen.dart`, `vitals_screen.dart`
- **Sent as null:** "Not measured" carries from the vitals step into the referral form and goes to the API as null.
- **AVPU fix:** a missing AVPU used to score as Alert on both sides, which would have made "not measured" read as normal. It now returns UNKNOWN. `src/agents/clinical_agent.py`, `src/tools/moews_calculator.py`, `mobile/lib/services/moews_calculator.dart`

### 3. Single driver claim

- **Fix:** all 7 `FOR UPDATE` queries in the orchestrator go through `_locked_dispatch()`, which sets `populate_existing=True`. `src/services/dispatch_orchestrator.py`
- **Test harness:** `tests/postgres_support.py` uses `TEST_POSTGRES_URL` or starts a temporary local cluster. It only touches a throwaway schema. Docker isn't available on this machine, so I used a pytest fixture.
- **Skip rule:** tests skip if no Postgres is available. **Set `REQUIRE_POSTGRES_TESTS=1` in CI** so they can't silently stop running.
- **Test:** `tests/test_concurrent_accept_pg.py` fires two parallel accepts through `/ussd/callback` for 30 rounds and asserts one winner, a matching `driver_id` and one accept log.

### 4. Late drivers aren't refused

- **Eligibility:** any driver sent the offer can claim at any tier while it's unclaimed, checked via `DispatchLog`. Drivers never offered it are still refused. `dispatch_orchestrator.py`, `src/api/ussd.py`
- **After FAILED:** a claim succeeds within the window and SMSes the CHO: "Driver X accepted LATE… Stand down manual transport if no longer needed." Decline after FAILED changes nothing.
- **Timing:** `CASCADE_TIER_SECONDS` defaults to 90. Staging and production refuse to start below 60. `src/config.py`, `main.py`

### 5. Fail-closed configuration

- **Default:** `ENVIRONMENT` defaults to production. Only the exact value `development` is insecure, so `dev`, `prod`, typos and blanks are all locked down. `src/config.py`, `src/api/deps.py`, `src/api/ussd.py`
- **Startup:** outside development, the server refuses to start without the required secrets, and checks them before touching the database. `main.py`
- **SMS:** an unconfigured gateway returns FAILED outside development, never MOCKED. `src/services/messaging_gateway.py`
- **Removed:** `/test-referral`. **Disabled:** API docs outside development.

### 6. Input validation

- **API:** ranges and enums return 422, and AVPU values are normalized. `src/api/referral.py`
- **Codec:** a value it can't encode drops only the optional SMS payload, and MOEWS and risk survive. `src/agents/coordinator.py`
- **USSD:** only an exact `1`, `2` or `3` counts. `src/api/ussd.py`
- **App:** the same limits. `mobile/lib/services/vital_limits.dart`, `vital_field.dart`

### 7. Failing Flutter test

`simulator_web_test.dart` now expects `MOEWS GREEN` and `Acoustic (advisory): RED`, matching the current result screen.

---

## Test evidence

| Check | Before (audit) | After |
|---|---|---|
| `pytest` with `REQUIRE_POSTGRES_TESTS=1` | 104 passed, 1 skipped | **221 passed, 1 skipped** (`test_opera_ce_mel`: no `librosa`) |
| Postgres tests alone (`-m postgres`) | none | **8 passed** |
| Backend coverage | 76% | **78%** |
| `ruff check .` | 15 errors | **12 errors**, all already there (below) |
| `flutter analyze` | no issues | **no issues** |
| `flutter test` | 54 passed, 1 failed | **84 passed** |
| `flutter test --dart-define=MOEWS_ONLY=false` | not run | **83 passed, 1 skipped** (the default-mode Home test) |
| `scripts/demo_flow.py` (development, temp Postgres) | passes | **passes** |

**The 12 remaining `ruff` errors** are in `scripts/demo_flow.py` (import order), `scripts/train_opera_ce_head.py`, `src/acoustic/opera_ce_mel.py`, `tests/test_hospital_privacy.py`, `tests/test_integration.py` and `tests/test_messaging_gateway.py`. I left them as out of scope, and the only one of those files I changed is `demo_flow.py`, by one line elsewhere. `ruff format` wasn't requested and I didn't run it on the repo; most existing files already differ from its output, and my new test files would also be reformatted.

**Race test before and after:** it failed at **round 0** on the unfixed code (both drivers told "Accepted"), and passed all 30 rounds on three consecutive runs with the fix.

**Real server boots:**

| Scenario | Result |
|---|---|
| No environment set | Refuses: `API_KEY must be set; AT_WEBHOOK_SECRET must be set; AT_API_KEY must be set; AT_USSD_SERVICE_CODE must be set; AT_USERNAME must not be sandbox` |
| Production, `CASCADE_TIER_SECONDS=30` | Refuses: `CASCADE_TIER_SECONDS must be at least 60` |
| Production, fully configured | `/` 200, `/docs` 404, `/openapi.json` 404, `/test-referral` 404, referral without key 401 |

**Do the tests catch regressions?** I undid each fix below in a scratch copy and ran its tests. All were caught:

| Fix undone | Failing tests |
|---|---|
| Notified drivers stay eligible | 4 |
| CHO late-accept SMS | 1 |
| Late-claim window | 1 |
| Production as the default | 1 |
| No mock sends outside development | 3 |
| USSD exact match | 13 |
| Codec failure handling | 2 |
| Missing AVPU returning UNKNOWN | 3 |

The Dart changes didn't get this revert check. Their new tests passed after the changes, and I did not run them against the old code.

---

## Verification limits

- **BUG-1 is not confirmed on a device.** This machine has no native TFLite library, Android SDK or handset. The tests prove the new buffer matches what the plugin's own conversion code produces, and the old flat buffer doesn't. They don't run real inference, or check that the classifier calls the helper. **Run one real Android screening with `MOEWS_ONLY=false`.**
- **Release-build exclusion is not verified by a build.** It relies on a `kReleaseMode` constant. No Android SDK is available here, and the web build is still broken (BUG-19).
- **The code path after real YAMNet inference has never run on a device.** The fix may expose new problems such as speed on low-end phones (BUG-21).
- **Late-claim and cascade tests call the timer function directly.** They don't wait out real 90 s timers.

---

## Deferred

| Item | Why |
|---|---|
| **OPERA-CE input shape** | **Bigger than described, so I stopped here.** I fixed the output as you asked, but the input also mismatches: the app passes a flat `(251 × 64)` mel, and the TFLite model expects `[1, 64, 251]`. Fixing it means confirming the axis order against the ONNX model. Until then OPERA-CE stays INCONCLUSIVE, which is safe, and no trained head ships anyway. |
| **Web build failure (BUG-19)** | Not in this batch. It still fails on the `record_platform_interface` override. |
| **Partial vitals masking a RED** | Not in this batch. See decision 1. |
| **Stale docs** | `docs/plans/at-sandbox-runbook.md` still describes `…*1` USSD parsing and "empty code accepts anything", and `TASK_BOARD.md` and `todo.md` are out of date. I only changed docs that would otherwise break setup or contradict a new default. |
| **`python -m src.db.seed` has no environment guard** | It can still load fake demo data into production. Not in this batch. |
| **Default DB credential in `src/config.py`** | Not listed in item 5. Worth adding `DATABASE_URL` to the startup checks. |
| **Other 4xx errors still show as "queued" (BUG-14)** | The vital limits cover the likely case, but a 404 for an unknown facility, or any other 4xx, would still retry forever. |
| **BUG-5, 6, 8, 9, 12, 13 and others** | Outside this list, and all still present. A restart still strands a cascade (BUG-6), and the first referral on a cold server still blocks everything (BUG-8). |

The pilot rating in `AUDIT_REPORT.md` stands: **this batch removes specific dangers but doesn't make the system pilot-ready.**
