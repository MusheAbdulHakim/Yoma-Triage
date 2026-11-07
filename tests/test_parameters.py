"""One parameters module per side, kept in sync, and every value on the sign-off sheet."""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from src import parameters
from src.api.referral import VitalsInput
from src.tools.moews_calculator import _score_band

REPO = Path(__file__).resolve().parents[1]
DART = (REPO / "mobile/lib/parameters.dart").read_text(encoding="utf-8")
SHEET = (REPO / "docs/PARAMETERS_SIGNOFF.md").read_text(encoding="utf-8")

DART_VITALS = {
    "systolic_bp": "systolicBp",
    "diastolic_bp": "diastolicBp",
    "heart_rate": "heartRate",
    "respiratory_rate": "respiratoryRate",
    "temperature": "temperature",
    "spo2": "spo2",
}
SHEET_LABELS = {
    "systolic_bp": "Systolic BP",
    "diastolic_bp": "Diastolic BP",
    "heart_rate": "Heart rate",
    "respiratory_rate": "Respiratory rate",
    "temperature": "Temperature",
    "spo2": "SpO₂",
}


def _dart_constant(name: str) -> float:
    match = re.search(rf"static const {name} = ([\d.]+);", DART)
    assert match, f"{name} not found in parameters.dart"
    return float(match.group(1))


def _dart_band(name: str) -> dict[str, float]:
    match = re.search(rf"static const {name}Band =\s*MoewsBand\((.*?)\);", DART, re.S)
    assert match, f"{name}Band not found in parameters.dart"
    return {key: float(value) for key, value in re.findall(r"(\w+): ([\d.]+)", match.group(1))}


@pytest.mark.parametrize("vital", list(parameters.VITAL_RANGES))
def test_vital_ranges_match_the_app(vital):
    low, high = parameters.VITAL_RANGES[vital]
    assert _dart_constant(f"{DART_VITALS[vital]}Min") == low
    assert _dart_constant(f"{DART_VITALS[vital]}Max") == high


@pytest.mark.parametrize("vital", list(parameters.MOEWS_BANDS))
def test_moews_bands_match_the_app(vital):
    band = parameters.MOEWS_BANDS[vital]
    expected = {}
    if band["red_below"] is not None:
        expected["redBelow"] = float(band["red_below"])
    if band["red_above"] is not None:
        expected["redAbove"] = float(band["red_above"])
    if band["yellow_low"]:
        expected["yellowLowMin"], expected["yellowLowMax"] = map(float, band["yellow_low"])
    if band["yellow_high"]:
        expected["yellowHighMin"], expected["yellowHighMax"] = map(float, band["yellow_high"])
    assert _dart_band(DART_VITALS[vital]) == expected


def test_stale_threshold_matches_the_app():
    assert _dart_constant("staleAfterMinutes") == parameters.STALE_AFTER_MINUTES


def test_unconfirmed_expiry_matches_the_app():
    assert _dart_constant("expireUnconfirmedHours") == parameters.EXPIRE_UNCONFIRMED_HOURS


def test_local_record_ttl_matches_the_app():
    assert _dart_constant("localRecordTtlHours") == parameters.LOCAL_RECORD_TTL_HOURS


def test_risk_rules_match_the_app():
    assert _dart_constant("moewsRedParameterScore") == parameters.MOEWS_RED_PARAMETER_SCORE
    assert _dart_constant("moewsRedTotal") == parameters.MOEWS_RED_TOTAL
    assert _dart_constant("moewsYellowTotal") == parameters.MOEWS_YELLOW_TOTAL


@pytest.mark.parametrize("vital", list(parameters.VITAL_RANGES))
def test_api_enforces_the_ranges(vital):
    low, high = parameters.VITAL_RANGES[vital]
    VitalsInput(**{vital: low})
    VitalsInput(**{vital: high})
    for outside in (low - 1, high + 1):
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
def test_scoring_bands_are_pinned(vital, value, score):
    """Every band edge, so a change to these numbers has to be deliberate."""
    assert _score_band(vital, value) == score


@pytest.mark.parametrize("vital", list(parameters.VITAL_RANGES))
def test_sheet_lists_each_vital_range(vital):
    low, high = parameters.VITAL_RANGES[vital]
    assert re.search(rf"\| {SHEET_LABELS[vital]} \| {low} \| {high} \|", SHEET)


@pytest.mark.parametrize("vital", list(parameters.MOEWS_BANDS))
def test_sheet_lists_each_moews_band(vital):
    band = parameters.MOEWS_BANDS[vital]
    cells = [
        f"<{band['red_below']}",
        f"{band['yellow_low'][0]}–{band['yellow_low'][1]}" if band["yellow_low"] else "—",
        f"{band['yellow_high'][0]}–{band['yellow_high'][1]}" if band["yellow_high"] else "—",
        f">{band['red_above']}" if band["red_above"] is not None else "—",
    ]
    assert f"| {SHEET_LABELS[vital]} | " + " | ".join(cells) + " |" in SHEET


@pytest.mark.parametrize(
    ("label", "value"),
    [
        ("Wait per cascade tier", parameters.CASCADE_TIER_SECONDS),
        ("Shortest tier wait allowed in the field", parameters.MIN_FIELD_CASCADE_TIER_SECONDS),
        ("Late-claim window", parameters.LATE_CLAIM_WINDOW_MINUTES),
        ("Stale queued referral", parameters.STALE_AFTER_MINUTES),
        ("Unanswered stale referral expires", parameters.EXPIRE_UNCONFIRMED_HOURS),
        ("Local record TTL", parameters.LOCAL_RECORD_TTL_HOURS),
        ("Cascade worker poll interval", parameters.WORKER_POLL_SECONDS),
        ("SMS outbox poll interval", parameters.OUTBOX_POLL_SECONDS),
        ("SMS send attempts before giving up", parameters.OUTBOX_MAX_ATTEMPTS),
        ("SMS retry backoff", parameters.OUTBOX_BACKOFF_SECONDS),
        ("SMS claim lease", parameters.OUTBOX_SENDING_LEASE_SECONDS),
        ("SMS batch size", parameters.OUTBOX_BATCH_SIZE),
        ("SMS sent at once", parameters.OUTBOX_SEND_CONCURRENCY),
        ("SMS send time limit", parameters.OUTBOX_SEND_TIMEOUT_SECONDS),
        ("ETA shown to the CHO", parameters.PLACEHOLDER_ETA_MINUTES),
        ("Fuel stipend recorded on accept", parameters.FUEL_STIPEND_GHS),
        ("Highest gestational age accepted", parameters.GESTATIONAL_WEEKS_MAX),
        ("RED: score of one measured vital", parameters.MOEWS_RED_PARAMETER_SCORE),
        ("RED: total of measured scores", parameters.MOEWS_RED_TOTAL),
        ("YELLOW: total of measured scores", parameters.MOEWS_YELLOW_TOTAL),
    ],
)
def test_sheet_lists_each_setting_with_its_current_value(label, value):
    assert f"| {label} | {value} |" in SHEET


@pytest.mark.parametrize(
    ("label", "name"),
    [
        ("Acoustic score for Code Red", "acousticRedAbove"),
        ("Acoustic score reported as Inconclusive", "acousticInconclusiveBelow"),
        ("OPERA-CE probability for GREEN", "operaGreenAbove"),
        ("Recording length", "defaultScreeningSeconds"),
        ("Device heart rate, lowest accepted", "deviceHeartRateMin"),
        ("Device heart rate, highest accepted", "deviceHeartRateMax"),
        ("Device SpO₂, lowest accepted", "deviceSpo2Min"),
        ("Device SpO₂, highest accepted", "deviceSpo2Max"),
        ("Facility list refresh warning", "catalogStaleAfterDays"),
        ("Local record deletion warning", "localRecordWarningHours"),
    ],
)
def test_sheet_lists_each_app_only_setting(label, name):
    value = _dart_constant(name)
    shown = int(value) if value == int(value) else value
    assert f"| {label} | {shown} |" in SHEET


def test_every_table_row_has_a_blank_sign_off_column():
    rows = [line for line in SHEET.splitlines() if line.startswith("| ") and "---" not in line]
    data_rows = [
        row
        for row in rows
        if "Sign-off" not in row
        and "Signature" not in row
        and not row.startswith(("| Clinical lead", "| Operations lead", "| GHS representative"))
    ]
    assert data_rows
    for row in data_rows:
        assert row.rstrip().endswith("| |"), row


def test_sheet_asks_about_green_without_spo2():
    questions = SHEET[SHEET.index("## Questions for the clinical lead") : SHEET.index("## Vital sign")]
    assert "every vital measured except SpO₂ can still be GREEN" in questions


def test_sheet_says_nothing_is_approved():
    assert "None of these values has been clinically approved" in SHEET
