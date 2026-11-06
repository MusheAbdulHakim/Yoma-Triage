#!/usr/bin/env python3
"""Generate the Dart constants and sign-off sheet from config/clinical_parameters.json.

Run after any parameter change. tests/test_clinical_params.py fails if the generated
files are out of date.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config" / "clinical_parameters.json"
DART_OUTPUT = ROOT / "mobile" / "lib" / "generated" / "clinical_parameters.dart"
SHEET_OUTPUT = ROOT / "docs" / "clinical-parameters-signoff.md"

VITAL_LABELS = {
    "systolic_bp": "Systolic BP",
    "diastolic_bp": "Diastolic BP",
    "heart_rate": "Heart rate",
    "respiratory_rate": "Respiratory rate",
    "temperature": "Temperature",
    "spo2": "SpO₂",
}

# (section, key, label, unit, owner, used for, what the reviewer should know)
SETTINGS = [
    ("dispatch", "cascade_tier_seconds", "Wait per cascade tier", "seconds", "Operations",
     "How long drivers in a tier get before the next tier is alerted.",
     "From spec §7.2.1. Not tested against real driver response times."),
    ("dispatch", "min_field_cascade_tier_seconds", "Shortest wait allowed in the field", "seconds",
     "Operations", "Staging and production refuse to start below this.",
     "Engineering guard chosen during the safety fixes."),
    ("dispatch", "late_claim_window_minutes", "Late-claim window", "minutes", "Operations",
     "How long after dispatch start a notified driver can still claim once the cascade has failed.",
     "45 minutes: by 2 hours the CHO has almost certainly arranged transport, and a late accept "
     "adds confusion and triggers the stipend. Please confirm against field experience."),
    ("dispatch", "clinical_assessment_timeout_seconds", "Longest dispatch waits for the assessment",
     "seconds", "Operations",
     "After this, dispatch goes ahead using MOEWS alone, without the protocol summary.",
     "Engineering choice. Patient risk is unaffected: MOEWS is always calculated."),
    ("dispatch", "placeholder_eta_minutes", "ETA shown to the CHO", "minutes", "Operations",
     "Shown as the ETA once a driver accepts.",
     "NOT a real estimate: the same number for every trip. It should be replaced or hidden."),
    ("payments", "fuel_stipend_ghs", "Fuel stipend recorded on accept", "GHS", "Finance / funder",
     "Mock ledger entry only; no money moves.",
     "30% of an assumed GHS 75 fare. There is no fare calculation yet."),
    ("acoustic", "red_above", "Acoustic score for Code Red", "0–1 score", "Clinical lead",
     "Above this, acoustic screening reports RED.",
     "From spec §7.1.1. Off by default and not clinically validated."),
    ("acoustic", "inconclusive_below", "Acoustic score reported as Inconclusive", "0–1 score",
     "Clinical lead", "Below this, acoustic screening reports Inconclusive.",
     "From spec §7.1.1. YAMNet never reports GREEN, because its score never measured normal."),
    ("acoustic", "opera_green_above", "OPERA-CE probability for GREEN", "0–1 probability",
     "Clinical lead", "Would apply only if a trained OPERA-CE classifier is ever shipped.",
     "Not in use: no trained classifier ships."),
    ("acoustic", "default_screening_seconds", "Recording length", "seconds", "Clinical lead",
     "Default capture length when acoustic screening is enabled.",
     "Spec §7.1.1 says 60 seconds; the app default is 15. Please decide."),
    ("referral_input", "gestational_weeks_max", "Highest gestational age accepted", "weeks",
     "Clinical lead", "The API rejects anything above this.", "Typo guard only."),
    ("advisory_device", "heart_rate_min", "Device heart rate, lowest accepted", "bpm",
     "Clinical lead", "Plausibility check on a typed-in device reading.", "Typo guard only."),
    ("advisory_device", "heart_rate_max", "Device heart rate, highest accepted", "bpm",
     "Clinical lead", "Plausibility check on a typed-in device reading.", "Typo guard only."),
    ("advisory_device", "spo2_min", "Device SpO₂, lowest accepted", "%",
     "Clinical lead", "Plausibility check on a typed-in device reading.", "Typo guard only."),
    ("advisory_device", "spo2_max", "Device SpO₂, highest accepted", "%",
     "Clinical lead", "Plausibility check on a typed-in device reading.", "Typo guard only."),
    ("catalog", "stale_after_days", "Facility list refresh warning", "days", "Operations",
     "The app warns when its facility list is older than this.", "Engineering choice."),
]


def _camel(*parts: str) -> str:
    words = "_".join(parts).split("_")
    return words[0] + "".join(word.capitalize() for word in words[1:])


def _dart_number(value: float | int | None) -> str:
    return "null" if value is None else repr(value)


def _dart_pair(pair: list[float] | None, suffix: str) -> list[str]:
    low, high = pair if pair else (None, None)
    return [f"{suffix}Min: {_dart_number(low)}", f"{suffix}Max: {_dart_number(high)}"]


def render_dart(params: dict) -> str:
    lines = [
        "// GENERATED from config/clinical_parameters.json. Do not edit by hand.",
        "// Run: python scripts/generate_clinical_params.py",
        "",
        "class MoewsBand {",
        "  const MoewsBand({",
        "    this.redBelow,",
        "    this.yellowLowMin,",
        "    this.yellowLowMax,",
        "    this.yellowHighMin,",
        "    this.yellowHighMax,",
        "    this.redAbove,",
        "  });",
        "",
        "  final num? redBelow;",
        "  final num? yellowLowMin;",
        "  final num? yellowLowMax;",
        "  final num? yellowHighMin;",
        "  final num? yellowHighMax;",
        "  final num? redAbove;",
        "}",
        "",
        "abstract final class ClinicalParameters {",
        f"  static const version = '{params['version']}';",
        "",
    ]
    for vital, limits in params["vital_ranges"].items():
        lines.append(f"  static const {_camel(vital, 'min')} = {limits['min']};")
        lines.append(f"  static const {_camel(vital, 'max')} = {limits['max']};")
    lines.append("")
    for vital, band in params["moews_bands"].items():
        fields = [
            f"redBelow: {_dart_number(band['red_below'])}",
            *_dart_pair(band["yellow_low"], "yellowLow"),
            *_dart_pair(band["yellow_high"], "yellowHigh"),
            f"redAbove: {_dart_number(band['red_above'])}",
        ]
        lines.append(f"  static const {_camel(vital, 'band')} = MoewsBand(")
        lines.extend(f"    {field}," for field in fields)
        lines.append("  );")
    lines.append("")
    for section in ("moews_risk", "acoustic", "advisory_device", "catalog"):
        for key, value in params[section].items():
            lines.append(f"  static const {_camel(section, key)} = {value!r};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _band_range(pair: list[float] | None) -> str:
    return f"{pair[0]}–{pair[1]}" if pair else "—"


def _limit(value: float | None, symbol: str) -> str:
    return "—" if value is None else f"{symbol}{value}"


def render_sheet(params: dict) -> str:
    out = [
        "# Clinical Parameters: Sign-off Sheet",
        "",
        "<!-- GENERATED from config/clinical_parameters.json by "
        "scripts/generate_clinical_params.py. Do not edit by hand. -->",
        "",
        f"**Parameters version:** `{params['version']}`  ",
        f"**Status:** {params['status']}",
        "",
        "Every number the system uses to judge risk or run dispatch is listed here. "
        "**None has been clinically approved.** To change a value, mark up this sheet; "
        "engineering then updates `config/clinical_parameters.json` and regenerates it, "
        "which updates the app and the server together.",
        "",
        "## 1. Questions for the clinical lead",
        "",
        "Please answer these first, because they can change the numbers below.",
        "",
        "1. **Are children in scope?** These bands are adult obstetric. A healthy toddler or "
        "newborn can score RED, and the app doesn't record age. Should children use a separate "
        "paediatric scale, or be left out of the pilot?",
        "2. **Is a single score of 1 enough for Yellow?** A temperature of exactly 36.0 °C, or a "
        "heart rate of exactly 60, makes a patient Yellow with no other sign. Is that intended?",
        "3. **Which band should a boundary value fall in?** The spec's bands overlap at their "
        "edges (SBP 90, for example, is in two). The system uses the higher score. Is that right?",
        "4. **Should diastolic BP below 60 be RED?** The spec table has no low diastolic band. "
        "The system adds one, scoring it 3.",
        "5. **Is the handling of missing vitals in section 4 right?** In particular: a patient "
        "with every vital measured except SpO₂ can still be GREEN, with a visible note.",
        "",
        "## 2. Vital sign entry limits",
        "",
        "These catch typing errors and impossible readings. They do not judge risk. Values "
        "outside them are refused by both the app and the API.",
        "",
        "| Vital | Lowest | Highest | Unit | Approved value | Initials |",
        "|---|---|---|---|---|---|",
    ]
    for vital, limits in params["vital_ranges"].items():
        out.append(
            f"| {VITAL_LABELS[vital]} | {limits['min']} | {limits['max']} | {limits['unit']} | | |"
        )
    out += [
        "",
        "## 3. MOEWS scoring bands",
        "",
        "From spec §9.3. A value that falls in no band below scores 0.",
        "",
        "| Vital | Score 3: below | Score 1: low | Score 1: high | Score 3: above | Unit "
        "| Approved | Initials |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for vital, band in params["moews_bands"].items():
        out.append(
            f"| {VITAL_LABELS[vital]} | {_limit(band['red_below'], '<')} "
            f"| {_band_range(band['yellow_low'])} | {_band_range(band['yellow_high'])} "
            f"| {_limit(band['red_above'], '>')} | {band['unit']} | | |"
        )
    risk = params["moews_risk"]
    out += [
        "| Consciousness (AVPU) | V, P or U scores 3 | — | — | — | — | | |",
        "",
        "## 4. How the risk level is decided",
        "",
        "The first matching row applies. All scoring uses measured vitals only.",
        "",
        "| Result | When | Approved | Initials |",
        "|---|---|---|---|",
        f"| **RED** | Any measured vital scores {risk['red_parameter_score']}, or measured "
        f"scores total {risk['red_total']} or more, even if other vitals are missing | | |",
        "| **Incomplete** | Otherwise, if any of these wasn't measured: systolic BP, diastolic BP, "
        "heart rate, respiratory rate, temperature or AVPU. The missing vitals are listed. "
        "Never reported as GREEN | | |",
        f"| **YELLOW** | Otherwise, if measured scores total {risk['yellow_total']} or more, "
        "or any vital scores 1 | | |",
        "| **GREEN** | Otherwise. SpO₂ is optional: if it wasn't measured, the result shows "
        "\"SpO₂ not measured\" | | |",
        "| **UNKNOWN** | The CHO chose \"Emergency: skip vitals\". Dispatch goes ahead at once, "
        "flagged \"vitals not taken\" | | |",
        "",
        "## 5. Operational and other settings",
        "",
        "| Setting | Value | Unit | Owner | What it does | Notes | Approved | Initials |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for section, key, label, unit, owner, purpose, note in SETTINGS:
        value = params[section][key]
        out.append(f"| {label} | **{value}** | {unit} | {owner} | {purpose} | {note} | | |")
    out += [
        "",
        "## 6. Known conflicts outside this file",
        "",
        "- `src/rag/engine.py` contains demo protocol text with different thresholds (MOEWS ≥6, "
        "SBP ≥160, HR ≥120, SpO₂ <92), and that text can appear in a referral's stored summary. "
        "It does not affect the risk level. Real GHS protocol text should replace it.",
        "- `data/ghs_protocols/moews_and_referral_rules.md` restates the bands for the same demo "
        "corpus and has to be kept in step by hand.",
        "",
        "## Sign-off",
        "",
        "| Role | Name | Signature | Date |",
        "|---|---|---|---|",
        "| Clinical lead | | | |",
        "| Operations lead | | | |",
        "| GHS representative | | | |",
    ]
    return "\n".join(out) + "\n"


def outputs(params: dict) -> dict[Path, str]:
    return {DART_OUTPUT: render_dart(params), SHEET_OUTPUT: render_sheet(params)}


def main() -> int:
    params = json.loads(SOURCE.read_text(encoding="utf-8"))
    for path, content in outputs(params).items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
