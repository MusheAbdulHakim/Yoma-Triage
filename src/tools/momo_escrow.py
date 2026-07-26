"""
Mobile Money (MoMo) Escrow Tool interfacing with MTN MoMo Sandbox/Production API.
"""
import uuid

import requests
from langchain_core.tools import tool

from src.config import settings


@tool
def disburse_fuel_stipend(driver_phone: str, amount_ghs: float) -> dict:
    """
    Disburses an initial 30% fuel stipend directly to a Motor-King driver's MoMo wallet upon USSD referral acceptance.
    """
    if settings.ENVIRONMENT == "development" or not settings.MOMO_PRIMARY_KEY:
        # Mock payload for local testing & hackathon demo
        return {
            "status": "INITIAL_DISBURSED",
            "transaction_id": str(uuid.uuid4()),
            "amount": amount_ghs,
            "recipient": driver_phone,
            "note": "Sandbox disbursement successful (Mock Mode)"
        }

    # Production / Live Sandbox Endpoint Execution
    endpoint = f"{settings.MOMO_API_URL}/disbursement/v1_0/transfer"
    tx_ref = str(uuid.uuid4())
    headers = {
        "X-Reference-Id": tx_ref,
        "X-Target-Environment": settings.ENVIRONMENT,
        "Ocp-Apim-Subscription-Key": settings.MOMO_PRIMARY_KEY,
        "Content-Type": "application/json"
    }

    payload = {
        "amount": str(amount_ghs),
        "currency": "GHS",
        "externalId": f"YOMA-{tx_ref[:8]}",
        "payee": {
            "partyIdType": "MSISDN",
            "partyId": driver_phone
        },
        "payerMessage": "Yoma Triage Emergency Fuel Stipend",
        "payeeNote": "30% Fuel Advance for Patient Referral"
    }

    try:
        response = requests.post(endpoint, json=payload, headers=headers, timeout=10)
        if response.status_code == 202:
            return {"status": "INITIAL_DISBURSED", "transaction_id": tx_ref}
        return {"status": "FAILED", "error": response.text}
    except Exception as e:
        return {"status": "FAILED", "error": str(e)}
