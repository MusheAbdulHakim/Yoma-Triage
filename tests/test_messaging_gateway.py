"""Africa's Talking bulk SMS gateway tests."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from src.services.messaging_gateway import MessagingGateway, SUCCESS_STATUS_CODES


@pytest.mark.asyncio
async def test_mock_when_no_at_keys(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "")
    gw = MessagingGateway()
    result = await gw.send_sms("+233240000001", "test", dispatch_id=1, role="driver")
    assert result["status"] == "MOCKED"
    assert result["provider"] == "mock"


@pytest.mark.asyncio
async def test_bulk_json_request_shape_and_sent_status(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_SENDER_ID", "YOMATRIAGE")
    monkeypatch.setattr(
        "src.services.messaging_gateway.settings.AT_API_BASE_URL",
        "https://api.sandbox.africastalking.com",
    )

    mock_response = MagicMock()
    mock_response.status_code = 201
    mock_response.json.return_value = {
        "SMSMessageData": {
            "Message": "Sent to 1/1 Total Cost: GHS 0.00",
            "Recipients": [
                {
                    "statusCode": 101,
                    "number": "+233240000001",
                    "status": "Success",
                    "cost": "GHS 0.00",
                    "messageId": "ATPid_test",
                }
            ],
        }
    }

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        gw = MessagingGateway()
        result = await gw.send_sms("+233240000001", "hello", dispatch_id=2, role="driver")

    assert result["status"] == "SENT"
    assert result["provider"] == "africas_talking"
    assert result["message_id"] == "ATPid_test"
    mock_client.post.assert_awaited_once()
    args, kwargs = mock_client.post.await_args
    assert args[0] == "https://api.sandbox.africastalking.com/version1/messaging/bulk"
    assert kwargs["headers"]["apiKey"] == "test-key"
    assert kwargs["headers"]["Content-Type"] == "application/json"
    assert kwargs["json"] == {
        "username": "sandbox",
        "message": "hello",
        "senderId": "YOMATRIAGE",
        "phoneNumbers": ["+233240000001"],
        "enqueue": 1,
    }


@pytest.mark.asyncio
async def test_recipient_error_status_code_is_failed(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_SENDER_ID", "YOMATRIAGE")

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "SMSMessageData": {
            "Message": "Sent to 0/1",
            "Recipients": [
                {
                    "statusCode": 403,
                    "number": "+233240000001",
                    "status": "InvalidPhoneNumber",
                    "cost": "GHS 0.00",
                    "messageId": "None",
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
            "+233240000001", "hello", dispatch_id=3, role="driver"
        )

    assert result["status"] == "FAILED"
    assert result["status_code"] == 403


@pytest.mark.asyncio
async def test_http_error_is_failed(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")

    mock_response = MagicMock()
    mock_response.status_code = 401
    mock_response.text = "Unauthorized"
    mock_response.json.side_effect = ValueError("not json")

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        result = await MessagingGateway().send_sms(
            "+233240000001", "hello", dispatch_id=4, role="driver"
        )

    assert result["status"] == "FAILED"
    assert result["http_status"] == 401


@pytest.mark.asyncio
async def test_exception_is_failed(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")

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
    assert 100 in SUCCESS_STATUS_CODES
    assert 101 in SUCCESS_STATUS_CODES
    assert 102 in SUCCESS_STATUS_CODES
    assert 403 not in SUCCESS_STATUS_CODES
