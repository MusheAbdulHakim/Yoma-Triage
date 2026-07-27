"""Africa's Talking SMS / Voice with auto-mock fallback.

Sandbox apps: form POST `/version1/messaging` (bulk path is not available yet).
Live apps: JSON POST `/version1/messaging/bulk`
  docs: https://developers.africastalking.com/docs/sms/sending/bulk
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
    @property
    def _use_bulk(self) -> bool:
        """Bulk JSON exists on live; sandbox currently 404s `/messaging/bulk`."""
        base = settings.at_api_base_url.lower()
        return "sandbox" not in base

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

        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                if self._use_bulk:
                    parsed = await self._send_bulk_json(client, to, message)
                else:
                    parsed = await self._send_sandbox_form(client, to, message)
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

        parsed.update({"to": to, "dispatch_id": dispatch_id, "role": role})
        return parsed

    async def _send_bulk_json(
        self, client: httpx.AsyncClient, to: str, message: str
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "username": settings.AT_USERNAME,
            "message": message,
            "senderId": settings.AT_SENDER_ID.strip() or settings.AT_USERNAME,
            "phoneNumbers": [to],
            "enqueue": True,
        }
        resp = await client.post(
            settings.at_sms_bulk_url,
            headers={
                "apiKey": settings.AT_API_KEY,
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        return self._parse_at_response(resp, api="bulk")

    async def _send_sandbox_form(
        self, client: httpx.AsyncClient, to: str, message: str
    ) -> dict[str, Any]:
        """Sandbox-compatible form POST — supports registered shortcode as `from`."""
        data: dict[str, str] = {
            "username": settings.AT_USERNAME,
            "to": to,
            "message": message,
        }
        sender = settings.AT_SENDER_ID.strip()
        if sender:
            data["from"] = sender
        url = f"{settings.at_api_base_url}/version1/messaging"
        resp = await client.post(
            url,
            headers={"apiKey": settings.AT_API_KEY, "Accept": "application/json"},
            data=data,
        )
        return self._parse_at_response(resp, api="sandbox_form")

    def _parse_at_response(self, resp: httpx.Response, *, api: str) -> dict[str, Any]:
        if resp.status_code >= 400:
            logger.warning("AT SMS HTTP %s (%s): %s", resp.status_code, api, resp.text[:300])
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "api": api,
                "http_status": resp.status_code,
                "error": resp.text[:500],
            }

        try:
            body: dict[str, Any] = resp.json()
        except Exception:
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "api": api,
                "http_status": resp.status_code,
                "error": "Invalid JSON response",
            }

        data = body.get("SMSMessageData") or {}
        summary = str(data.get("Message") or "")
        recipients = data.get("Recipients") or []
        recipient = recipients[0] if recipients else {}
        status_code = recipient.get("statusCode")
        message_id = recipient.get("messageId")

        if not recipients and summary and any(
            token in summary.lower()
            for token in ("invalid", "error", "reject", "insufficient")
        ):
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "api": api,
                "http_status": resp.status_code,
                "error": summary,
                "provider_response": body,
            }

        ok = status_code in SUCCESS_STATUS_CODES or (
            str(recipient.get("status", "")).lower() == "success"
        )
        if recipients and not ok:
            logger.warning(
                "AT SMS recipient rejected statusCode=%s status=%s",
                status_code,
                recipient.get("status"),
            )
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "api": api,
                "http_status": resp.status_code,
                "status_code": status_code,
                "provider_response": body,
            }

        if not recipients:
            return {
                "status": "FAILED",
                "provider": "africas_talking",
                "api": api,
                "http_status": resp.status_code,
                "error": summary or "No recipients in response",
                "provider_response": body,
            }

        return {
            "status": "SENT",
            "provider": "africas_talking",
            "api": api,
            "provider_response": body,
            "message_id": message_id,
            "status_code": status_code,
            "cost": recipient.get("cost"),
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
