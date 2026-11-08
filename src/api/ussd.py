"""
USSD Webhook Receiver — Africa's Talking session callback.

AT docs: https://developers.africastalking.com/docs/ussd/handle_sessions

Contract:
- AT POSTs application/x-www-form-urlencoded to the registered callback.
- Fields: sessionId, serviceCode, phoneNumber, text (also accept snake_case).
- text is "" on first dial; deeper menus accumulate as "1*2".
- Respond within ~10s with a plain string starting with CON (continue) or END
  (terminate). Content-Type: text/plain. Never return JSON to AT.

Menus (BUG-9). Each answer is read from the whole accumulated text, and every action
names its referral by the Ref number the driver typed, never "the newest", so a list
that changes between screens can't make a driver act on a referral they didn't pick:

    ""            root: 1 Open referrals, 2 Confirm arrival, 3 Availability
    "1"           the driver's open offers, each with its Ref number
    "1*<ref>"     that referral: type, compound, destination, how long ago; 1 Accept, 2 Decline
    "1*<ref>*1"   accept it          "1*<ref>*2"   decline it
    "2"           the driver's own trip; "2*1" confirms arrival
                  (with several open trips, from before ON_TRIP: "2*<ref>", then "2*<ref>*1")
    "3"           availability; "3*1" Available, "3*2" Off duty

One open offer. When a session's first screen would be the root menu but the driver has
exactly one open offer (and no trip), it shows that referral instead: "1" accepts it,
"2" declines it, "9" opens the root menu above (so "9*3*2" is Off duty). What the first
screen showed is stored by AT's sessionId (ussd_sessions), so "1" always means the
referral the driver saw, even if offers change before they answer.

Dial string. *CODE*REF# opens referral REF directly, in the same one-referral screen. AT
may deliver REF in serviceCode or as the first request's text; both are read.

Without a sessionId (tests, scripts) the root-menu grammar above applies, unchanged.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.deps import require_webhook_secret
from src.config import settings
from src.db.database import get_db
from src.db.models import CHPSCompound, Dispatch, Driver, Facility, Referral, UssdSession
from src.services.dispatch_orchestrator import (
    ACCEPT_ELIGIBLE,
    ARRIVAL_ELIGIBLE,
    ON_TRIP_REPLY,
    DispatchOrchestrator,
)
from src.services.driver_pool import AVAILABLE, OFF_DUTY, ON_TRIP, set_availability
from src.utils.phones import normalize_ghana_phone

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])

# How long after confirming arrival a repeated "2*1" still gets "Arrival confirmed".
REPEAT_WINDOW = timedelta(minutes=15)
# Sessions older than this are deleted when a new one starts. AT ends a session long before.
SESSION_TTL = timedelta(hours=1)
# Key that leaves the one-referral screen for the root menu.
MAIN_MENU = "9"
# How many referrals one screen lists. AT allows about 180 characters.
LIST_LIMIT = 4
# Short names, so a referral fits on a feature phone's screen.
EMERGENCY_LABELS = {
    "respiratory_distress": "Breathing problem",
    "pph": "PPH bleeding",
    "maternal_hemorrhage": "Bleeding",
    "neonatal_asphyxia": "Newborn not breathing",
    "neonatal_sepsis": "Newborn sepsis",
    "eclampsia": "Eclampsia",
    "severe_malaria": "Severe malaria",
    "other": "Other emergency",
}
AVAILABILITY_LABELS = {AVAILABLE: "AVAILABLE", ON_TRIP: "ON TRIP", OFF_DUTY: "OFF DUTY"}


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


def dial_ref(incoming: str | None) -> str | None:
    """REF from a dial string *CODE*REF#, if AT passed it in serviceCode."""
    expected = _configured_service_code()
    if not expected or not incoming or not expected.endswith("#"):
        return None
    code = _normalize_service_code(incoming)
    stem = expected[:-1] + "*"
    if code.startswith(stem) and code.endswith("#"):
        ref = code[len(stem) : -1]
        return ref if ref.isdigit() else None
    return None


def _service_code_allowed(incoming: str | None) -> bool:
    """Require a configured shortcode outside development; match when set."""
    expected = _configured_service_code()
    if not expected:
        # Fail closed outside local/demo — empty allow-all is unsafe.
        return settings.is_development
    if not incoming:
        return False
    return _normalize_service_code(incoming) == expected or dial_ref(incoming) is not None


async def _find_driver(session: AsyncSession, phone_number: str) -> Driver | None:
    """Match driver by E.164 or common Ghana local formats AT may send."""
    normalized = normalize_ghana_phone(phone_number)
    candidates = {normalized, phone_number.strip()}
    if normalized.startswith("+233") and len(normalized) == 13:
        candidates.add("0" + normalized[4:])
        candidates.add(normalized[1:])  # 233…
    return await session.scalar(select(Driver).where(Driver.phone.in_(candidates)))


# --- What a driver sees ----------------------------------------------------------------


@dataclass(frozen=True)
class Item:
    """A referral as a driver sees it."""

    dispatch: Dispatch
    referral: Referral
    compound: str
    destination: str

    @property
    def ref(self) -> int:
        return self.referral.id

    @property
    def emergency(self) -> str:
        kind = self.referral.emergency_type
        return EMERGENCY_LABELS.get(kind, kind.replace("_", " ").capitalize())


def _minutes_ago(moment: datetime | None) -> str:
    if moment is None:
        return "just now"
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=UTC)
    minutes = max(int((datetime.now(UTC) - moment).total_seconds() // 60), 0)
    if minutes < 1:
        return "just now"
    if minutes < 120:
        return f"{minutes} min ago"
    return f"{minutes // 60} h ago"


async def _item(session: AsyncSession, dispatch: Dispatch) -> Item:
    referral = await session.get_one(Referral, dispatch.referral_id)
    compound = await session.get(CHPSCompound, referral.chps_compound_id)
    facility = await session.get(Facility, dispatch.facility_id)
    return Item(
        dispatch=dispatch,
        referral=referral,
        compound=compound.name if compound else f"CHPS #{referral.chps_compound_id}",
        destination=facility.name if facility else "hospital",
    )


async def open_offers(session: AsyncSession, driver: Driver) -> list[Item]:
    """Referrals this driver may accept now, oldest first. None while on a trip.

    Oldest first, so a referral keeps its place as newer ones arrive. One the driver
    declined stays listed while nobody has it: they may change their mind (BUG-4).
    """
    if driver.availability == ON_TRIP:
        return []
    orchestrator = DispatchOrchestrator()
    rows = await session.scalars(
        select(Dispatch)
        .join(Referral, Dispatch.referral_id == Referral.id)
        .where(
            Referral.chps_compound_id == driver.chps_compound_id,
            Dispatch.status.in_(ACCEPT_ELIGIBLE),
        )
        .order_by(Dispatch.initiated_at, Dispatch.id)
    )
    offers = []
    for dispatch in rows:
        referral = await session.get_one(Referral, dispatch.referral_id)
        if await orchestrator.may_claim(session, dispatch, referral, driver.id):
            offers.append(await _item(session, dispatch))
    return offers


async def own_trips(session: AsyncSession, driver: Driver) -> list[Item]:
    """Trips this driver accepted and hasn't finished, oldest first."""
    rows = await session.scalars(
        select(Dispatch)
        .where(Dispatch.driver_id == driver.id, Dispatch.status.in_(ARRIVAL_ELIGIBLE))
        .order_by(Dispatch.initiated_at, Dispatch.id)
    )
    return [await _item(session, dispatch) for dispatch in rows]


def _offer_line(item: Item) -> str:
    return f"Ref {item.ref}: {item.emergency}, {_minutes_ago(item.dispatch.initiated_at)}"


def _detail(item: Item, *, when: str) -> str:
    return (
        f"Ref {item.ref}: {item.emergency}\n"
        f"From {item.compound}\n"
        f"To {item.destination}\n"
        f"{when}"
    )


# --- Menus ------------------------------------------------------------------------------


async def _root(session: AsyncSession, driver: Driver) -> str:
    trips = await own_trips(session, driver)
    offers = await open_offers(session, driver)
    state = AVAILABILITY_LABELS.get(driver.availability, driver.availability)
    if trips:
        state += f": Ref {trips[0].ref}" if len(trips) == 1 else f": {len(trips)} trips"
    return (
        f"CON Yoma Triage ({state})\n"
        f"1. Open referrals ({len(offers)})\n"
        "2. Confirm arrival\n"
        "3. Availability"
    )


async def _offers_menu(session: AsyncSession, driver: Driver, rest: list[str]) -> str:
    if len(rest) == 2 and rest[1] == "1":
        # Accepting again what this driver already accepted gets the same answer.
        trip = next((t for t in await own_trips(session, driver) if str(t.ref) == rest[0]), None)
        if trip is not None:
            return await DispatchOrchestrator().handle_accept(session, trip.dispatch.id, driver.id)
    if driver.availability == ON_TRIP:
        return ON_TRIP_REPLY
    offers = await open_offers(session, driver)
    if not rest:
        if not offers:
            return "END No open referrals for you."
        lines = "\n".join(_offer_line(item) for item in offers[:LIST_LIMIT])
        more = f"\n+{len(offers) - LIST_LIMIT} more" if len(offers) > LIST_LIMIT else ""
        return f"CON Reply with the Ref no.\n{lines}{more}"

    ref = rest[0]
    item = next((o for o in offers if str(o.ref) == ref), None)
    if item is None:
        return f"END Ref {ref} is not open for you. Dial again to see open referrals."
    if len(rest) == 1:
        sent = f"Sent {_minutes_ago(item.dispatch.initiated_at)}"
        return f"CON {_detail(item, when=sent)}\n1. Accept\n2. Decline"
    if len(rest) > 2 or rest[1] not in {"1", "2"}:
        return "END Invalid option selected."

    orchestrator = DispatchOrchestrator()
    if rest[1] == "1":
        reply = await orchestrator.handle_accept(session, item.dispatch.id, driver.id)
    else:
        reply = await orchestrator.handle_decline(session, item.dispatch.id, driver.id)
    await session.commit()
    return reply


async def _arrival_menu(session: AsyncSession, driver: Driver, rest: list[str]) -> str:
    trips = await own_trips(session, driver)
    if not trips:
        if rest == ["1"]:
            # A repeat of a confirmation that already went through gets the same answer.
            done = await session.scalar(
                select(Dispatch)
                .where(
                    Dispatch.driver_id == driver.id,
                    Dispatch.status == "COMPLETED",
                    Dispatch.completed_at >= datetime.now(UTC) - REPEAT_WINDOW,
                )
                .order_by(Dispatch.completed_at.desc())
                .limit(1)
            )
            if done is not None:
                return await DispatchOrchestrator().handle_arrival(session, done.id, driver.id)
        return "END You have no trip to confirm."

    if len(trips) == 1:
        # One trip: it is the only thing "2*1" can mean.
        item, answer = trips[0], rest
    elif not rest:
        lines = "\n".join(f"Ref {t.ref}: {t.emergency}" for t in trips[:LIST_LIMIT])
        return f"CON Which trip? Reply with the Ref no.\n{lines}"
    else:
        found = next((t for t in trips if str(t.ref) == rest[0]), None)
        if found is None:
            return f"END Ref {rest[0]} is not your trip."
        item, answer = found, rest[1:]

    if not answer:
        accepted = f"Accepted {_minutes_ago(item.dispatch.driver_assigned_at)}"
        return f"CON Confirm arrival?\n{_detail(item, when=accepted)}\n1. Yes, patient arrived"
    if answer != ["1"]:
        return "END Invalid option selected."
    reply = await DispatchOrchestrator().handle_arrival(session, item.dispatch.id, driver.id)
    await session.commit()
    return reply


async def _availability_menu(session: AsyncSession, driver: Driver, rest: list[str]) -> str:
    if driver.availability == ON_TRIP:
        return "END You are on a trip. Confirm arrival, then you are AVAILABLE again."
    if not rest:
        state = AVAILABILITY_LABELS.get(driver.availability, driver.availability)
        return f"CON You are {state}.\n1. Available\n2. Off duty"
    choice = {"1": AVAILABLE, "2": OFF_DUTY}.get(rest[0]) if len(rest) == 1 else None
    if choice is None:
        return "END Invalid option selected."
    set_availability(session, driver, choice, actor="driver")
    await session.commit()
    if choice == OFF_DUTY:
        return "END You are now OFF DUTY. You will not get referral SMS."
    return "END You are now AVAILABLE for referrals."


async def _menu_grammar(session: AsyncSession, driver: Driver, user_input: str) -> str:
    """The root-menu grammar, where every action names its referral."""
    if user_input == "":
        return await _root(session, driver)
    first, *rest = user_input.split("*")
    menus = {"1": _offers_menu, "2": _arrival_menu, "3": _availability_menu}
    menu = menus.get(first)
    if menu is None or any(not part.isdigit() for part in rest):
        return "END Invalid option selected."
    return await menu(session, driver, rest)


async def _offer_screen(session: AsyncSession, driver: Driver, ref: int) -> str:
    """One referral: what, where from, where to, how long ago; accept or decline."""
    if driver.availability == ON_TRIP:
        return ON_TRIP_REPLY
    item = next((o for o in await open_offers(session, driver) if o.ref == ref), None)
    if item is None:
        return f"END Ref {ref} is not open for you. Dial again to see open referrals."
    sent = f"Sent {_minutes_ago(item.dispatch.initiated_at)}"
    return f"CON {_detail(item, when=sent)}\n1. Accept\n2. Decline\n{MAIN_MENU}. Main menu"


async def _offer_grammar(
    session: AsyncSession, driver: Driver, ref: int, user_input: str
) -> str:
    """Keys pressed on the one-referral screen, which always mean that referral."""
    if user_input == "":
        return await _offer_screen(session, driver, ref)
    if user_input == MAIN_MENU or user_input.startswith(MAIN_MENU + "*"):
        return await _menu_grammar(session, driver, user_input[len(MAIN_MENU) + 1 :])
    if user_input not in {"1", "2"}:
        return "END Invalid option selected."
    # The same path as typing the Ref in the menu: its checks, its idempotency.
    return await _offers_menu(session, driver, [str(ref), user_input])


async def _first_screen(session: AsyncSession, driver: Driver) -> tuple[str, int | None]:
    """The mode a new session starts in: one referral if that's all there is to answer."""
    # An ON_TRIP driver has no offers. A trip from before ON_TRIP existed needs the menu
    # too, for Confirm arrival.
    if await own_trips(session, driver):
        return "menu", None
    offers = await open_offers(session, driver)
    if len(offers) == 1:
        return "offer", offers[0].ref
    return "menu", None


async def _start_session(
    session: AsyncSession, session_id: str, phone: str, mode: str, ref: int | None, prefix: str
) -> None:
    await session.execute(
        delete(UssdSession).where(UssdSession.created_at < datetime.now(UTC) - SESSION_TTL)
    )
    session.add(UssdSession(session_id=session_id, phone=phone, mode=mode, ref=ref, prefix=prefix))
    await session.commit()


async def process_ussd(
    session: AsyncSession,
    phone_number: str,
    text: str,
    *,
    session_id: str | None = None,
    service_code: str | None = None,
) -> Response:
    """Handle a USSD response. All SMS go to the outbox, so this makes no external calls."""
    driver = await _find_driver(session, phone_number)
    if not driver:
        return _ussd_response("END Unknown driver.")

    user_input = text.strip()
    if not session_id:
        return _ussd_response(await _menu_grammar(session, driver, user_input))

    state = await session.get(UssdSession, session_id)
    if state is not None and state.phone != driver.phone:
        # Another phone's session id: trust nothing stored, and store nothing.
        return _ussd_response(await _menu_grammar(session, driver, user_input))
    if state is None:
        # A new session. Its first request has empty text, unless the dial string
        # carried a Ref: *CODE*REF# arrives as serviceCode, or as the text.
        ref_text = dial_ref(service_code)
        prefix = ""
        if ref_text is None and user_input.isdigit():
            ref_text, prefix = user_input, user_input
        if ref_text is not None:
            await _start_session(session, session_id, driver.phone, "offer", int(ref_text), prefix)
            return _ussd_response(await _offer_screen(session, driver, int(ref_text)))
        if user_input != "":
            # Mid-session text we have no record of: the Ref-naming grammar is safe.
            return _ussd_response(await _menu_grammar(session, driver, user_input))
        mode, ref = await _first_screen(session, driver)
        await _start_session(session, session_id, driver.phone, mode, ref, "")
        if mode == "offer":
            assert ref is not None
            return _ussd_response(await _offer_screen(session, driver, ref))
        return _ussd_response(await _root(session, driver))

    if state.prefix:
        if user_input == state.prefix:
            user_input = ""
        elif user_input.startswith(state.prefix + "*"):
            user_input = user_input[len(state.prefix) + 1 :]
    if state.mode == "offer" and state.ref is not None:
        return _ussd_response(await _offer_grammar(session, driver, state.ref, user_input))
    return _ussd_response(await _menu_grammar(session, driver, user_input))


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

    return await process_ussd(
        session, phone_number, text, session_id=session_id, service_code=service_code
    )
