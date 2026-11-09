"""What a receiving facility is told, and the code it must quote to answer."""
from __future__ import annotations

import math
import secrets

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Dispatch, Driver, Facility, Referral
from src.services.outbox import enqueue_sms
from src.tools.moews_calculator import missing_vitals

# How many other facilities the notice lists as places to divert to.
DIVERT_OPTIONS = 3
# A facility name in that list is cut to this, so the notice stays short.
DIVERT_NAME_CHARS = 22
# Dispatches whose code a facility may still quote. Kept here, not imported from the
# orchestrator, which imports this module.
_OPEN_STATUSES = ("ACCEPTED", "HOSPITAL_NOTIFIED", "HOSPITAL_CONFIRMED", "DIVERTED")


async def new_hospital_code(session: AsyncSession) -> str:
    """Four random digits no other open dispatch is using.

    Random, not the dispatch number, so a spoofed sender can't guess it. Unique among open
    dispatches, so a reply can't reach the wrong one.
    """
    while True:
        code = f"{1000 + secrets.randbelow(9000)}"
        taken = await session.scalar(
            select(Dispatch.id).where(
                Dispatch.hospital_code == code, Dispatch.status.in_(_OPEN_STATUSES)
            )
        )
        if taken is None:
            return code


def _distance_km(a: Facility, b: Facility) -> float:
    if a.latitude is None or a.longitude is None or b.latitude is None or b.longitude is None:
        return math.inf
    lat1, lon1 = math.radians(a.latitude), math.radians(a.longitude)
    lat2, lon2 = math.radians(b.latitude), math.radians(b.longitude)
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(
        (lon2 - lon1) / 2
    ) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


async def divert_options(session: AsyncSession, facility: Facility) -> list[Facility]:
    """The nearest other facilities, by straight line; ones with no location go last."""
    others = list(await session.scalars(select(Facility).where(Facility.id != facility.id)))
    others.sort(key=lambda other: (_distance_km(facility, other), other.id))
    return others[:DIVERT_OPTIONS]


def facility_codes_line(options: list[Facility]) -> str:
    """'2 Navrongo War Memorial, 5 Savelugu', the codes DIVERT accepts."""
    return ", ".join(f"{f.id} {f.name[:DIVERT_NAME_CHARS].strip()}" for f in options)


#: What the app sends as ai_screen_result when no breathing check was done.
NOT_SCREENED = "NOT_SCREENED"


class HospitalNotifier:
    async def notify_pre_arrival(
        self,
        session: AsyncSession,
        referral: Referral,
        driver: Driver,
        facility: Facility,
        dispatch_id: int,
        *,
        code: str,
        diverted_from: str | None = None,
    ) -> None:
        """Queue the pre-arrival SMS in the caller's transaction."""
        token = referral.patient_hash[:12]
        vitals = referral.vitals_json or {}
        missing = missing_vitals(vitals) if vitals else []
        if vitals.get("vitals_taken") is False:
            not_measured = "Vitals not taken\n"
        else:
            not_measured = f"Not measured: {', '.join(missing)}\n" if missing else ""
        diverted = f"DIVERTED here from {diverted_from}\n" if diverted_from else ""
        # Acoustic builds send NOT_SCREENED when the CHO referred without a breathing check.
        screened = (
            "Breathing check: not screened\n"
            if (referral.ai_screen_result or "").upper() == NOT_SCREENED
            else ""
        )
        options = facility_codes_line(await divert_options(session, facility))
        message = (
            "YOMA TRIAGE EMERGENCY REFERRAL\n"
            f"{diverted}"
            f"Referral #{referral.id}, from compound #{referral.chps_compound_id}\n"
            f"Patient token: {token}\n"
            f"Condition: {referral.emergency_type}\n"
            f"Severity: {referral.risk_level}\n"
            f"{not_measured}"
            f"{screened}"
            f"Driver: {driver.name}\n"
            f"Driver phone: {driver.phone}\n"
            f"Code: {code}\n"
            f"Reply CONFIRM {code}, or DIVERT {code} <facility code>"
            + (f"\nFacility codes: {options}" if options else "")
        )
        enqueue_sms(
            session,
            recipient=facility.phone,
            body=message,
            purpose="hospital_pre_arrival",
            dispatch_id=dispatch_id,
        )
