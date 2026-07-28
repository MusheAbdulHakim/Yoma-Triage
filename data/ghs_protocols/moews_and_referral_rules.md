# Ghana Health Service Emergency Referral & MOEWS Protocol
# Demo corpus for Yoma Triage RAG (not an official GHS PDF substitute).
#
# AUTHORITATIVE for this repo's calculator: `src/tools/moews_calculator.py`
# and `mobile/lib/services/moews_calculator.dart` (locked product rule).
# This file MUST stay aligned with those implementations.

## 1. MOEWS thresholds (as implemented in Yoma Triage)

Risk level (locked):
- **RED** if any single vital score is **3**, OR total score **≥ 5**
- **YELLOW** if total **≥ 3** or any score is **1** (and not RED)
- **GREEN** otherwise

Per-vital bands (score 0 / 1 / 3):

| Vital | Score 3 | Score 1 | Score 0 |
|-------|---------|---------|---------|
| Systolic BP | &lt;80 or &gt;150 | 80–90 or 140–150 | 91–139 |
| Diastolic BP | &lt;60 or &gt;100 | 90–100 | 60–89 |
| Heart rate | &lt;50 or &gt;130 | 50–60 or 110–130 | 61–109 |
| Respiratory rate | &lt;10 or &gt;30 | 10–14 or 24–30 | 15–23 |
| Temperature °C | &lt;35 or &gt;39 | 35–36 or 38–39 | 36.1–37.9 |
| SpO2 % | &lt;90 | 90–94 | ≥95 |
| Consciousness | not Alert (AVPU ≠ A) | — | Alert (A) |

Acoustic screening is **advisory only**. Acoustic GREEN must **never** downgrade MOEWS RED or YELLOW.

## 2. Northern Region transport protocol (Networks of Practice)
- CHPS compounds in rural sub-districts must route emergency transfers via local Motor-King tricycle ambulances when district hospital ambulances are unavailable.
- **Pilot / demo:** fuel stipend is recorded on a **mock ledger** after USSD accept. Live MTN MoMo disbursement requires merchant keys and is not claimed as completed by the app until that integration is live.
- Remaining 70% balance is a production design target when hospital confirms arrival — not implemented as a real payout yet.

## 3. Obstetric haemorrhage at CHPS
- For suspected PPH or antepartum bleeding with shock (low SBP, tachycardia): IV fluids, keep warm, urgent referral — do not wait for labs.
