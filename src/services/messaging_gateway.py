"""Africa's Talking bulk SMS / Voice with auto-mock fallback.

Bulk SMS docs: https://developers.africastalking.com/docs/sms/sending/bulk
"""
from __future__ import annotations

import logging
from typing import Any

import httpx

from src.config import settings

logger = logging.getLogger(__name__)

# AT recipient statusCode values that mean the API accepted the message.
SUCCESS_STATUS_CODES = frozenset({100, 101, 102})  # Processed / Sent / Queued


class MessagingGateway:
    async def send_sms(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        if not settings.at_configured:
            logger.info(
                "MOCK SMS dispatch=%s role=%s to=%s msg=%s",
                dispatch_id,
                role,
                to,
                message,
            )
            return {
                "status": "MOCKED",
                "provider": "mock",
                "to": to,
                "message": message,
                "role": role,
                "dispatch_id": dispatch_id,
            }

        payload = {
            "username": settings.AT_USERNAME,
            "message": message,
            "senderId": settings.AT_SENDER_ID,
            "phoneNumbers": [to],
            "enqueue": 1,
        }
        headers = {
            "apiKey": settings.AT_API_KEY,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        url = settings.at_sms_bulk_url

        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(url, headers=headers, json=payload)
        except Exception as exc:
            logger.warning("AT SMS request failed (%s)", exc)
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "error": str(exc),
                "error_type": type(exc).__name__,
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }

        if resp.status_code >= 400:
            logger.warning("AT SMS HTTP %s: %s", resp.status_code, resp.text[:300])
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "http_status": resp.status_code,
                "error": resp.text[:500],
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }

        try:
            body: dict[str, Any] = resp.json()
        except Exception:
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "http_status": resp.status_code,
                "error": "Invalid JSON response",
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }

        recipients = (
            (body.get("SMSMessageData") or {}).get("Recipients") or []
        )
        recipient = recipients[0] if recipients else {}
        status_code = recipient.get("statusCode")
        message_id = recipient.get("messageId")
        ok = status_code in SUCCESS_STATUS_CODES or (
            str(recipient.get("status", "")).lower() == "success"
        )
        if not ok:
            logger.warning(
                "AT SMS recipient rejected statusCode=%s status=%s",
                status_code,
                recipient.get("status"),
            )
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "http_status": resp.status_code,
                "status_code": status_code,
                "provider_response": body,
                "to": to,
                "dispatch_id": dispatch_id,
                "role": role,
            }

        return {
            "status": "SENT",
            "provider": "africas_talking",
            "provider_response": body,
            "message_id": message_id,
            "status_code": status_code,
            "cost": recipient.get("cost"),
            "to": to,
            "dispatch_id": dispatch_id,
            "role": role,
        }

    async def initiate_voice(self, to: str, message: str, dispatch_id: int, role: str) -> dict:
        if not settings.at_configured:
            logger.info("MOCK VOICE dispatch=%s to=%s", dispatch_id, to)
            return {
                "status": "MOCKED",
                "provider": "mock",
                "to": to,
                "message": message,
                "dispatch_id": dispatch_id,
                "role": role,
            }
        return {
            "status": "FAILED",
            "error": "Voice not configured for MVP",
            "to": to,
            "dispatch_id": dispatch_id,
            "role": role,
        }
