"""Driver arrival confirmation via USSD option 3."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import Dispatch, DispatchLog, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator

VALID_PATIENT_HASH = "0123456789abcdef" * 4


async def _seed_arrival_dispatch(
    db_session,
    *,
    status: str = "HOSPITAL_NOTIFIED",
    driver_id: int = 1,
) -> Dispatch:
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash=VALID_PATIENT_HASH,
        emergency_type="Obstetric haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id="12121212-1212-1212-1212-121212121212",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id,
        facility_id=1,
        driver_id=driver_id,
        status=status,
        current_tier=1,
        declined_driver_ids=[],
    )
    db_session.add(dispatch)
    await db_session.flush()
    return dispatch


@pytest.mark.asyncio
async def test_handle_arrival_completes_hospital_notified_dispatch(db_session, seeded_db):
    dispatch = await _seed_arrival_dispatch(db_session)
    orch = DispatchOrchestrator()

    result = await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    await db_session.refresh(dispatch)
    assert "Arrival confirmed" in result
    assert dispatch.status == "COMPLETED"
    assert dispatch.completed_at is not None


@pytest.mark.asyncio
async def test_handle_arrival_completes_hospital_confirmed_dispatch(db_session, seeded_db):
    dispatch = await _seed_arrival_dispatch(db_session, status="HOSPITAL_CONFIRMED")
    orch = DispatchOrchestrator()

    result = await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    await db_session.refresh(dispatch)
    assert "Arrival confirmed" in result
    assert dispatch.status == "COMPLETED"


@pytest.mark.asyncio
async def test_handle_arrival_rejects_wrong_driver(db_session, seeded_db):
    dispatch = await _seed_arrival_dispatch(db_session)
    orch = DispatchOrchestrator()

    result = await orch.handle_arrival(db_session, dispatch.id, driver_id=2)
    await db_session.refresh(dispatch)
    assert "not assigned" in result
    assert dispatch.status == "HOSPITAL_NOTIFIED"


@pytest.mark.asyncio
async def test_handle_arrival_rejects_before_hospital_notification(db_session, seeded_db):
    dispatch = await _seed_arrival_dispatch(db_session, status="ACCEPTED")
    orch = DispatchOrchestrator()

    result = await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.refresh(dispatch)
    assert "not available" in result
    assert dispatch.status == "ACCEPTED"


@pytest.mark.asyncio
async def test_duplicate_arrival_is_idempotent(db_session, seeded_db):
    dispatch = await _seed_arrival_dispatch(db_session)
    orch = DispatchOrchestrator()

    first = await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    second = await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()

    assert first == second
    logs = await db_session.scalars(
        select(DispatchLog).where(
            DispatchLog.dispatch_id == dispatch.id,
            DispatchLog.action == "arrival_confirm",
        )
    )
    assert len(list(logs)) == 1


@pytest.mark.asyncio
async def test_ussd_option_three_completes_dispatch(
    db_session, seeded_db, monkeypatch
):
    from src.api.ussd import process_ussd

    dispatch = await _seed_arrival_dispatch(db_session, status="HOSPITAL_CONFIRMED")

    response = await process_ussd(db_session, "+233240000001", "3"
    )
    await db_session.refresh(dispatch)

    assert b"Arrival confirmed" in response.body
    assert dispatch.status == "COMPLETED"


@pytest.mark.asyncio
async def test_ussd_option_three_rejects_unassigned_driver(
    db_session, seeded_db, monkeypatch
):
    from src.api.ussd import process_ussd

    await _seed_arrival_dispatch(db_session, status="HOSPITAL_CONFIRMED", driver_id=1)

    response = await process_ussd(db_session, "+233240000002", "3"
    )

    assert b"not assigned" in response.body.lower() or b"No active dispatch" in response.body


@pytest.mark.asyncio
async def test_arrival_notifies_cho_once_even_if_repeated(db_session, seeded_db):
    from tests.conftest import queued_sms

    dispatch = await _seed_arrival_dispatch(db_session)
    orch = DispatchOrchestrator()

    await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    await orch.handle_arrival(db_session, dispatch.id, driver_id=1)
    await db_session.commit()

    messages = await queued_sms(db_session, "cho_arrival")
    assert len(messages) == 1
    assert "arrived" in messages[0].body
