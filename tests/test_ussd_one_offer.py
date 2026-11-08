"""A driver with exactly one open offer sees it at once, and 1 accepts it; a dial string
*CODE*REF# opens a referral directly. Each session keeps meaning what it first showed."""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from src.db.models import Dispatch, Driver, Referral, UssdSession
from src.services.dispatch_orchestrator import ACCEPTED_REPLY, ON_TRIP_REPLY, DispatchOrchestrator

DRIVER_1, DRIVER_2 = "+233240000001", "+233240000002"
CODE = "*384*99193#"


@pytest.fixture(autouse=True)
def service_code(monkeypatch):
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", CODE)


async def _open(db_session) -> Dispatch:
    referral = Referral(
        chps_compound_id=1, facility_id=1, cho_id=1, patient_hash="a" * 64,
        emergency_type="pph", status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await DispatchOrchestrator().initiate_dispatch(db_session, referral.id)
    await db_session.commit()
    return dispatch


class Session:
    """One USSD session, as AT sends it: the same sessionId, text accumulating."""

    def __init__(self, client, phone: str, service_code: str = CODE):
        self.client, self.phone, self.code = client, phone, service_code
        self.id = f"ATUid_{uuid.uuid4().hex}"

    async def send(self, text: str) -> str:
        response = await self.client.post(
            "/ussd/callback",
            data={
                "sessionId": self.id,
                "serviceCode": self.code,
                "phoneNumber": self.phone,
                "text": text,
            },
        )
        assert response.status_code == 200
        return response.text


async def _driver_of(db_session, dispatch: Dispatch) -> int | None:
    await db_session.refresh(dispatch)
    return dispatch.driver_id


@pytest.mark.asyncio
async def test_one_offer_is_shown_at_once_and_1_accepts_it(client, db_session, seeded_db):
    dispatch = await _open(db_session)
    ussd = Session(client, DRIVER_1)

    screen = await ussd.send("")

    assert screen == (
        f"CON Ref {dispatch.referral_id}: PPH bleeding\n"
        "From Tamale South CHPS\n"
        "To Tamale Teaching Hospital\n"
        "Sent just now\n"
        "1. Accept\n"
        "2. Decline\n"
        "9. Main menu"
    )
    assert await ussd.send("1") == ACCEPTED_REPLY
    assert await _driver_of(db_session, dispatch) == 1


@pytest.mark.asyncio
async def test_2_declines_the_one_offer(client, db_session, seeded_db):
    dispatch = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    await ussd.send("")

    assert await ussd.send("2") == "END Referral declined."
    await db_session.refresh(dispatch)
    assert dispatch.declined_driver_ids == [1]


@pytest.mark.asyncio
async def test_1_accepts_the_referral_shown_even_if_another_arrives(
    client, db_session, seeded_db
):
    shown = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    assert f"Ref {shown.referral_id}:" in await ussd.send("")
    newer = await _open(db_session)  # arrives while the driver reads the screen

    assert await ussd.send("1") == ACCEPTED_REPLY

    assert (await _driver_of(db_session, shown), await _driver_of(db_session, newer)) == (1, None)


@pytest.mark.asyncio
async def test_1_on_the_menu_stays_the_menu_if_offers_drop_to_one(
    client, db_session, seeded_db
):
    """The first screen was the menu, so 1 means Open referrals, never Accept."""
    first = await _open(db_session)
    second = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    assert "1. Open referrals (2)" in await ussd.send("")
    await DispatchOrchestrator().handle_accept(db_session, first.id, 2)
    await db_session.commit()

    listing = await ussd.send("1")

    assert listing.startswith("CON Reply with the Ref no.")
    assert await _driver_of(db_session, second) is None


@pytest.mark.asyncio
async def test_the_offer_shown_is_taken_before_the_driver_answers(client, db_session, seeded_db):
    dispatch = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    await ussd.send("")
    await DispatchOrchestrator().handle_accept(db_session, dispatch.id, 2)
    await db_session.commit()

    reply = await ussd.send("1")

    assert reply.startswith(f"END Ref {dispatch.referral_id} is not open for you.")
    assert await _driver_of(db_session, dispatch) == 2


@pytest.mark.asyncio
async def test_9_opens_the_main_menu(client, db_session, seeded_db):
    await _open(db_session)
    ussd = Session(client, DRIVER_1)
    await ussd.send("")

    assert (await ussd.send("9")).startswith("CON Yoma Triage (AVAILABLE)\n1. Open referrals (1)")
    assert (await ussd.send("9*3")).startswith("CON You are AVAILABLE.")
    assert await ussd.send("9*3*2") == "END You are now OFF DUTY. You will not get referral SMS."
    driver = await db_session.get(Driver, 1)
    await db_session.refresh(driver)
    assert driver.availability == "OFF_DUTY"


@pytest.mark.asyncio
@pytest.mark.parametrize("text", ["3", "11", "1*1", "0", "9*9"])
async def test_other_keys_on_the_one_offer_screen(client, db_session, seeded_db, text):
    dispatch = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    await ussd.send("")

    assert (await ussd.send(text)).startswith("END ")
    assert await _driver_of(db_session, dispatch) is None


@pytest.mark.asyncio
async def test_several_offers_still_ask_for_the_ref(client, db_session, seeded_db):
    await _open(db_session)
    await _open(db_session)
    assert "1. Open referrals (2)" in await Session(client, DRIVER_1).send("")


@pytest.mark.asyncio
async def test_a_driver_on_a_trip_gets_the_menu(client, db_session, seeded_db):
    trip = await _open(db_session)
    await DispatchOrchestrator().handle_accept(db_session, trip.id, 1)
    await db_session.commit()
    await _open(db_session)  # one more open, but driver 1 is on a trip

    screen = await Session(client, DRIVER_1).send("")

    assert screen.startswith(f"CON Yoma Triage (ON TRIP: Ref {trip.referral_id})")


@pytest.mark.asyncio
async def test_a_trip_from_before_on_trip_existed_gets_the_menu(client, db_session, seeded_db):
    """A driver left AVAILABLE with an open trip still needs Confirm arrival."""
    trip = await _open(db_session)
    trip.driver_id, trip.status = 1, "HOSPITAL_NOTIFIED"
    await db_session.commit()
    await _open(db_session)

    screen = await Session(client, DRIVER_1).send("")

    assert screen.startswith(f"CON Yoma Triage (AVAILABLE: Ref {trip.referral_id})")


@pytest.mark.asyncio
async def test_no_offers_gets_the_menu(client, db_session, seeded_db):
    assert "1. Open referrals (0)" in await Session(client, DRIVER_1).send("")


@pytest.mark.asyncio
async def test_without_a_session_id_the_menu_grammar_applies(client, db_session, seeded_db):
    """Scripts and tests that send each step on its own keep the Ref-naming paths."""
    dispatch = await _open(db_session)
    response = await client.post(
        "/ussd/callback", data={"serviceCode": CODE, "phoneNumber": DRIVER_1, "text": "1"}
    )
    assert response.text.startswith("CON Reply with the Ref no.")
    assert await _driver_of(db_session, dispatch) is None


@pytest.mark.asyncio
async def test_a_session_id_from_another_phone_is_not_trusted(client, db_session, seeded_db):
    dispatch = await _open(db_session)
    ussd = Session(client, DRIVER_1)
    await ussd.send("")

    other = Session(client, DRIVER_2)
    other.id = ussd.id
    reply = await other.send("1")

    assert reply.startswith("CON Reply with the Ref no.")  # menu grammar, not Accept
    assert await _driver_of(db_session, dispatch) is None


# --- The dial string -------------------------------------------------------------------


@pytest.mark.asyncio
async def test_dial_string_ref_in_service_code(client, db_session, seeded_db):
    await _open(db_session)
    wanted = await _open(db_session)
    ref = wanted.referral_id
    ussd = Session(client, DRIVER_1, service_code=f"*384*99193*{ref}#")

    assert (await ussd.send("")).startswith(f"CON Ref {ref}: PPH bleeding")
    assert await ussd.send("1") == ACCEPTED_REPLY
    assert await _driver_of(db_session, wanted) == 1


@pytest.mark.asyncio
async def test_dial_string_ref_in_text(client, db_session, seeded_db):
    """If AT passes the extension as the first request's text, and repeats it after."""
    await _open(db_session)
    wanted = await _open(db_session)
    ref = wanted.referral_id
    ussd = Session(client, DRIVER_1)

    assert (await ussd.send(str(ref))).startswith(f"CON Ref {ref}: PPH bleeding")
    assert await ussd.send(f"{ref}*1") == ACCEPTED_REPLY
    assert await _driver_of(db_session, wanted) == 1
    row = await db_session.get(UssdSession, ussd.id)
    assert (row.mode, row.ref, row.prefix) == ("offer", ref, str(ref))


@pytest.mark.asyncio
async def test_dial_string_ref_in_text_not_repeated(client, db_session, seeded_db):
    """If AT doesn't repeat the extension in later text, 1 still accepts it.

    Ambiguous for Ref 1 and 2, where "1" could be the extension repeated; the sandbox
    rehearsal settles which AT does.
    """
    for _ in range(2):
        await _open(db_session)
    wanted = await _open(db_session)
    assert wanted.referral_id == 3
    ussd = Session(client, DRIVER_1)
    await ussd.send(str(wanted.referral_id))
    assert await ussd.send("1") == ACCEPTED_REPLY


@pytest.mark.asyncio
async def test_dial_string_for_a_referral_not_open_to_this_driver(client, db_session, seeded_db):
    dispatch = await _open(db_session)
    await DispatchOrchestrator().handle_accept(db_session, dispatch.id, 2)
    await db_session.commit()
    ussd = Session(client, DRIVER_1, service_code=f"*384*99193*{dispatch.referral_id}#")

    assert (await ussd.send("")).startswith(f"END Ref {dispatch.referral_id} is not open for you.")


@pytest.mark.asyncio
async def test_dial_string_while_on_a_trip(client, db_session, seeded_db):
    trip = await _open(db_session)
    other = await _open(db_session)
    await DispatchOrchestrator().handle_accept(db_session, trip.id, 1)
    await db_session.commit()
    ussd = Session(client, DRIVER_1, service_code=f"*384*99193*{other.referral_id}#")

    assert await ussd.send("") == ON_TRIP_REPLY


@pytest.mark.asyncio
@pytest.mark.parametrize("code", ["*384*1#", "*384*99193*abc#", "*384*991931#", "*384*99193*1"])
async def test_other_service_codes_are_refused(client, db_session, seeded_db, code):
    reply = await Session(client, DRIVER_1, service_code=code).send("")
    assert reply == "END Unknown service code."


@pytest.mark.asyncio
async def test_old_sessions_are_cleared(client, db_session, seeded_db):
    from datetime import UTC, datetime, timedelta

    db_session.add(
        UssdSession(
            session_id="old", phone=DRIVER_1, mode="menu", prefix="",
            created_at=datetime.now(UTC) - timedelta(hours=2),
        )
    )
    await db_session.commit()

    await Session(client, DRIVER_1).send("")

    assert list(await db_session.scalars(select(UssdSession.session_id).where(
        UssdSession.session_id == "old"))) == []
