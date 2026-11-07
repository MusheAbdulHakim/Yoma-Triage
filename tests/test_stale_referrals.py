"""Stale queued referrals and cancelling a dispatch (item 1, BUG-12)."""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from src import parameters
from src.api import errors
from src.db.models import AuditLog, Cho, Dispatch, DispatchLog, OutboundMessage, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator
from src.services.outbox import CANCELLED, OutboxSender
from tests.conftest import SEEDED_CHO_PHONE, queued_sms
from tests.postgres_support import (
    CHO_PHONE,
    DRIVER_PHONES,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)

THRESHOLD = parameters.STALE_AFTER_MINUTES * 60


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


async def _stale(client) -> dict:
    response = await client.post(
        "/api/v1/referral", json=_referral(queue_age_seconds=THRESHOLD + 1)
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _resolve(client, referral_id, action, phone=SEEDED_CHO_PHONE):
    return await client.post(
        f"/api/v1/referral/{referral_id}/resolve", json={"action": action, "cho_phone": phone}
    )


# --- Stale referrals --------------------------------------------------------------


@pytest.mark.asyncio
async def test_stale_referral_is_stored_but_not_dispatched(client, seeded_db, db_session):
    body = await _stale(client)

    assert body["dispatch"] is None
    assert body["referral"]["status"] == "AWAITING_CONFIRMATION"
    assert body["referral"]["queue_age_seconds"] == THRESHOLD + 1
    assert await db_session.scalar(select(Dispatch)) is None
    assert await queued_sms(db_session) == []


@pytest.mark.asyncio
@pytest.mark.parametrize("age", [0, 60, THRESHOLD])
async def test_referral_at_or_under_the_threshold_dispatches(client, seeded_db, age):
    response = await client.post("/api/v1/referral", json=_referral(queue_age_seconds=age))
    body = response.json()
    assert body["dispatch"]["status"] == "TIER1_NOTIFIED"
    assert body["referral"]["status"] == "CONFIRMED"
    assert body["referral"]["queue_age_seconds"] == age


@pytest.mark.asyncio
async def test_no_queue_age_means_a_live_send(client, seeded_db):
    response = await client.post("/api/v1/referral", json=_referral())
    assert response.json()["dispatch"] is not None


@pytest.mark.asyncio
async def test_threshold_can_be_overridden(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.referral.settings.STALE_AFTER_MINUTES", 1)
    response = await client.post("/api/v1/referral", json=_referral(queue_age_seconds=61))
    assert response.json()["dispatch"] is None


@pytest.mark.asyncio
async def test_a_negative_age_is_refused(client, seeded_db):
    response = await client.post("/api/v1/referral", json=_referral(queue_age_seconds=-1))
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_a_skip_vitals_referral_can_be_stale_too(client, seeded_db):
    response = await client.post(
        "/api/v1/referral",
        json=_referral(vitals={}, vitals_taken=False, queue_age_seconds=THRESHOLD + 1),
    )
    assert response.json()["dispatch"] is None


@pytest.mark.asyncio
async def test_a_retry_of_a_stale_referral_does_not_dispatch(client, seeded_db, db_session):
    first = _referral(queue_age_seconds=THRESHOLD + 1)
    await client.post("/api/v1/referral", json=first)
    # The retry measures a longer wait, and must get the same stored referral back.
    retried = await client.post(
        "/api/v1/referral", json={**first, "queue_age_seconds": THRESHOLD + 90}
    )
    assert retried.json()["dispatch"] is None
    assert retried.json()["referral"]["status"] == "AWAITING_CONFIRMATION"
    assert await db_session.scalar(select(Dispatch)) is None


@pytest.mark.asyncio
async def test_send_now_dispatches(client, seeded_db, db_session):
    referral_id = (await _stale(client))["referral"]["id"]

    response = await _resolve(client, referral_id, "send_now")

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["referral"]["status"] == "CONFIRMED"
    assert body["dispatch"]["status"] == "TIER1_NOTIFIED"
    assert {m.purpose for m in await queued_sms(db_session)} == {"driver_offer"}


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("action", "status"), [("already_handled", "MANUALLY_HANDLED"), ("cancel", "CANCELLED")]
)
async def test_other_answers_are_recorded_and_tell_nobody(
    client, seeded_db, db_session, action, status
):
    referral_id = (await _stale(client))["referral"]["id"]

    response = await _resolve(client, referral_id, action)

    assert response.status_code == 200, response.text
    assert response.json()["referral"]["status"] == status
    assert response.json()["dispatch"] is None
    assert await db_session.scalar(select(Dispatch)) is None
    assert await queued_sms(db_session) == []
    audit = await db_session.scalar(select(AuditLog).where(AuditLog.entity_type == "referral"))
    assert audit.action == f"referral_{action}"
    assert audit.entity_id == str(referral_id)


@pytest.mark.asyncio
async def test_repeating_an_answer_changes_nothing(client, seeded_db, db_session):
    referral_id = (await _stale(client))["referral"]["id"]
    first = await _resolve(client, referral_id, "send_now")
    second = await _resolve(client, referral_id, "send_now")

    assert second.status_code == 200
    assert second.json()["dispatch"]["id"] == first.json()["dispatch"]["id"]
    assert len((await db_session.scalars(select(Dispatch))).all()) == 1


@pytest.mark.asyncio
async def test_a_different_answer_after_resolving_is_refused(client, seeded_db):
    referral_id = (await _stale(client))["referral"]["id"]
    await _resolve(client, referral_id, "cancel")

    response = await _resolve(client, referral_id, "send_now")

    assert response.status_code == 409
    assert response.json()["code"] == errors.REFERRAL_ALREADY_RESOLVED


@pytest.mark.asyncio
async def test_send_now_on_an_ordinary_referral_is_a_no_op(client, seeded_db, db_session):
    created = (await client.post("/api/v1/referral", json=_referral())).json()
    response = await _resolve(client, created["referral"]["id"], "send_now")
    assert response.json()["dispatch"]["id"] == created["dispatch"]["id"]
    assert len((await db_session.scalars(select(Dispatch))).all()) == 1


@pytest.mark.asyncio
async def test_resolve_unknown_referral(client, seeded_db):
    response = await _resolve(client, 999, "cancel")
    assert (response.status_code, response.json()["code"]) == (404, errors.REFERRAL_NOT_FOUND)


@pytest.mark.asyncio
async def test_resolve_needs_a_registered_cho_of_that_compound(client, seeded_db, db_session):
    referral_id = (await _stale(client))["referral"]["id"]
    assert (await _resolve(client, referral_id, "cancel", "+233249999999")).status_code == 403
    db_session.add(Cho(id=9, name="Other", phone="+233240000090", compound_id=2))
    await db_session.commit()
    response = await _resolve(client, referral_id, "cancel", "+233240000090")
    assert response.json()["code"] == errors.CHO_WRONG_COMPOUND


@pytest.mark.asyncio
async def test_a_moved_cho_can_stand_down_their_own_referral_but_not_send(
    client, seeded_db, db_session
):
    referral_id = (await _stale(client))["referral"]["id"]
    (await db_session.scalar(select(Cho))).compound_id = 2
    await db_session.commit()

    refused = await _resolve(client, referral_id, "send_now")
    assert refused.json()["code"] == errors.CHO_WRONG_COMPOUND
    assert (await _resolve(client, referral_id, "cancel")).status_code == 200


@pytest.mark.asyncio
async def test_a_deactivated_cho_can_stand_down_but_not_send(client, seeded_db, db_session):
    referral_id = (await _stale(client))["referral"]["id"]
    cho = await db_session.scalar(select(Cho))
    cho.active = False
    await db_session.commit()

    refused = await _resolve(client, referral_id, "send_now")
    assert (refused.status_code, refused.json()["code"]) == (403, errors.CHO_NOT_ACTIVE)
    assert (await _resolve(client, referral_id, "already_handled")).status_code == 200


@pytest.mark.asyncio
async def test_resolve_needs_the_api_key(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "secret")
    assert (await _resolve(client, 1, "cancel")).status_code == 401


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_two_send_nows_at_once_make_one_dispatch(pg_sessions):  # noqa: F811
    import asyncio

    from httpx import ASGITransport, AsyncClient

    from main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as http:
        created = await http.post(
            "/api/v1/referral",
            json=_referral(cho_phone=CHO_PHONE, queue_age_seconds=THRESHOLD + 1),
        )
        referral_id = created.json()["referral"]["id"]
        answers = await asyncio.gather(
            *(_resolve(http, referral_id, "send_now", CHO_PHONE) for _ in range(5))
        )
    assert {answer.status_code for answer in answers} == {200}
    assert len({answer.json()["dispatch"]["id"] for answer in answers}) == 1
    async with pg_sessions() as session:
        assert len((await session.scalars(select(Dispatch))).all()) == 1


# --- Cancelling a dispatch --------------------------------------------------------


async def _dispatch(client) -> dict:
    return (await client.post("/api/v1/referral", json=_referral())).json()["dispatch"]


async def _cancel(client, dispatch_id, phone=SEEDED_CHO_PHONE):
    return await client.post(f"/api/v1/dispatch/{dispatch_id}/cancel", json={"cho_phone": phone})


async def _accept(session, dispatch_id) -> None:
    await DispatchOrchestrator().handle_accept(session, dispatch_id, 1)
    await session.commit()


@pytest.mark.asyncio
async def test_cancel_stops_the_cascade(client, seeded_db, db_session):
    dispatch = await _dispatch(client)

    response = await _cancel(client, dispatch["id"])

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "CANCELLED"
    row = await db_session.get(Dispatch, dispatch["id"])
    await db_session.refresh(row)
    assert row.next_action is None and row.next_action_at is None
    referral = await db_session.get(Referral, row.referral_id)
    await db_session.refresh(referral)
    assert referral.status == "CANCELLED"
    log = await db_session.scalar(
        select(DispatchLog).where(DispatchLog.action == "dispatch_cancelled")
    )
    assert log.metadata_json["cho_id"] == 1


@pytest.mark.asyncio
async def test_cancel_before_accept_tells_no_driver_or_hospital(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _cancel(client, dispatch["id"])
    purposes = {m.purpose for m in await queued_sms(db_session)}
    assert purposes == {"driver_offer"}, "only the offers queued before the cancel"


@pytest.mark.asyncio
async def test_cancel_after_accept_tells_the_driver_and_hospital(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _accept(db_session, dispatch["id"])

    await _cancel(client, dispatch["id"])

    messages = await queued_sms(db_session)
    by_purpose = {m.purpose: m for m in messages}
    assert by_purpose["cancel_driver"].recipient == "+233240000001"
    assert by_purpose["cancel_hospital"].recipient == "+233240000200"
    assert "CANCELLED" in by_purpose["cancel_driver"].body
    assert "CANCELLED" in by_purpose["cancel_hospital"].body


@pytest.mark.asyncio
async def test_a_pre_arrival_notice_still_waiting_is_withdrawn(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _accept(db_session, dispatch["id"])
    await _cancel(client, dispatch["id"])
    notice = await db_session.scalar(
        select(OutboundMessage).where(OutboundMessage.purpose == "hospital_pre_arrival")
    )
    await db_session.refresh(notice)
    assert notice.status == CANCELLED


@pytest.mark.asyncio
async def test_after_cancel_no_driver_can_claim(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _cancel(client, dispatch["id"])
    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch["id"], 2)
    assert reply == "END Dispatch not available."


@pytest.mark.asyncio
async def test_a_failed_dispatch_can_be_cancelled_to_stop_late_claims(
    client, seeded_db, db_session
):
    dispatch = await _dispatch(client)
    row = await db_session.get(Dispatch, dispatch["id"])
    row.status = "FAILED"
    await db_session.commit()

    assert (await _cancel(client, dispatch["id"])).status_code == 200

    reply = await DispatchOrchestrator().handle_accept(db_session, dispatch["id"], 1)
    assert reply == "END Dispatch not available."


@pytest.mark.asyncio
async def test_cancel_twice_sends_one_notice(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _accept(db_session, dispatch["id"])
    await _cancel(client, dispatch["id"])
    assert (await _cancel(client, dispatch["id"])).status_code == 200
    purposes = [m.purpose for m in await queued_sms(db_session)]
    assert purposes.count("cancel_driver") == 1


@pytest.mark.asyncio
async def test_a_completed_dispatch_cannot_be_cancelled(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    row = await db_session.get(Dispatch, dispatch["id"])
    row.status = "COMPLETED"
    await db_session.commit()

    response = await _cancel(client, dispatch["id"])

    assert response.status_code == 409
    assert response.json()["code"] == errors.DISPATCH_NOT_CANCELLABLE


@pytest.mark.asyncio
async def test_cancel_unknown_dispatch(client, seeded_db):
    response = await _cancel(client, 999)
    assert (response.status_code, response.json()["code"]) == (404, errors.DISPATCH_NOT_FOUND)


@pytest.mark.asyncio
async def test_cancel_needs_a_cho_of_that_compound(client, seeded_db):
    dispatch = await _dispatch(client)
    response = await _cancel(client, dispatch["id"], "+233249999999")
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_cancel_needs_the_api_key(client, seeded_db, monkeypatch):
    monkeypatch.setattr("src.api.deps.settings.API_KEY", "secret")
    assert (await _cancel(client, 1)).status_code == 401


class _Gateway:
    def __init__(self):
        self.sent = []

    async def send_sms(self, to, message, dispatch_id, role):
        self.sent.append(to)
        return {"status": "SENT"}


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_waiting_offers_are_not_sent_after_cancel(pg_sessions):  # noqa: F811
    async with pg_sessions() as session:
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            patient_hash="0" * 64,
            emergency_type="pph",
            status="CONFIRMED",
            client_request_id=str(uuid.uuid4()),
        )
        session.add(referral)
        await session.flush()
        dispatch = await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()
        await DispatchOrchestrator().cancel_dispatch(session, dispatch.id, 1)
        await session.commit()

    gateway = _Gateway()
    await OutboxSender(gateway).run_once()

    assert not set(gateway.sent) & set(DRIVER_PHONES.values())


@pytest.mark.postgres
@pytest.mark.asyncio
async def test_cancel_and_accept_at_once_end_consistently(pg_sessions):  # noqa: F811
    """Whichever wins the lock, a cancelled dispatch never keeps a driver on the way silently."""
    import asyncio

    async with pg_sessions() as session:
        referral = Referral(
            chps_compound_id=1,
            facility_id=1,
            patient_hash="0" * 64,
            emergency_type="pph",
            status="CONFIRMED",
            client_request_id=str(uuid.uuid4()),
        )
        session.add(referral)
        await session.flush()
        dispatch = await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()
        dispatch_id = dispatch.id

    async def accept():
        async with pg_sessions() as session:
            await DispatchOrchestrator().handle_accept(session, dispatch_id, 1)
            await session.commit()

    async def cancel():
        async with pg_sessions() as session:
            await DispatchOrchestrator().cancel_dispatch(session, dispatch_id, 1)
            await session.commit()

    await asyncio.gather(accept(), cancel())

    async with pg_sessions() as session:
        row = await session.get(Dispatch, dispatch_id)
        assert row.status == "CANCELLED"
        messages = await queued_sms(session)
        purposes = [m.purpose for m in messages]
        if row.driver_id is not None:
            assert "cancel_driver" in purposes


# --- B2: a manual Call or SMS -------------------------------------------------------


@pytest.mark.asyncio
async def test_after_a_manual_call_a_fresh_referral_waits_for_the_answer(
    client, seeded_db, db_session
):
    response = await client.post(
        "/api/v1/referral", json=_referral(queue_age_seconds=5, manual_contact=True)
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["referral"]["status"] == "AWAITING_CONFIRMATION"
    assert body["dispatch"] is None
    assert (await db_session.scalars(select(Dispatch))).all() == []


@pytest.mark.asyncio
async def test_without_a_manual_call_a_fresh_referral_dispatches(client, seeded_db):
    response = await client.post(
        "/api/v1/referral", json=_referral(queue_age_seconds=5, manual_contact=False)
    )
    assert response.json()["referral"]["status"] == "CONFIRMED"
    assert response.json()["dispatch"] is not None


@pytest.mark.asyncio
async def test_send_now_after_a_manual_call_dispatches(client, seeded_db):
    response = await client.post(
        "/api/v1/referral", json=_referral(queue_age_seconds=0, manual_contact=True)
    )
    referral_id = response.json()["referral"]["id"]
    resolved = await _resolve(client, referral_id, "send_now")
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["dispatch"] is not None
