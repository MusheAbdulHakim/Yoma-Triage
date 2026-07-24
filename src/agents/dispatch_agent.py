"""
Dispatch & Logistics Node: Encodes binary 2G SMS payloads and triggers Mobile Money fuel escrow.
"""
from src.agents.state import ReferralState
from src.tools.sms_codec import compress_referral_payload
from src.tools.momo_escrow import disburse_fuel_stipend

RISK_CODE_MAP = {"NORMAL": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}

def run_dispatch_coordination(state: ReferralState) -> ReferralState:
    """
    Coordinates transport dispatch for high-risk referrals and triggers automated MoMo fuel escrow.
    """
    chps_numeric_id = int(''.join(filter(str.isdigit, state["chps_id"])) or "0")
    risk_code = RISK_CODE_MAP.get(state["risk_level"], 1)
    
    # 1. Compress clinical state to Base64 SMS payload
    compressed_sms = compress_referral_payload.invoke({
        "chps_id_int": chps_numeric_id,
        "moews_score": state["moews_score"],
        "risk_code": risk_code,
        "hr": state["vitals"]["heart_rate"],
        "sbp": state["vitals"]["systolic_bp"]
    })
    
    # 2. Trigger initial fuel stipend via MoMo API if emergency criteria met
    driver_phone = "233240000000"  # Example driver phone number
    escrow_result = disburse_fuel_stipend.invoke({
        "driver_phone": driver_phone,
        "amount_ghs": 50.0  # 30% advance fuel stipend (GHS)
    })
    
    # 3. Update LangGraph state
    state["compressed_sms_payload"] = compressed_sms
    state["assigned_driver_id"] = "MK-DRIVER-GH-409"
    state["escrow_status"] = escrow_result["status"]
    
    return state