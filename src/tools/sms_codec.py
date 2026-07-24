"""
Compresses clinical state into a Base64 string fitting into a single 140-octet 2G SMS payload.
"""
import base64
import struct
from typing import Optional
from langchain_core.tools import tool

@tool
def compress_referral_payload(
    chps_id_int: int,
    moews_score: Optional[int],
    risk_code: int,
    hr: int,
    sbp: int,
) -> str:
    """
    Compresses emergency referral metrics into a compact Base64 payload for 2G SMS transmission.
    
    Parameters:
      chps_id_int: Integer ID of the CHPS compound.
      moews_score: Calculated MOEWS risk score (0-15).
      risk_code: 0=Normal, 1=Medium, 2=High, 3=Critical.
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

@tool
def decompress_referral_payload(encoded_str: str) -> dict:
    """
    Decompresses a Base64 2G SMS payload back into structured telemetry at the receiving hospital.
    """
    binary_data = base64.b64decode(encoded_str.encode('ascii'))
    chps_id_int, moews_score, risk_code, hr, sbp = struct.unpack("!HBBBB", binary_data)
    
    risk_map = {0: "NORMAL", 1: "MEDIUM", 2: "HIGH", 3: "CRITICAL"}
    return {
        "chps_id_int": chps_id_int,
        "moews_score": moews_score,
        "risk_level": risk_map.get(risk_code, "UNKNOWN"),
        "heart_rate": hr,
        "systolic_bp": sbp
    }