"""Africa's Talking delivery reports reach the message they are about."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import DispatchLog, OutboundMessage
from src.services.outbox import enqueue_sms


async def _sent(db_session, *, message_id="ATXid_1", dispatch_id=None) -> OutboundMessage:
    message = enqueue_sms(
        db_session,
        recipient="+233200000101",
        body="Yoma: test",
        purpose="driver_offer" if dispatch_id else "test_message",
        dispatch_id=dispatch_id,
    )
    message.status = "SENT"
    message.provider_message_id = message_id
    await db_session.commit()
    return message


async def _report(client, **fields):
    data = {"phoneNumber": "+233200000101", "networkCode": "62001", **fields}
    return await client.post("/api/v1/sms/delivery", data=data)


@pytest.mark.asyncio
async def test_a_report_updates_its_message(client, db_session, seeded_db):
    message = await _sent(db_session)

    response = await _report(client, id="ATXid_1", status="Success")

    assert (response.status_code, response.text) == (200, "OK")
    await db_session.refresh(message)
    assert message.status == "SENT"  # what we did; delivery is what the network did
    assert message.delivery_status == "Success"
    assert message.delivery_updated_at is not None
    assert message.provider_response["delivery"] == {"status": "Success", "network_code": "62001"}
    assert "+233200000101" not in str(message.provider_response)


@pytest.mark.asyncio
async def test_a_failure_keeps_the_reason_and_logs_it_on_the_dispatch(
    client, db_session, seeded_db, sample_referral_payload
):
    created = await client.post("/api/v1/referral", json=sample_referral_payload)
    dispatch_id = created.json()["dispatch"]["id"]
    message = await _sent(db_session, message_id="ATXid_9", dispatch_id=dispatch_id)

    await _report(client, id="ATXid_9", status="Failed", failureReason="AbsentSubscriber")

    await db_session.refresh(message)
    assert message.delivery_status == "Failed"
    log = await db_session.scalar(
        select(DispatchLog).where(DispatchLog.action == "sms_delivery_report")
    )
    assert (log.response, log.target_role, log.dispatch_id) == ("Failed", "driver", dispatch_id)
    assert log.metadata_json["failure_reason"] == "AbsentSubscriber"


@pytest.mark.asyncio
async def test_later_reports_replace_earlier_ones(client, db_session, seeded_db):
    message = await _sent(db_session)
    await _report(client, id="ATXid_1", status="Sent")
    await _report(client, id="ATXid_1", status="Success")
    await db_session.refresh(message)
    assert message.delivery_status == "Success"


@pytest.mark.asyncio
async def test_a_report_for_an_unknown_message_is_acknowledged(client, db_session, seeded_db):
    response = await _report(client, id="nobody", status="Success")
    assert (response.status_code, response.text) == (200, "UNKNOWN")


@pytest.mark.asyncio
@pytest.mark.parametrize("fields", [{"id": "ATXid_1"}, {"status": "Success"}, {"id": "x", "status": "Weird"}])
async def test_unreadable_reports(client, db_session, seeded_db, fields):
    message = await _sent(db_session)
    response = await _report(client, **fields)
    assert response.status_code == 400
    await db_session.refresh(message)
    assert message.delivery_status is None


@pytest.mark.asyncio
async def test_the_secret_is_required_when_set(client, db_session, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.AT_WEBHOOK_SECRET", "s3cret")
    await _sent(db_session)
    assert (await _report(client, id="ATXid_1", status="Success")).status_code == 401
    response = await client.post(
        "/api/v1/sms/delivery?secret=s3cret",
        data={"id": "ATXid_1", "status": "Success"},
    )
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_the_sender_keeps_the_provider_message_id(db_session, seeded_db, monkeypatch):
    from contextlib import asynccontextmanager

    from src.services import outbox

    @asynccontextmanager
    async def same_session():
        yield db_session

    monkeypatch.setattr(outbox, "async_session", same_session)

    class Gateway:
        async def send_sms(self, to, message, dispatch_id, role):
            return {"status": "SENT", "message_id": "ATXid_42", "to": to, "message": message}

    message = enqueue_sms(
        db_session, recipient="+233200000101", body="x", purpose="test_message", dispatch_id=None
    )
    await db_session.commit()

    await outbox.OutboxSender(Gateway()).run_once()

    await db_session.refresh(message)
    assert (message.status, message.provider_message_id) == ("SENT", "ATXid_42")
