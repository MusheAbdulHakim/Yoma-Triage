from src.tools.moews_calculator import calculate_moews


def test_normal_vitals_green():
    result = calculate_moews.invoke({
        "sbp": 120, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["moews_score"] == 0
    assert result["risk_level"] == "GREEN"


def test_critical_vitals_red():
    result = calculate_moews.invoke({
        "sbp": 70, "dbp": 50, "hr": 140, "rr": 35, "temp": 39.5, "spo2": 85, "consciousness": "V"
    })
    assert result["moews_score"] >= 5
    assert result["risk_level"] == "RED"


def test_moderate_vitals_yellow():
    # Single elevated RR often maps to YELLOW (score 1–4) depending on thresholds.
    result = calculate_moews.invoke({
        "sbp": 120, "dbp": 80, "hr": 80, "rr": 25, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["moews_score"] is not None
    assert 1 <= result["moews_score"] <= 4
    assert result["risk_level"] == "YELLOW"


def test_null_vitals_unknown():
    result = calculate_moews.invoke({
        "sbp": None, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None


def test_single_parameter_score_three_is_red():
    # Only SBP is critical (score 3); other vitals are normal.
    result = calculate_moews.invoke({
        "sbp": 70, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["moews_score"] == 3
    assert result["risk_level"] == "RED"
