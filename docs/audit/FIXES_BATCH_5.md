# Fixes: Batch 5

**Branch:** `fix/batch-5`, pushed to `origin` for a PR, not merged
**Source:** `docs/testing/EMULATOR_PASS.md` (part A), `FIXES_BATCH_4.md` (part B), batch 5 brief

**Base: `test/emulator-pass`, not `origin/main`.** The brief says `test/emulator-pass` should be merged, but at the fetch `origin/main` was still `9fe1d01`, without it. As you chose, this branch starts from `test/emulator-pass` (`9a53e3a`), whose runner and integration tests part A needs. **A PR to `main` will therefore also show its 3 commits** (`f6ae6a6`, `04a2390`, `9a53e3a`). Merge that branch first if you want them reviewed separately.

**Parameters:** the new placeholder `EXPIRE_UNCONFIRMED_HOURS = 24` is in `src/parameters.py` and `mobile/lib/parameters.dart`, is listed in `docs/PARAMETERS_SIGNOFF.md`, and is checked by `tests/test_parameters.py`.

All items are done, one commit each with tests. Part A was checked on both emulators. **Nothing has run on a physical phone, and nothing reached Africa's Talking, MTN MoMo or Supabase** (see [Verification limits](#verification-limits)).

| Item | Commit | Fixes |
|---|---|---|
| A1. Inference off the main thread, progress, Cancel | `cb946d1` | Emulator pass B2 (ANR) |
| A2. Emergency Referral pinned, warnings in one banner, Home scrolls | `f548e70` | Emulator pass B3 |
| A3. Release builds fail closed | `25538ec`, `b3d3b2f` | Emulator pass B7 |
| A4. Queued screen follows an automatic send; plain errors | `cd9985a` | Emulator pass B5, B6, B10 |
| A5. App size: no ONNX, no OPERA-CE assets, split APKs and a bundle | `bbafabe` | Emulator pass B4, B8 |
| B1. Pre-deploy compound check | `7da60e2` | Batch 4 decision 1 |
| B2. "Still needs transport?" after a manual Call or SMS, any age | `8d77cca` | Batch 4 decision 4 |
| B3. Stipend kept but marked cancelled | `767bbfd` | Batch 4 decision 8 |
| B4. Expire unanswered AWAITING_CONFIRMATION after 24 hours | `7467eef` | Batch 4 decision 5 |
| Runner: memory limits, the A1 test, build before boot, partial screen reads | `46559f2`, `cae05ca`, `f046c2b` | Host ran out of memory; a flaky read |
| Tests found missing while checking the batch | `3756955`, `5071bd9`, `739fb73` | Not brief items |
| Emulator tests brought up to date | `ac04cec` | s6 after B2; the harness's app restart |
| Docs: this report, the emulator report, the spec | the last commit | |

---

## Decisions for you to review

Items 1–6 matter most.

1. **Cancel goes on to vitals, with the breath result INCONCLUSIVE** ("Breath check cancelled — use MOEWS and clinical judgment"). It never counts as normal. Leaving the screen mid-analysis cancels too.
2. **A3 also requires `API_KEY`** in a production release, which the brief didn't name. A release without it can't talk to our backend, so letting it build seemed wrong.
3. **Release signing still uses the debug key.** A3 checks settings, not signing. A store or sideloaded pilot build needs a real upload key, which only you can create and keep.
4. **OPERA-CE's files are left out of every build, debug included.** Flutter can't vary assets by build mode. The code stays, and returns INCONCLUSIVE with "OPERA-CE is not included in this build". If its files are added back but the model can't start, it now says "OPERA-CE could not start on this phone" instead.
5. **B2 adds a field to the API, `manual_contact`.** An older server ignores it and dispatches, so **deploy the backend first.**
6. **B4 counts the 24 hours from when the server received the referral** (`initiated_at`), not from when it was queued on the phone. A referral that sat offline for a day then got a stale answer has 24 more hours. When an answer comes back `REFERRAL_EXPIRED`, the app removes its local copy: after Send now it first says drivers were not told and waits for OK; after Already handled or Cancel it says nothing, as nobody was told either way.
7. **Each analysis starts a fresh background isolate and copies the 4 MB model into it.** That's simpler and can't leak a stuck interpreter, at the cost of the 0.3–0.7 s load each time. Keeping one isolate alive would save that, if a phone shows it matters.
8. **On the emulators, analysis is slower while the screen animates:** a full capture took 13–27 s in the responsiveness test, against 5.3–10.3 s with nothing moving. My guess is the emulators' software rendering competing for the CPU. Only a real phone can say whether the progress bar costs real time.
9. **The warnings banner always starts closed,** naming the most urgent warning (failed, then stale, expiring, retry, catalog) and how many more there are. Tapping opens it. It doesn't remember being open.
10. **B1 fails when there are no compounds at all,** and counts drivers by `is_active` only, not whether they have a phone or a recent trip. It prints compound IDs and names, never phone numbers.
11. **B3 decides nothing about payment.** The ledger entry keeps its amount, gets status CANCELLED and a `momo_escrow_cancelled` line in the dispatch log. Whether a driver who set off is paid is still for whoever settles the ledger.
12. **The runner limits the emulators' memory** (API 34 at 3 GB, API 24 at 2 GB) and stops Gradle before each boot, as you chose. The host has 13 GB; it ran out twice and restarted once during this batch. The runner now also builds the release before booting any emulator.
13. **The wording is mine and hasn't been reviewed:** the analysis and cancel text, the warnings banner, the plain error messages, the "built wrongly" screen, the test label, the expired-referral dialog and the B1 report.

### Breaking changes

- **Release builds need settings.** `flutter build apk --release` without `APP_ENV=production`, an `https://` `API_BASE_URL` and `API_KEY` now fails. The command is in `docs/deploy-environments.md`. A test release needs `YOMA_TEST_RELEASE=true`.
- **Deploy the backend before the app** (decision 5).
- **New status `EXPIRED_UNCONFIRMED`** on referrals, and **new error code `REFERRAL_EXPIRED`** (409) from `POST /api/v1/referral/{id}/resolve`. The status column is a string, so there is no migration. Reports that list statuses should add it.
- **New stipend status `CANCELLED`** in the mock ledger.
- **New environment variable `EXPIRE_UNCONFIRMED_HOURS`** (default 24). Startup refuses 0 or less.
- **The cascade worker now also runs the expiry,** after each round of dispatch work.

---

## What changed

### A1. Inference off the main thread

- **Background isolate:** `mobile/lib/services/background_job.dart` runs work with `Isolate.spawn` and can kill it at once. YAMNet and OPERA-CE build their interpreter inside the isolate from the model bytes (`Interpreter.fromBuffer`), so no TFLite call runs on the main thread. `yamnet_classifier_io.dart`, `opera_ce_classifier_io.dart`
- **Screen:** while analysing, a progress bar, "Checking breath… You can keep using the phone.", and a Cancel button. `screening_screen.dart`
- **Cancel:** reaches the service and the classifier, and is checked after the recorder stops, after the classifier starts and after it returns, so a cancel at any moment wins. `screening_service.dart`
- **Measured** with the same on-device test (`integration_test/s10_responsive_test.dart`: a 10 ms timer on the main isolate, a tap one second in), debug builds, full 15 s capture:

| | API 34 | API 24 (2 GB) |
|---|---|---|
| Longest main-thread block, before (`46559f2`) | **5,810 ms**, tap not handled | **10,618 ms**, tap not handled |
| Longest main-thread block, after | **194 ms**, tap handled | **148 ms**, tap handled |
| The same test with no inference (the harness's own stalls) | 412 ms | 182 ms |
| Frames drawn during analysis, after | 18.8 per second | 32.2 per second |

  The after figures are from the final pass. An earlier run measured 265 ms and 326 ms. The no-inference control shows these remaining blocks are the test's own pumps and tap in a debug build, not inference. The test fails above 1,000 ms, or below 10 frames per second.
- **ANR probe** (touches once a second during analysis in the release build): no ANR in 6 runs on API 34 and 6 on API 24. Before, 7 of 8 runs on API 34 logged one.

### A2. Emergency Referral always reachable

- **Pinned:** Emergency Referral sits at the top of Home, outside the scrolling part, so nothing can push it down. `home_screen.dart`
- **One banner:** the warning cards (failed, stale, expiring, retry, stale catalog) collapse into one summary, most urgent first, that opens on tap. The rest of Home scrolls.
- **Tested** at 320×568 and 360×640 dp with every card active: fully visible, at least 48 dp tall, a real tap opens the referral (`test/home_layout_test.dart`), and on both emulators at 320×568 dp and at their own sizes (`integration_test/s9_home_banners_test.dart`).

### A3. Release builds fail closed

- **Gradle:** `checkReleaseSettings` reads the dart-defines and stops a release build without `APP_ENV=production`, an `https://` `API_BASE_URL` that isn't a local or emulator address, and `API_KEY`. `mobile/android/app/build.gradle.kts`
- **App:** checks the same at startup, and shows only a "built wrongly" screen if anything is missing. `config.dart` no longer has a default server in release. `release_settings.dart`, `main.dart`
- **Test releases:** `YOMA_TEST_RELEASE=true` allows a test server, never with production, and shows a red "TEST BUILD — not for patient use" label on every screen.
- **Found by the emulator pass and fixed in `b3d3b2f`:** the label was drawn but missing from the accessibility tree, so TalkBack wouldn't read it. The route blocked the semantics of anything painted before it; the Navigator now has its own semantics boundary.
- **Runbook:** "Release build (deploy runbook)" in `docs/deploy-environments.md`.
- **Checked by building:** a plain release is refused, listing all three problems; `https://10.0.2.2` is refused; the test flag with production is refused; the test release and a production `https://` release both build.

### A4. Accurate status, plain errors

- **Automatic send:** the queue announces each flush (`OfflineQueue.changes`), and the queued screen follows it: to the dispatch screen with drivers notified, or to "Still needs transport?" if the server held it. `offline_queue.dart`, `queued_referral_screen.dart`
- **Server unreachable** on the dispatch screen: "Server unreachable, so this status may be out of date. Your referral was sent, and this screen will keep checking. Use Call or SMS below if urgent.", with the Call and SMS panel. `dispatch_status_screen.dart`
- **Microphone:** "Microphone permission is off." or "The microphone could not start.", with what to do next. The catalog and save errors on the referral form are plain too.
- **A test** fails if any screen interpolates an exception into its text.

### A5. App size

- `pubspec.yaml` bundles only `yamnet.tflite` and the catalog. The 16 MB ONNX file and the OPERA-CE TFLite file are no longer shipped (decision 4).
- The runner builds with `--split-per-abi` and also an app bundle, with the test release settings:

| Output | Bytes | MB (10⁶) |
|---|---|---|
| `app-arm64-v8a-release.apk` | 30,101,519 | 30.1 |
| `app-armeabi-v7a-release.apk` | 25,127,819 | 25.1 |
| `app-x86_64-release.apk` | 33,603,765 | 33.6 |
| `app-release.aab` | 64,285,672 | 64.3 |
| Before: one APK for all ABIs | 101,275,955 | 101.3 (the emulator pass's "96.6 MB" is in MiB) |

  No OPERA-CE file is in any APK or the bundle. The largest remaining entries are `libflutter.so` (12.3 MB on x86_64), the compiled Dart (5.9 MB), the TFLite runtime (5.0 MB), YAMNet (3.9 MB) and the unused TFLite GPU library (3.8 MB).

### B1. Pre-deploy check

`python -m src.admin.check_compounds` lists every compound with no active CHO or no active driver and exits 1 if there are any, or if there are no compounds. It only reads and prints no phone numbers. Added to the deploy runbook with `alembic upgrade head`. `src/admin/check_compounds.py`

### B2. Manual-call prompt

The app sends `manual_contact: true` for a queued referral whose Call or SMS button was tapped. The server then holds it as AWAITING_CONFIRMATION whatever its age, and the app asks "Still needs transport?" with Already handled chosen. `src/api/referral.py`, `mobile/lib/models/referral.dart`, `offline_queue.dart`

### B3. Stipend after cancel

Cancelling after a driver accepted keeps the ledger entry, sets its status to CANCELLED and logs `momo_escrow_cancelled`, in the same transaction. A second cancel changes nothing. `dispatch_orchestrator.py`

### B4. Expire stuck referrals

`expire_unconfirmed_referrals` runs in the cascade worker. A referral still AWAITING_CONFIRMATION `EXPIRE_UNCONFIRMED_HOURS` after `initiated_at` becomes EXPIRED_UNCONFIRMED, with an `audit_logs` row (`referral_expired_unconfirmed`, actor `worker`). Rows are taken with `FOR UPDATE SKIP LOCKED`, 100 per run, so an answer being saved always wins. An answer afterwards gets 409 `REFERRAL_EXPIRED`. `src/services/referral_expiry.py`, `main.py`, `stale_referral_screen.dart`

`PRODUCT_SPEC.md` is now version 2.3, with §7.10 and §10.2 updated.

---

## Test evidence

| Check | After batch 4 | After this batch |
|---|---|---|
| `pytest`, `REQUIRE_POSTGRES_TESTS=1` | 561 passed, 4 skipped | **599 passed, 4 skipped** |
| `ruff check .` | 10 errors | **10 errors**, the same files, none on lines I wrote |
| `mypy src main.py` | 11 errors in 4 files | **11 errors in 4 files**, the same ones |
| `flutter analyze` | no issues | **no issues** |
| `flutter test` | 263 passed | **320 passed, 2 skipped** (two A1 service tests need acoustic mode) |
| `flutter test --dart-define=MOEWS_ONLY=false` | 262 passed, 1 skipped | **321 passed, 1 skipped** |
| `scripts/demo_flow.py` | passes | **passes**, 0 phone numbers and 0 tracebacks in the server log |
| `alembic upgrade head`, then `alembic check`, fresh database | no drift | **no drift**; `check_compounds` exits 1 on it, as it has no compounds |
| Emulator pass, both AVDs | 2 failures (screen size) | **every scenario passes on both**, including scenario 9 and the banner tests on API 24. See `docs/testing/EMULATOR_PASS.md` |

All were run at `f046c2b`, with no emulator running; the only later change is the docs. The emulator results are from runs at `739fb73` (the full pass) and `ac04cec`–`f046c2b` (the reruns); `b3d3b2f` is the only app change between them.

**Emulator pass:** the full pass failed s2, s6 and the banner tests on both AVDs. s2 found the hidden label (a real bug, fixed); s6 still expected a dispatch after Call and SMS, which B2 changed; the banner test's app restart kept Home's old state. Those were rerun after the fixes and pass. Two rerun failures were the host (lost DNS during a Gradle build) and the runner (a partial screen read), and passed when repeated.

### Revert check

I undid each fix in a scratch copy and ran its tests, after confirming they pass unmodified. Each catch names the failing test. **Backend 21/21 caught. Dart 35/36: the one miss is explained below, and removing both of the guards it duplicates is caught.**

| Item | Undone | Caught |
|---|---|---|
| A1 | Work runs on the main isolate; cancel doesn't kill the isolate, or not during start-up; a failed job reports success; no progress; Cancel does nothing or doesn't stop the model; leaving mid-analysis lets it run on; the service's cancel doesn't reach the classifier; windows don't overlap; a short capture isn't scored | 11/12 |
| A2 | Home as before A2; warnings not collapsed; the banner names the least urgent | 3/3 |
| A3 | Plain http, the emulator address or no API key accepted; test flag allowed with production; startup ignores the problems; Gradle check not wired into the build; label hidden from screen readers | 7/7 |
| A4 | Queue doesn't announce sends; queued screen doesn't follow them; raw network, microphone or catalog error shown; no Call or SMS while unreachable | 6/6 |
| A5 | Every model bundled again; old "not installed" message; a start-up failure called "not in build" | 3/3 |
| B1 | Inactive CHO or driver counts; a CHO anywhere counts for every compound; gaps or no compounds exit 0; gaps not on stdout | 6/6 |
| B2 Backend | Server ignores `manual_contact` | 1/1 |
| B2 Dart | Queue doesn't send it; request leaves it out | 2/2 |
| B3 | Stipend left as it was; row deleted; no dispatch-log line | 3/3 |
| B4 Backend | Worker never expires; any status expires; exactly at the limit kept; no audit row; waits on a row being answered; limit or override ignored; generic code for expired; startup allows 0; server value differs from the app and sheet; app doesn't know `REFERRAL_EXPIRED` | 11/11 |
| B4 Dart | Expired treated as answered, silently; Send now on expired says nothing; every answer gets the message | 3/3 |

**What this check found:**

- **The A1 miss:** removing the service's check for a cancel before it starts the classifier is not caught, because a second check, after the classifier is created, catches the same cancel. `739fb73` adds a test that cancels while the recorder is still stopping; it fails when both checks are removed.
- **A test that could hang:** undoing SKIP LOCKED made the lock test wait forever instead of failing. It is now bounded at 10 s (`3756955`).
- **Gaps:** nothing checked that a cancelled isolate really exits, or that startup refuses a wrongly built release, or measured the harness's own stalls. Added in `5071bd9`.
- **A real bug, found on the emulator, not by tests:** the hidden test label (`b3d3b2f`, above).

---

## Verification limits

- **No physical phone.** A1's speed and responsiveness, and A5's install size, are from x86_64 emulators on a desktop CPU with software rendering. A budget ARM phone will be slower.
- **Release signing** is the debug key (decision 3), and no production `https://` release was installed on anything.
- **B1–B4** ran against the local PostgreSQL only. The expiry runs in the worker but was tested by calling it, not by leaving a referral for 24 hours.
- **No live Africa's Talking, MoMo or Supabase traffic.** Still not shown: YAMNet ever returning RED (emulator pass B9).

---

## Deferred

| Item | Why |
|---|---|
| **Real upload key and signing** | Needs your key (decision 3). |
| **GPU delegate library** | 3.8 MB per APK, unused. Dropping it needs a plugin change. |
| **OPERA-CE** | Excluded, still INCONCLUSIVE. Making it load needs work on the model. |
| **Home shows no compound name; cosmetic issues at 320 dp** | Emulator pass B11, B12. Not in this brief. |
| **The open banner repeats the first card's title** | Cosmetic, seen on the emulators. The header could say "5 warnings" when open. |
| **Reactivating a CHO, OTP, diversion, driver trip state, web build** | Not in this brief. |

**The pilot rating in `AUDIT_REPORT.md` stands.** Clinical sign-off of the placeholders (now including `EXPIRE_UNCONFIRMED_HOURS`), OTP, ethics clearance, real signing and real-device testing are still open.
