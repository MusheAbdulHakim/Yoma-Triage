"""Hospital replies by SMS: CONFIRM and DIVERT (Africa's Talking, and JSON for demos).

Only the destination facility's registered phone may act, and every reply must quote
the dispatch's four-digit code from the facility's notice ("CONFIRM 4821",
"DIVERT 4821 7"). The code is what stops a reply reaching the wrong dispatch, and means
a spoofed sender ID isn't enough on its own. Every reply, accepted or not, gets an SMS
back saying what happened.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.deps import require_webhook_secret
from src.db.database import get_db
from src.db.models import Cho, Dispatch, DispatchLog, Driver, Facility
from src.services.dispatch_orchestrator import (
    ASSIGNED,
    DispatchOrchestrator,
    DiversionError,
)
from src.services.hospital_notifier import divert_options, facility_codes_line
from src.services.outbox import enqueue_sms, record_delivery_report
from src.utils.phones import normalize_ghana_phone

router = APIRouter(prefix="/api/v1/sms", tags=["SMS Gateway"])

CONFIRM_WORDS = frozenset({"CONFIRM", "CONFIRMED", "YES", "OK", "Y"})
CONFIRMABLE = frozenset({"ACCEPTED", "HOSPITAL_NOTIFIED"})
# Already past hospital confirm — an inbound CONFIRM is a status ping.
EN_ROUTE_STATUSES = frozenset({"HOSPITAL_CONFIRMED", "COMPLETED"})
CODE_LENGTH = 4
PREFIX = "Yoma Triage:"
HOW_TO_REPLY = "Reply CONFIRM <code> or DIVERT <code> <facility code>, using the code in our SMS."


class InboundSMS(BaseModel):
    """JSON body used by local demos / curl."""

    from_: str = Field(alias="from")
    text: str


@dataclass(frozen=True)
class Command:
    verb: str  # CONFIRM | DIVERT | NEED_CODE | INVALID
    code: str | None = None
    facility_code: str | None = None


def _form_map(form) -> dict[str, str]:
    return {
        key: (value if isinstance(value, str) else str(value))
        for key, value in form.items()
    }


def _is_code(word: str) -> bool:
    return len(word) == CODE_LENGTH and word.isdigit()


def parse_command(text: str) -> Command:
    """Read a hospital's reply. Anything not understood becomes NEED_CODE or INVALID."""
    cleaned = text.strip().upper().replace(".", " ").replace("!", " ").replace(",", " ")
    parts = cleaned.split()
    if not parts:
        return Command("INVALID")
    verb = "CONFIRM" if parts[0] in CONFIRM_WORDS else parts[0]
    if verb not in {"CONFIRM", "DIVERT"}:
        return Command("INVALID")
    if len(parts) < 2 or not _is_code(parts[1]):
        return Command("NEED_CODE")
    if verb == "CONFIRM":
        return Command("CONFIRM", parts[1]) if len(parts) == 2 else Command("INVALID")
    if len(parts) != 3:
        return Command("INVALID")
    return Command("DIVERT", parts[1], parts[2])


def _phone_variants(phone: str) -> set[str]:
    normalized = normalize_ghana_phone(phone)
    variants = {normalized, phone.strip()}
    if normalized.startswith("+233") and len(normalized) == 13:
        variants |= {"0" + normalized[4:], normalized[1:]}
    return variants


async def sender_role(session: AsyncSession, phone: str) -> str:
    """Who a phone belongs to, for the record: hospital, driver, cho or unknown."""
    variants = _phone_variants(phone)
    normalized = normalize_ghana_phone(phone)
    facilities = await session.scalars(select(Facility.phone))
    if any(normalize_ghana_phone(number) == normalized for number in facilities):
        return "hospital"
    if await session.scalar(select(Driver.id).where(Driver.phone.in_(variants)).limit(1)):
        return "driver"
    if await session.scalar(select(Cho.id).where(Cho.phone.in_(variants)).limit(1)):
        return "cho"
    return "unknown"


async def _dispatch_for_code(session: AsyncSession, code: str) -> Dispatch | None:
    """The open dispatch with this code, else the most recent closed one."""
    rows = list(
        await session.scalars(
            select(Dispatch)
            .where(Dispatch.hospital_code == code)
            .order_by(Dispatch.id.desc())
            .limit(20)
        )
    )
    return next((d for d in rows if d.status in ASSIGNED), rows[0] if rows else None)


async def _is_destination(session: AsyncSession, phone: str, dispatch: Dispatch) -> bool:
    facility = await session.get(Facility, dispatch.facility_id)
    return facility is not None and normalize_ghana_phone(facility.phone) == normalize_ghana_phone(
        phone
    )


async def _reply(
    session: AsyncSession,
    sender: str,
    body: str,
    dispatch_id: int | None,
    *,
    purpose: str = "inbound_reply",
) -> None:
    """Queue a reply to whoever texted us, and commit it with any state change."""
    enqueue_sms(session, recipient=sender, body=body, purpose=purpose, dispatch_id=dispatch_id)
    await session.commit()


async def _reject(
    session: AsyncSession,
    sender: str,
    text: str,
    status: str,
    body: str,
    dispatch: Dispatch | None = None,
) -> dict[str, Any]:
    """Say why nothing happened. Logged on the dispatch, with the sender's real role."""
    if dispatch is not None:
        session.add(
            DispatchLog(
                dispatch_id=dispatch.id,
                action="hospital_command_rejected",
                target_phone=sender,
                target_role=await sender_role(session, sender),
                response=status,
                metadata_json={"text": text},
            )
        )
    await _reply(session, sender, f"{PREFIX} {body}", dispatch.id if dispatch else None)
    return {"status": status, "dispatch_id": dispatch.id if dispatch else None}


async def _status_reply(
    session: AsyncSession, sender: str, dispatch: Dispatch, code: str
) -> dict[str, Any]:
    facility = await session.get(Facility, dispatch.facility_id)
    name = facility.name if facility else "the hospital"
    ref = f"Referral #{dispatch.referral_id} (code {code})"
    if dispatch.status == "COMPLETED":
        body, status = f"{PREFIX} {ref} is complete. The patient has arrived.", "ALREADY_CONFIRMED"
    elif dispatch.status in EN_ROUTE_STATUSES:
        body = f"{PREFIX} {ref} is already confirmed. Driver is on the way to {name}."
        status = "ALREADY_CONFIRMED"
    else:
        body = f"{PREFIX} {ref} status is {dispatch.status}. No action taken."
        status = "STATUS_ONLY"
    await _reply(session, sender, body, dispatch.id)
    return {"status": status, "dispatch_id": dispatch.id, "dispatch_status": dispatch.status}


async def _confirm(
    session: AsyncSession, sender: str, text: str, dispatch: Dispatch, code: str
) -> dict[str, Any]:
    if dispatch.status not in CONFIRMABLE:
        return await _status_reply(session, sender, dispatch, code)
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
    await _reply(
        session,
        sender,
        f"{PREFIX} Confirmed referral #{dispatch.referral_id} (code {code}). "
        "Awaiting arrival.",
        dispatch.id,
        purpose="inbound_confirm_ack",
    )
    return {"status": "CONFIRMED", "dispatch_id": dispatch.id}


async def _divert(
    session: AsyncSession,
    sender: str,
    text: str,
    dispatch: Dispatch,
    facility_code: str,
) -> dict[str, Any]:
    destination = (
        await session.get(Facility, int(facility_code)) if facility_code.isdigit() else None
    )
    if destination is None:
        current = await session.get_one(Facility, dispatch.facility_id)
        options = facility_codes_line(await divert_options(session, current))
        return await _reject(
            session,
            sender,
            text,
            "UNKNOWN_FACILITY",
            f"Unknown facility code {facility_code}. Codes: {options}.",
            dispatch,
        )
    try:
        await DispatchOrchestrator().divert(
            session,
            dispatch.id,
            destination.id,
            actor_phone=sender,
            actor_role="hospital",
            text=text,
        )
    except DiversionError as exc:
        # divert() checks everything before it changes anything, so nothing to undo.
        return await _reject(session, sender, text, "DIVERT_REJECTED", str(exc), dispatch)
    # The old facility's "diverted" notice, queued by divert(), is the sender's receipt.
    await session.commit()
    return {"status": "DIVERTED", "dispatch_id": dispatch.id, "facility_id": destination.id}


async def process_inbound_sms(session: AsyncSession, sender: str, text: str) -> dict[str, Any]:
    """Apply a hospital's reply, or explain by SMS why it can't be applied."""
    command = parse_command(text)
    if command.verb == "INVALID":
        return await _reject(session, sender, text, "INVALID", f"Not understood. {HOW_TO_REPLY}")
    if command.verb == "NEED_CODE":
        return await _reject(
            session,
            sender,
            text,
            "NEED_CODE",
            f"Please include the 4-digit code from our referral SMS. {HOW_TO_REPLY}",
        )
    assert command.code is not None
    dispatch = await _dispatch_for_code(session, command.code)
    if dispatch is None:
        return await _reject(
            session,
            sender,
            text,
            "UNKNOWN_CODE",
            f"Unknown code {command.code}. Check the code in our referral SMS.",
        )
    if not await _is_destination(session, sender, dispatch):
        return await _reject(
            session,
            sender,
            text,
            "NOT_YOUR_DISPATCH",
            f"Code {command.code} is not a referral for this number. Only the receiving "
            "facility's registered phone can reply.",
            dispatch,
        )
    if dispatch.status not in ASSIGNED:
        return await _status_reply(session, sender, dispatch, command.code)
    if command.verb == "CONFIRM":
        return await _confirm(session, sender, text, dispatch, command.code)
    assert command.facility_code is not None
    return await _divert(session, sender, text, dispatch, command.facility_code)


@router.post("/inbound", dependencies=[Depends(require_webhook_secret)])
async def inbound_sms(
    request: Request, session: AsyncSession = Depends(get_db)
) -> Any:
    """Africa's Talking posts form-urlencoded; local demos may post JSON.

    AT two-way callbacks expect a plain ``GOOD`` / ``BAD`` body. Every reply we can read
    gets an SMS back, so even a rejected one is ``GOOD`` to AT.
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

    result = await process_inbound_sms(session, str(sender), str(text or ""))
    if at_form:
        return Response(content="GOOD", media_type="text/plain")
    return result



@router.post("/delivery", dependencies=[Depends(require_webhook_secret)])
async def delivery_report(request: Request, session: AsyncSession = Depends(get_db)) -> Any:
    """Africa's Talking delivery reports: form fields id, status, failureReason, ...

    Always 200 for a report we could read, known message or not, so AT doesn't retry it.
    """
    form = _form_map(await request.form())
    message_id, status = form.get("id", "").strip(), form.get("status", "").strip()
    if not message_id or not status:
        return Response(content="BAD", media_type="text/plain", status_code=400)
    try:
        row = await record_delivery_report(
            session,
            message_id=message_id,
            status=status,
            failure_reason=form.get("failureReason") or None,
            network_code=form.get("networkCode") or None,
            retry_count=form.get("retryCount") or None,
        )
    except ValueError:
        return Response(content="BAD", media_type="text/plain", status_code=400)
    await session.commit()
    return Response(content="OK" if row else "UNKNOWN", media_type="text/plain")
