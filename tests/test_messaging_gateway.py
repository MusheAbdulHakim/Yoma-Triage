import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from src.services.messaging_gateway import MessagingGateway


@pytest.mark.asyncio
async def test_mock_when_no_at_keys(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "")
    gw = MessagingGateway()
    result = await gw.send_sms("+233240000001", "test", dispatch_id=1, role="driver")
    assert result["status"] == "MOCKED"


@pytest.mark.asyncio
async def test_sent_when_at_configured(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"SMSMessageData": {"Recipients": [{"status": "Success"}]}}

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        gw = MessagingGateway()
        result = await gw.send_sms("+233240000001", "test", dispatch_id=2, role="driver")

    assert result["status"] == "SENT"
    assert "provider_response" in result


@pytest.mark.asyncio
async def test_failed_on_at_http_error(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")

    mock_response = MagicMock()
    mock_response.status_code = 400
    mock_response.text = "Invalid phone number"

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        gw = MessagingGateway()
        result = await gw.send_sms("+233240000001", "test", dispatch_id=3, role="driver")

    assert result["status"] == "FAILED"


@pytest.mark.asyncio
async def test_failed_on_at_exception(monkeypatch):
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_API_KEY", "test-key")
    monkeypatch.setattr("src.services.messaging_gateway.settings.AT_USERNAME", "sandbox")

    mock_client = AsyncMock()
    mock_client.post = AsyncMock(side_effect=TimeoutError("timeout"))
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)

    with patch("src.services.messaging_gateway.httpx.AsyncClient", return_value=mock_client):
        gw = MessagingGateway()
        result = await gw.send_sms("+233240000001", "test", dispatch_id=4, role="driver")

    assert result["status"] == "FAILED"
