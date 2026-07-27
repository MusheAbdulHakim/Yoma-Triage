"""Africa's Talking SMS gateway tests (sandbox form + live bulk)."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from src.services.messaging_gateway import MessagingGateway, SUCCESS_STATUS_CODES


@pytest.mark.asyncio
async def test_mock_when_no_at_keys(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "")
    result = await MessagingGateway().send_sms(
        "+233240000001", "test", dispatch_id=1, role="driver"
    )
    assert result["status"] == "MOCKED"


@pytest.mark.asyncio
async def test_sandbox_uses_form_messaging_with_shortcode_from(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_SENDER_ID", "99193")
    monkeypatch.setattr(
        "src.services.messaging_gateway.settings.AT_API_BASE_URL",
        "https://api.sandbox.africastalking.com",
    )

    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "SMSMessageData": {
            "Message": "Sent to 1/1",
            "Recipients": [
                {
                    "statusCode": 101,
                    "number": "+233542441933",
                    "status": "Success",
                    "cost": "USD 0.0200",
                    "messageId": "ATXid_ok",
                }
            ],
        }
    }
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        result = await MessagingGateway().send_sms(
            "+233542441933", "hello", dispatch_id=2, role="driver"
        )

    assert result["status"] == "SENT"
    assert result["api"] == "sandbox_form"
    assert result["message_id"] == "ATXid_ok"
    args, kwargs = mock_client.post.await_args
    assert args[0] == "https://api.sandbox.africastalking.com/version1/messaging"
    assert kwargs["data"]["from"] == "99193"
    assert "json" not in kwargs


@pytest.mark.asyncio
async def test_live_uses_bulk_json(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "live-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "yomaapp")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_SENDER_ID", "99193")
    monkeypatch.setattr(
        "src.services.messaging_gateway.settings.AT_API_BASE_URL",
        "https://api.africastalking.com",
    )

    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "SMSMessageData": {
            "Message": "Sent to 1/1",
            "Recipients": [
                {
                    "statusCode": 101,
                    "number": "+233542441933",
                    "status": "Success",
                    "cost": "GHS 0.20",
                    "messageId": "ATPid_live",
                }
            ],
        }
    }
    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        result = await MessagingGateway().send_sms(
            "+233542441933", "hello", dispatch_id=3, role="driver"
        )

    assert result["status"] == "SENT"
    assert result["api"] == "bulk"
    args, kwargs = mock_client.post.await_args
    assert args[0] == "https://api.africastalking.com/version1/messaging/bulk"
    assert kwargs["json"]["senderId"] == "99193"
    assert kwargs["json"]["enqueue"] is True


@pytest.mark.asyncio
async def test_exception_is_failed(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")
    monkeypatch.setattr(
        "src.services.messaging_gateway.settings.AT_API_BASE_URL",
        "https://api.sandbox.africastalking.com",
    )

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(side_effect=TimeoutError("timeout"))
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        result = await MessagingGateway().send_sms(
            "+233240000001", "hello", dispatch_id=5, role="driver"
        )

    assert result["status"] == "FAILED"


def test_success_status_codes_include_sent_and_queued():
    assert {100, 101, 102} <= SUCCESS_STATUS_CODES
