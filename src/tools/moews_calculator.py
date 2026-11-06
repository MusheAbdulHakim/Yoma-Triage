"""
Deterministic Modified Obstetric Early Warning Score (MOEWS) calculator.
"""

from langchain_core.tools import tool

from src.clinical_params import PARAMS


def _score_band(vital: str, value: float) -> int:
    band = PARAMS["moews_bands"][vital]
    if (band["red_below"] is not None and value < band["red_below"]) or (
        band["red_above"] is not None and value > band["red_above"]
    ):
        return 3
    for span in (band["yellow_low"], band["yellow_high"]):
        if span and span[0] <= value <= span[1]:
            return 1
    return 0


def _score_consciousness(consciousness: str) -> int:
    if consciousness.upper() != "A":
        return 3
    return 0


# SpO2 is optional: without it a complete set can still be scored, but the result
# must say it wasn't measured. Every other vital is needed before calling a patient
# anything other than RED or INCOMPLETE.
OPTIONAL_VITALS = frozenset({"spo2"})
VITAL_ORDER = (
    "systolic_bp",
    "diastolic_bp",
    "heart_rate",
    "respiratory_rate",
    "temperature",
    "spo2",
    "consciousness_level",
)


def missing_vitals(vitals: dict | None) -> list[str]:
    """Vitals that were not measured, in a stable order."""
    vitals = vitals or {}
    return [name for name in VITAL_ORDER if vitals.get(name) is None]


def _risk_level(scores: list[int], total: int, missing: list[str]) -> str:
    risk = PARAMS["moews_risk"]
    # A measured critical value is never hidden by what wasn't measured.
    if any(s == risk["red_parameter_score"] for s in scores) or total >= risk["red_total"]:
        return "RED"
    # A patient can't be called normal from half a set.
    if any(name not in OPTIONAL_VITALS for name in missing):
        return "INCOMPLETE"
    if total >= risk["yellow_total"] or any(s == 1 for s in scores):
        return "YELLOW"
    return "GREEN"


def score_vitals(
    sbp: int | None,
    dbp: int | None,
    hr: int | None,
    rr: int | None,
    temp: float | None,
    spo2: int | None = None,
    consciousness: str | None = "A",
) -> dict:
    """Score what was measured. Plain function, no I/O: it can always run."""
    measured = {
        "systolic_bp": sbp,
        "diastolic_bp": dbp,
        "heart_rate": hr,
        "respiratory_rate": rr,
        "temperature": temp,
        "spo2": spo2,
    }
    scores = [_score_band(name, value) for name, value in measured.items() if value is not None]
    if consciousness is not None:
        scores.append(_score_consciousness(consciousness))
    missing = missing_vitals({**measured, "consciousness_level": consciousness})
    total = sum(scores)
    return {
        "moews_score": total if scores else None,
        "risk_level": _risk_level(scores, total, missing),
        "missing_vitals": missing,
    }


@tool
def calculate_moews(
    sbp: int | None,
    dbp: int | None,
    hr: int | None,
    rr: int | None,
    temp: float | None,
    spo2: int | None = None,
    consciousness: str | None = "A",
) -> dict:
    """
    Calculates the MOEWS risk score based on Ghana Health Service clinical thresholds.

    Vital bands come from config/clinical_parameters.json.

    Only measured vitals are scored:
    - RED: any measured parameter scores 3, or measured scores total 5 or more.
    - INCOMPLETE: otherwise, if any vital except SpO2 is missing.
    - YELLOW: otherwise, total 3-4 or any parameter scoring 1.
    - GREEN: otherwise. The result lists SpO2 as missing if it wasn't measured.
    """
    return score_vitals(sbp, dbp, hr, rr, temp, spo2, consciousness)
