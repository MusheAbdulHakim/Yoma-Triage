"""Referral input validation and USSD exact matching (audit BUG-10, BUG-11)."""
from __future__ import annotations

import re
import uuid
from pathlib import Path

import pytest

from src.api.referral import VitalsInput
from src.tools.sms_codec import encode_referral_payload_or_none

REPO = Path(__file__).resolve().parents[1]
NORMAL_VITALS = {
    "systolic_bp": 120,
    "diastolic_bp": 80,
    "heart_rate": 80,
    "respiratory_rate": 18,
    "temperature": 37.0,
    "spo2": 98,
    "consciousness_level": "A",
}


@pytest.fixture
def no_side_effects(monkeypatch):
    return None


def _payload(**overrides):
    return {
        "chps_compound_id": 1,
        "cho_phone": "+233240000010",
        "facility_id": 1,
        "patient_hash": "0123456789abcdef" * 4,
        "emergency_type": "pph",
        "client_request_id": str(uuid.uuid4()),
        "vitals": NORMAL_VITALS,
        **overrides,
    }


def _vitals(**overrides):
    return _payload(vitals={**NORMAL_VITALS, **overrides})


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        _vitals(systolic_bp=301),
        _vitals(systolic_bp=1200),
        _vitals(systolic_bp=-1),
        _vitals(diastolic_bp=201),
        _vitals(diastolic_bp=-1),
        _vitals(heart_rate=301),
        _vitals(heart_rate=-5),
        _vitals(respiratory_rate=121),
        _vitals(respiratory_rate=-1),
        _vitals(temperature=45.1),
        _vitals(temperature=19.9),
        _vitals(temperature="NaN"),
        _vitals(temperature="Infinity"),
        _vitals(spo2=101),
        _vitals(spo2=-1),
        _vitals(heart_rate="fast"),
        _vitals(heart_rate=10**30),
        _vitals(consciousness_level="X"),
        _vitals(consciousness_level="1"),
        _payload(emergency_type="x" * 100),
        _payload(emergency_type="Obstetric haemorrhage"),
        _payload(emergency_type=""),
        _payload(ai_screen_result="y" * 40),
        _payload(ai_confidence=5.0),
        _payload(ai_confidence=-0.1),
        _payload(gestational_weeks=-3),
        _payload(gestational_weeks=60),
        _payload(chps_compound_id=2**40),
        _payload(facility_id=0),
    ],
)
async def test_bad_input_is_422_never_500(client, seeded_db, no_side_effects, payload):
    response = await client.post("/api/v1/referral", json=payload)
    assert response.status_code == 422, response.text


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "emergency_type",
    [
        "respiratory_distress",
        "pph",
        "neonatal_asphyxia",
        "eclampsia",
        "maternal_hemorrhage",
        "neonatal_sepsis",
        "severe_malaria",
        "other",
    ],
)
async def test_known_emergency_types_accepted(
    client, seeded_db, no_side_effects, emergency_type
):
    response = await client.post(
        "/api/v1/referral", json=_payload(emergency_type=emergency_type)
    )
    assert response.status_code == 201, response.text


@pytest.mark.parametrize(
    ("given", "stored"),
    [("a", "A"), ("Alert", "A"), ("v", "V"), ("PAIN", "P"), (" U ", "U"), (None, None)],
)
def test_consciousness_is_normalized(given, stored):
    assert VitalsInput(consciousness_level=given).consciousness_level == stored


@pytest.mark.asyncio
async def test_top_of_range_vitals_keep_moews_when_codec_cannot_encode(
    client, seeded_db, no_side_effects
):
    # In range for the API, too large for the codec's one-byte fields.
    response = await client.post(
        "/api/v1/referral", json=_vitals(systolic_bp=300, heart_rate=280)
    )
    assert response.status_code == 201, response.text
    referral = response.json()["referral"]
    assert referral["risk_level"] == "RED"
    assert referral["moews_score"] == 6
    assert referral["severity"] == "RED"
    assert referral["compressed_sms_payload"] is None


def test_payload_that_cannot_be_encoded_is_dropped_not_raised():
    assert (
        encode_referral_payload_or_none(
            chps_id_int=1, moews_score=3, risk_level="RED", hr=80, sbp=999
        )
        is None
    )


def test_payload_within_range_is_encoded():
    assert encode_referral_payload_or_none(
        chps_id_int=1, moews_score=0, risk_level="GREEN", hr=80, sbp=120
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "text",
    ["21", "13", "11", "31", "99*1", "4", "0", "a1", "1a", "*1", "1*", "1*{ref}*11",
     "1*{ref}*1*1", "1*{ref}*3", "1*{ref}1*1", "1*1{ref}*1", "2*1", "3*3"],
)
async def test_ussd_typo_does_not_claim_dispatch(
    client, seeded_db, no_side_effects, monkeypatch, text
):
    """BUG-10: only the exact path 1*<ref>*1 accepts. Nothing near it does."""
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    created = await client.post("/api/v1/referral", json=_payload())
    dispatch_id = created.json()["dispatch"]["id"]
    ref = created.json()["referral"]["id"]

    reply = await client.post(
        "/ussd/callback",
        data={
            "phoneNumber": "+233240000001",
            "serviceCode": "*1#",
            "text": text.format(ref=ref),
        },
    )

    assert reply.text.startswith("END ")
    assert "Accepted" not in reply.text
    dispatch = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()
    assert dispatch["driver_id"] is None


def test_every_emergency_type_in_the_app_is_accepted():
    # The app's one list of types (the form's chips and every label come from it).
    source = (REPO / "mobile/lib/models/emergency_type.dart").read_text()
    block = source[source.index("const emergencyTypes") :]
    values = re.findall(r"\('(\w+)', '", block[: block.index("];")])
    assert len(values) == 4, values
    from typing import get_args

    from src.api.referral import EmergencyType

    assert set(values) <= set(get_args(EmergencyType))


@pytest.mark.asyncio
async def test_api_reports_red_and_what_is_missing_for_partial_vitals(
    client, seeded_db, no_side_effects
):
    response = await client.post(
        "/api/v1/referral", json=_vitals(systolic_bp=60, temperature=None)
    )
    assert response.status_code == 201, response.text
    referral = response.json()["referral"]
    assert referral["risk_level"] == "RED"
    assert referral["moews_score"] == 3
    assert referral["missing_vitals"] == ["temperature"]


@pytest.mark.asyncio
async def test_api_reports_incomplete_when_nothing_measured_is_critical(
    client, seeded_db, no_side_effects
):
    response = await client.post(
        "/api/v1/referral", json=_vitals(temperature=None, spo2=None)
    )
    assert response.status_code == 201, response.text
    referral = response.json()["referral"]
    assert referral["risk_level"] == "INCOMPLETE"
    assert referral["missing_vitals"] == ["temperature", "spo2"]
