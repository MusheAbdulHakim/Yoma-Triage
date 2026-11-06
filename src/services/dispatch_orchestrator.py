"""Deterministic cascade dispatch — no LLM.

Every state change and the SMS it causes commit together, in one transaction: messages
go into the outbox (src/services/outbox.py), and nothing here calls Africa's Talking.
"""
from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src import parameters
from src.config import settings
from src.db.database import async_session
from src.db.models import (
    CHPSCompound,
    Dispatch,
    DispatchLog,
    Driver,
    Facility,
    OutboundMessage,
    Referral,
    Wallet,
)
from src.services.driver_pool import DriverPoolManager
from src.services.hospital_notifier import HospitalNotifier
from src.services.outbox import FAILED as MESSAGE_FAILED
from src.services.outbox import enqueue_sms

logger = logging.getLogger(__name__)

CLAIMABLE = {"PENDING", "TIER1_NOTIFIED", "TIER2_NOTIFIED"}
# A notified driver may still claim after the cascade gives up, within a time window.
ACCEPT_ELIGIBLE = CLAIMABLE | {"FAILED"}
ASSIGNED = {"ACCEPTED", "HOSPITAL_NOTIFIED", "HOSPITAL_CONFIRMED"}
ARRIVAL_ELIGIBLE = {"HOSPITAL_NOTIFIED", "HOSPITAL_CONFIRMED"}
NEXT_ACTION_TIER_TIMEOUT = "tier_timeout"
FUEL_STIPEND_GHS = parameters.FUEL_STIPEND_GHS
ACCEPTED_REPLY = "END Accepted! Proceed to CHPS. (Fuel stipend: mock ledger until MoMo is live.)"


def _locked_dispatch(dispatch_id: int):
    """SELECT ... FOR UPDATE that returns the row as committed once the lock is held.

    Without populate_existing, a Dispatch already loaded in the session keeps its
    stale attributes after the lock wait, and two drivers can both claim it.
    """
    return (
        select(Dispatch)
        .where(Dispatch.id == dispatch_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )


def build_driver_offer_message(
    *,
    tier: int,
    compound_id: int,
    referral_id: int,
    vehicle_label: str,
    ussd_code: str | None = None,
) -> str:
    """SMS body for cascade driver offers (tier 1 Motor-King, tier 2 personal)."""
    if tier <= 1:
        role = "Motor-King"
    else:
        role = vehicle_label or "Personal vehicle"
        if "personal" in role.lower():
            role = "Personal vehicle backup"
    code = (ussd_code if ussd_code is not None else settings.AT_USSD_SERVICE_CODE).strip()
    dial = f"Dial {code} to ACCEPT." if code else "Dial USSD to ACCEPT."
    return (
        f"Yoma: {role} needed. CHPS #{compound_id} Ref #{referral_id}. "
        f"{dial}"
    )


def build_cho_escalation_message(*, referral_id: int, compound_id: int) -> str:
    """Tier-3 / no-candidate CHO message — NAS / manual ambulance coordination."""
    return (
        f"Yoma: Tier3 — no transport for Ref #{referral_id} (CHPS #{compound_id}). "
        f"Escalate NAS / coordinate ambulance manually."
    )


def build_cho_late_accept_message(
    *, referral_id: int, compound_id: int, driver_name: str, driver_phone: str
) -> str:
    """Sent when a driver claims after the CHO was told to coordinate manually."""
    return (
        f"Yoma: Driver {driver_name} ({driver_phone}) accepted LATE for Ref #{referral_id} "
        f"(CHPS #{compound_id}). Stand down manual transport if no longer needed."
    )


def _late_claim_open(dispatch: Dispatch) -> bool:
    initiated_at = dispatch.initiated_at
    if initiated_at.tzinfo is None:
        initiated_at = initiated_at.replace(tzinfo=UTC)
    window = timedelta(minutes=settings.LATE_CLAIM_WINDOW_MINUTES)
    return datetime.now(UTC) - initiated_at <= window


class DispatchOrchestrator:
    def __init__(self) -> None:
        self.pool = DriverPoolManager()
        self.hospital = HospitalNotifier()

    async def initiate_dispatch(self, session: AsyncSession, referral_id: int) -> Dispatch:
        referral = await session.get(Referral, referral_id)
        if not referral:
            raise ValueError(f"referral {referral_id} not found")

        dispatch = Dispatch(
            referral_id=referral.id,
            facility_id=referral.facility_id,
            status="PENDING",
            current_tier=0,
            declined_driver_ids=[],
        )
        session.add(dispatch)
        await session.flush()
        await self._notify_tier(session, dispatch, referral, tier=1)
        await session.flush()
        return dispatch

    @staticmethod
    def _set_next_action(dispatch: Dispatch) -> None:
        """Stored with the state change, so a restart can't lose the schedule."""
        if dispatch.status in CLAIMABLE:
            dispatch.next_action = NEXT_ACTION_TIER_TIMEOUT
            dispatch.next_action_at = datetime.now(UTC) + timedelta(
                seconds=settings.CASCADE_TIER_SECONDS
            )
        else:
            dispatch.next_action = None
            dispatch.next_action_at = None

    async def _notify_tier(
        self,
        session: AsyncSession,
        dispatch: Dispatch,
        referral: Referral,
        tier: int,
    ) -> None:
        declined = list(dispatch.declined_driver_ids or [])
        candidates = await self.pool.get_candidates(
            session, referral.chps_compound_id, tier, declined
        )
        dispatch.current_tier = tier

        # Tier three is intentionally a CHO manual-coordination notification,
        # never an attempt to contact an emergency contact.
        if tier >= 3 or (tier == 2 and not candidates):
            compound = await session.get(CHPSCompound, referral.chps_compound_id)
            enqueue_sms(
                session,
                recipient=compound.cho_phone,
                body=build_cho_escalation_message(
                    referral_id=referral.id,
                    compound_id=referral.chps_compound_id,
                ),
                purpose="cho_escalation",
                dispatch_id=dispatch.id,
            )
            dispatch.status = "FAILED"
            self._set_next_action(dispatch)
            return

        dispatch.status = f"TIER{tier}_NOTIFIED"
        self._set_next_action(dispatch)
        for driver in candidates:
            enqueue_sms(
                session,
                recipient=driver.phone,
                body=build_driver_offer_message(
                    tier=tier,
                    compound_id=referral.chps_compound_id,
                    referral_id=referral.id,
                    vehicle_label=driver.vehicle_type or "Personal vehicle",
                ),
                purpose="driver_offer",
                dispatch_id=dispatch.id,
            )

    async def _was_notified(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> bool:
        """True if this dispatch offer went to the driver, at any tier, and hasn't failed."""
        message_id = await session.scalar(
            select(OutboundMessage.id)
            .join(Driver, Driver.phone == OutboundMessage.recipient)
            .where(
                Driver.id == driver_id,
                OutboundMessage.dispatch_id == dispatch_id,
                OutboundMessage.purpose == "driver_offer",
                OutboundMessage.status != MESSAGE_FAILED,
            )
            .limit(1)
        )
        return message_id is not None

    async def handle_accept(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> str:
        """Claim the dispatch. The ledger entry and all SMS commit with the claim."""
        dispatch = await session.scalar(_locked_dispatch(dispatch_id))
        if not dispatch:
            return "END No active dispatch."
        if dispatch.status in ASSIGNED:
            return ACCEPTED_REPLY if dispatch.driver_id == driver_id else "END Already assigned."
        if dispatch.status not in ACCEPT_ELIGIBLE:
            return "END Dispatch not available."
        late = dispatch.status == "FAILED"
        if late and not _late_claim_open(dispatch):
            return "END Dispatch not available."

        referral = await session.get(Referral, dispatch.referral_id)
        candidates = await self.pool.get_candidates(
            session,
            referral.chps_compound_id,
            dispatch.current_tier,
            list(dispatch.declined_driver_ids or []),
        )
        eligible = (
            not late and driver_id in {candidate.id for candidate in candidates}
        ) or await self._was_notified(session, dispatch.id, driver_id)
        if not eligible:
            return "END You are not eligible for this dispatch."

        dispatch.driver_id = driver_id
        dispatch.driver_assigned_at = datetime.now(UTC)
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="ussd_accept",
                target_role="driver",
                response="ACCEPTED",
                metadata_json={"driver_id": driver_id, "late": late},
            )
        )
        self._record_stipend(session, dispatch, driver_id)
        driver = await session.get(Driver, driver_id)
        facility = await session.get(Facility, dispatch.facility_id)
        self.hospital.notify_pre_arrival(session, referral, driver, facility, dispatch.id)
        if late:
            compound = await session.get(CHPSCompound, referral.chps_compound_id)
            enqueue_sms(
                session,
                recipient=compound.cho_phone,
                body=build_cho_late_accept_message(
                    referral_id=referral.id,
                    compound_id=referral.chps_compound_id,
                    driver_name=driver.name,
                    driver_phone=driver.phone,
                ),
                purpose="cho_late_accept",
                dispatch_id=dispatch.id,
            )
        dispatch.status = "HOSPITAL_NOTIFIED"
        self._set_next_action(dispatch)
        return ACCEPTED_REPLY

    @staticmethod
    def _record_stipend(session: AsyncSession, dispatch: Dispatch, driver_id: int) -> None:
        transaction_id = str(uuid.uuid4())
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="momo_escrow",
                target_role="driver",
                response="MOCK_RECORDED",
                metadata_json={
                    "idempotency_key": f"{dispatch.id}:{driver_id}",
                    "transaction_id": transaction_id,
                    "amount_ghs": FUEL_STIPEND_GHS,
                    "stage": "INITIAL_30PCT_MOCK",
                    "note": "No MoMo provider call — ledger only until live keys",
                },
            )
        )
        session.add(
            Wallet(
                referral_id=dispatch.referral_id,
                dispatch_id=dispatch.id,
                amount=FUEL_STIPEND_GHS,
                transaction_id=transaction_id,
                status="INITIAL_DISBURSED",
            )
        )

    async def handle_decline(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> str:
        """Record a decline, escalating in the same transaction once a tier is exhausted."""
        dispatch = await session.scalar(_locked_dispatch(dispatch_id))
        if not dispatch:
            return "END No active dispatch."

        declined = list(dispatch.declined_driver_ids or [])
        if driver_id in declined:
            return "END Decline noted."

        declined.append(driver_id)
        dispatch.declined_driver_ids = declined
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="ussd_decline",
                target_role="driver",
                response="DECLINED",
                metadata_json={"driver_id": driver_id},
            )
        )

        # Never advance a dispatch claimed by any driver.
        if dispatch.status not in CLAIMABLE:
            return "END Decline noted."

        referral = await session.get(Referral, dispatch.referral_id)
        tier = dispatch.current_tier
        remaining = await self.pool.get_candidates(
            session, referral.chps_compound_id, tier, declined
        )
        if remaining:
            # Same-tier drivers were already notified; wait for accept/timeout.
            session.add(
                DispatchLog(
                    dispatch_id=dispatch.id,
                    action="decline_tier_remaining",
                    target_role="system",
                    response="WAIT",
                    metadata_json={
                        "declined_driver_id": driver_id,
                        "tier": tier,
                        "remaining_candidates": len(remaining),
                    },
                )
            )
        else:
            next_tier = tier + 1 if tier >= 1 else 2
            await self._notify_tier(session, dispatch, referral, tier=next_tier)
        return "END Referral declined."

    async def handle_arrival(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> str:
        """Confirm patient arrival at hospital and mark dispatch complete."""
        dispatch = await session.scalar(_locked_dispatch(dispatch_id))
        if not dispatch:
            return "END No active dispatch."

        if dispatch.status == "COMPLETED" and dispatch.driver_id == driver_id:
            return "END Arrival confirmed. Referral complete."

        if dispatch.driver_id != driver_id:
            return "END You are not assigned to this dispatch."

        if dispatch.status not in ARRIVAL_ELIGIBLE:
            return "END Arrival not available yet."

        dispatch.status = "COMPLETED"
        dispatch.completed_at = datetime.now(UTC)
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="arrival_confirm",
                target_role="driver",
                response="COMPLETED",
                metadata_json={"driver_id": driver_id},
            )
        )
        referral = await session.get(Referral, dispatch.referral_id)
        compound = await session.get(CHPSCompound, referral.chps_compound_id)
        enqueue_sms(
            session,
            recipient=compound.cho_phone,
            body=f"Yoma Triage: Patient arrived at hospital for referral #{referral.id}.",
            purpose="cho_arrival",
            dispatch_id=dispatch.id,
        )
        return "END Arrival confirmed. Referral complete."

    async def _perform_next_action(self, session: AsyncSession, dispatch: Dispatch) -> None:
        """Re-checks the state it holds the lock on, so a repeat run changes nothing."""
        if dispatch.next_action != NEXT_ACTION_TIER_TIMEOUT or dispatch.status not in CLAIMABLE:
            dispatch.next_action = None
            dispatch.next_action_at = None
            return
        referral = await session.get(Referral, dispatch.referral_id)
        await self._notify_tier(session, dispatch, referral, tier=dispatch.current_tier + 1)

    async def process_due_dispatches(self, limit: int = 100) -> int:
        """Advance every overdue dispatch, one transaction each.

        SKIP LOCKED lets several workers run at once without touching the same row. A
        dispatch that errors is skipped for this pass so it can't block the others.
        """
        processed = 0
        failed_ids: set[int] = set()
        for _ in range(limit):
            async with async_session() as session:
                query = select(Dispatch).where(
                    Dispatch.next_action_at.is_not(None),
                    Dispatch.next_action_at <= datetime.now(UTC),
                )
                if failed_ids:
                    query = query.where(Dispatch.id.not_in(failed_ids))
                dispatch = await session.scalar(
                    query.order_by(Dispatch.next_action_at)
                    .limit(1)
                    .with_for_update(skip_locked=True)
                    .execution_options(populate_existing=True)
                )
                if dispatch is None:
                    return processed
                dispatch_id = dispatch.id
                try:
                    await self._perform_next_action(session, dispatch)
                    await session.commit()
                    processed += 1
                except Exception:
                    await session.rollback()
                    failed_ids.add(dispatch_id)
                    logger.exception("Cascade step failed for dispatch %s", dispatch_id)
        return processed
