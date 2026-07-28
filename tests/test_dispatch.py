from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import BackgroundTasks


def test_claimable_statuses():
    from src.services.dispatch_orchestrator import CLAIMABLE

    assert "TIER1_NOTIFIED" in CLAIMABLE
    assert "TIER2_NOTIFIED" in CLAIMABLE
    assert "ACCEPTED" not in CLAIMABLE


@pytest.mark.asyncio
async def test_decline_marks_unclaimed_dispatch_for_background_escalation():
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="TIER1_NOTIFIED",
        driver_id=None,
        current_tier=1,
        declined_driver_ids=[],
    )
    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)
    gateway = MagicMock()
    gateway.send_sms = AsyncMock()
    orchestrator = DispatchOrchestrator(gateway=gateway)

    result = await orchestrator.handle_decline(session, dispatch.id, driver_id=3)

    assert result["ussd"] == "END Referral declined."
    assert result["run_side_effects"] is True
    assert dispatch.declined_driver_ids == [3]
    assert dispatch.current_tier == 1
    gateway.send_sms.assert_not_awaited()


@pytest.mark.asyncio
async def test_decline_does_not_escalate_when_same_tier_candidates_remain(monkeypatch):
    from src.services import dispatch_orchestrator as orch_mod

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="TIER1_NOTIFIED",
        driver_id=None,
        current_tier=1,
        declined_driver_ids=[3],
    )
    referral = SimpleNamespace(id=20, chps_compound_id=1)
    remaining = [SimpleNamespace(id=1), SimpleNamespace(id=2)]

    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)
    session.get = AsyncMock(return_value=referral)
    session.commit = AsyncMock()
    session.add = MagicMock()

    session_cm = MagicMock()
    session_cm.__aenter__ = AsyncMock(return_value=session)
    session_cm.__aexit__ = AsyncMock(return_value=None)
    monkeypatch.setattr(orch_mod, "async_session", lambda: session_cm)

    orchestrator = orch_mod.DispatchOrchestrator()
    orchestrator.pool.get_candidates = AsyncMock(return_value=remaining)
    orchestrator._notify_tier = AsyncMock()
    orchestrator.schedule_tier_timeouts = MagicMock()

    await orchestrator.run_decline_side_effects(dispatch.id, driver_id=3)

    orchestrator._notify_tier.assert_not_awaited()
    orchestrator.schedule_tier_timeouts.assert_not_called()
    assert dispatch.current_tier == 1
    actions = [
        call.args[0].action
        for call in session.add.call_args_list
        if hasattr(call.args[0], "action")
    ]
    assert "decline_tier_remaining" in actions


@pytest.mark.asyncio
async def test_decline_escalates_only_when_tier_exhausted(monkeypatch):
    from src.services import dispatch_orchestrator as orch_mod

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="TIER1_NOTIFIED",
        driver_id=None,
        current_tier=1,
        declined_driver_ids=[1, 2, 3],
    )
    referral = SimpleNamespace(id=20, chps_compound_id=1)

    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)
    session.get = AsyncMock(return_value=referral)
    session.commit = AsyncMock()

    session_cm = MagicMock()
    session_cm.__aenter__ = AsyncMock(return_value=session)
    session_cm.__aexit__ = AsyncMock(return_value=None)
    monkeypatch.setattr(orch_mod, "async_session", lambda: session_cm)

    orchestrator = orch_mod.DispatchOrchestrator()
    orchestrator.pool.get_candidates = AsyncMock(return_value=[])
    orchestrator.schedule_tier_timeouts = MagicMock()

    async def _notify(session, dispatch, referral, tier):
        dispatch.current_tier = tier
        dispatch.status = f"TIER{tier}_NOTIFIED"

    orchestrator._notify_tier = AsyncMock(side_effect=_notify)

    await orchestrator.run_decline_side_effects(dispatch.id, driver_id=3)

    orchestrator._notify_tier.assert_awaited_once()
    assert orchestrator._notify_tier.await_args.kwargs["tier"] == 2
    orchestrator.schedule_tier_timeouts.assert_called_once()


@pytest.mark.asyncio
async def test_second_driver_cannot_accept_claimed_dispatch():
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    dispatch = SimpleNamespace(id=10, status="ACCEPTED", driver_id=3)
    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)

    result = await DispatchOrchestrator().handle_accept(session, dispatch.id, driver_id=4)

    assert result == {"ussd": "END Already assigned.", "run_side_effects": False}


@pytest.mark.asyncio
async def test_tier_two_driver_cannot_accept_while_tier_one_is_active():
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    tier_two_driver = SimpleNamespace(id=4)
    tier_one_driver = SimpleNamespace(id=3)
    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="TIER1_NOTIFIED",
        driver_id=None,
        current_tier=1,
        declined_driver_ids=[],
    )
    referral = SimpleNamespace(chps_compound_id=1)
    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)
    session.get = AsyncMock(return_value=referral)
    orchestrator = DispatchOrchestrator()
    orchestrator.pool.get_candidates = AsyncMock(return_value=[tier_one_driver])

    result = await orchestrator.handle_accept(session, dispatch.id, tier_two_driver.id)

    assert result == {
        "ussd": "END You are not eligible for this dispatch.",
        "run_side_effects": False,
    }
    assert dispatch.status == "TIER1_NOTIFIED"
    assert dispatch.driver_id is None


@pytest.mark.asyncio
async def test_ussd_accept_queues_side_effects_in_background(monkeypatch):
    from src.api import ussd

    driver = SimpleNamespace(id=3, chps_compound_id=1)
    dispatch = SimpleNamespace(id=10)
    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[driver, dispatch])
    session.commit = AsyncMock()

    orchestrator = MagicMock()
    orchestrator.handle_accept = AsyncMock(
        return_value={"ussd": "END Accepted!", "run_side_effects": True}
    )
    monkeypatch.setattr(ussd, "DispatchOrchestrator", lambda: orchestrator)
    background_tasks = BackgroundTasks()

    response = await ussd.process_ussd(
        session,
        background_tasks,
        "+233240000003",
        "1",
    )

    assert response.body == b"END Accepted!"
    orchestrator.handle_accept.assert_awaited_once_with(session, 10, 3)
    session.commit.assert_awaited_once()
    assert len(background_tasks.tasks) == 1
    assert background_tasks.tasks[0].args == (10, 3)


@pytest.mark.asyncio
async def test_two_drivers_accept_only_one_wins(db_session, seeded_db, monkeypatch):
    """Claim race: first committed accept wins; second gets Already assigned."""
    from src.db.models import Referral
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    monkeypatch.setattr(
        DispatchOrchestrator, "schedule_tier_timeouts", lambda self, *a, **k: None
    )
    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "MOCKED", "provider": "mock"})
    orch = DispatchOrchestrator(gateway=gateway)

    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        emergency_type="Obstetric haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = await orch.initiate_dispatch(db_session, referral.id)
    await db_session.commit()

    first = await orch.handle_accept(db_session, dispatch.id, driver_id=1)
    await db_session.commit()
    second = await orch.handle_accept(db_session, dispatch.id, driver_id=2)
    await db_session.commit()

    assert first["run_side_effects"] is True
    assert second == {"ussd": "END Already assigned.", "run_side_effects": False}
    await db_session.refresh(dispatch)
    assert dispatch.status == "ACCEPTED"
    assert dispatch.driver_id == 1
