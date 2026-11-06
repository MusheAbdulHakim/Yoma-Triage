"""Transactional SMS outbox (B3)."""
from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text, update

from src import parameters
from src.db.models import Dispatch, DispatchLog, OutboundMessage, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator
from src.services.messaging_gateway import MessagingGateway
from src.services.outbox import OutboxSender, enqueue_sms
from tests.conftest import queued_sms
from tests.postgres_support import (
    CHO_PHONE,
    DRIVER_PHONES,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

pytestmark = pytest.mark.postgres

DRIVER = DRIVER_PHONES[1]
SECRET_BODY = "BODY-MUST-NOT-BE-LOGGED"


class FakeGateway:
    """Records sends. ``fail`` makes every send fail, ``raises`` makes it raise."""

    def __init__(self, *, fail: bool = False, raises: bool = False, during=None):
        self.fail = fail
        self.raises = raises
        self.during = during
        self.sent: list[tuple[str, str]] = []

    async def send_sms(self, to, message, dispatch_id, role):
        if self.during:
            await self.during()
        self.sent.append((to, message))
        if self.raises:
            raise RuntimeError(f"boom {to} {message}")
        if self.fail:
            return {"status": "FAILED", "error": "rejected", "to": to, "message": message}
        return {"status": "SENT", "message_id": "m1", "to": to, "message": message}


async def _open(sessions) -> int:
    async with sessions() as session:
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            patient_hash="0" * 64,
            emergency_type="pph",
            severity="RED",
            risk_level="RED",
            status="CONFIRMED",
            client_request_id=str(uuid.uuid4()),
        )
        session.add(referral)
        await session.flush()
        dispatch = await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()
        return dispatch.id


async def _all(sessions) -> list[OutboundMessage]:
    async with sessions() as session:
        return await queued_sms(session)


async def _make_due(sessions) -> None:
    async with sessions() as session:
        await session.execute(
            update(OutboundMessage)
            .where(OutboundMessage.next_attempt_at.is_not(None))
            .values(next_attempt_at=datetime.now(UTC) - timedelta(seconds=1))
        )
        await session.commit()


async def _queue_one(sessions, *, purpose="hospital_pre_arrival", dispatch_id=None) -> int:
    async with sessions() as session:
        message = enqueue_sms(
            session,
            recipient=DRIVER,
            body=SECRET_BODY,
            purpose=purpose,
            dispatch_id=dispatch_id,
        )
        await session.commit()
        return message.id


async def _get(sessions, message_id: int) -> OutboundMessage:
    async with sessions() as session:
        return await session.get(OutboundMessage, message_id)


# --- Atomic with the state change ------------------------------------------------


@pytest.mark.asyncio
async def test_failed_commit_leaves_no_message(pg_sessions):  # noqa: F811
    async with pg_sessions() as session:
        enqueue_sms(
            session, recipient=DRIVER, body="x", purpose="inbound_reply", dispatch_id=None
        )
        await session.flush()
        await session.rollback()
    assert await _all(pg_sessions) == []


@pytest.mark.asyncio
async def test_referral_commits_its_offers_and_makes_no_provider_call(
    pg_sessions, monkeypatch  # noqa: F811
):
    from main import app

    async def fail(*args, **kwargs):
        raise AssertionError("no provider call inside a request")

    monkeypatch.setattr(MessagingGateway, "send_sms", fail)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/referral",
            json={
                "chps_compound_id": 1,
                "cho_phone": CHO_PHONE,
                "facility_id": 1,
                "patient_hash": "0" * 64,
                "emergency_type": "pph",
                "vitals_taken": False,
                "client_request_id": str(uuid.uuid4()),
            },
        )
    assert response.status_code == 201, response.text
    assert len(await _all(pg_sessions)) == 2


@pytest.mark.asyncio
async def test_unknown_purpose_is_refused(pg_sessions):  # noqa: F811
    async with pg_sessions() as session:
        with pytest.raises(ValueError):
            enqueue_sms(session, recipient=DRIVER, body="x", purpose="nope", dispatch_id=None)


# --- Sending ---------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sender_sends_and_records(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    gateway = FakeGateway()

    assert await OutboxSender(gateway).run_once() == 2

    assert {to for to, _ in gateway.sent} == set(DRIVER_PHONES.values())
    for message in await _all(pg_sessions):
        assert message.status == "SENT"
        assert message.attempts == 1
        assert message.next_attempt_at is None
        assert "message" not in message.provider_response
        assert "to" not in message.provider_response
    async with pg_sessions() as session:
        logs = (
            await session.scalars(
                select(DispatchLog).where(
                    DispatchLog.dispatch_id == dispatch_id, DispatchLog.action == "sms_send"
                )
            )
        ).all()
    assert len(logs) == 2


@pytest.mark.asyncio
async def test_nothing_is_sent_twice(pg_sessions):  # noqa: F811
    await _open(pg_sessions)
    gateway = FakeGateway()
    sender = OutboxSender(gateway)

    await sender.run_once()
    await sender.run_once()

    assert len(gateway.sent) == 2


@pytest.mark.asyncio
async def test_no_row_is_locked_while_sending(pg_sessions):  # noqa: F811
    """A slow provider must not block USSD: these locks would fail if anything were held."""
    dispatch_id = await _open(pg_sessions)
    checked = []

    async def assert_nothing_locked():
        async with pg_sessions() as session:
            await session.execute(
                select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update(nowait=True)
            )
            await session.execute(select(OutboundMessage).with_for_update(nowait=True))
            await session.rollback()
        checked.append(True)

    # One at a time, or these test locks would collide with each other.
    await OutboxSender(FakeGateway(during=assert_nothing_locked), concurrency=1).run_once(limit=2)

    assert len(checked) == 2


@pytest.mark.asyncio
async def test_parallel_senders_send_each_message_once(pg_sessions):  # noqa: F811
    for _ in range(10):
        await _queue_one(pg_sessions, purpose="inbound_reply")
    gateway = FakeGateway()

    await asyncio.gather(*(OutboxSender(gateway).run_once() for _ in range(5)))

    assert len(gateway.sent) == 10
    assert all(message.attempts == 1 for message in await _all(pg_sessions))


# --- Retry and failure -----------------------------------------------------------


@pytest.mark.asyncio
async def test_failure_retries_later_with_growing_backoff(pg_sessions):  # noqa: F811
    message_id = await _queue_one(pg_sessions)
    sender = OutboxSender(FakeGateway(fail=True))

    await sender.run_once()
    first = await _get(pg_sessions, message_id)
    assert (first.status, first.attempts) == ("PENDING", 1)
    first_wait = first.next_attempt_at - datetime.now(UTC)
    assert timedelta(seconds=10) < first_wait <= timedelta(seconds=parameters.OUTBOX_BACKOFF_SECONDS)

    assert await sender.run_once() == 0, "must wait for the backoff"

    await _make_due(pg_sessions)
    await sender.run_once()
    second = await _get(pg_sessions, message_id)
    assert second.attempts == 2
    assert second.next_attempt_at - datetime.now(UTC) > timedelta(
        seconds=parameters.OUTBOX_BACKOFF_SECONDS
    )


@pytest.mark.asyncio
async def test_a_raising_gateway_counts_as_a_failure(pg_sessions):  # noqa: F811
    message_id = await _queue_one(pg_sessions)
    await OutboxSender(FakeGateway(raises=True)).run_once()
    message = await _get(pg_sessions, message_id)
    assert (message.status, message.attempts) == ("PENDING", 1)


async def _exhaust(sessions, sender: OutboxSender) -> None:
    for _ in range(parameters.OUTBOX_MAX_ATTEMPTS):
        await _make_due(sessions)
        await sender.run_once()


@pytest.mark.asyncio
@pytest.mark.parametrize("purpose", ["hospital_pre_arrival", "driver_offer"])
async def test_exhausted_driver_or_hospital_sms_alerts_the_cho(pg_sessions, purpose):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await session.execute(update(OutboundMessage).values(status="SENT", next_attempt_at=None))
        await session.commit()
    message_id = await _queue_one(pg_sessions, purpose=purpose, dispatch_id=dispatch_id)

    await _exhaust(pg_sessions, OutboxSender(FakeGateway(fail=True)))

    message = await _get(pg_sessions, message_id)
    assert (message.status, message.attempts) == ("FAILED", parameters.OUTBOX_MAX_ATTEMPTS)
    async with pg_sessions() as session:
        alerts = await queued_sms(session, "send_failure_alert")
    assert len(alerts) == 1
    assert alerts[0].recipient == CHO_PHONE
    assert DRIVER not in alerts[0].body, "alert must not repeat the phone number"


@pytest.mark.asyncio
async def test_exhausted_cho_sms_does_not_alert_itself(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await session.execute(update(OutboundMessage).values(status="SENT", next_attempt_at=None))
        await session.commit()
    message_id = await _queue_one(pg_sessions, purpose="cho_escalation", dispatch_id=dispatch_id)

    await _exhaust(pg_sessions, OutboxSender(FakeGateway(fail=True)))

    assert (await _get(pg_sessions, message_id)).status == "FAILED"
    async with pg_sessions() as session:
        assert await queued_sms(session, "send_failure_alert") == []


@pytest.mark.asyncio
async def test_failed_sends_are_no_longer_treated_as_offers(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    sender = OutboxSender(FakeGateway(fail=True))
    await _exhaust(pg_sessions, sender)

    async with pg_sessions() as session:
        notified = await DispatchOrchestrator()._was_notified(session, dispatch_id, 1)
    assert notified is False


# --- Crash recovery --------------------------------------------------------------


@pytest.mark.asyncio
async def test_message_abandoned_mid_send_is_retried_after_the_lease(pg_sessions):  # noqa: F811
    message_id = await _queue_one(pg_sessions)
    sender = OutboxSender(FakeGateway())
    # Claim, then "crash" before sending.
    claimed = await sender._claim(10)
    assert [message.id for message in claimed] == [message_id]
    assert (await _get(pg_sessions, message_id)).status == "SENDING"

    assert await sender.run_once() == 0, "the lease is still held"

    await _make_due(pg_sessions)
    assert await sender.run_once() == 1
    message = await _get(pg_sessions, message_id)
    assert (message.status, message.attempts) == ("SENT", 2)


@pytest.mark.asyncio
async def test_late_result_from_an_expired_lease_is_ignored(pg_sessions):  # noqa: F811
    message_id = await _queue_one(pg_sessions)
    sender = OutboxSender(FakeGateway())
    old_claim = (await sender._claim(10))[0]
    await _make_due(pg_sessions)
    await sender.run_once()

    await sender._record(old_claim, {"status": "FAILED", "error": "too late"})

    assert (await _get(pg_sessions, message_id)).status == "SENT"


@pytest.mark.asyncio
async def test_final_attempt_abandoned_mid_send_is_failed_and_alerts(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await session.execute(update(OutboundMessage).values(status="SENT", next_attempt_at=None))
        await session.commit()
    message_id = await _queue_one(
        pg_sessions, purpose="hospital_pre_arrival", dispatch_id=dispatch_id
    )
    async with pg_sessions() as session:
        await session.execute(
            update(OutboundMessage)
            .where(OutboundMessage.id == message_id)
            .values(status="SENDING", attempts=parameters.OUTBOX_MAX_ATTEMPTS)
        )
        await session.commit()
    await _make_due(pg_sessions)

    await OutboxSender(FakeGateway()).run_once()

    assert (await _get(pg_sessions, message_id)).status == "FAILED"
    async with pg_sessions() as session:
        assert len(await queued_sms(session, "send_failure_alert")) == 1


# --- Stale offers ----------------------------------------------------------------


@pytest.mark.asyncio
async def test_offer_is_cancelled_once_another_driver_has_claimed(pg_sessions):  # noqa: F811
    dispatch_id = await _open(pg_sessions)
    async with pg_sessions() as session:
        await DispatchOrchestrator().handle_accept(session, dispatch_id, 1)
        await session.commit()
    gateway = FakeGateway()

    await OutboxSender(gateway).run_once()

    async with pg_sessions() as session:
        offers = await queued_sms(session, "driver_offer")
        hospital = await queued_sms(session, "hospital_pre_arrival")
    assert {message.status for message in offers} == {"CANCELLED"}
    assert hospital[0].status == "SENT"
    assert len(gateway.sent) == 1


# --- Nothing sensitive in logs ---------------------------------------------------


@pytest.mark.asyncio
async def test_phones_and_bodies_stay_out_of_logs_on_every_path(
    pg_sessions, caplog, monkeypatch  # noqa: F811
):
    caplog.set_level(logging.DEBUG)
    dispatch_id = await _open(pg_sessions)
    await _queue_one(pg_sessions, dispatch_id=dispatch_id)

    await OutboxSender(FakeGateway(raises=True)).run_once()
    await _exhaust(pg_sessions, OutboxSender(FakeGateway(fail=True)))

    # The real gateway, in mock mode and against a failing provider.
    gateway = MessagingGateway()
    await gateway.send_sms(DRIVER, SECRET_BODY, 1, "driver")
    monkeypatch.setattr("src.config.settings.AT_API_KEY", "k")
    monkeypatch.setattr("src.config.settings.AT_USERNAME", "yoma")

    async def provider_error(self, url, **kwargs):
        request = httpx.Request("POST", url)
        return httpx.Response(500, text=f"rejected {DRIVER} {SECRET_BODY}", request=request)

    monkeypatch.setattr(httpx.AsyncClient, "post", provider_error)
    await gateway.send_sms(DRIVER, SECRET_BODY, 1, "driver")

    async def provider_down(self, url, **kwargs):
        raise httpx.ConnectError(f"cannot reach for {DRIVER} {SECRET_BODY}")

    monkeypatch.setattr(httpx.AsyncClient, "post", provider_down)
    await gateway.send_sms(DRIVER, SECRET_BODY, 1, "driver")

    assert caplog.records, "expected something to be logged"
    for phone in (*DRIVER_PHONES.values(), CHO_PHONE):
        assert phone not in caplog.text
    assert SECRET_BODY not in caplog.text
    assert "No transport" not in caplog.text


@pytest.mark.asyncio
async def test_migration_table_matches_the_brief(pg_sessions):  # noqa: F811
    async with pg_sessions() as session:
        rows = await session.execute(
            text(
                "select column_name from information_schema.columns "
                "where table_name = 'outbound_messages' and table_schema = current_schema()"
            )
        )
        columns = {row[0] for row in rows}
    assert columns == {
        "id", "recipient", "body", "purpose", "dispatch_id", "status", "attempts",
        "next_attempt_at", "provider_response", "created_at",
    }
