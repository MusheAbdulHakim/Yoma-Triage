"""
USSD Webhook Receiver — Africa's Talking session callback.

AT docs: https://developers.africastalking.com/docs/ussd/handle_sessions

Contract:
- AT POSTs application/x-www-form-urlencoded to the registered callback.
- Fields: sessionId, serviceCode, phoneNumber, text (also accept snake_case).
- text is "" on first dial; deeper menus accumulate as "1*2".
- Respond within ~10s with a plain string starting with CON (continue) or END
  (terminate). Content-Type: text/plain. Never return JSON to AT.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.deps import require_webhook_secret
from src.config import settings
from src.db.database import get_db
from src.db.models import Dispatch, Driver, Referral
from src.services.dispatch_orchestrator import (
    ACCEPT_ELIGIBLE,
    ARRIVAL_ELIGIBLE,
    ASSIGNED,
    CLAIMABLE,
    DispatchOrchestrator,
)
from src.utils.phones import normalize_ghana_phone

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])

ROOT_MENU = (
    "CON Yoma Triage Emergency Referral\n"
    "1. Accept\n"
    "2. Decline\n"
    "3. Confirm arrival"
)


def _ussd_response(body: str) -> Response:
    """Africa's Talking expects a raw CON/END string as text/plain."""
    return Response(content=body, media_type="text/plain")


def _form_value(form: dict[str, str], *keys: str, default: str | None = None) -> str | None:
    for key in keys:
        if key not in form:
            continue
        value = form.get(key)
        if value is None:
            continue
        # Empty text is meaningful (first dial) — only skip missing keys.
        return str(value)
    return default


def _normalize_service_code(code: str) -> str:
    return "".join(str(code).split())


def _configured_service_code() -> str:
    return _normalize_service_code(settings.AT_USSD_SERVICE_CODE)


def _service_code_allowed(incoming: str | None) -> bool:
    """Require a configured shortcode outside development; match when set."""
    expected = _configured_service_code()
    if not expected:
        # Fail closed outside local/demo — empty allow-all is unsafe.
        return settings.is_development
    if not incoming:
        return False
    return _normalize_service_code(incoming) == expected


def _menu_choice(user_input: str) -> str | None:
    """Exact match on the whole input. The menu has one level, so AT never sends
    accumulated text here, and "21" or "1*2" must not be read as a choice."""
    return user_input if user_input in {"1", "2", "3"} else None


async def _find_driver(session: AsyncSession, phone_number: str) -> Driver | None:
    """Match driver by E.164 or common Ghana local formats AT may send."""
    normalized = normalize_ghana_phone(phone_number)
    candidates = {normalized, phone_number.strip()}
    if normalized.startswith("+233") and len(normalized) == 13:
        candidates.add("0" + normalized[4:])
        candidates.add(normalized[1:])  # 233…
    return await session.scalar(select(Driver).where(Driver.phone.in_(candidates)))


async def process_ussd(session: AsyncSession, phone_number: str, text: str) -> Response:
    """Handle a USSD response. All SMS go to the outbox, so this makes no external calls."""
    user_input = text.strip()

    if user_input == "":
        return _ussd_response(ROOT_MENU)

    choice = _menu_choice(user_input)
    if choice is None:
        return _ussd_response("END Invalid option selected.")

    driver = await _find_driver(session, phone_number)
    if not driver:
        return _ussd_response("END Unknown driver.")

    orchestrator = DispatchOrchestrator()

    if choice == "3":
        dispatch = await session.scalar(
            select(Dispatch)
            .join(Referral, Dispatch.referral_id == Referral.id)
            .where(
                Referral.chps_compound_id == driver.chps_compound_id,
                Dispatch.driver_id == driver.id,
                or_(
                    Dispatch.status.in_(ARRIVAL_ELIGIBLE),
                    Dispatch.status == "COMPLETED",
                ),
            )
            .order_by(Dispatch.initiated_at.desc(), Dispatch.id.desc())
        )
        if not dispatch:
            return _ussd_response("END No active dispatch.")

        reply = await orchestrator.handle_arrival(session, dispatch.id, driver.id)
        await session.commit()
        return _ussd_response(reply)

    dispatch = await session.scalar(
        select(Dispatch)
        .join(Referral, Dispatch.referral_id == Referral.id)
        .where(
            Referral.chps_compound_id == driver.chps_compound_id,
            or_(
                Dispatch.status.in_(ACCEPT_ELIGIBLE if choice == "1" else CLAIMABLE),
                Dispatch.status.in_(ASSIGNED) & (Dispatch.driver_id == driver.id),
            ),
        )
        .order_by(Dispatch.initiated_at.desc(), Dispatch.id.desc())
    )
    if not dispatch:
        return _ussd_response("END No active dispatch.")

    if choice == "1":
        reply = await orchestrator.handle_accept(session, dispatch.id, driver.id)
    else:
        reply = await orchestrator.handle_decline(session, dispatch.id, driver.id)
    await session.commit()
    return _ussd_response(reply)


@router.post("/callback", dependencies=[Depends(require_webhook_secret)])
async def handle_ussd(
    request: Request,
    session: AsyncSession = Depends(get_db),
):
    """Africa's Talking USSD session callback (≤10s, text/plain CON|END)."""
    form = {
        key: (value if isinstance(value, str) else str(value))
        for key, value in (await request.form()).items()
    }
    # Mirror AT sample: sessionId / serviceCode / phoneNumber / text
    session_id = _form_value(form, "sessionId", "session_id")
    service_code = _form_value(form, "serviceCode", "service_code")
    phone_number = _form_value(form, "phoneNumber", "phone_number")
    # First dial sends text as empty string — do not treat as missing.
    text = _form_value(form, "text", "Text", default="") or ""

    if not phone_number:
        # Never JSON to AT — terminate the session with plain text.
        return _ussd_response("END Missing phoneNumber.")

    if not _service_code_allowed(service_code):
        return _ussd_response("END Unknown service code.")

    _ = session_id  # available for session continuity / logging
    return await process_ussd(session, phone_number, text)
