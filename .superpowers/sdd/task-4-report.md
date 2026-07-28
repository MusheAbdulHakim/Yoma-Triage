# Task 4 Report: Vitals-before-result + MOEWS fusion

## Status

Implemented A2 on `feature/phase-a-c-gating-geo`.

## Changes

- Added `VitalsScreen` with SBP, DBP, HR, RR, temperature, SpO2, and AVPU entry.
- Changed the screening journey to `ScreeningScreen → VitalsScreen → ResultScreen`.
- Calculated MOEWS before displaying the acoustic result.
- Added optional `MoewsResult` and session vitals to `ResultScreen`.
- Passed `moews.riskLevel` into `referralIndicated`, so GREEN acoustic + RED MOEWS shows `Confirm Referral`.
- Prefilled `ReferralScreen` from screening-session vitals.
- Kept the Home `Emergency Referral` path directly connected to `ReferralScreen`, with its existing defaults.
- Updated native/stub and web simulator flow tests for the vitals step.

## TDD evidence

1. Added `result_moews_fusion_test.dart`.
2. Initial fusion test failed to compile because `ResultScreen` had no `moews` parameter.
3. Added minimal fusion wiring; the focused test passed.
4. Added vitals journey and prefill tests; they failed because `VitalsScreen` and the `vitals` parameter did not exist.
5. Implemented the journey and prefill; all focused tests passed.
6. Added screening-to-vitals navigation coverage; it failed while screening still opened `ResultScreen`, then passed after navigation was changed.

## Verification

- `flutter test test/result_moews_fusion_test.dart`: 4 passed.
- Focused simulator/fusion tests: 8 passed.
- `flutter test`: 38 passed.
- `flutter analyze`: no issues found.
- `dart format --set-exit-if-changed ...`: clean after formatting.
- `git diff --check`: clean.

## Concerns

- Vitals entry validates numeric shape but not physiological ranges, matching the current referral form behavior.
- MOEWS is fused into CTA gating but is not separately visualized on `ResultScreen`; the task only required gating.
- Flutter reports newer incompatible dependency versions during resolution; this is pre-existing and does not fail verification.
