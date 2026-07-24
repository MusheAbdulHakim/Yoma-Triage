"""
Deterministic Modified Obstetric Early Warning Score (MOEWS) calculator.
"""
from langchain_core.tools import tool

@tool
def calculate_moews(sbp: int, dbp: int, hr: int, rr: int, temp: float) -> dict:
    """
    Calculates the MOEWS risk score based on Ghana Health Service clinical thresholds.
    """
    score = 0
    
    # Systolic Blood Pressure
    if sbp >= 160 or sbp < 90:
        score += 3
    elif 140 <= sbp < 160:
        score += 2
    elif 100 <= sbp < 140:
        score += 0

    # Heart Rate
    if hr >= 120 or hr < 50:
        score += 3
    elif 100 <= hr < 120:
        score += 2
        
    # Respiratory Rate
    if rr >= 30 or rr < 12:
        score += 3
    elif 21 <= rr < 30:
        score += 2

    # Risk Stratification
    if score >= 6:
        risk_level = "CRITICAL"
    elif score >= 4:
        risk_level = "HIGH"
    elif score >= 1:
        risk_level = "MEDIUM"
    else:
        risk_level = "NORMAL"

    return {
        "moews_score": score,
        "risk_level": risk_level
    }