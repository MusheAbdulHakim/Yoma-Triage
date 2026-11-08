"""Hospital replies by SMS: who may CONFIRM or DIVERT, the per-dispatch code, and the
replies each mistake gets (audit security High, "driver can DIVERT")."""
from __future__ import annotations

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.api.sms_webhook import Command, parse_command
from src.db.models import Dispatch, DispatchLog, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator
from tests.conftest import SEEDED_CHO_PHONE, queued_sms

HOSPITAL_1 = "+233240000200"
HOSPITAL_2 = "+233240000201"
DRIVER_1 = "+233240000001"
STRANGER = "+233599999999"


async def _accepted(
    db_session: AsyncSession, driver_id: int = 1, patient_hash: str = "0123456789abcdef" * 4
) -> Dispatch:
    """A dispatch a driver has accepted, so facility 1 has its notice and code."""
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        cho_id=1,
        patient_hash=patient_hash,
        emergency_type="Haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    orchestrator = DispatchOrchestrator()
    dispatch = await orchestrator.initiate_dispatch(db_session, referral.id)
    assert "Accepted" in await orchestrator.handle_accept(db_session, dispatch.id, driver_id)
    await db_session.commit()
    assert dispatch.hospital_code
    return dispatch


async def _send(client, sender: str, text: str, *, form: bool = False):
    if form:
        return await client.post(
            "/api/v1/sms/inbound",
            data={"text": text, "to": "99193", "from": sender, "date": "2026-11-07 10:00:00"},
        )
    return await client.post("/api/v1/sms/inbound", json={"from": sender, "text": text})


async def _replies_to(db_session, phone: str) -> list[str]:
    return [m.body for m in await queued_sms(db_session) if m.recipient == phone]


async def _status(db_session, dispatch: Dispatch) -> tuple[str, int]:
    await db_session.refresh(dispatch)
    return dispatch.status, dispatch.facility_id


# --- Reading the reply ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("CONFIRM 4821", Command("CONFIRM", "4821")),
        ("confirmed 4821.", Command("CONFIRM", "4821")),
        ("ok 4821", Command("CONFIRM", "4821")),
        ("  DIVERT 4821 7 ", Command("DIVERT", "4821", "7")),
        ("divert 4821 tamale", Command("DIVERT", "4821", "TAMALE")),
        ("CONFIRM", Command("NEED_CODE")),
        ("confirmed", Command("NEED_CODE")),
        ("CONFIRM 12", Command("NEED_CODE")),  # a dispatch number, not a code
        ("DIVERT 7", Command("NEED_CODE")),
        ("CONFIRM 4821 4821", Command("INVALID")),
        ("DIVERT 4821", Command("INVALID")),
        ("hello", Command("INVALID")),
        ("", Command("INVALID")),
    ],
)
def test_parse_command(text, expected):
    assert parse_command(text) == expected


# --- Who may act ----------------------------------------------------------------------


@pytest.mark.asyncio
async def test_destination_facility_confirms_with_its_code(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    response = await _send(client, HOSPITAL_1, f"CONFIRM {dispatch.hospital_code}", form=True)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert response.text == "GOOD"
    assert await _status(db_session, dispatch) == ("HOSPITAL_CONFIRMED", 1)
    log = await db_session.scalar(
        select(DispatchLog).where(DispatchLog.action == "hospital_confirm")
    )
    assert (log.target_role, log.target_phone) == ("hospital", HOSPITAL_1)
    assert (await _replies_to(db_session, HOSPITAL_1))[-1] == (
        f"Yoma Triage: Confirmed referral #{dispatch.referral_id} "
        f"(code {dispatch.hospital_code}). Awaiting arrival."
    )


@pytest.mark.asyncio
async def test_local_phone_format_of_the_facility_is_accepted(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    response = await _send(client, "0240000200", f"CONFIRM {dispatch.hospital_code}")
    assert response.json()["status"] == "CONFIRMED"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("sender", "role"),
    [
        (DRIVER_1, "driver"),
        (SEEDED_CHO_PHONE, "cho"),
        (HOSPITAL_2, "hospital"),
        (STRANGER, "unknown"),
    ],
)
@pytest.mark.parametrize("verb", ["CONFIRM {code}", "DIVERT {code} 2"])
async def test_nobody_but_the_destination_facility_can_act(
    client, seeded_db, db_session, sender, role, verb
):
    dispatch = await _accepted(db_session)
    before = len(await queued_sms(db_session))

    response = await _send(client, sender, verb.format(code=dispatch.hospital_code))

    assert response.json()["status"] == "NOT_YOUR_DISPATCH"
    assert await _status(db_session, dispatch) == ("HOSPITAL_NOTIFIED", 1)
    new = (await queued_sms(db_session))[before:]
    assert [(m.recipient, m.purpose) for m in new] == [(sender, "inbound_reply")]
    assert "not a referral for this number" in new[0].body
    logs = list(await db_session.scalars(select(DispatchLog).order_by(DispatchLog.id)))
    rejected = [log for log in logs if log.action == "hospital_command_rejected"]
    assert [(log.target_role, log.target_phone) for log in rejected] == [(role, sender)]
    assert not [log for log in logs if log.action in {"hospital_confirm", "hospital_divert"}]


# --- Mistakes, and the replies they get -----------------------------------------------


@pytest.mark.asyncio
@pytest.mark.parametrize("text", ["confirmed", "CONFIRM", "DIVERT 2"])
async def test_a_reply_without_the_code_is_asked_for_it(client, seeded_db, db_session, text):
    dispatch = await _accepted(db_session)

    response = await _send(client, HOSPITAL_1, text, form=True)

    assert response.text == "GOOD"
    assert await _status(db_session, dispatch) == ("HOSPITAL_NOTIFIED", 1)
    reply = (await _replies_to(db_session, HOSPITAL_1))[-1]
    assert "include the 4-digit code" in reply
    assert "CONFIRM <code>" in reply


@pytest.mark.asyncio
async def test_old_style_reply_with_the_dispatch_number_is_not_enough(
    client, seeded_db, db_session
):
    dispatch = await _accepted(db_session)
    response = await _send(client, HOSPITAL_1, f"CONFIRM {dispatch.id}")
    assert response.json()["status"] == "NEED_CODE"
    assert await _status(db_session, dispatch) == ("HOSPITAL_NOTIFIED", 1)


@pytest.mark.asyncio
async def test_unknown_code(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    wrong = "1000" if dispatch.hospital_code != "1000" else "1001"

    response = await _send(client, HOSPITAL_1, f"CONFIRM {wrong}")

    assert response.json()["status"] == "UNKNOWN_CODE"
    assert await _status(db_session, dispatch) == ("HOSPITAL_NOTIFIED", 1)
    reply = (await _replies_to(db_session, HOSPITAL_1))[-1]
    assert reply == f"Yoma Triage: Unknown code {wrong}. Check the code in our referral SMS."


@pytest.mark.asyncio
async def test_unknown_facility_code_lists_the_codes(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)

    response = await _send(client, HOSPITAL_1, f"DIVERT {dispatch.hospital_code} 99")

    assert response.json()["status"] == "UNKNOWN_FACILITY"
    assert await _status(db_session, dispatch) == ("HOSPITAL_NOTIFIED", 1)
    reply = (await _replies_to(db_session, HOSPITAL_1))[-1]
    assert "Unknown facility code 99" in reply
    assert "2 Navrongo War Memorial" in reply


@pytest.mark.asyncio
async def test_unreadable_text(client, seeded_db, db_session):
    response = await _send(client, STRANGER, "hello?", form=True)
    assert response.text == "GOOD"
    reply = (await _replies_to(db_session, STRANGER))[-1]
    assert reply.startswith("Yoma Triage: Not understood.")


@pytest.mark.asyncio
async def test_confirm_twice_says_already_confirmed(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    await _send(client, HOSPITAL_1, f"CONFIRM {dispatch.hospital_code}")

    response = await _send(client, HOSPITAL_1, f"CONFIRM {dispatch.hospital_code}")

    assert response.json()["status"] == "ALREADY_CONFIRMED"
    assert "already confirmed" in (await _replies_to(db_session, HOSPITAL_1))[-1]


@pytest.mark.asyncio
async def test_confirm_after_arrival_says_complete(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    await DispatchOrchestrator().handle_arrival(db_session, dispatch.id, 1)
    await db_session.commit()

    response = await _send(client, HOSPITAL_1, f"CONFIRM {dispatch.hospital_code}")

    assert response.json()["status"] == "ALREADY_CONFIRMED"
    assert "complete" in (await _replies_to(db_session, HOSPITAL_1))[-1]


@pytest.mark.asyncio
async def test_divert_after_arrival_changes_nothing(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    await DispatchOrchestrator().handle_arrival(db_session, dispatch.id, 1)
    await db_session.commit()

    response = await _send(client, HOSPITAL_1, f"DIVERT {dispatch.hospital_code} 2")

    assert response.json()["status"] == "ALREADY_CONFIRMED"
    assert await _status(db_session, dispatch) == ("COMPLETED", 1)


# --- The code ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_each_open_dispatch_gets_its_own_code(client, seeded_db, db_session, monkeypatch):
    """Even when chance picks a code an open dispatch already has."""
    from src.services import hospital_notifier

    picks = iter([3821, 3821, 3821, 4000])
    monkeypatch.setattr(hospital_notifier.secrets, "randbelow", lambda _: next(picks))
    first = await _accepted(db_session)
    second = await _accepted(db_session, driver_id=2, patient_hash="b" * 64)

    assert (first.hospital_code, second.hospital_code) == ("4821", "5000")


@pytest.mark.asyncio
async def test_a_reply_reaches_only_the_dispatch_with_that_code(client, seeded_db, db_session):
    first = await _accepted(db_session)
    second = await _accepted(db_session, driver_id=2, patient_hash="b" * 64)

    await _send(client, HOSPITAL_1, f"CONFIRM {first.hospital_code}")

    assert (await _status(db_session, first))[0] == "HOSPITAL_CONFIRMED"
    assert (await _status(db_session, second))[0] == "HOSPITAL_NOTIFIED"


@pytest.mark.asyncio
async def test_the_notice_carries_the_code_and_nearby_facility_codes(
    client, seeded_db, db_session
):
    dispatch = await _accepted(db_session)
    notice = (await queued_sms(db_session, "hospital_pre_arrival"))[0].body
    code = dispatch.hospital_code
    assert f"Code: {code}" in notice
    assert f"Reply CONFIRM {code}, or DIVERT {code} <facility code>" in notice
    assert notice.endswith("Facility codes: 2 Navrongo War Memorial")
    assert f"Referral #{dispatch.referral_id}" in notice


@pytest.mark.asyncio
async def test_after_a_diversion_the_old_code_is_dead_and_the_new_facility_has_its_own(
    client, seeded_db, db_session
):
    dispatch = await _accepted(db_session)
    old_code = dispatch.hospital_code
    response = await _send(client, HOSPITAL_1, f"DIVERT {old_code} 2")
    assert response.json()["status"] == "DIVERTED"
    await db_session.refresh(dispatch)
    assert dispatch.hospital_code != old_code

    # The old facility, even sending as the new one, can't act with the code it had.
    response = await _send(client, HOSPITAL_2, f"CONFIRM {old_code}")
    assert response.json()["status"] == "UNKNOWN_CODE"
    new_notice = [
        m.body
        for m in await queued_sms(db_session, "hospital_pre_arrival")
        if m.recipient == HOSPITAL_2
    ]
    assert f"Code: {dispatch.hospital_code}" in new_notice[0]
    response = await _send(client, HOSPITAL_2, f"CONFIRM {dispatch.hospital_code}")
    assert response.json()["status"] == "CONFIRMED"


@pytest.mark.asyncio
async def test_divert_is_logged_with_the_real_role(client, seeded_db, db_session):
    dispatch = await _accepted(db_session)
    await _send(client, HOSPITAL_1, f"DIVERT {dispatch.hospital_code} 2")
    log = await db_session.scalar(
        select(DispatchLog).where(DispatchLog.action == "hospital_divert")
    )
    assert (log.target_role, log.target_phone) == ("hospital", HOSPITAL_1)
    assert log.metadata_json["from_facility_id"] == 1
    assert log.metadata_json["destination_facility_id"] == 2


@pytest.mark.asyncio
async def test_facility_codes_are_the_nearest_three(db_session, seeded_db):
    from src.db.models import Facility
    from src.services.hospital_notifier import divert_options, facility_codes_line

    # Facility 1 is at 9.4034, -0.8424. Facility 2 (Navrongo) is about 165 km away.
    db_session.add_all(
        [
            Facility(id=3, name="Near", phone="+233240000203", district="D",
                     latitude=9.41, longitude=-0.85),
            Facility(id=4, name="Nowhere known", phone="+233240000204", district="D"),
            Facility(id=5, name="Middle distance hospital name", phone="+233240000205",
                     district="D", latitude=9.9, longitude=-0.85),
        ]
    )
    await db_session.flush()
    home = await db_session.get(Facility, 1)

    options = await divert_options(db_session, home)

    assert [f.id for f in options] == [3, 5, 2]
    assert facility_codes_line(options) == (
        "3 Near, 5 Middle distance hospit, 2 Navrongo War Memorial"
    )
