"""Deterministic hospital-facing summary. States facts only, and never gives advice."""
from __future__ import annotations

from src.tools.moews_calculator import missing_vitals

_VITAL_LABELS = (
    ("systolic_bp", "SBP"),
    ("diastolic_bp", "DBP"),
    ("heart_rate", "HR"),
    ("respiratory_rate", "RR"),
    ("temperature", "Temp"),
    ("spo2", "SpO2"),
    ("consciousness_level", "AVPU"),
)


def build_clinical_summary(
    *,
    emergency_type: str,
    risk_level: str,
    moews_score: int | None,
    vitals: dict,
    vitals_taken: bool = True,
) -> str:
    if not vitals_taken:
        return f"Emergency: {emergency_type}. Risk: {risk_level}. Vitals not taken."
    score = "" if moews_score is None else f" (MOEWS {moews_score})"
    measured = [
        f"{label} {vitals[name]}" for name, label in _VITAL_LABELS if vitals.get(name) is not None
    ]
    parts = [f"Emergency: {emergency_type}.", f"Risk: {risk_level}{score}."]
    if measured:
        parts.append(f"Vitals: {', '.join(measured)}.")
    missing = missing_vitals(vitals)
    if missing:
        parts.append(f"Not measured: {', '.join(missing)}.")
    return " ".join(parts)
