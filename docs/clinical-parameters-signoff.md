# Clinical Parameters: Sign-off Sheet

<!-- GENERATED from config/clinical_parameters.json by scripts/generate_clinical_params.py. Do not edit by hand. -->

**Parameters version:** `2026-11-06-draft`  
**Status:** PLACEHOLDER: not yet clinically signed off

Every number the system uses to judge risk or run dispatch is listed here. **None has been clinically approved.** To change a value, mark up this sheet; engineering then updates `config/clinical_parameters.json` and regenerates it, which updates the app and the server together.

## 1. Questions for the clinical lead

Please answer these first, because they can change the numbers below.

1. **Are children in scope?** These bands are adult obstetric. A healthy toddler or newborn can score RED, and the app doesn't record age. Should children use a separate paediatric scale, or be left out of the pilot?
2. **Is a single score of 1 enough for Yellow?** A temperature of exactly 36.0 °C, or a heart rate of exactly 60, makes a patient Yellow with no other sign. Is that intended?
3. **Which band should a boundary value fall in?** The spec's bands overlap at their edges (SBP 90, for example, is in two). The system uses the higher score. Is that right?
4. **Should diastolic BP below 60 be RED?** The spec table has no low diastolic band. The system adds one, scoring it 3.
5. **Is the handling of missing vitals in section 4 right?** In particular: a patient with every vital measured except SpO₂ can still be GREEN, with a visible note.

## 2. Vital sign entry limits

These catch typing errors and impossible readings. They do not judge risk. Values outside them are refused by both the app and the API.

| Vital | Lowest | Highest | Unit | Approved value | Initials |
|---|---|---|---|---|---|
| Systolic BP | 0 | 300 | mmHg | | |
| Diastolic BP | 0 | 200 | mmHg | | |
| Heart rate | 0 | 300 | bpm | | |
| Respiratory rate | 0 | 120 | breaths/min | | |
| Temperature | 20 | 45 | °C | | |
| SpO₂ | 0 | 100 | % | | |

## 3. MOEWS scoring bands

From spec §9.3. A value that falls in no band below scores 0.

| Vital | Score 3: below | Score 1: low | Score 1: high | Score 3: above | Unit | Approved | Initials |
|---|---|---|---|---|---|---|---|
| Systolic BP | <80 | 80–90 | 140–150 | >150 | mmHg | | |
| Diastolic BP | <60 | — | 90–100 | >100 | mmHg | | |
| Heart rate | <50 | 50–60 | 110–130 | >130 | bpm | | |
| Respiratory rate | <10 | 10–14 | 24–30 | >30 | breaths/min | | |
| Temperature | <35 | 35–36 | 38–39 | >39 | °C | | |
| SpO₂ | <90 | 90–94 | — | — | % | | |
| Consciousness (AVPU) | V, P or U scores 3 | — | — | — | — | | |

## 4. How the risk level is decided

The first matching row applies. All scoring uses measured vitals only.

| Result | When | Approved | Initials |
|---|---|---|---|
| **RED** | Any measured vital scores 3, or measured scores total 5 or more, even if other vitals are missing | | |
| **Incomplete** | Otherwise, if any of these wasn't measured: systolic BP, diastolic BP, heart rate, respiratory rate, temperature or AVPU. The missing vitals are listed. Never reported as GREEN | | |
| **YELLOW** | Otherwise, if measured scores total 3 or more, or any vital scores 1 | | |
| **GREEN** | Otherwise. SpO₂ is optional: if it wasn't measured, the result shows "SpO₂ not measured" | | |
| **UNKNOWN** | The CHO chose "Emergency: skip vitals". Dispatch goes ahead at once, flagged "vitals not taken" | | |

## 5. Operational and other settings

| Setting | Value | Unit | Owner | What it does | Notes | Approved | Initials |
|---|---|---|---|---|---|---|---|
| Wait per cascade tier | **90** | seconds | Operations | How long drivers in a tier get before the next tier is alerted. | From spec §7.2.1. Not tested against real driver response times. | | |
| Shortest wait allowed in the field | **60** | seconds | Operations | Staging and production refuse to start below this. | Engineering guard chosen during the safety fixes. | | |
| Late-claim window | **45** | minutes | Operations | How long after dispatch start a notified driver can still claim once the cascade has failed. | 45 minutes: by 2 hours the CHO has almost certainly arranged transport, and a late accept adds confusion and triggers the stipend. Please confirm against field experience. | | |
| Longest dispatch waits for the assessment | **3** | seconds | Operations | After this, dispatch goes ahead using MOEWS alone, without the protocol summary. | Engineering choice. Patient risk is unaffected: MOEWS is always calculated. | | |
| ETA shown to the CHO | **30** | minutes | Operations | Shown as the ETA once a driver accepts. | NOT a real estimate: the same number for every trip. It should be replaced or hidden. | | |
| Fuel stipend recorded on accept | **22.5** | GHS | Finance / funder | Mock ledger entry only; no money moves. | 30% of an assumed GHS 75 fare. There is no fare calculation yet. | | |
| Acoustic score for Code Red | **0.7** | 0–1 score | Clinical lead | Above this, acoustic screening reports RED. | From spec §7.1.1. Off by default and not clinically validated. | | |
| Acoustic score reported as Inconclusive | **0.5** | 0–1 score | Clinical lead | Below this, acoustic screening reports Inconclusive. | From spec §7.1.1. YAMNet never reports GREEN, because its score never measured normal. | | |
| OPERA-CE probability for GREEN | **0.7** | 0–1 probability | Clinical lead | Would apply only if a trained OPERA-CE classifier is ever shipped. | Not in use: no trained classifier ships. | | |
| Recording length | **15** | seconds | Clinical lead | Default capture length when acoustic screening is enabled. | Spec §7.1.1 says 60 seconds; the app default is 15. Please decide. | | |
| Highest gestational age accepted | **45** | weeks | Clinical lead | The API rejects anything above this. | Typo guard only. | | |
| Device heart rate, lowest accepted | **30** | bpm | Clinical lead | Plausibility check on a typed-in device reading. | Typo guard only. | | |
| Device heart rate, highest accepted | **250** | bpm | Clinical lead | Plausibility check on a typed-in device reading. | Typo guard only. | | |
| Device SpO₂, lowest accepted | **50** | % | Clinical lead | Plausibility check on a typed-in device reading. | Typo guard only. | | |
| Device SpO₂, highest accepted | **100** | % | Clinical lead | Plausibility check on a typed-in device reading. | Typo guard only. | | |
| Facility list refresh warning | **30** | days | Operations | The app warns when its facility list is older than this. | Engineering choice. | | |

## 6. Known conflicts outside this file

- `src/rag/engine.py` contains demo protocol text with different thresholds (MOEWS ≥6, SBP ≥160, HR ≥120, SpO₂ <92), and that text can appear in a referral's stored summary. It does not affect the risk level. Real GHS protocol text should replace it.
- `data/ghs_protocols/moews_and_referral_rules.md` restates the bands for the same demo corpus and has to be kept in step by hand.

## Sign-off

| Role | Name | Signature | Date |
|---|---|---|---|
| Clinical lead | | | |
| Operations lead | | | |
| GHS representative | | | |
