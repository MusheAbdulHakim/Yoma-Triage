"""One source for every clinical and operational number."""
from __future__ import annotations

import importlib.util
import json
from datetime import timedelta
from pathlib import Path

import pytest

from src.api.referral import VitalsInput
from src.clinical_params import PARAMETERS_PATH, PARAMS
from src.config import DEFAULT_CASCADE_TIER_SECONDS, MIN_FIELD_CASCADE_TIER_SECONDS
from src.services.dispatch_orchestrator import FUEL_STIPEND_GHS, LATE_CLAIM_WINDOW
from src.tools.moews_calculator import _score_band

REPO = Path(__file__).resolve().parents[1]


def _generator():
    spec = importlib.util.spec_from_file_location(
        "generate_clinical_params", REPO / "scripts" / "generate_clinical_params.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_generated_files_are_up_to_date():
    generator = _generator()
    for path, expected in generator.outputs(json.loads(PARAMETERS_PATH.read_text())).items():
        assert path.read_text(encoding="utf-8") == expected, (
            f"{path.name} is stale: run python scripts/generate_clinical_params.py"
        )


def test_sign_off_sheet_lists_every_setting():
    generator = _generator()
    listed = {(section, key) for section, key, *_ in generator.SETTINGS}
    for section in ("dispatch", "payments", "acoustic", "referral_input", "advisory_device", "catalog"):
        for key in PARAMS[section]:
            assert (section, key) in listed, f"{section}.{key} is missing from the sign-off sheet"


def test_sign_off_sheet_is_marked_unapproved():
    sheet = (REPO / "docs" / "clinical-parameters-signoff.md").read_text(encoding="utf-8")
    assert "PLACEHOLDER" in sheet
    assert "None has been clinically approved" in sheet


def test_late_claim_window_is_45_minutes():
    assert timedelta(minutes=45) == LATE_CLAIM_WINDOW


def test_runtime_values_come_from_the_parameters_file():
    assert PARAMS["dispatch"]["cascade_tier_seconds"] == DEFAULT_CASCADE_TIER_SECONDS
    assert PARAMS["dispatch"]["min_field_cascade_tier_seconds"] == MIN_FIELD_CASCADE_TIER_SECONDS
    assert PARAMS["payments"]["fuel_stipend_ghs"] == FUEL_STIPEND_GHS


@pytest.mark.parametrize("vital", list(PARAMS["vital_ranges"]))
def test_api_enforces_the_vital_ranges(vital):
    limits = PARAMS["vital_ranges"][vital]
    VitalsInput(**{vital: limits["min"]})
    VitalsInput(**{vital: limits["max"]})
    for outside in (limits["min"] - 1, limits["max"] + 1):
        with pytest.raises(ValueError):
            VitalsInput(**{vital: outside})


@pytest.mark.parametrize(
    ("vital", "value", "score"),
    [
        ("systolic_bp", 79, 3), ("systolic_bp", 80, 1), ("systolic_bp", 90, 1), ("systolic_bp", 91, 0),
        ("systolic_bp", 139, 0), ("systolic_bp", 140, 1), ("systolic_bp", 150, 1), ("systolic_bp", 151, 3),
        ("diastolic_bp", 59, 3), ("diastolic_bp", 60, 0), ("diastolic_bp", 89, 0), ("diastolic_bp", 90, 1),
        ("diastolic_bp", 100, 1), ("diastolic_bp", 101, 3),
        ("heart_rate", 49, 3), ("heart_rate", 50, 1), ("heart_rate", 60, 1), ("heart_rate", 61, 0),
        ("heart_rate", 109, 0), ("heart_rate", 110, 1), ("heart_rate", 130, 1), ("heart_rate", 131, 3),
        ("respiratory_rate", 9, 3), ("respiratory_rate", 10, 1), ("respiratory_rate", 14, 1),
        ("respiratory_rate", 15, 0), ("respiratory_rate", 23, 0), ("respiratory_rate", 24, 1),
        ("respiratory_rate", 30, 1), ("respiratory_rate", 31, 3),
        ("temperature", 34.9, 3), ("temperature", 35, 1), ("temperature", 36, 1), ("temperature", 36.1, 0),
        ("temperature", 37.9, 0), ("temperature", 38, 1), ("temperature", 39, 1), ("temperature", 39.1, 3),
        ("spo2", 89, 3), ("spo2", 90, 1), ("spo2", 94, 1), ("spo2", 95, 0), ("spo2", 100, 0),
    ],
)
def test_scoring_bands_are_unchanged_by_the_move(vital, value, score):
    """Pins every band edge to the behaviour before these numbers moved to config."""
    assert _score_band(vital, value) == score
