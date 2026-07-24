"""
Deterministic Modified Obstetric Early Warning Score (MOEWS) calculator.
"""

from langchain_core.tools import tool


def _score_sbp(sbp: int) -> int:
    if sbp < 80 or sbp > 150:
        return 3
    if 80 <= sbp <= 90 or 140 <= sbp <= 150:
        return 1
    return 0


def _score_dbp(dbp: int) -> int:
    if dbp > 100:
        return 3
    if 90 <= dbp <= 100:
        return 1
    if dbp < 60:
        return 3
    return 0


def _score_hr(hr: int) -> int:
    if hr < 50 or hr > 130:
        return 3
    if 50 <= hr <= 60 or 110 <= hr <= 130:
        return 1
    return 0


def _score_rr(rr: int) -> int:
    if rr < 10 or rr > 30:
        return 3
    if 10 <= rr <= 14 or 24 <= rr <= 30:
        return 1
    return 0


def _score_temp(temp: float) -> int:
    if temp < 35 or temp > 39:
        return 3
    if 35 <= temp <= 36 or 38 <= temp <= 39:
        return 1
    return 0


def _score_spo2(spo2: int) -> int:
    if spo2 < 90:
        return 3
    if 90 <= spo2 <= 94:
        return 1
    return 0


def _score_consciousness(consciousness: str) -> int:
    if consciousness.upper() != "A":
        return 3
    return 0


def _risk_level(scores: list[int], total: int) -> str:
    if any(s == 3 for s in scores) or total >= 5:
        return "RED"
    if total >= 3 or any(s == 1 for s in scores):
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
    consciousness: str = "A",
) -> dict:
    """
    Calculates the MOEWS risk score based on Ghana Health Service clinical thresholds.

    Vital bands (score 3 / 1 / 0):
    - SBP: <80 or >150 / 80–90 or 140–150 / else
    - DBP: >100 or <60 / 90–100 / else
    - HR: <50 or >130 / 50–60 or 110–130 / else
    - RR: <10 or >30 / 10–14 or 24–30 / else
    - Temp: <35 or >39 / 35–36 or 38–39 / else
    - SpO2 (if provided): <90 / 90–94 / else
    - Consciousness: not Alert (A) / Alert

    Risk: any param score 3 or total ≥5 → RED; total 3–4 or any param 1 → YELLOW; 0–2 → GREEN.
    Missing required vitals (sbp, dbp, hr, rr, temp) → UNKNOWN.
    """
    required = (sbp, dbp, hr, rr, temp)
    if any(v is None for v in required):
        return {"moews_score": None, "risk_level": "UNKNOWN"}

    scores = [
        _score_sbp(sbp),
        _score_dbp(dbp),
        _score_hr(hr),
        _score_rr(rr),
        _score_temp(temp),
        _score_consciousness(consciousness),
    ]
    if spo2 is not None:
        scores.append(_score_spo2(spo2))

    total = sum(scores)
    return {
        "moews_score": total,
        "risk_level": _risk_level(scores, total),
    }
