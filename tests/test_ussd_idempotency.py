from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import BackgroundTasks


@pytest.mark.asyncio
async def test_double_accept_returns_the_same_terminal_response(monkeypatch):
    from src.api.ussd import process_ussd
    from src.services.driver_pool import DriverPoolManager

    driver = SimpleNamespace(id=3, chps_compound_id=1)
    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="TIER1_NOTIFIED",
        driver_id=None,
        current_tier=1,
        declined_driver_ids=[],
    )
    session = MagicMock()
    session.scalar = AsyncMock(
        side_effect=[driver, dispatch, dispatch, driver, dispatch, dispatch]
    )
    session.get = AsyncMock(return_value=SimpleNamespace(chps_compound_id=1))
    session.commit = AsyncMock()
    session.add = MagicMock()
    monkeypatch.setattr(
        DriverPoolManager, "get_candidates", AsyncMock(return_value=[driver])
    )
    background_tasks = BackgroundTasks()

    first = await process_ussd(session, background_tasks, "+233240000001", "1")
    second = await process_ussd(session, background_tasks, "+233240000001", "1")

    assert first.body == (
        b"END Accepted! Proceed to CHPS. "
        b"(Fuel stipend: mock ledger until MoMo is live.)"
    )
    assert second.body == first.body
    assert len(background_tasks.tasks) == 1


@pytest.mark.asyncio
async def test_decline_queues_escalation_without_sending_sms_synchronously(monkeypatch):
    from src.api import ussd

    driver = SimpleNamespace(id=3, chps_compound_id=1)
    dispatch = SimpleNamespace(id=10)
    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[driver, dispatch])
    session.commit = AsyncMock()

    gateway = MagicMock()
    gateway.send_sms = AsyncMock()
    orchestrator = MagicMock(gateway=gateway)
    orchestrator.handle_decline = AsyncMock(
        return_value={"ussd": "END Referral declined.", "run_side_effects": True}
    )
    monkeypatch.setattr(ussd, "DispatchOrchestrator", lambda: orchestrator)
    background_tasks = BackgroundTasks()

    response = await ussd.process_ussd(
        session, background_tasks, "+233240000003", "2"
    )

    assert response.body == b"END Referral declined."
    session.commit.assert_awaited_once()
    gateway.send_sms.assert_not_awaited()
    assert len(background_tasks.tasks) == 1
    assert background_tasks.tasks[0].func == orchestrator.run_decline_side_effects
    assert background_tasks.tasks[0].args == (10, 3)


@pytest.mark.asyncio
async def test_decline_after_accept_has_no_effect(db_session, seeded_db, monkeypatch):
    from src.api.ussd import process_ussd
    from src.db.models import Referral
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    monkeypatch.setattr(
        DispatchOrchestrator, "schedule_tier_timeouts", lambda self, *a, **k: None
    )
    monkeypatch.setattr(
        DispatchOrchestrator, "run_accept_side_effects", AsyncMock()
    )
    monkeypatch.setattr(
        DispatchOrchestrator, "run_decline_side_effects", AsyncMock()
    )
    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "MOCKED", "provider": "mock"})
    orch = DispatchOrchestrator(gateway=gateway)

    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        emergency_type="Obstetric haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id="dddddddd-dddd-dddd-dddd-dddddddddddd",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await orch.initiate_dispatch(db_session, referral.id)
    await db_session.commit()

    accept_result = await orch.handle_accept(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    assert accept_result["run_side_effects"] is True

    background_tasks = BackgroundTasks()
    decline = await process_ussd(
        db_session, background_tasks, "+233240000001", "2"
    )
    assert decline.body == b"END Decline noted."
    await db_session.refresh(dispatch)
    assert dispatch.status == "ACCEPTED"
    assert dispatch.driver_id == 1
