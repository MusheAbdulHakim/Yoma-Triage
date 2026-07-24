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
async def test_decline_does_not_escalate_an_accepted_dispatch():
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        status="ACCEPTED",
        current_tier=1,
        declined_driver_ids=[],
    )
    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)
    session.get = AsyncMock()
    orchestrator = DispatchOrchestrator()
    orchestrator._notify_tier = AsyncMock()
    orchestrator.schedule_tier_timeouts = MagicMock()

    result = await orchestrator.handle_decline(session, dispatch.id, driver_id=3)

    assert result["ussd"] == "END Decline noted."
    assert dispatch.declined_driver_ids == [3]
    orchestrator._notify_tier.assert_not_awaited()


@pytest.mark.asyncio
async def test_second_driver_cannot_accept_claimed_dispatch():
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    dispatch = SimpleNamespace(id=10, status="ACCEPTED", driver_id=3)
    session = MagicMock()
    session.scalar = AsyncMock(return_value=dispatch)

    result = await DispatchOrchestrator().handle_accept(session, dispatch.id, driver_id=4)

    assert result == {"ussd": "END Already assigned.", "run_side_effects": False}


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

    response = await ussd.handle_ussd(
        session_id="session-1",
        service_code="*123#",
        phone_number="+233240000003",
        text="1",
        session=session,
        background_tasks=background_tasks,
    )

    assert response.body == b"END Accepted!"
    orchestrator.handle_accept.assert_awaited_once_with(session, 10, 3)
    session.commit.assert_awaited_once()
    assert len(background_tasks.tasks) == 1
    assert background_tasks.tasks[0].args == (10, 3)
