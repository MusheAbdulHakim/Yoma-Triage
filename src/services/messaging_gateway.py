"""Africa's Talking SMS/Voice with auto-mock fallback."""
import logging

import httpx

from src.config import settings

logger = logging.getLogger(__name__)


class MessagingGateway:
    SMS_URL = "https://api.africastalking.com/version1/messaging"

    async def send_sms(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        if not settings.at_configured:
            logger.info("MOCK SMS dispatch=%s role=%s to=%s msg=%s", dispatch_id, role, to, message)
            return {"status": "MOCKED", "to": to, "message": message, "role": role, "dispatch_id": dispatch_id}
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(
                    self.SMS_URL,
                    headers={"apiKey": settings.AT_API_KEY, "Accept": "application/json"},
                    data={
                        "username": settings.AT_USERNAME,
                        "to": to,
                        "message": message,
                        "from": settings.AT_SENDER_ID,
                    },
                )
            if resp.status_code >= 400:
                return {
                    "status": "FAILED",
                    "error": resp.text,
                    "to": to,
                    "dispatch_id": dispatch_id,
                    "role": role,
                }
            return {
                "status": "SENT",
                "provider_response": resp.json(),
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }
        except Exception as exc:
            logger.exception("AT SMS failed")
            return {
                "status": "FAILED",
                "error": str(exc),
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }

    async def initiate_voice(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        if not settings.at_configured:
            logger.info("MOCK VOICE dispatch=%s to=%s", dispatch_id, to)
            return {"status": "MOCKED", "to": to, "message": message, "dispatch_id": dispatch_id, "role": role}
        return {
            "status": "FAILED",
            "error": "Voice not configured for MVP",
            "to": to,
            "dispatch_id": dispatch_id,
            "role": role,
        }
