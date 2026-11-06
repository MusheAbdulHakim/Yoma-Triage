"""
Compresses clinical state into a Base64 string fitting into a single 140-octet 2G SMS payload.
"""
import base64
import logging
import struct

logger = logging.getLogger(__name__)

RISK_CODE_MAP = {"GREEN": 0, "YELLOW": 1, "RED": 2, "UNKNOWN": 3, "INCOMPLETE": 4}


def compress_referral_payload(
    chps_id_int: int,
    moews_score: int | None,
    risk_code: int,
    hr: int,
    sbp: int,
) -> str:
    """
    Compresses emergency referral metrics into a compact Base64 payload for 2G SMS transmission.

    Parameters:
      chps_id_int: Integer ID of the CHPS compound.
      moews_score: Calculated MOEWS risk score (0-15).
      risk_code: 0=GREEN, 1=YELLOW, 2=RED, 3=UNKNOWN, 4=INCOMPLETE.
      hr: Heart rate in BPM.
      sbp: Systolic blood pressure in mmHg.
    """
    # Packed format: unsigned short (CHPS ID), unsigned char (MOEWS), unsigned char (Risk), unsigned char (HR), unsigned char (SBP)
    # Total byte size = 2 + 1 + 1 + 1 + 1 = 6 bytes!
    binary_data = struct.pack(
        "!HBBBB", chps_id_int, moews_score or 0, risk_code, hr, sbp
    )
    encoded = base64.b64encode(binary_data).decode('ascii')
    return encoded

def encode_referral_payload_or_none(
    *, chps_id_int: int, moews_score: int | None, risk_level: str, hr: int | None, sbp: int | None
) -> str | None:
    """Optional telemetry: a value that doesn't fit (HR or SBP above 255) costs only this
    payload, never the referral's MOEWS score or risk level."""
    try:
        return compress_referral_payload(
            chps_id_int=chps_id_int,
            moews_score=moews_score,
            risk_code=RISK_CODE_MAP.get(risk_level, RISK_CODE_MAP["UNKNOWN"]),
            hr=hr or 0,
            sbp=sbp or 0,
        )
    except (struct.error, ValueError, TypeError, OverflowError) as exc:
        logger.warning("SMS payload encoding failed; continuing without it: %s", type(exc).__name__)
        return None


def decompress_referral_payload(encoded_str: str) -> dict:
    """
    Decompresses a Base64 2G SMS payload back into structured telemetry at the receiving hospital.
    """
    binary_data = base64.b64decode(encoded_str.encode('ascii'))
    chps_id_int, moews_score, risk_code, hr, sbp = struct.unpack("!HBBBB", binary_data)

    risk_map = {0: "GREEN", 1: "YELLOW", 2: "RED", 3: "UNKNOWN", 4: "INCOMPLETE"}
    return {
        "chps_id_int": chps_id_int,
        "moews_score": moews_score,
        "risk_level": risk_map.get(risk_code, "UNKNOWN"),
        "heart_rate": hr,
        "systolic_bp": sbp
    }
