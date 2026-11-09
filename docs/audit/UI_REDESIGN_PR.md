# UI redesign: Clinical Field Resilience screens (feat/ui-redesign → main)

## Summary

The CHO-facing app is redrawn to the Stitch designs in the Clinical Field Resilience design
system, over seven review rounds. Every round is recorded in
[`docs/audit/UI_REDESIGN.md`](UI_REDESIGN.md), and the reference designs are in
`docs/design/stitch/`. Most changes are visual. Clinical logic and scoring are unchanged:
MOEWS bands, risk thresholds, dispatch cascade and validation limits are all the same.

The flow changes, the backend additions and the deploy order are listed below. Read
"Flow changes" before approving.

## What changed

**Design system.**

- Navy palette: primary `#0F2744`, secondary `#1B3B6F`, tertiary `#2C5E8A`, neutral
  `#0B192C`.
- Atkinson Hyperlegible Next, bundled with the app.
- Every colour comes from `lib/theme/yoma_theme.dart`; a test fails on any colour literal
  elsewhere.
- Red, amber and green are used only for triage risk levels and destructive actions.

**Screens redesigned.**

| Screen | Changes |
|---|---|
| First-run setup | Three states: enter number, clinic confirmed, error |
| Home | Both modes; Offline pill; light and dark warning strip |
| Record vitals | Compact cards |
| Result | Four risk variants, plus the breathing advisory row |
| Emergency referral form | Single bottom button |
| Breathing check | Ready, recording pulse, analysing, results, microphone blocked |
| Referral status | Timeline, driver card, Call/SMS rows |
| Not sent yet | Restyled to match the status screen |
| "Still needs transport?" | Now a bottom sheet |

**Copy.**

- No raw codes: "Heavy bleeding", not "pph".
- Correct plurals.
- Friendly dates and ages ("Today, 17:43", "Saved 45 minutes ago").
- The risk words Critical / Elevated / Stable, with "Score N".

**Accessibility.**

- Every control is its own named node in the semantics tree.
- Every enabled button can be activated by TalkBack; six were fixed in round 6.
- Tap targets are at least 48 dp.
- WCAG AA contrast, checked on the rendered screens.
- No overflow at 320 dp with 130% text.
- The keyboard never hides the focused field or the main button.

## Flow changes (reviewers: please check these)

1. **Referral form: one bottom button.**
   - With vitals recorded, the button reads "Send referral".
   - Without vitals, it reads "Send now (vitals not taken)" and uses the existing
     skip-vitals path and hospital notice.
   - The separate red "Emergency: skip vitals" button is gone.
   - Vitals are entered only on Record vitals; the form shows one summary row.
2. **"Still needs transport?" is a bottom sheet with one-tap answers.**
   - It replaces the page with radio buttons and Confirm.
   - The answers are Send now, Already handled and Cancel referral, with the same actions
     as before.
   - After Call or SMS, "Already handled" leads instead of being preselected.
   - Several waiting referrals are shown one at a time ("1 of 3").
   - The sheet can't be dismissed without an answer, by tapping outside, dragging or
     Android back.
3. **First-run setup: a confirm step.**
   - The server's clinic name is shown, and the CHO taps Start.
   - The identity is saved on Start; contacts are fetched at lookup.
   - "Not your clinic? Use a different number" goes back.
4. **Home in acoustic builds** shows Emergency referral, Check breathing and Record vitals.
   A referral made without a breathing check sends `ai_screen_result: NOT_SCREENED`.
5. **Record vitals:**
   - SpO₂ is optional.
   - "See result – N left" counts the five required vitals: BP as one item, heart rate,
     breathing rate, temperature, consciousness.
   - Blood pressure has one "Not measured" for both fields.
   - See result stays enabled; with gaps it scrolls to the first missing vital and
     announces it.
6. **Referral status:**
   - After FAILED, the screen keeps checking every 30 s until the late-claim window ends,
     and shows a late acceptance.
   - After "Call a driver instead", returning to the app asks "Did a driver agree to come?".
     "Yes, cancel referral" uses the existing cancel.
7. **Patient name removed** from the form. It was never sent, stored or shown anywhere.
8. **Breathing check: Ready and result steps on by default** (`BREATHING_STEPS` defaults to
   true).
   - In acoustic builds the check opens on a Ready step (Start), and shows the breathing
     result before vitals.
   - Each adds one tap.
   - `--dart-define=BREATHING_STEPS=false` restores the old flow.
   - MOEWS-only builds have no breathing check.
9. **Result:**
   - The disclaimer is one line under Why: "Score thresholds pending clinical sign-off."
   - The advisory wording appears only with breathing-check content.
   - Buttons are in sentence case.

## Backend changes

All of these are additive: no schema change and no migration.

- `GET /api/v1/dispatch/{id}` adds three fields:
  - `step_times`: when each step happened, ISO 8601 with offset, taken from existing
    dispatch and log rows;
  - `late_claim_until`: `initiated_at` + `LATE_CLAIM_WINDOW_MINUTES`, in UTC. The
    orchestrator now uses the same function to accept late claims;
  - `driver_vehicle`: the accepted driver's vehicle type and description, the same label
    the driver SMS uses. Null until a driver accepts.
- Hospital pre-arrival SMS: adds the line "Breathing check: not screened" when
  `ai_screen_result` is `NOT_SCREENED`.
- `tests/test_referral_validation.py`: the emergency-type parity test now reads
  `mobile/lib/models/emergency_type.dart`. It had silently stopped checking anything
  since the form's dropdown was removed.

## Deploy order

1. **Backend first.**
   - The new fields are additive, so the current app ignores them.
   - The new SMS line only appears for `NOT_SCREENED`, which only the new app sends.
2. **Then the app.**
   - The new app also works against the old backend: it shows no times, no vehicle, and
     stops checking at FAILED as before.
   - Pushing the app first is harmless, but late acceptances and step times only appear
     once the backend is updated.

No configuration changes. `LATE_CLAIM_WINDOW_MINUTES` keeps its default (45).

## How it was tested

- `flutter analyze`: no issues.
- `flutter test`: 560 passed (default build), 561 passed (`MOEWS_ONLY=false`); 0 failed.
- Backend: full `pytest`, run with `AT_WEBHOOK_SECRET=`: 712 passed, 5 failed, 4 skipped.
  - The 4 `test_startup_config` failures come from the local `.env` (development settings)
    and also happen on `main`.
  - `test_durable_cascade_pg::test_killed_mid_tier_cascade_continues_after_restart` fails
    identically on `main` (checked in a clean worktree), so it is pre-existing and not
    caused by this branch.
  - All tests for the changed code pass: `test_dispatch_step_times`,
    `test_dispatch_vehicle`, `test_not_screened`, `test_skip_vitals`,
    `test_hospital_privacy`, `test_diversion`, `test_referral_validation`,
    `test_parameters`.
- Device pass on both emulators (API 34 and API 24), one at a time, via
  `scripts/run_emulator_pass.py`. It covers every existing scenario, plus:
  - every redesigned screen photographed at 360×640 dp;
  - the keyboard check;
  - real dialler and messaging apps opened from Call/SMS;
  - Android back from each screen;
  - 130% system font size;
  - TalkBack really on, reading each main screen.

  Results:
  - **Both AVDs (API 34 and API 24) pass every scenario except** scenario 2 (release build:
    microphone denied / allowed and the ANR probe), which failed on both. On API 34, ANR
    probes 1 and 2 passed (no ANR, no "isn't responding" dialog) and the emulator died
    during probe 3. On API 24 the probe did not finish (blank screen).
  - The release timings ran on API 24: cold start to Home 2.07–2.14 s; Confirm referral to
    "drivers notified" 1.53–1.55 s. On API 34 they did not complete, because the emulator
    died.
  - **Emulator deaths** came from host memory pressure: `systemd-oomd` on a 13 GB machine
    with swap near 90%. The pass script now survives them and lowers its own memory use.
    See `docs/audit/UI_REDESIGN.md`, round 7, step 6.
  - **Found and fixed by the pass:**
    - the keyboard covering the main button (round 6);
    - six buttons TalkBack could not activate (round 6);
    - the setup label over "+233" (round 7);
    - integration tests that still expected older screens.
- Side-by-sides with the designs, at equal dp scale:
  `docs/testing/screenshots/ui-redesign/fidelity/`.

## Still open (not blocking this PR)

- The emergency-type list and the risk words (Critical / Elevated / Stable) await the
  clinical leads (`docs/PARAMETERS_SIGNOFF.md`, questions 1–6).
- The breathing pulse was not checked with live sound in the emulator. The emulator's
  PulseAudio client would not connect on the test host; scripted levels and a
  fake-stream test were used instead.
- Not yet tested on a physical phone. Every device check above ran on emulators.
- Africa's Talking (SMS to drivers and hospitals) has been tested in its sandbox only.
- `test_durable_cascade_pg` fails on `main` as well; it needs its own fix.
- See "Open questions" at the end of [`UI_REDESIGN.md`](UI_REDESIGN.md).
