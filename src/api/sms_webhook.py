"""Inbound hospital SMS confirmations and diversions (Africa's Talking + JSON demos)."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.deps import require_webhook_secret
from src.db.database import get_db
from src.db.models import CHPSCompound, Dispatch, DispatchLog, Driver, Facility, Referral
from src.services.messaging_gateway import MessagingGateway
from src.utils.phones import normalize_ghana_phone

router = APIRouter(prefix="/api/v1/sms", tags=["SMS Gateway"])

CONFIRM_ALIASES = frozenset({"CONFIRM", "CONFIRMED", "YES", "OK", "Y"})
ELIGIBLE_STATUSES = frozenset({"ACCEPTED", "HOSPITAL_NOTIFIED"})
# Already past hospital confirm — treat inbound CONFIRM as status ping.
EN_ROUTE_STATUSES = frozenset({"HOSPITAL_CONFIRMED", "COMPLETED"})
# Broader lookup when no eligible open dispatch exists.
RELATED_STATUSES = frozenset(
    {
        *ELIGIBLE_STATUSES,
        *EN_ROUTE_STATUSES,
        "TIER1_NOTIFIED",
        "TIER2_NOTIFIED",
        "TIER3_NOTIFIED",
        "DIVERTED",
        "FAILED",
        "PENDING",
    }
)


class InboundSMS(BaseModel):
    """JSON body used by local demos / curl."""

    from_: str = Field(alias="from")
    text: str


def _form_map(form) -> dict[str, str]:
    return {
        key: (value if isinstance(value, str) else str(value))
        for key, value in form.items()
    }


def _parse_command(text: str) -> tuple[str, int | None, int | None]:
    """Parse CONFIRM/DIVERT commands, including bare 'confirmed' replies."""
    cleaned = text.strip().upper().replace(".", "").replace("!", "").replace(",", "")
    if not cleaned:
        raise ValueError("Empty SMS text")

    if cleaned in CONFIRM_ALIASES:
        return "CONFIRM", None, None

    parts = cleaned.split()
    if not parts:
        raise ValueError("Empty SMS text")

    if parts[0] in CONFIRM_ALIASES:
        if len(parts) == 1:
            return "CONFIRM", None, None
        if len(parts) == 2:
            try:
                return "CONFIRM", int(parts[1]), None
            except ValueError as exc:
                raise ValueError("Dispatch ID must be an integer") from exc
        raise ValueError("Expected CONFIRM or CONFIRM <dispatch_id>")

    if parts[0] != "DIVERT":
        raise ValueError(
            "Expected CONFIRM / confirmed, CONFIRM <dispatch_id>, "
            "or DIVERT <dispatch_id> <facility_id>"
        )
    if len(parts) != 3:
        raise ValueError("Expected DIVERT <dispatch_id> <facility_id>")
    try:
        return "DIVERT", int(parts[1]), int(parts[2])
    except ValueError as exc:
        raise ValueError("Dispatch and facility IDs must be integers") from exc


async def _sender_matches_dispatch(
    session: AsyncSession, phone: str, dispatch: Dispatch
) -> bool:
    facility = await session.get(Facility, dispatch.facility_id)
    if facility and normalize_ghana_phone(facility.phone) == phone:
        return True
    if dispatch.driver_id:
        driver = await session.get(Driver, dispatch.driver_id)
        if driver and normalize_ghana_phone(driver.phone) == phone:
            return True
    return False


async def _latest_dispatch_for_sender(
    session: AsyncSession,
    sender: str,
    statuses: frozenset[str],
) -> Dispatch | None:
    phone = normalize_ghana_phone(sender)
    rows = (
        await session.scalars(
            select(Dispatch)
            .where(Dispatch.status.in_(statuses))
            .order_by(Dispatch.id.desc())
            .limit(50)
        )
    ).all()
    for dispatch in rows:
        if await _sender_matches_dispatch(session, phone, dispatch):
            return dispatch
    return None


async def _find_dispatch_for_sender(
    session: AsyncSession, sender: str, dispatch_id: int | None
) -> Dispatch:
    if dispatch_id is not None:
        dispatch = await session.get(Dispatch, dispatch_id)
        if not dispatch:
            raise ValueError("Dispatch not found")
        return dispatch

    dispatch = await _latest_dispatch_for_sender(session, sender, ELIGIBLE_STATUSES)
    if dispatch:
        return dispatch
    raise ValueError("No open dispatch found for this sender")


async def _assert_sender_authorized(
    session: AsyncSession, sender: str, dispatch: Dispatch
) -> None:
    phone = normalize_ghana_phone(sender)
    if await _sender_matches_dispatch(session, phone, dispatch):
        return
    raise ValueError("Unauthorized sender")


async def _reply_sms(
    session: AsyncSession,
    sender: str,
    message: str,
    dispatch_id: int | None,
    *,
    action: str = "inbound_status_reply",
) -> dict[str, Any]:
    gateway = MessagingGateway()
    did = dispatch_id or 0
    result = await gateway.send_sms(sender, message, did, "inbound_reply")
    if dispatch_id:
        session.add(
            DispatchLog(
                dispatch_id=dispatch_id,
                action=action,
                target_phone=sender,
                target_role="inbound_reply",
                response=result["status"],
                metadata_json={"message": message, **result},
            )
        )
        await session.commit()
    return result


async def _facility_name(session: AsyncSession, facility_id: int | None) -> str:
    if not facility_id:
        return "the hospital"
    facility = await session.get(Facility, facility_id)
    return facility.name if facility else "the hospital"


async def _status_reply_for_dispatch(
    session: AsyncSession, sender: str, dispatch: Dispatch
) -> dict[str, Any]:
    facility_name = await _facility_name(session, dispatch.facility_id)
    if dispatch.status in EN_ROUTE_STATUSES:
        msg = (
            f"Yoma Triage: Referral #{dispatch.referral_id} already confirmed. "
            f"Driver is on the way to {facility_name}."
        )
        await _reply_sms(session, sender, msg, dispatch.id)
        return {
            "status": "ALREADY_CONFIRMED",
            "dispatch_id": dispatch.id,
            "dispatch_status": dispatch.status,
        }

    msg = (
        f"Yoma Triage: Referral #{dispatch.referral_id} status is "
        f"{dispatch.status}. No CONFIRM action taken."
    )
    await _reply_sms(session, sender, msg, dispatch.id)
    return {
        "status": "STATUS_ONLY",
        "dispatch_id": dispatch.id,
        "dispatch_status": dispatch.status,
    }


async def process_inbound_sms(
    session: AsyncSession, sender: str, text: str
) -> dict[str, Any]:
    """Apply a hospital/driver command and persist its audit trail."""
    command, dispatch_id, facility_id = _parse_command(text)

    if command == "CONFIRM":
        try:
            dispatch = await _find_dispatch_for_sender(session, sender, dispatch_id)
        except ValueError as exc:
            if str(exc) == "No open dispatch found for this sender":
                related = await _latest_dispatch_for_sender(
                    session, sender, RELATED_STATUSES
                )
                if related:
                    return await _status_reply_for_dispatch(session, sender, related)
                await _reply_sms(
                    session,
                    sender,
                    (
                        "Yoma Triage: No open referral for this number. "
                        "If this is an emergency, contact your CHPS compound."
                    ),
                    None,
                )
                return {"status": "NO_OPEN_DISPATCH"}
            raise

        referral = await session.get(Referral, dispatch.referral_id)
        if not referral:
            raise ValueError("Referral not found")
        await _assert_sender_authorized(session, sender, dispatch)

        if dispatch.status in EN_ROUTE_STATUSES:
            return await _status_reply_for_dispatch(session, sender, dispatch)

        if dispatch.status not in ELIGIBLE_STATUSES:
            return await _status_reply_for_dispatch(session, sender, dispatch)

        dispatch.status = "HOSPITAL_CONFIRMED"
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="hospital_confirm",
                target_phone=sender,
                target_role="hospital",
                response="CONFIRMED",
                metadata_json={"text": text},
            )
        )
        await session.commit()
        await _reply_sms(
            session,
            sender,
            (
                f"Yoma Triage: Confirmed. Awaiting arrival for referral "
                f"#{referral.id}."
            ),
            dispatch.id,
            action="inbound_confirm_ack",
        )
        return {"status": "CONFIRMED", "dispatch_id": dispatch.id}

    # DIVERT
    dispatch = await _find_dispatch_for_sender(session, sender, dispatch_id)
    referral = await session.get(Referral, dispatch.referral_id)
    if not referral:
        raise ValueError("Referral not found")
    await _assert_sender_authorized(session, sender, dispatch)
    if dispatch.status not in ELIGIBLE_STATUSES:
        raise ValueError("Hospital command not available for this dispatch status")

    destination = await session.get(Facility, facility_id)
    if not destination:
        raise ValueError("Destination facility not found")
    compound = await session.get(CHPSCompound, referral.chps_compound_id)
    driver = await session.get(Driver, dispatch.driver_id) if dispatch.driver_id else None

    referral.facility_id = destination.id
    dispatch.facility_id = destination.id
    dispatch.status = "DIVERTED"
    session.add(
        DispatchLog(
            dispatch_id=dispatch.id,
            action="hospital_divert",
            target_phone=sender,
            target_role="hospital",
            response="DIVERTED",
            metadata_json={"destination_facility_id": destination.id, "text": text},
        )
    )

    gateway = MessagingGateway()
    message = (
        f"Yoma Triage diversion: referral #{referral.id} destination changed to "
        f"{destination.name}."
    )
    recipients = []
    if driver:
        recipients.append((driver.phone, "driver"))
    if compound:
        recipients.append((compound.cho_phone, "cho"))
    for phone, role in recipients:
        result = await gateway.send_sms(phone, message, dispatch.id, role)
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="divert_notify" if result["status"] != "FAILED" else "divert_notify_failed",
                target_phone=phone,
                target_role=role,
                response=result["status"],
                metadata_json=result,
            )
        )
    await session.commit()
    return {
        "status": "DIVERTED",
        "dispatch_id": dispatch.id,
        "facility_id": destination.id,
    }


@router.post("/inbound", dependencies=[Depends(require_webhook_secret)])
async def inbound_sms(
    request: Request, session: AsyncSession = Depends(get_db)
) -> Any:
    """Africa's Talking posts form-urlencoded; local demos may post JSON.

    AT two-way callbacks expect a plain ``GOOD`` / ``BAD`` body.
    """
    content_type = (request.headers.get("content-type") or "").lower()
    at_form = "application/json" not in content_type

    if at_form:
        form = _form_map(await request.form())
        sender = form.get("from") or form.get("phoneNumber")
        text = form.get("text", "")
    else:
        try:
            body = await request.json()
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
        sender = body.get("from") or body.get("from_")
        text = body.get("text", "")

    if not sender:
        if at_form:
            return Response(content="BAD", media_type="text/plain", status_code=400)
        raise HTTPException(status_code=400, detail="Missing from")

    try:
        result = await process_inbound_sms(session, str(sender), str(text or ""))
    except ValueError as exc:
        if at_form:
            return Response(
                content=f"BAD {exc}",
                media_type="text/plain",
                status_code=200,
            )
        raise HTTPException(
            status_code=400 if "not found" not in str(exc).lower() else 404,
            detail=str(exc),
        ) from exc

    if at_form:
        # Status-only / no-open cases still reply by SMS; acknowledge AT with GOOD.
        return Response(content="GOOD", media_type="text/plain")
    return result
