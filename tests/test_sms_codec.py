import pytest

from src.tools.sms_codec import compress_referral_payload, decompress_referral_payload


@pytest.mark.parametrize(
    ("risk_code", "risk_level"),
    [(0, "GREEN"), (1, "YELLOW"), (2, "RED"), (3, "UNKNOWN")],
)
def test_referral_payload_round_trips_coordinator_risk_contract(
    risk_code, risk_level
):
    encoded = compress_referral_payload.invoke(
        {
            "chps_id_int": 1,
            "moews_score": 6,
            "risk_code": risk_code,
            "hr": 140,
            "sbp": 70,
        }
    )

    decoded = decompress_referral_payload.invoke({"encoded_str": encoded})

    assert decoded["chps_id_int"] == 1
    assert decoded["moews_score"] == 6
    assert decoded["risk_level"] == risk_level
    assert decoded["heart_rate"] == 140
    assert decoded["systolic_bp"] == 70


@pytest.mark.parametrize(
    ("chps_id_int", "moews_score", "risk_code", "hr", "sbp"),
    [
        (0, 0, 0, 0, 0),
        (65535, 15, 3, 255, 255),
        (1, None, 3, 60, 90),
    ],
)
def test_referral_payload_round_trips_edge_values(
    chps_id_int, moews_score, risk_code, hr, sbp
):
    encoded = compress_referral_payload.invoke(
        {
            "chps_id_int": chps_id_int,
            "moews_score": moews_score,
            "risk_code": risk_code,
            "hr": hr,
            "sbp": sbp,
        }
    )
    decoded = decompress_referral_payload.invoke({"encoded_str": encoded})
    assert decoded["chps_id_int"] == chps_id_int
    assert decoded["moews_score"] == (moews_score or 0)
    assert decoded["heart_rate"] == hr
    assert decoded["systolic_bp"] == sbp
