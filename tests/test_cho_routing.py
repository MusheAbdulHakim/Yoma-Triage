"""Who hears what: cho_id on referrals, and CHO alert routing (item 3)."""
from __future__ import annotations

import logging
import re
import uuid
from pathlib import Path

import pytest
from sqlalchemy import select

from src.db.models import Cho, Dispatch, DispatchLog, OutboundMessage, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator
from src.services.outbox import OutboxSender
from tests.conftest import SEEDED_CHO_PHONE, queued_sms
from tests.hospital_replies import divert_text
from tests.postgres_support import (
    CHO_PHONE,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

REPO = Path(__file__).resolve().parents[1]
SECOND_CHO = "+233240000020"
OLD_NUMBER = "+233240000099"


def _referral(**overrides):
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "a" * 64,
        "cho_phone": SEEDED_CHO_PHONE,
        "emergency_type": "pph",
        "client_request_id": str(uuid.uuid4()),
        "vitals": {"systolic_bp": 60},
        **overrides,
    }


@pytest.fixture
async def two_chos(db_session, seeded_db):
    """A second CHO at the compound, and a compound number that belongs to neither."""
    seeded_db["compounds"][0].cho_phone = OLD_NUMBER
    db_session.add(Cho(id=2, name="Fatima", phone=SECOND_CHO, compound_id=1))
    await db_session.commit()


async def _send(client, phone=SEEDED_CHO_PHONE) -> dict:
    response = await client.post("/api/v1/referral", json=_referral(cho_phone=phone))
    assert response.status_code == 201, response.text
    return response.json()


async def _recipients(session, purpose: str) -> list[str]:
    return sorted(m.recipient for m in await queued_sms(session) if m.purpose == purpose)


async def _dispatch_and_referral(session, dispatch_id):
    dispatch = await session.get(Dispatch, dispatch_id)
    return dispatch, await session.get(Referral, dispatch.referral_id)


async def _arrive(session, dispatch_id) -> None:
    orchestrator = DispatchOrchestrator()
    await orchestrator.handle_accept(session, dispatch_id, 1)
    await orchestrator.handle_arrival(session, dispatch_id, 1)
    await session.commit()


async def _no_driver(session, dispatch_id) -> None:
    dispatch, referral = await _dispatch_and_referral(session, dispatch_id)
    await DispatchOrchestrator()._notify_tier(session, dispatch, referral, tier=3)
    await session.commit()


# --- cho_id ------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_referral_records_who_sent_it(client, two_chos, db_session):
    body = await _send(client, SECOND_CHO)
    assert body["referral"]["cho_id"] == 2
    row = await db_session.get(Referral, body["referral"]["id"])
    assert row.cho_id == 2


@pytest.mark.asyncio
async def test_a_stale_referral_records_who_sent_it(client, two_chos):
    response = await client.post(
        "/api/v1/referral", json=_referral(cho_phone=SECOND_CHO, queue_age_seconds=999_999)
    )
    assert response.json()["referral"]["cho_id"] == 2


# --- Routing -----------------------------------------------------------------------


@pytest.mark.asyncio
async def test_arrival_goes_to_the_sending_cho_only(client, two_chos, db_session):
    body = await _send(client, SECOND_CHO)
    await _arrive(db_session, body["dispatch"]["id"])
    assert await _recipients(db_session, "cho_arrival") == [SECOND_CHO]


@pytest.mark.asyncio
async def test_diversion_notice_goes_to_the_sending_cho_only(client, two_chos, db_session):
    body = await _send(client, SECOND_CHO)
    dispatch_id = body["dispatch"]["id"]
    await DispatchOrchestrator().handle_accept(db_session, dispatch_id, 1)
    await db_session.commit()

    response = await client.post(
        "/api/v1/sms/inbound",
        json={
            "from": "+233240000200",
            "text": await divert_text(db_session, dispatch_id, 2),
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "DIVERTED"
    assert await _recipients(db_session, "divert_cho") == [SECOND_CHO]


@pytest.mark.asyncio
async def test_no_driver_alert_goes_to_every_active_cho(client, two_chos, db_session):
    body = await _send(client)
    await _no_driver(db_session, body["dispatch"]["id"])
    assert await _recipients(db_session, "cho_escalation") == sorted(
        [SEEDED_CHO_PHONE, SECOND_CHO]
    )


@pytest.mark.asyncio
async def test_no_driver_alert_skips_inactive_chos_and_other_compounds(
    client, two_chos, db_session, seed_second_compound
):
    fatima = await db_session.get(Cho, 2)
    fatima.active = False
    db_session.add(Cho(id=3, name="Elsewhere", phone="+233240000030", compound_id=2))
    await db_session.commit()

    body = await _send(client)
    await _no_driver(db_session, body["dispatch"]["id"])

    assert await _recipients(db_session, "cho_escalation") == [SEEDED_CHO_PHONE]


@pytest.mark.asyncio
async def test_late_accept_goes_to_everyone_who_got_the_no_driver_alert(
    client, two_chos, db_session
):
    body = await _send(client, SECOND_CHO)
    dispatch_id = body["dispatch"]["id"]
    await _no_driver(db_session, dispatch_id)

    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch_id, 1)
    await db_session.commit()

    assert "Accepted" in reply
    assert await _recipients(db_session, "cho_late_accept") == sorted(
        [SEEDED_CHO_PHONE, SECOND_CHO]
    )


@pytest.mark.asyncio
async def test_update_falls_back_when_the_sender_was_deactivated(client, two_chos, db_session):
    body = await _send(client, SECOND_CHO)
    (await db_session.get(Cho, 2)).active = False
    await db_session.commit()

    await _arrive(db_session, body["dispatch"]["id"])

    assert await _recipients(db_session, "cho_arrival") == [SEEDED_CHO_PHONE]


@pytest.mark.asyncio
async def test_update_falls_back_when_the_sender_moved(
    client, two_chos, db_session, seed_second_compound
):
    body = await _send(client, SECOND_CHO)
    (await db_session.get(Cho, 2)).compound_id = 2
    await db_session.commit()

    await _arrive(db_session, body["dispatch"]["id"])

    assert await _recipients(db_session, "cho_arrival") == [SEEDED_CHO_PHONE]


@pytest.mark.asyncio
async def test_a_referral_from_before_this_column_tells_every_active_cho(
    client, two_chos, db_session
):
    body = await _send(client)
    referral = await db_session.get(Referral, body["referral"]["id"])
    referral.cho_id = None
    await db_session.commit()

    await _arrive(db_session, body["dispatch"]["id"])

    assert await _recipients(db_session, "cho_arrival") == sorted([SEEDED_CHO_PHONE, SECOND_CHO])


@pytest.mark.asyncio
async def test_with_no_active_cho_the_gap_is_recorded(client, two_chos, db_session, caplog):
    body = await _send(client)
    for cho in (await db_session.scalars(select(Cho))).all():
        cho.active = False
    await db_session.commit()

    with caplog.at_level(logging.ERROR):
        await _no_driver(db_session, body["dispatch"]["id"])

    assert await _recipients(db_session, "cho_escalation") == []
    row = await db_session.scalar(
        select(DispatchLog).where(DispatchLog.action == "cho_alert_no_recipient")
    )
    assert row.metadata_json["purpose"] == "cho_escalation"
    assert "No active CHO" in caplog.text
    assert "+233" not in caplog.text


@pytest.mark.asyncio
async def test_the_compound_number_is_never_alerted(client, two_chos, db_session):
    first = await _send(client)
    second = await _send(client)
    await _no_driver(db_session, first["dispatch"]["id"])
    await _arrive(db_session, second["dispatch"]["id"])
    assert OLD_NUMBER not in {m.recipient for m in await queued_sms(db_session)}


def test_no_code_reads_the_compound_number_for_a_message():
    uses = []
    for path in [*(REPO / "src/services").glob("*.py"), *(REPO / "src/api").glob("*.py")]:
        for line in path.read_text(encoding="utf-8").splitlines():
            if re.search(r"compound\w*\.cho_phone", line):
                uses.append(f"{path.name}: {line.strip()}")
    assert uses == []


class _Failing:
    async def send_sms(self, to, message, dispatch_id, role):
        return {"status": "FAILED", "error": "rejected"}


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_undeliverable_driver_sms_alerts_every_active_cho(
    pg_sessions, monkeypatch  # noqa: F811
):
    monkeypatch.setattr("src.services.outbox.parameters.OUTBOX_MAX_ATTEMPTS", 1)
    async with pg_sessions() as session:
        sender = Cho(name="Second", phone=SECOND_CHO, compound_id=1)
        session.add(sender)
        await session.flush()
        # A known sender, so a sender-only alert can't pass by falling back to everyone.
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            cho_id=sender.id,
            patient_hash="0" * 64,
            emergency_type="pph",
            status="CONFIRMED",
            client_request_id=str(uuid.uuid4()),
        )
        session.add(referral)
        await session.flush()
        await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()

    await OutboxSender(_Failing()).drain()

    async with pg_sessions() as session:
        alerts = await session.scalars(
            select(OutboundMessage.recipient).where(OutboundMessage.purpose == "send_failure_alert")
        )
        assert set(alerts) == {CHO_PHONE, SECOND_CHO}
