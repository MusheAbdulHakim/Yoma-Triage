"""Deterministic cascade dispatch — no LLM."""
from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.config import settings
from src.db.database import async_session
from src.db.models import CHPSCompound, Dispatch, DispatchLog, Driver, Facility, Referral, Wallet
from src.services.driver_pool import DriverPoolManager
from src.services.hospital_notifier import HospitalNotifier
from src.services.messaging_gateway import MessagingGateway

logger = logging.getLogger(__name__)

CLAIMABLE = {"PENDING", "TIER1_NOTIFIED", "TIER2_NOTIFIED"}
FUEL_STIPEND_GHS = 22.5


class DispatchOrchestrator:
    def __init__(self, gateway: MessagingGateway | None = None):
        self.gateway = gateway or MessagingGateway()
        self.pool = DriverPoolManager()
        self.hospital = HospitalNotifier(self.gateway)

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
        self.schedule_tier_timeouts(dispatch.id, tier=1)
        return dispatch

    def schedule_tier_timeouts(self, dispatch_id: int, tier: int = 1) -> None:
        asyncio.create_task(self._tier_timeout(dispatch_id, tier))

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
            message = f"RelayAI: No driver for referral #{referral.id}. Coordinate manually."
            result = await self.gateway.send_sms(
                compound.cho_phone, message, dispatch.id, "cho"
            )
            session.add(
                DispatchLog(
                    dispatch_id=dispatch.id,
                    action="cho_give_up",
                    target_phone=compound.cho_phone,
                    target_role="cho",
                    response=result["status"],
                    metadata_json=result,
                )
            )
            dispatch.status = "FAILED"
            return

        dispatch.status = f"TIER{tier}_NOTIFIED"
        for driver in candidates:
            message = (
                f"EMERGENCY: Patient at compound #{referral.chps_compound_id}. "
                f"Dial USSD to accept. Ref #{referral.id}"
            )
            result = await self.gateway.send_sms(
                driver.phone, message, dispatch.id, "driver"
            )
            session.add(
                DispatchLog(
                    dispatch_id=dispatch.id,
                    action="sms_send" if result["status"] != "FAILED" else "sms_failed",
                    target_phone=driver.phone,
                    target_role="driver",
                    response=result["status"],
                    metadata_json=result,
                )
            )
            # A failed SMS does not stop notifications to remaining candidates.

    async def handle_accept(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> dict:
        dispatch = await session.scalar(
            select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
        )
        if not dispatch:
            return {"ussd": "END No active dispatch.", "run_side_effects": False}
        if dispatch.status == "ACCEPTED" and dispatch.driver_id == driver_id:
            return {
                "ussd": "END Accepted! Fuel stipend queued. Proceed to CHPS.",
                "run_side_effects": False,
            }
        if dispatch.status == "ACCEPTED" and dispatch.driver_id != driver_id:
            return {"ussd": "END Already assigned.", "run_side_effects": False}
        if dispatch.status not in CLAIMABLE:
            return {"ussd": "END Dispatch not available.", "run_side_effects": False}

        referral = await session.get(Referral, dispatch.referral_id)
        candidates = await self.pool.get_candidates(
            session,
            referral.chps_compound_id,
            dispatch.current_tier,
            list(dispatch.declined_driver_ids or []),
        )
        if driver_id not in {candidate.id for candidate in candidates}:
            return {
                "ussd": "END You are not eligible for this dispatch.",
                "run_side_effects": False,
            }

        dispatch.status = "ACCEPTED"
        dispatch.driver_id = driver_id
        dispatch.driver_assigned_at = datetime.now(timezone.utc)
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="ussd_accept",
                target_role="driver",
                response="ACCEPTED",
                metadata_json={"driver_id": driver_id},
            )
        )
        return {
            "ussd": "END Accepted! Fuel stipend queued. Proceed to CHPS.",
            "run_side_effects": True,
        }

    async def handle_decline(
        self, session: AsyncSession, dispatch_id: int, driver_id: int
    ) -> dict:
        """Record a decline and indicate whether escalation should run after commit."""
        dispatch = await session.scalar(
            select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
        )
        if not dispatch:
            return {"ussd": "END No active dispatch.", "run_side_effects": False}

        declined = list(dispatch.declined_driver_ids or [])
        if driver_id in declined:
            return {"ussd": "END Decline noted.", "run_side_effects": False}

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
        if dispatch.status == "ACCEPTED" or dispatch.status not in CLAIMABLE:
            return {"ussd": "END Decline noted.", "run_side_effects": False}

        return {"ussd": "END Referral declined.", "run_side_effects": True}

    async def run_accept_side_effects(self, dispatch_id: int, driver_id: int) -> None:
        """Run payment and hospital notification once after a successful claim."""
        async with async_session() as session:
            dispatch = await session.scalar(
                select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
            )
            if (
                not dispatch
                or dispatch.status != "ACCEPTED"
                or dispatch.driver_id != driver_id
            ):
                return

            idempotency_key = f"{dispatch_id}:{driver_id}"
            existing = await session.scalar(
                select(DispatchLog).where(
                    DispatchLog.dispatch_id == dispatch_id,
                    DispatchLog.action == "momo_escrow",
                )
            )
            if existing:
                return

            transaction_id = str(uuid.uuid4())
            session.add(
                DispatchLog(
                    dispatch_id=dispatch_id,
                    action="momo_escrow",
                    target_role="driver",
                    response="INITIAL_DISBURSED",
                    metadata_json={
                        "idempotency_key": idempotency_key,
                        "transaction_id": transaction_id,
                        "amount_ghs": FUEL_STIPEND_GHS,
                        "stage": "INITIAL_30PCT",
                    },
                )
            )
            session.add(
                Wallet(
                    referral_id=dispatch.referral_id,
                    dispatch_id=dispatch_id,
                    amount=FUEL_STIPEND_GHS,
                    transaction_id=transaction_id,
                    status="INITIAL_DISBURSED",
                )
            )

            referral = await session.get(Referral, dispatch.referral_id)
            driver = await session.get(Driver, driver_id)
            facility = await session.get(Facility, dispatch.facility_id)
            await self.hospital.notify_pre_arrival(
                session, referral, driver, facility, dispatch_id
            )
            dispatch.status = "HOSPITAL_NOTIFIED"
            await session.commit()

    async def run_decline_side_effects(self, dispatch_id: int, driver_id: int) -> None:
        """Escalate an eligible decline after its USSD response has returned."""
        async with async_session() as session:
            dispatch = await session.scalar(
                select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
            )
            if (
                not dispatch
                or driver_id not in (dispatch.declined_driver_ids or [])
                or dispatch.status == "ACCEPTED"
                or dispatch.status not in CLAIMABLE
            ):
                return

            referral = await session.get(Referral, dispatch.referral_id)
            next_tier = 2 if dispatch.current_tier <= 1 else 3
            await self._notify_tier(session, dispatch, referral, tier=next_tier)
            await session.commit()
            if dispatch.status.startswith("TIER"):
                self.schedule_tier_timeouts(dispatch.id, tier=dispatch.current_tier)

    async def _tier_timeout(self, dispatch_id: int, tier: int) -> None:
        await asyncio.sleep(settings.CASCADE_TIER_SECONDS)
        async with async_session() as session:
            dispatch = await session.scalar(
                select(Dispatch).where(Dispatch.id == dispatch_id).with_for_update()
            )
            if (
                not dispatch
                or dispatch.status == "ACCEPTED"
                or dispatch.current_tier != tier
                or dispatch.status not in CLAIMABLE
            ):
                return

            referral = await session.get(Referral, dispatch.referral_id)
            await self._notify_tier(session, dispatch, referral, tier=tier + 1)
            await session.commit()
            if dispatch.status.startswith("TIER"):
                self.schedule_tier_timeouts(dispatch.id, tier=dispatch.current_tier)
