"""Who is told what, at each step, through the whole lifecycle (batch 6 item 4).

Each step asserts the exact set of new messages, by recipient and purpose, so a missing
notice and an extra one both fail.
"""
from __future__ import annotations

from collections import Counter

import pytest

from src.db.models import Cho, Dispatch
from src.services.dispatch_orchestrator import DispatchOrchestrator
from tests.conftest import SEEDED_CHO_PHONE, queued_sms
from tests.hospital_replies import confirm_text, divert_text
from tests.ussd_paths import CONFIRM_ARRIVAL, accept, decline

CHO = SEEDED_CHO_PHONE
OTHER_CHO = "+233240000020"
DRIVER_1, DRIVER_2 = "+233240000001", "+233240000002"
HOSPITAL_1, HOSPITAL_2 = "+233240000200", "+233240000201"


class Outbox:
    """What was queued since the last look."""

    def __init__(self, session):
        self.session = session
        self.seen = 0

    async def new(self) -> list:
        messages = await queued_sms(self.session)
        fresh, self.seen = messages[self.seen :], len(messages)
        return fresh

    async def expect(self, *pairs: tuple[str, str]) -> list:
        fresh = await self.new()
        assert Counter((m.recipient, m.purpose) for m in fresh) == Counter(pairs)
        return fresh


async def _ussd(client, phone: str, text: str) -> str:
    response = await client.post(
        "/ussd/callback", data={"phoneNumber": phone, "serviceCode": "*1#", "text": text}
    )
    return response.text


async def _hospital(client, phone: str, text: str) -> dict:
    return (await client.post("/api/v1/sms/inbound", json={"from": phone, "text": text})).json()


@pytest.fixture
def no_service_code(monkeypatch):
    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")


@pytest.fixture
async def second_cho(db_session, seeded_db):
    """Another CHO at the compound: alerts reach them, routine updates don't."""
    db_session.add(Cho(id=2, name="Fatima", phone=OTHER_CHO, compound_id=1))
    await db_session.commit()


async def _refer(client, payload) -> tuple[int, int]:
    response = await client.post("/api/v1/referral", json=payload)
    assert response.status_code == 201, response.text
    body = response.json()
    return body["dispatch"]["id"], body["referral"]["id"]


@pytest.mark.asyncio
async def test_the_divert_path(
    client, db_session, second_cho, sample_referral_payload, no_service_code
):
    outbox = Outbox(db_session)
    dispatch_id, ref = await _refer(client, sample_referral_payload)
    await outbox.expect((DRIVER_1, "driver_offer"), (DRIVER_2, "driver_offer"))

    assert "declined" in await _ussd(client, DRIVER_1, decline(ref))
    await outbox.expect()

    assert "Accepted" in await _ussd(client, DRIVER_2, accept(ref))
    pre_arrival, cho_accept = await outbox.expect(
        (HOSPITAL_1, "hospital_pre_arrival"), (CHO, "cho_driver_accepted")
    )
    assert cho_accept.body == (
        f"Yoma Triage: Driver Musah accepted Ref #{ref} (Motor-King, Blue tricycle). "
        f"Phone {DRIVER_2}. Going to Tamale Teaching Hospital."
    )

    assert (await _hospital(client, HOSPITAL_1, await confirm_text(db_session, dispatch_id)))[
        "status"
    ] == "CONFIRMED"
    await outbox.expect((HOSPITAL_1, "inbound_confirm_ack"))

    assert (await _hospital(client, HOSPITAL_1, await divert_text(db_session, dispatch_id, 2)))[
        "status"
    ] == "DIVERTED"
    await outbox.expect(
        (HOSPITAL_2, "hospital_pre_arrival"),
        (HOSPITAL_1, "divert_old_hospital"),
        (DRIVER_2, "divert_driver"),
        (CHO, "divert_cho"),
    )

    assert "Arrival confirmed" in await _ussd(client, DRIVER_2, CONFIRM_ARRIVAL)
    cho_arrival, hospital_arrival = sorted(
        await outbox.expect((CHO, "cho_arrival"), (HOSPITAL_2, "hospital_arrival")),
        key=lambda m: m.purpose,
    )
    assert cho_arrival.body == (
        f"Yoma Triage: Patient arrived at Navrongo War Memorial Hospital for referral #{ref}."
    )
    dispatch = await db_session.get(Dispatch, dispatch_id)
    await db_session.refresh(dispatch)
    assert dispatch.status == "COMPLETED"
    assert hospital_arrival.body == (
        f"Yoma Triage: The driver reports the patient for referral #{ref} "
        f"(code {dispatch.hospital_code}) has arrived at Navrongo War Memorial Hospital."
    )

    # Nobody who wasn't part of it heard anything, the other CHO included.
    everyone = {m.recipient for m in await queued_sms(db_session)}
    assert everyone == {CHO, DRIVER_1, DRIVER_2, HOSPITAL_1, HOSPITAL_2}


@pytest.mark.asyncio
async def test_the_straight_path(
    client, db_session, second_cho, sample_referral_payload, no_service_code
):
    outbox = Outbox(db_session)
    dispatch_id, ref = await _refer(client, sample_referral_payload)
    await outbox.expect((DRIVER_1, "driver_offer"), (DRIVER_2, "driver_offer"))

    await _ussd(client, DRIVER_1, accept(ref))
    await outbox.expect((HOSPITAL_1, "hospital_pre_arrival"), (CHO, "cho_driver_accepted"))

    await _hospital(client, HOSPITAL_1, await confirm_text(db_session, dispatch_id))
    await outbox.expect((HOSPITAL_1, "inbound_confirm_ack"))

    await _ussd(client, DRIVER_1, CONFIRM_ARRIVAL)
    await outbox.expect((CHO, "cho_arrival"), (HOSPITAL_1, "hospital_arrival"))


@pytest.mark.asyncio
async def test_a_late_accept_tells_every_cho_once(
    client, db_session, second_cho, sample_referral_payload, no_service_code
):
    outbox = Outbox(db_session)
    dispatch_id, ref = await _refer(client, sample_referral_payload)
    orchestrator = DispatchOrchestrator()
    for _ in range(2):  # tier 1 times out, then tier 2: the cascade gives up
        dispatch = await db_session.get(Dispatch, dispatch_id)
        await orchestrator._perform_next_action(db_session, dispatch)
        await db_session.commit()
    await outbox.new()
    assert dispatch.status == "FAILED"

    assert "Accepted" in await _ussd(client, DRIVER_1, accept(ref))

    late = await outbox.expect(
        (HOSPITAL_1, "hospital_pre_arrival"),
        (CHO, "cho_late_accept"),
        (OTHER_CHO, "cho_late_accept"),
    )
    body = next(m.body for m in late if m.purpose == "cho_late_accept")
    assert f"Driver Ibrahim ({DRIVER_1}, Motor-King, Red tricycle) accepted LATE" in body


@pytest.mark.asyncio
async def test_cancel_after_accept(
    client, db_session, second_cho, sample_referral_payload, no_service_code
):
    outbox = Outbox(db_session)
    dispatch_id, ref = await _refer(client, sample_referral_payload)
    await _ussd(client, DRIVER_1, accept(ref))
    await outbox.new()

    response = await client.post(
        f"/api/v1/dispatch/{dispatch_id}/cancel", json={"cho_phone": CHO}
    )
    assert response.status_code == 200, response.text
    await outbox.expect((DRIVER_1, "cancel_driver"), (HOSPITAL_1, "cancel_hospital"))

