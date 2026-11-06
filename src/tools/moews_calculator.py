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


def _risk_level(scores: list[int], total: int) -> str:
    risk = PARAMS["moews_risk"]
    if any(s == risk["red_parameter_score"] for s in scores) or total >= risk["red_total"]:
        return "RED"
    if total >= risk["yellow_total"] or any(s == 1 for s in scores):
        return "YELLOW"
    return "GREEN"


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

    Risk: any param score 3 or total ≥5 → RED; total 3–4 or any param 1 → YELLOW; 0–2 → GREEN.
    Missing required vitals (sbp, dbp, hr, rr, temp, consciousness) → UNKNOWN.
    """
    # Consciousness scores 3 when impaired, so unmeasured must not read as Alert.
    required = (sbp, dbp, hr, rr, temp, consciousness)
    if any(v is None for v in required):
        return {"moews_score": None, "risk_level": "UNKNOWN"}

    scores = [
        _score_band("systolic_bp", sbp),
        _score_band("diastolic_bp", dbp),
        _score_band("heart_rate", hr),
        _score_band("respiratory_rate", rr),
        _score_band("temperature", temp),
        _score_consciousness(consciousness),
    ]
    if spo2 is not None:
        scores.append(_score_band("spo2", spo2))

    total = sum(scores)
    return {
        "moews_score": total,
        "risk_level": _risk_level(scores, total),
    }
