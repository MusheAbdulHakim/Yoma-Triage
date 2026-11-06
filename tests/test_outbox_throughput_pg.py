"""Sender throughput: a hung provider can't hold up a new emergency (item 2)."""
from __future__ import annotations

import asyncio
import inspect
import time
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select, update

import main
from src import parameters
from src.config import Settings
from src.db.models import OutboundMessage
from src.services.outbox import OTHER_PRIORITY, PURPOSES, ROLE_PRIORITY, OutboxSender, enqueue_sms
from src.services.workers import run_worker_loop
from tests.postgres_support import (
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

pytestmark = pytest.mark.postgres

NEW_ALERT = "+233240009999"


class Gateway:
    """Hangs on every number except those in ``works``, and records what it saw."""

    def __init__(self, *, works: tuple[str, ...] = (), hang: bool = True):
        self.works = works
        self.hang = hang
        self.started: dict[str, float] = {}
        self.finished: list[str] = []
        self.in_flight = 0
        self.most_in_flight = 0

    async def send_sms(self, to, message, dispatch_id, role):
        self.started[to] = time.monotonic()
        self.in_flight += 1
        self.most_in_flight = max(self.most_in_flight, self.in_flight)
        try:
            if self.hang and to not in self.works:
                await asyncio.sleep(3600)
            await asyncio.sleep(0.01)
            self.finished.append(to)
            return {"status": "SENT"}
        finally:
            self.in_flight -= 1


async def _queue(sessions, purpose: str, count: int, *, attempts: int = 0, start: int = 0) -> None:
    async with sessions() as session:
        for index in range(start, start + count):
            message = enqueue_sms(
                session,
                recipient=f"+2332410{index:05d}",
                body="b",
                purpose=purpose,
                dispatch_id=None,
            )
            message.attempts = attempts
        await session.commit()


async def _queue_new_alert(sessions) -> None:
    async with sessions() as session:
        enqueue_sms(
            session, recipient=NEW_ALERT, body="b", purpose="driver_offer", dispatch_id=None
        )
        await session.commit()


async def _seconds_until_new_alert_goes_out(sessions, gateway, *, backlog_settles=1.0) -> float:
    """Runs the real worker loop, with real time limits, as the server does."""
    stop = asyncio.Event()
    worker = asyncio.create_task(
        run_worker_loop(
            "sms-outbox", OutboxSender(gateway).drain, parameters.OUTBOX_POLL_SECONDS, stop
        )
    )
    try:
        await asyncio.sleep(backlog_settles)
        await _queue_new_alert(sessions)
        queued_at = time.monotonic()
        while NEW_ALERT not in gateway.finished:
            assert time.monotonic() - queued_at < 30, "the alert never went out"
            await asyncio.sleep(0.05)
        return time.monotonic() - queued_at
    finally:
        stop.set()
        worker.cancel()
        await asyncio.gather(worker, return_exceptions=True)


@pytest.mark.asyncio
async def test_new_driver_alert_beats_a_backlog_on_a_hung_provider(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", 20)
    await _queue(pg_sessions, "cho_arrival", 20, start=100)
    await _queue(pg_sessions, "inbound_reply", 20, start=200)

    seconds = await _seconds_until_new_alert_goes_out(pg_sessions, Gateway(works=(NEW_ALERT,)))

    assert seconds < 10, f"took {seconds:.1f} s"


@pytest.mark.asyncio
async def test_new_driver_alert_beats_older_driver_retries(pg_sessions):  # noqa: F811
    """Retries to dead numbers come after first attempts, even in the same priority."""
    await _queue(pg_sessions, "driver_offer", 30, attempts=1)

    seconds = await _seconds_until_new_alert_goes_out(pg_sessions, Gateway(works=(NEW_ALERT,)))

    assert seconds < 10, f"took {seconds:.1f} s"


@pytest.mark.asyncio
async def test_a_hung_send_times_out_counts_as_failed_and_retries(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", 1)
    started = time.monotonic()

    await OutboxSender(Gateway(), send_timeout=0.2).run_once()

    assert time.monotonic() - started < 2
    async with pg_sessions() as session:
        row = await session.scalar(select(OutboundMessage))
    assert row.status == "PENDING"
    assert row.attempts == 1
    assert row.provider_response["error_type"] == "TimeoutError"
    assert row.next_attempt_at > datetime.now(UTC)


@pytest.mark.asyncio
async def test_sends_really_run_in_parallel_up_to_the_limit(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", 12)
    gateway = Gateway()
    started = time.monotonic()

    await OutboxSender(gateway, concurrency=3, send_timeout=0.3).run_once(limit=12)

    assert gateway.most_in_flight == 3, "never more than the limit, and it reaches the limit"
    assert len(gateway.started) == 12
    # 4 rounds of 3 at 0.3 s each. One at a time would take 3.6 s.
    assert time.monotonic() - started < 3


@pytest.mark.asyncio
async def test_default_limits_come_from_the_parameters(pg_sessions, monkeypatch):  # noqa: F811
    sender = OutboxSender(Gateway())
    assert sender.concurrency == parameters.OUTBOX_SEND_CONCURRENCY == 5
    assert sender.send_timeout == parameters.OUTBOX_SEND_TIMEOUT_SECONDS == 5


@pytest.mark.asyncio
async def test_a_pass_claims_no_more_than_it_can_send(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", 12)
    assert await OutboxSender(Gateway(hang=False), concurrency=5).run_once() == 5


@pytest.mark.asyncio
async def test_priority_order(pg_sessions):  # noqa: F811
    """Queued lowest priority first, and must go out highest first."""
    for purpose, start in [
        ("inbound_reply", 0),
        ("cho_arrival", 10),
        ("hospital_pre_arrival", 20),
        ("driver_offer", 30),
    ]:
        await _queue(pg_sessions, purpose, 1, start=start)
    gateway = Gateway(hang=False)
    sender = OutboxSender(gateway, concurrency=1)

    for _ in range(4):
        await sender.run_once()

    assert gateway.finished == [
        "+233241000030",
        "+233241000020",
        "+233241000010",
        "+233241000000",
    ]


def test_every_purpose_maps_to_the_briefed_priority():
    assert ROLE_PRIORITY == {"driver": 0, "hospital": 1, "cho": 2}
    assert PURPOSES["driver_offer"].role == "driver"
    assert PURPOSES["hospital_pre_arrival"].role == "hospital"
    assert PURPOSES["cho_arrival"].role == "cho"
    assert PURPOSES["inbound_reply"].role not in ROLE_PRIORITY
    assert max(ROLE_PRIORITY.values()) < OTHER_PRIORITY


@pytest.mark.asyncio
async def test_a_message_due_later_is_not_sent_early_whatever_its_priority(
    pg_sessions,  # noqa: F811
):
    await _queue(pg_sessions, "driver_offer", 1)
    async with pg_sessions() as session:
        await session.execute(
            update(OutboundMessage).values(next_attempt_at=datetime.now(UTC) + timedelta(hours=1))
        )
        await session.commit()
    assert await OutboxSender(Gateway(hang=False)).run_once() == 0


@pytest.mark.asyncio
async def test_drain_sends_a_healthy_backlog_up_to_the_batch_size(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", parameters.OUTBOX_BATCH_SIZE + 3)
    gateway = Gateway(hang=False)

    attempted = await OutboxSender(gateway, concurrency=5).drain()

    assert attempted == parameters.OUTBOX_BATCH_SIZE
    assert len(gateway.finished) == parameters.OUTBOX_BATCH_SIZE


@pytest.mark.asyncio
async def test_drain_stops_when_nothing_is_left(pg_sessions):  # noqa: F811
    await _queue(pg_sessions, "hospital_pre_arrival", 7)
    assert await OutboxSender(Gateway(hang=False), concurrency=5).drain() == 7


def test_the_server_runs_the_draining_sender():
    assert "OutboxSender().drain" in inspect.getsource(main.lifespan)


@pytest.mark.parametrize(
    ("name", "value", "error"),
    [
        ("OUTBOX_SEND_CONCURRENCY", 0, "OUTBOX_SEND_CONCURRENCY must be at least 1"),
        ("OUTBOX_SEND_TIMEOUT_SECONDS", 0, "OUTBOX_SEND_TIMEOUT_SECONDS must be above 0"),
    ],
)
def test_settings_that_would_stop_all_sms_refuse_to_start(monkeypatch, name, value, error):
    candidate = Settings()
    monkeypatch.setattr(candidate, name, value)
    assert error in candidate.startup_errors()
