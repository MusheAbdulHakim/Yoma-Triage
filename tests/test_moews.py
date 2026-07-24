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


def test_null_vitals_unknown():
    result = calculate_moews.invoke({
        "sbp": None, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["risk_level"] == "UNKNOWN"
    assert result["moews_score"] is None
