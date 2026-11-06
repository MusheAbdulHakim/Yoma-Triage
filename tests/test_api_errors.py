"""The app trusts a refusal only if it carries one of the API's defined codes."""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from src.api import errors
from src.api.errors import ApiError
from tests.conftest import SEEDED_CHO_PHONE

DART = (Path(__file__).resolve().parents[1] / "mobile/lib/services/api_client.dart").read_text(
    encoding="utf-8"
)


def _dart_codes() -> set[str]:
    block = re.search(r"apiErrorCodes = \{(.*?)\};", DART, re.S)
    assert block, "apiErrorCodes not found in api_client.dart"
    return set(re.findall(r"'([A-Z_]+)'", block.group(1)))


def test_app_and_api_list_the_same_codes():
    assert _dart_codes() == errors.ALL_CODES


def test_an_undefined_code_is_refused():
    with pytest.raises(ValueError):
        ApiError(404, "MADE_UP", "x")


def _body(**overrides):
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "a" * 64,
        "cho_phone": SEEDED_CHO_PHONE,
        "emergency_type": "pph",
        **overrides,
    }


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("overrides", "status", "code"),
    [
        ({"chps_compound_id": 99}, 404, errors.COMPOUND_NOT_FOUND),
        ({"facility_id": 99}, 404, errors.FACILITY_NOT_FOUND),
        ({"cho_phone": "+233249999999"}, 403, errors.CHO_NOT_REGISTERED),
        ({"patient_hash": "not-hex"}, 422, errors.VALIDATION_ERROR),
    ],
)
async def test_referral_refusals_carry_a_code(client, seeded_db, overrides, status, code):
    response = await client.post("/api/v1/referral", json=_body(**overrides))
    assert response.status_code == status
    assert response.json()["code"] == code
    assert response.json()["detail"]


@pytest.mark.asyncio
async def test_lookup_refusals_carry_a_code(client, seeded_db):
    missing = await client.post("/api/v1/cho/lookup", json={"phone": "0249999999"})
    assert (missing.status_code, missing.json()["code"]) == (404, errors.CHO_NOT_REGISTERED)
    bad = await client.post("/api/v1/cho/lookup", json={"phone": "12345"})
    assert (bad.status_code, bad.json()["code"]) == (422, errors.INVALID_PHONE)


@pytest.mark.asyncio
async def test_a_bad_api_key_has_no_code(client, seeded_db, monkeypatch):
    """Rotating the server's key mustn't permanently kill every queued emergency."""
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "secret")
    response = await client.post("/api/v1/referral", json=_body())
    assert response.status_code == 401
    assert "code" not in response.json()


@pytest.mark.asyncio
async def test_a_route_that_does_not_exist_has_no_code(client):
    assert "code" not in (await client.get("/api/v1/nothing-here")).json()
