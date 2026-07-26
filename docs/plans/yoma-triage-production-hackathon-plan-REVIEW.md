# Review — Yoma Triage Production-Close Hackathon Plan

## Verdict: APPROVE WITH CHANGES

## Summary

The plan has the right strategic cut: prove the deterministic MOEWS/referral/dispatch path, label acoustic screening honestly, and defer SLM, TTS, real MoMo, production auth, and clinical model claims. It was not ready to execute as written. Repository verification found a failing Flutter baseline, an insufficient name-derived token proposal, raw names persisted in the offline outbox, absent web CORS, a duplicate proposed timeline endpoint, incomplete rebrand inventory, and an inaccurate description of both voice and YAMNet behavior.

The original plan has been patched with concrete amendments. Implementation must still wait for product-owner approval and the four blocking choices in §11.

## Findings

### Blocker — Current Flutter baseline is red

Evidence:

- `mobile/lib/main.dart` defines `YomaApp`.
- `mobile/test/widget_test.dart` and `mobile/test/simulator_flow_test.dart` instantiate nonexistent `RelayApp`.
- A fresh `flutter test` on 2026-07-26 failed at compile time for those three uses; only seven tests reached/pass status.

Concrete fix:

- Execute new Task W0.0 first: preserve the observed failure, replace stale test constructors, and require the full pre-existing Flutter suite to pass before feature work.
- Do not describe mobile as verified/green until this succeeds.

### Blocker — Original privacy task replaced one weak identifier with another

Evidence:

- `mobile/lib/screens/referral_screen.dart` currently uses `hash-${name.hashCode}`.
- The original plan proposed deterministic SHA-256 of a normalized patient name. Common names are low entropy, so that digest is dictionary-attackable and linkable across referrals.
- `mobile/lib/models/referral.dart` serializes `patient_name`.
- `mobile/lib/services/offline_queue.dart` persists that name in SQLite or SharedPreferences.
- `src/api/referral.py` stores and echoes the name and accepts any nonempty `patient_hash`, not a 64-character SHA-256 value.
- `src/services/hospital_notifier.py` sends the raw name by SMS.

Concrete fix applied to plan:

- Generate cryptographically random per-referral material and SHA-256 it; never derive the token from name, phone, or DOB.
- Reuse the same token for retries with the same `client_request_id`.
- Remove `patient_name` from mobile serialization/outbox and API responses; use `Unknown` in the current backend until an encrypted identity design is approved.
- Validate exactly 64 lowercase hex at the API boundary.
- Add mobile, backend, persistence, and hospital-message privacy tests.

### Blocker — Flutter web stage path has no CORS support

Evidence:

- `mobile/lib/config.dart` sends web requests to `http://127.0.0.1:8000`.
- Flutter web runs from a different browser origin.
- `main.py` includes no `CORSMiddleware`.

Concrete fix applied to plan:

- New Task B0 adds a configurable explicit demo-origin allowlist, preflight test, README startup instructions, and an actual browser smoke.
- Wildcard production CORS is not acceptable.

### Major — YAMNet behavior was overstated

Evidence:

- No model exists at `mobile/assets/models/yamnet.tflite`.
- `mobile/lib/services/yamnet_classifier_io.dart::_abnormalScore` averages the top five values across 521 AudioSet outputs without loading/selecting respiratory class labels.
- Therefore, even adding official YAMNet weights would not make the current value a defensible “generic respiratory anomaly proxy.”

Concrete fix applied to plan:

- Simulator/stub remains the recommended demo path.
- Any YAMNet asset is a local-inference technical smoke only.
- The “not clinically validated” disclaimer is mandatory for every source; stub/simulator receives an additional demo-mode label.
- No environment flag may remove the disclaimer.

### Major — Proposed observability endpoint duplicated existing code

Evidence:

- `src/api/referral.py` already implements `GET /api/v1/dispatch/{dispatch_id}/logs`.
- `scripts/demo_flow.py` already consumes it.

Concrete fix applied to plan:

- Task B4 now extends the existing logs route test and demo script with arrival/privacy assertions.
- Removed `src/api/demo_ops.py` and the proposed duplicate unauthenticated timeline route from scope.

### Major — Rebrand inventory was incomplete and its grep would miss failures

Evidence:

- The original case-sensitive expression found RelayCare/RelayDispatch docs but missed:
  - `RelayApp` in two Flutter test files.
  - `RELAY-` in `src/tools/momo_escrow.py`.
- Those stale test identifiers currently break the suite.
- Package/application identities are already `yoma_triage` and `gh.yomatriage.yoma_triage`; those claims were accurate.

Concrete fix applied to plan:

- Use case-insensitive `rg -ni 'relay'`.
- Include tests and MoMo external-id prefix in W0.
- Preserve intentional historical mentions only in review/changelog context.

### Major — Active product specs contradict the honest demo cut

Evidence:

- `PRODUCT_SPEC.md` and `docs/yoma-triage-product-spec.md` still claim Phase 1 ships an on-device SLM and YAMNet clinical flow.
- Their architecture diagram visually routes mobile SMS to Africa's Talking despite the backend-only rule.
- They include patient names in SMS examples while also claiming names are never stored.
- They describe SQLCipher, pinning, encrypted telemetry, TTS, and other production controls as if implemented.

Concrete fix applied to plan:

- New Task W0.2 reconciles Phase 1, architecture, privacy examples, and production backlog language in both active specs.

### Major — Voice and arrival behavior needed accurate state/timeout design

Evidence:

- `src/services/dispatch_orchestrator.py` never calls `MessagingGateway.initiate_voice`; voice is absent from the cascade, not merely failed when configured.
- `src/api/ussd.py` currently resolves claimable or `ACCEPTED` dispatches only. After accept side effects, status becomes `HOSPITAL_NOTIFIED`; after hospital reply it becomes `HOSPITAL_CONFIRMED`.
- External messaging must not block the USSD response.

Concrete fix applied to plan:

- Corrected the voice audit.
- Arrival resolves only the assigned driver's `HOSPITAL_NOTIFIED`/`HOSPITAL_CONFIRMED` dispatch.
- The locked state transition stays in-request; CHO notification is an idempotent background side effect.
- Tests cover wrong driver, premature arrival, duplicate arrival, and duplicate logs.
- The demo must not claim the deferred production 70% payout.

### Major — Several tasks were not genuinely test-first

Evidence:

- Original M1, M4, M5, and M6 lacked an explicit failing test and/or objective acceptance contract.
- M7 introduced optional navigation refactoring with no demonstrated demo need.

Concrete fix applied to plan:

- Added failing widget/contract tests and measurable acceptance criteria.
- Deferred navigation refactoring.

### Minor — Route documentation needed one canonical inventory

Verified routes:

- `POST /api/v1/referral`
- `GET /api/v1/referral/{id}`
- `GET /api/v1/dispatch/{id}`
- `GET /api/v1/dispatch/{id}/logs`
- `POST /ussd/callback`
- `POST /api/v1/sms/inbound`
- `POST /api/v1/driver/{id}/availability`
- `GET /api/v1/compound/{id}/drivers`

Not implemented:

- `GET /api/v1/driver/{id}/status`
- `POST /api/v1/ussd/callback`
- Voice callback
- Separate demo timeline route

Concrete fix applied to plan:

- Added the canonical route table and made `/ussd/callback` the safe default. No alias is added without an explicit product-owner decision.

### Minor — SMS segment claim was unmeasured

The 6-byte Base64 telemetry codec in `src/tools/sms_codec.py` fits easily. The human-readable multi-line hospital notification is a separate operational SMS and was merely described as “short”; its GSM-7/UCS-2 segment count was not measured.

Concrete fix applied to plan:

- Require an encoded-length assertion or explicitly disclose multipart operational SMS as a demo limitation.
- Raw identity is prohibited in both telemetry and operational messages.

## Repository path and claim spot-checks

1. `src/services/hospital_notifier.py` exists; the plan correctly found the raw `referral.patient_name` SMS leak.
2. `mobile/lib/screens/referral_screen.dart` exists; it uses the weak Dart `hashCode` scheme exactly as claimed.
3. `mobile/assets/models/.gitkeep` exists and no `yamnet.tflite` is present.
4. `src/api/ussd.py` exists and mounts `/ussd/callback`, not `/api/v1/ussd/callback`.
5. `src/api/sms_webhook.py` exists and mounts `/api/v1/sms/inbound`.
6. `src/api/driver.py` exists and exposes POST availability plus GET compound drivers; no GET driver-status route exists.
7. `src/api/referral.py` exists and already exposes dispatch logs, making the original B4 endpoint redundant.
8. `data/demo_data.json` exists and IDs 1/1 are Tamale South CHPS/Tamale Teaching Hospital.
9. `scripts/demo_flow.py` exists and already exercises referral, USSD, mock MoMo logs, hospital confirm/divert, and the existing logs endpoint.
10. `mobile/lib/screens/dispatch_status_screen.dart` already treats `COMPLETED` as terminal, but it does not rebound a synced queued request to a dispatch ID.

Result: paths are repository-specific, but several original factual claims were inaccurate; checklist item 1 therefore fails until the applied amendments are accepted.

## Checklist results

1. **Real repo paths and accurate claims — FAIL (amended).** More than five paths were real and useful, but timeline, voice, test-suite, YAMNet, and rebrand claims contained factual errors.
2. **Privacy gaps identified/actionable — FAIL (amended).** SMS leak was correct; original name-derived SHA-256 and retained raw outbox/API name were insufficient.
3. **Honest audio/language strategy — FAIL (amended).** Deferral of trained/local assets was honest, but current YAMNet scoring was falsely characterized as an anomaly proxy.
4. **Demo vs production cut — PASS.** SLM, Dagbani TTS/recordings, real MoMo, production shortcode/auth, and hospital dashboard are clearly deferred.
5. **Rebrand inventory complete — FAIL (amended).** It missed `RelayApp` and `RELAY-`; case-insensitive inventory is now required.
6. **E2E routes match code — PASS WITH CORRECTION.** Core flow routes were right; the patched canonical inventory now explicitly records driver routes and absent aliases/endpoints.
7. **`.cursorrules` constraints preserved — FAIL (amended).** MOEWS, HITL, backend-mediated AT, mock MoMo, and test-first intent were preserved; original privacy token/outbox design and unmeasured SMS assertion were not strong enough.
8. **Bite-sized/test-first/acceptance criteria — FAIL (amended).** Core privacy/arrival tasks were good, but polish/offline/facility tasks were incomplete; explicit tests and criteria were added.
9. **Critical demo gaps adequately weighted — FAIL (amended).** Failing Flutter baseline, CORS, browser smoke, and product-spec contradictions were missing.
10. **Hackathon scope appropriate — FAIL (amended).** Original scope overreached with duplicate timeline API, optional navigation refactor, and YAMNet “boost,” while under-scoping stage reliability. The patched ordering is materially better.

## Required plan amendments

Applied to the original plan:

1. **Top changelog:** records review corrections and approval block.
2. **§2 Current State Audit:** correct Flutter baseline, voice, token/outbox, CORS, logs, and YAMNet facts.
3. **§3 Rebrand Inventory:** add `RelayApp`, `RELAY-`, and case-insensitive gate.
4. **§4 Demo/Production Cut:** token-only transport and existing observability route.
5. **§5 Audio Strategy:** make YAMNet asset a technical smoke, not clinical/anomaly evidence.
6. **§7 E2E:** add canonical routes, CORS, baseline, and existing-log hardening.
7. **§8 Touch Map:** remove duplicate demo endpoint; add API validation/CORS/name-removal files.
8. **§9 W0:** add baseline repair and active-spec reconciliation.
9. **§9 W1:** replace name-derived hash with random per-referral SHA-256 token; remove names from outbox/API.
10. **§9 W2:** mandatory disclaimer for all sources.
11. **§9 W3:** add CORS/startup task; make arrival state-safe, idempotent, and nonblocking; reuse logs route.
12. **§9 W4:** add test-first criteria and defer navigation refactor.
13. **§9 W5:** require full suites, browser smoke, and offline reconnect rehearsal.
14. **§10 Risks:** distinguish compact telemetry from operational SMS and require segment measurement.
15. **§11 Open Questions:** identify Q1/Q2/Q3/Q10 as blocking and record safe defaults for privacy, arrival, and route alias.
16. **§12–13:** prioritize baseline/privacy/CORS and strengthen the test-first self-review.

## Questions still blocking product owner

The parent should ask these before dispatching implementation:

1. What is the exact stage target: Flutter web, Android emulator, or physical Android device?
2. Must Africa's Talking run live, or is mock plus simulator the accepted success bar?
3. Should YAMNet remain simulator/stub-only as recommended, or is a non-clinical TFLite load smoke required?
4. Is the final naming “Yoma Care/Yoma Dispatch” or simply “CHO app/dispatch gateway”?

Useful but not blocking the first safety/reliability tasks:

- Confirm demo geography.
- Confirm whether any Dagbani copy must appear.
- Confirm whether the submission also requires a written Phase 2 architecture narrative.

## May implementation start?

**No.** `APPROVE WITH CHANGES` does not authorize implementation.

Must fix before implementation:

1. Product owner reviews and approves the amended plan.
2. Product owner answers §11 Q1, Q2, Q3, and Q10.
3. The implementation dispatcher accepts W0.0 → W0.1/W0.2 → W1/B0 as the mandatory first sequence, with no feature code started from this review.

