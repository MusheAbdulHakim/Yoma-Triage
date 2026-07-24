"""
USSD Webhook Receiver for Ghana Telecom Gateways (Arkesel / Hubtel).
"""
from fastapi import APIRouter, Form, Response

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])

@router.post("/callback")
async def handle_ussd(
    session_id: str = Form(...),
    service_code: str = Form(...),
    phone_number: str = Form(...),
    text: str = Form("")
):
    """
    Processes USSD inputs from drivers responding to emergency referrals.
    Format required by Ghanaian Telco gateways: 'CON' (continue) or 'END' (terminate).
    """
    user_input = text.strip()
    
    if user_input == "":
        # Initial Dial
        response_text = "CON RelayAI Emergency Referral\n1. Accept Transfer (CHPS-104)\n2. Reject"
    elif user_input == "1":
        # Driver Accepts Referral
        response_text = "END Accepted! 50 GHS fuel stipend sent to your MoMo wallet. Proceed to CHPS-104."
        # Trigger escrow payout asynchronously here
    elif user_input == "2":
        response_text = "END Referral declined."
    else:
        response_text = "END Invalid option selected."

    return Response(content=response_text, media_type="text/plain")