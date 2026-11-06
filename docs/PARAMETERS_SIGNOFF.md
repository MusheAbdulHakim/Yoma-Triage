# Clinical and Operational Parameters: Sign-off

**None of these values has been clinically approved.** Each is listed with where it came from. To change one, mark it up here; engineering then updates `src/parameters.py` and `mobile/lib/parameters.dart`. A test fails if the two disagree, or if this sheet no longer matches them.

## Questions for the clinical lead

Please answer these first, because they can change the numbers below.

1. **Are children in scope?** These bands are adult obstetric. A healthy toddler or newborn can score RED, and the app doesn't record age. Should children use a paediatric scale, or be left out of the pilot?
2. **Is a single score of 1 enough for Yellow?** A temperature of exactly 36.0 °C, or a heart rate of exactly 60, makes a patient Yellow with no other sign.
3. **Which band should a boundary value fall in?** The spec's bands overlap at their edges (SBP 90 is in two). The system uses the higher score.
4. **Should diastolic BP below 60 be RED?** The spec table has no low diastolic band. The system adds one, scoring it 3.
5. **Is the handling of missing vitals in "How the risk level is decided" right?** In particular: a patient with every vital measured except SpO₂ can still be GREEN, with a visible note.

## Vital sign entry limits

These catch typing errors and impossible readings. They don't judge risk. Both the app and the API refuse values outside them.

| Vital | Lowest | Highest | Unit | Comes from | Sign-off |
|---|---|---|---|---|---|
| Systolic BP | 0 | 300 | mmHg | Engineering placeholder (batch 1) | |
| Diastolic BP | 0 | 200 | mmHg | Engineering placeholder (batch 1) | |
| Heart rate | 0 | 300 | bpm | Engineering placeholder (batch 1) | |
| Respiratory rate | 0 | 120 | breaths/min | Engineering placeholder (batch 1) | |
| Temperature | 20 | 45 | °C | Engineering placeholder (batch 1) | |
| SpO₂ | 0 | 100 | % | Engineering placeholder (batch 1) | |

## MOEWS scoring bands

A value in no band below scores 0. A boundary value takes the higher score.

| Vital | Score 3: below | Score 1: low | Score 1: high | Score 3: above | Unit | Comes from | Sign-off |
|---|---|---|---|---|---|---|---|
| Systolic BP | <80 | 80–90 | 140–150 | >150 | mmHg | Spec §9.3 | |
| Diastolic BP | <60 | — | 90–100 | >100 | mmHg | Spec §9.3, except <60, which engineering added | |
| Heart rate | <50 | 50–60 | 110–130 | >130 | bpm | Spec §9.3 | |
| Respiratory rate | <10 | 10–14 | 24–30 | >30 | breaths/min | Spec §9.3 | |
| Temperature | <35 | 35–36 | 38–39 | >39 | °C | Spec §9.3 | |
| SpO₂ | <90 | 90–94 | — | — | % | Spec §9.3 | |
| Consciousness (AVPU) | V, P or U | — | — | — | — | Spec §9.3 | |

## How the risk level is decided

The first matching row applies. Only measured vitals are scored.

| Rule | Value | Meaning | Comes from | Sign-off |
|---|---|---|---|---|
| RED: score of one measured vital | 3 | Any measured vital scoring this is RED, even if others are missing | Spec §9.3; missing-vitals rule set by the product owner (batch 2) | |
| RED: total of measured scores | 5 | This total or more is RED, even if others are missing | Spec §9.3; missing-vitals rule set by the product owner (batch 2) | |
| INCOMPLETE: any required vital missing | n/a | Otherwise, if any vital except SpO₂ wasn't measured. The missing vitals are listed. Never GREEN | Product owner (batch 2) | |
| YELLOW: total of measured scores | 3 | This total or more, or any vital scoring 1 | Spec §9.3 | |
| GREEN | n/a | Otherwise. If SpO₂ wasn't measured, the result says "SpO₂ not measured" | Spec §9.3; note set by the product owner (batch 2) | |
| UNKNOWN | n/a | The CHO chose "Emergency: skip vitals". Dispatch goes ahead at once, flagged vitals not taken | Product owner (batch 2) | |

## Operational settings

| Setting | Value | Unit | What it does | Comes from | Sign-off |
|---|---|---|---|---|---|
| Wait per cascade tier | 90 | seconds | How long drivers in a tier get before the next tier is alerted. `CASCADE_TIER_SECONDS` overrides it | Spec §7.2.1. Not tested against real driver response times | |
| Shortest tier wait allowed in the field | 60 | seconds | Staging and production refuse to start below this | Engineering placeholder (batch 1) | |
| Late-claim window | 45 | minutes | How long after dispatch start a notified driver can still claim a failed dispatch. `LATE_CLAIM_WINDOW_MINUTES` overrides it | Product owner (batch 2) | |
| Stale queued referral | 20 | minutes | A referral that waited longer than this on the phone isn't dispatched until the CHO says it's still needed. `STALE_AFTER_MINUTES` overrides it | Engineering placeholder (batch 4) | |
| Cascade worker poll interval | 5 | seconds | How often overdue cascade steps are looked for, so a tier can run up to this much late. `WORKER_POLL_SECONDS` overrides it | Product owner (batch 2, B2) | |
| SMS outbox poll interval | 2 | seconds | How often waiting SMS are sent, so an SMS can leave up to this much after its commit. `OUTBOX_POLL_SECONDS` overrides it | Engineering placeholder (batch 2, B3) | |
| SMS send attempts before giving up | 5 | attempts | After this, the message is marked failed. If it was to a driver or hospital, the CHO is alerted | Engineering placeholder (batch 2, B3) | |
| SMS retry backoff | 15 | seconds | Wait before the first retry, doubling each time (15, 30, 60, 120 s). A failing SMS takes about 4 minutes to reach the CHO alert | Engineering placeholder (batch 2, B3) | |
| SMS claim lease | 60 | seconds | If the server dies mid-send, the message is retried after this. The SMS may then be sent twice | Engineering placeholder (batch 2, B3) | |
| SMS batch size | 20 | messages | The most SMS sent before the sender waits for its next poll | Engineering placeholder (batch 2, B3) | |
| SMS sent at once | 5 | messages | The most SMS sent in parallel. `OUTBOX_SEND_CONCURRENCY` overrides it | Engineering placeholder (batch 4) | |
| SMS send time limit | 5 | seconds | A send that takes longer counts as failed and is retried, so the SMS may be sent twice. `OUTBOX_SEND_TIMEOUT_SECONDS` overrides it | Engineering placeholder (batch 4) | |
| ETA shown to the CHO | 30 | minutes | Shown once a driver accepts. **Not a real estimate: the same number for every trip** | Hardcoded in the original demo | |
| Fuel stipend recorded on accept | 22.5 | GHS | Mock ledger entry only; no money moves. 30% of an assumed GHS 75 fare | Spec §7.4 demo figure | |
| Highest gestational age accepted | 45 | weeks | The API refuses anything above this. Typo guard only | Engineering placeholder (batch 1) | |
| Acoustic score for Code Red | 0.7 | 0–1 score | Above this, acoustic screening reports RED. Off by default, not clinically validated | Spec §7.1.1 | |
| Acoustic score reported as Inconclusive | 0.5 | 0–1 score | Below this, acoustic screening reports Inconclusive | Spec §7.1.1 | |
| OPERA-CE probability for GREEN | 0.7 | 0–1 probability | Applies only if a trained OPERA-CE classifier ever ships. Not in use | Engineering placeholder | |
| Recording length | 15 | seconds | Default capture length when acoustic screening is enabled. Spec §7.1.1 says 60 | Engineering placeholder | |
| Device heart rate, lowest accepted | 30 | bpm | Plausibility check on a typed-in device reading | Engineering placeholder | |
| Device heart rate, highest accepted | 250 | bpm | Plausibility check on a typed-in device reading | Engineering placeholder | |
| Device SpO₂, lowest accepted | 50 | % | Plausibility check on a typed-in device reading | Engineering placeholder | |
| Device SpO₂, highest accepted | 100 | % | Plausibility check on a typed-in device reading | Engineering placeholder | |
| Facility list refresh warning | 30 | days | The app warns when its facility list is older than this | Engineering placeholder | |

## Sign-off

| Role | Name | Signature | Date |
|---|---|---|---|
| Clinical lead | | | |
| Operations lead | | | |
| GHS representative | | | |
