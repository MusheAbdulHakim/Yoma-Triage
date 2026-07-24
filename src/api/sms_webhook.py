"""Inbound hospital SMS confirmations and diversions."""
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.database import get_db
from src.db.models import CHPSCompound, Dispatch, DispatchLog, Driver, Facility, Referral
from src.services.messaging_gateway import MessagingGateway

router = APIRouter(prefix="/api/v1/sms", tags=["SMS Gateway"])


class InboundSMS(BaseModel):
    from_: str = Field(alias="from")
    text: str


def _normalize_ghana_phone(phone: str) -> str:
    """Normalize local Ghana phone numbers to their +233 representation."""
    normalized = "".join(str(phone).split())
    if normalized.startswith("+233"):
        return normalized
    if normalized.startswith("233"):
        return f"+{normalized}"
    if normalized.startswith("0"):
        return f"+233{normalized[1:]}"
    return f"+233{normalized}"


def _parse_command(text: str) -> tuple[str, int, int | None]:
    parts = text.strip().upper().split()
    if len(parts) < 2 or parts[0] not in {"CONFIRM", "DIVERT"}:
        raise ValueError("Expected CONFIRM <dispatch_id> or DIVERT <dispatch_id> <facility_id>")
    try:
        dispatch_id = int(parts[1])
        facility_id = int(parts[2]) if parts[0] == "DIVERT" and len(parts) == 3 else None
    except ValueError as exc:
        raise ValueError("Dispatch and facility IDs must be integers") from exc
    if parts[0] == "DIVERT" and facility_id is None:
        raise ValueError("Expected DIVERT <dispatch_id> <facility_id>")
    if len(parts) != (3 if parts[0] == "DIVERT" else 2):
        raise ValueError("Invalid SMS command")
    return parts[0], dispatch_id, facility_id


async def process_inbound_sms(
    session: AsyncSession, sender: str, text: str
) -> dict[str, Any]:
    """Apply a hospital command and persist its audit trail."""
    command, dispatch_id, facility_id = _parse_command(text)
    dispatch = await session.get(Dispatch, dispatch_id)
    if not dispatch:
        raise ValueError("Dispatch not found")
    referral = await session.get(Referral, dispatch.referral_id)
    if not referral:
        raise ValueError("Referral not found")
    current_facility = await session.get(Facility, dispatch.facility_id)
    if not current_facility:
        raise ValueError("Current facility not found")
    if _normalize_ghana_phone(sender) != _normalize_ghana_phone(current_facility.phone):
        raise ValueError("Unauthorized sender")
    if dispatch.status not in {"ACCEPTED", "HOSPITAL_NOTIFIED"}:
        raise ValueError("Hospital command not available for this dispatch status")

    if command == "CONFIRM":
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
        return {"status": "CONFIRMED", "dispatch_id": dispatch.id}

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
        f"RelayAI diversion: referral #{referral.id} destination changed to "
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


@router.post("/inbound")
async def inbound_sms(
    payload: InboundSMS, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    try:
        return await process_inbound_sms(session, payload.from_, payload.text)
    except ValueError as exc:
        raise HTTPException(status_code=400 if "not found" not in str(exc) else 404, detail=str(exc)) from exc
