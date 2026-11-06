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


# SpO2 is optional: without it a complete set can still be scored, but the result
# must say so. Every other vital is required before a patient can be anything other
# than RED or INCOMPLETE.
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
    # A measured critical value is never hidden by what wasn't measured.
    if any(s == 3 for s in scores) or total >= 5:
        return "RED"
    # A patient can't be called normal from half a set.
    if any(name not in OPTIONAL_VITALS for name in missing):
        return "INCOMPLETE"
    if total >= 3 or any(s == 1 for s in scores):
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
    """Score what was measured. Plain function with no I/O, so it can always run."""
    scorers = (
        ("systolic_bp", sbp, _score_sbp),
        ("diastolic_bp", dbp, _score_dbp),
        ("heart_rate", hr, _score_hr),
        ("respiratory_rate", rr, _score_rr),
        ("temperature", temp, _score_temp),
        ("spo2", spo2, _score_spo2),
    )
    scores = [score(value) for _, value, score in scorers if value is not None]
    if consciousness is not None:
        scores.append(_score_consciousness(consciousness))
    missing = missing_vitals(
        {name: value for name, value, _ in scorers} | {"consciousness_level": consciousness}
    )
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

    Vital bands (score 3 / 1 / 0):
    - SBP: <80 or >150 / 80–90 or 140–150 / else
    - DBP: >100 or <60 / 90–100 / else
    - HR: <50 or >130 / 50–60 or 110–130 / else
    - RR: <10 or >30 / 10–14 or 24–30 / else
    - Temp: <35 or >39 / 35–36 or 38–39 / else
    - SpO2 (if provided): <90 / 90–94 / else
    - Consciousness: not Alert (A) / Alert

    Only measured vitals are scored:
    - RED: any measured parameter scores 3, or measured scores total 5 or more.
    - INCOMPLETE: otherwise, if any vital except SpO2 is missing.
    - YELLOW: otherwise, total 3-4 or any parameter scoring 1.
    - GREEN: otherwise. SpO2 is listed as missing if it wasn't measured.
    """
    return score_vitals(sbp, dbp, hr, rr, temp, spo2, consciousness)
