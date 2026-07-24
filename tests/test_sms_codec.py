from src.tools.sms_codec import compress_referral_payload, decompress_referral_payload


def test_referral_payload_round_trips_critical_vitals():
    encoded = compress_referral_payload.invoke(
        {"chps_id_int": 1, "moews_score": 6, "risk_code": 3, "hr": 140, "sbp": 70}
    )

    decoded = decompress_referral_payload.invoke({"encoded_str": encoded})

    assert decoded["chps_id_int"] == 1
    assert decoded["moews_score"] == 6
    assert decoded["risk_level"] == "CRITICAL"
    assert decoded["heart_rate"] == 140
    assert decoded["systolic_bp"] == 70
