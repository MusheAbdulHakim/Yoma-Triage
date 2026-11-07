"""Transactional outbox for all outbound SMS.

Business code calls ``enqueue_sms`` in the same transaction as its state change, so a
message exists if and only if that change committed. ``OutboxSender`` sends separately
and never holds a row lock during a network call: it claims rows in a short transaction,
sends with no transaction open, then records the result in another short transaction.

A pass claims only as many messages as it can send at once, highest priority first, and
each send has a short time limit. So however slow the provider is, a new driver alert
waits for at most the pass in progress, not for a backlog.

Delivery is at least once. If the process dies after sending but before recording, the
claim expires and the message is sent again. Duplicate SMS is the accepted cost, because
a lost emergency SMS is worse.

Phone numbers and message bodies must never reach application logs.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import case, select
from sqlalchemy.ext.asyncio import AsyncSession

from src import parameters
from src.config import settings
from src.db.database import async_session
from src.db.models import Cho, Dispatch, DispatchLog, OutboundMessage, Referral
from src.services.messaging_gateway import MessagingGateway

logger = logging.getLogger(__name__)

PENDING = "PENDING"
SENDING = "SENDING"
SENT = "SENT"
FAILED = "FAILED"
CANCELLED = "CANCELLED"


@dataclass(frozen=True)
class Purpose:
    role: str
    sent_action: str
    failed_action: str


PURPOSES = {
    "driver_offer": Purpose("driver", "sms_send", "sms_failed"),
    "hospital_pre_arrival": Purpose("hospital", "hospital_notify", "hospital_notify_failed"),
    "cho_escalation": Purpose("cho", "cho_give_up", "cho_give_up_failed"),
    "cho_arrival": Purpose("cho", "cho_arrival_notify", "cho_arrival_notify_failed"),
    "cho_late_accept": Purpose("cho", "cho_late_accept_notify", "cho_late_accept_notify_failed"),
    "divert_driver": Purpose("driver", "divert_notify", "divert_notify_failed"),
    "divert_old_hospital": Purpose("hospital", "divert_notify", "divert_notify_failed"),
    "cancel_driver": Purpose("driver", "cancel_notify", "cancel_notify_failed"),
    "cancel_hospital": Purpose("hospital", "cancel_notify", "cancel_notify_failed"),
    "divert_cho": Purpose("cho", "divert_notify", "divert_notify_failed"),
    "inbound_reply": Purpose("inbound_reply", "inbound_status_reply", "inbound_reply_failed"),
    "inbound_confirm_ack": Purpose("inbound_reply", "inbound_confirm_ack", "inbound_reply_failed"),
    "send_failure_alert": Purpose("cho", "send_failure_alert", "send_failure_alert_failed"),
}
# Who to reach first when there's a queue. Lower goes first.
ROLE_PRIORITY = {"driver": 0, "hospital": 1, "cho": 2}
OTHER_PRIORITY = 3
_SEND_ORDER = case(
    {name: ROLE_PRIORITY.get(purpose.role, OTHER_PRIORITY) for name, purpose in PURPOSES.items()},
    value=OutboundMessage.purpose,
    else_=OTHER_PRIORITY,
)
# If one of these roles can't be reached, the CHO has to step in.
ALERT_CHO_ROLES = frozenset({"driver", "hospital"})
# What the provider returned is kept for diagnosis, minus who was messaged and what it said.
_REDACTED_RESPONSE_KEYS = frozenset({"to", "message", "dispatch_id", "role"})


def enqueue_sms(
    session: AsyncSession,
    *,
    recipient: str,
    body: str,
    purpose: str,
    dispatch_id: int | None,
) -> OutboundMessage:
    """Add a message to the caller's transaction. Nothing is sent until it commits."""
    if purpose not in PURPOSES:
        raise ValueError(f"Unknown SMS purpose: {purpose}")
    message = OutboundMessage(
        recipient=recipient,
        body=body,
        purpose=purpose,
        dispatch_id=dispatch_id,
        status=PENDING,
        attempts=0,
        next_attempt_at=datetime.now(UTC),
    )
    session.add(message)
    return message


async def _active_cho_phones(session: AsyncSession, compound_id: int) -> list[str]:
    phones = await session.scalars(
        select(Cho.phone).where(Cho.compound_id == compound_id, Cho.active.is_(True)).order_by(Cho.id)
    )
    return list(phones)


async def _enqueue_to_chos(
    session: AsyncSession,
    phones: list[str],
    *,
    referral: Referral,
    body: str,
    purpose: str,
    dispatch_id: int | None,
) -> None:
    if not phones:
        # Nobody to tell. Recorded rather than sent to a number that may be nobody's.
        logger.error("No active CHO to alert for referral %s (%s)", referral.id, purpose)
        if dispatch_id is not None:
            session.add(
                DispatchLog(
                    dispatch_id=dispatch_id,
                    action="cho_alert_no_recipient",
                    target_role="cho",
                    response="NO_ACTIVE_CHO",
                    metadata_json={"purpose": purpose},
                )
            )
    for phone in phones:
        enqueue_sms(session, recipient=phone, body=body, purpose=purpose, dispatch_id=dispatch_id)


async def enqueue_cho_alert(
    session: AsyncSession, referral: Referral, *, body: str, purpose: str, dispatch_id: int | None
) -> None:
    """Something went wrong and someone must act: every active CHO at the compound."""
    await _enqueue_to_chos(
        session,
        await _active_cho_phones(session, referral.chps_compound_id),
        referral=referral,
        body=body,
        purpose=purpose,
        dispatch_id=dispatch_id,
    )


async def enqueue_cho_update(
    session: AsyncSession, referral: Referral, *, body: str, purpose: str, dispatch_id: int | None
) -> None:
    """A routine update: the CHO who sent the referral.

    If that CHO has left the compound or been deactivated, the update goes to whoever is
    there now, so it isn't lost and doesn't go to someone no longer responsible.
    """
    sender = await session.get(Cho, referral.cho_id) if referral.cho_id is not None else None
    if sender is not None and sender.active and sender.compound_id == referral.chps_compound_id:
        phones = [sender.phone]
    else:
        phones = await _active_cho_phones(session, referral.chps_compound_id)
    await _enqueue_to_chos(
        session,
        phones,
        referral=referral,
        body=body,
        purpose=purpose,
        dispatch_id=dispatch_id,
    )


def _backoff(attempts: int) -> timedelta:
    return timedelta(seconds=parameters.OUTBOX_BACKOFF_SECONDS * 2 ** max(attempts - 1, 0))


def _safe_response(result: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in result.items() if key not in _REDACTED_RESPONSE_KEYS}


@dataclass(frozen=True)
class _Claimed:
    id: int
    recipient: str
    body: str
    purpose: str
    dispatch_id: int | None
    attempts: int


class OutboxSender:
    def __init__(
        self,
        gateway: MessagingGateway | None = None,
        *,
        concurrency: int | None = None,
        send_timeout: float | None = None,
    ):
        self.gateway = gateway or MessagingGateway()
        self.concurrency = concurrency or settings.OUTBOX_SEND_CONCURRENCY
        self.send_timeout = send_timeout or settings.OUTBOX_SEND_TIMEOUT_SECONDS

    async def run_once(self, limit: int | None = None) -> int:
        """One pass: send what's due, in parallel. Returns how many were attempted.

        Takes at most the send timeout, however the provider behaves, because nothing
        claimed here waits behind anything else claimed here.
        """
        claimed = await self._claim(limit or self.concurrency)
        slots = asyncio.Semaphore(self.concurrency)

        async def send(message: _Claimed) -> dict[str, Any]:
            async with slots:
                return await self._send(message)

        results = await asyncio.gather(*(send(message) for message in claimed))
        for message, result in zip(claimed, results, strict=True):
            await self._record(message, result)
        return len(claimed)

    async def drain(self) -> int:
        """Passes until nothing more is due, up to the batch size. Runs in the worker.

        Each pass claims afresh, so an alert that arrives mid-drain goes in the next one.
        """
        attempted = 0
        while attempted < parameters.OUTBOX_BATCH_SIZE:
            count = await self.run_once()
            attempted += count
            if count < self.concurrency:
                break
        return attempted

    async def _claim(self, limit: int) -> list[_Claimed]:
        """Mark due messages SENDING and release their locks before anything is sent.

        The claim's next_attempt_at is a lease: if this process dies, the message comes
        due again and another run picks it up.
        """
        now = datetime.now(UTC)
        claimed: list[_Claimed] = []
        async with async_session() as session:
            rows = (
                await session.scalars(
                    select(OutboundMessage)
                    .where(
                        OutboundMessage.status.in_((PENDING, SENDING)),
                        OutboundMessage.next_attempt_at <= now,
                    )
                    # First attempts go before retries, so messages to a failing
                    # number can't get in the way of a new emergency.
                    .order_by(
                        _SEND_ORDER,
                        OutboundMessage.attempts,
                        OutboundMessage.next_attempt_at,
                        OutboundMessage.id,
                    )
                    .limit(limit)
                    .with_for_update(skip_locked=True)
                    .execution_options(populate_existing=True)
                )
            ).all()
            for row in rows:
                if await self._offer_is_stale(session, row):
                    row.status = CANCELLED
                    row.next_attempt_at = None
                elif row.attempts >= parameters.OUTBOX_MAX_ATTEMPTS:
                    # Only reached when the lease on a final attempt expired.
                    await self._fail(session, row, {"error": "No result recorded for last attempt"})
                else:
                    row.status = SENDING
                    row.attempts += 1
                    row.next_attempt_at = now + timedelta(
                        seconds=parameters.OUTBOX_SENDING_LEASE_SECONDS
                    )
                    claimed.append(
                        _Claimed(
                            id=row.id,
                            recipient=row.recipient,
                            body=row.body,
                            purpose=row.purpose,
                            dispatch_id=row.dispatch_id,
                            attempts=row.attempts,
                        )
                    )
            await session.commit()
        return claimed

    @staticmethod
    async def _offer_is_stale(session: AsyncSession, row: OutboundMessage) -> bool:
        """Don't tell a driver about an emergency someone else has already taken."""
        if row.purpose != "driver_offer" or row.dispatch_id is None:
            return False
        from src.services.dispatch_orchestrator import ACCEPT_ELIGIBLE

        dispatch = await session.get(Dispatch, row.dispatch_id)
        return dispatch is not None and dispatch.status not in ACCEPT_ELIGIBLE

    async def _send(self, message: _Claimed) -> dict[str, Any]:
        """Runs with no transaction open and no row locked."""
        try:
            return await asyncio.wait_for(
                self.gateway.send_sms(
                    message.recipient,
                    message.body,
                    message.dispatch_id or 0,
                    PURPOSES[message.purpose].role,
                ),
                timeout=self.send_timeout,
            )
        except Exception as exc:
            logger.warning(
                "SMS send raised for outbound message %s: %s", message.id, type(exc).__name__
            )
            return {"status": "FAILED", "error_type": type(exc).__name__}

    async def _record(self, message: _Claimed, result: dict[str, Any]) -> None:
        async with async_session() as session:
            row = await session.scalar(
                select(OutboundMessage)
                .where(OutboundMessage.id == message.id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            # If the lease expired, a newer attempt owns this row now.
            if row is None or row.status != SENDING or row.attempts != message.attempts:
                return
            row.provider_response = _safe_response(result)
            if result.get("status") != "FAILED":
                row.status = SENT
                row.next_attempt_at = None
                self._log_outcome(session, row, PURPOSES[row.purpose].sent_action, result)
            elif row.attempts >= parameters.OUTBOX_MAX_ATTEMPTS:
                await self._fail(session, row, result)
            else:
                row.status = PENDING
                row.next_attempt_at = datetime.now(UTC) + _backoff(row.attempts)
            await session.commit()

    async def _fail(
        self, session: AsyncSession, row: OutboundMessage, result: dict[str, Any]
    ) -> None:
        purpose = PURPOSES[row.purpose]
        row.status = FAILED
        row.next_attempt_at = None
        row.provider_response = _safe_response(result)
        logger.error("Outbound message %s failed permanently (%s)", row.id, row.purpose)
        self._log_outcome(session, row, purpose.failed_action, {**result, "status": FAILED})
        if purpose.role in ALERT_CHO_ROLES and row.dispatch_id is not None:
            await self._alert_cho(session, row, purpose.role)

    @staticmethod
    async def _alert_cho(session: AsyncSession, row: OutboundMessage, role: str) -> None:
        dispatch = await session.get(Dispatch, row.dispatch_id)
        referral = await session.get(Referral, dispatch.referral_id) if dispatch else None
        if referral is None:
            return
        await enqueue_cho_alert(
            session,
            referral,
            body=(
                f"Yoma: SMS to the {role} for Ref #{referral.id} could not be delivered. "
                "Call them directly."
            ),
            purpose="send_failure_alert",
            dispatch_id=row.dispatch_id,
        )

    @staticmethod
    def _log_outcome(
        session: AsyncSession, row: OutboundMessage, action: str, result: dict[str, Any]
    ) -> None:
        if row.dispatch_id is None:
            return
        session.add(
            DispatchLog(
                dispatch_id=row.dispatch_id,
                action=action,
                target_phone=row.recipient,
                target_role=PURPOSES[row.purpose].role,
                response=str(result.get("status", "")),
                metadata_json={
                    "outbound_message_id": row.id,
                    "message_preview": row.body.split("\n", 1)[0],
                    **_safe_response(result),
                },
            )
        )
