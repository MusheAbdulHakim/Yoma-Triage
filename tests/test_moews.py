import json
from pathlib import Path

import pytest

from src.tools.moews_calculator import calculate_moews

# Shared with mobile/test/moews_shared_cases_test.dart, so the server and the app
# can't disagree about a patient.
SHARED_CASES = json.loads(
    (Path(__file__).parent / "fixtures" / "moews_cases.json").read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", SHARED_CASES, ids=lambda case: case["name"])
def test_shared_cases(case):
    vitals = case["vitals"]
    result = calculate_moews.invoke(
        {
            "sbp": vitals["systolic_bp"],
            "dbp": vitals["diastolic_bp"],
            "hr": vitals["heart_rate"],
            "rr": vitals["respiratory_rate"],
            "temp": vitals["temperature"],
            "spo2": vitals["spo2"],
            "consciousness": vitals["consciousness_level"],
        }
    )
    assert result["risk_level"] == case["risk"]
    assert result["moews_score"] == case["score"]
    assert result["missing_vitals"] == case["missing"]


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


def test_missing_vital_with_nothing_critical_is_incomplete():
    result = calculate_moews.invoke({
        "sbp": None, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["risk_level"] == "INCOMPLETE"
    assert result["missing_vitals"] == ["systolic_bp"]


def test_single_parameter_score_three_is_red():
    # Only SBP is critical (score 3); other vitals are normal.
    result = calculate_moews.invoke({
        "sbp": 70, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": "A"
    })
    assert result["moews_score"] == 3
    assert result["risk_level"] == "RED"


def test_unmeasured_consciousness_is_incomplete_not_alert():
    result = calculate_moews.invoke({
        "sbp": 120, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": 98, "consciousness": None
    })
    assert result["risk_level"] == "INCOMPLETE"
    assert result["missing_vitals"] == ["consciousness_level"]


def test_unmeasured_spo2_is_scored_from_the_rest():
    result = calculate_moews.invoke({
        "sbp": 120, "dbp": 80, "hr": 80, "rr": 18, "temp": 37.0, "spo2": None, "consciousness": "A"
    })
    assert result["risk_level"] == "GREEN"
    assert result["moews_score"] == 0
    assert result["missing_vitals"] == ["spo2"]
