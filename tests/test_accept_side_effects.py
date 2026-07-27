"""Coverage for post-accept MoMo escrow + hospital notify side effects."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest


@pytest.mark.asyncio
async def test_run_accept_side_effects_disburses_momo_and_notifies_hospital(
    monkeypatch,
):
    from src.services import dispatch_orchestrator as orch_mod

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        driver_id=3,
        facility_id=1,
        status="ACCEPTED",
    )
    referral = SimpleNamespace(id=20, compressed_sms_payload="abc")
    driver = SimpleNamespace(id=3, name="Ibrahim", phone="+233240000001")
    facility = SimpleNamespace(id=1, name="TTH", phone="+233240000099")

    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[dispatch, None])  # dispatch, no existing momo log
    session.get = AsyncMock(side_effect=[referral, driver, facility])
    session.add = MagicMock()
    session.commit = AsyncMock()

    session_cm = MagicMock()
    session_cm.__aenter__ = AsyncMock(return_value=session)
    session_cm.__aexit__ = AsyncMock(return_value=None)
    monkeypatch.setattr(orch_mod, "async_session", lambda: session_cm)

    hospital = MagicMock()
    hospital.notify_pre_arrival = AsyncMock()
    orchestrator = orch_mod.DispatchOrchestrator()
    orchestrator.hospital = hospital

    await orchestrator.run_accept_side_effects(10, 3)

    hospital.notify_pre_arrival.assert_awaited_once()
    call_args = hospital.notify_pre_arrival.await_args
    assert call_args.args[1] is referral
    assert call_args.args[2] is driver
    assert call_args.args[3] is facility
    assert call_args.args[4] == 10
    session.commit.assert_awaited_once()
    assert dispatch.status == "HOSPITAL_NOTIFIED"
    actions = [
        call.args[0].action
        for call in session.add.call_args_list
        if hasattr(call.args[0], "action")
    ]
    assert "momo_escrow" in actions


@pytest.mark.asyncio
async def test_run_accept_side_effects_is_idempotent_when_momo_log_exists(
    monkeypatch,
):
    from src.services import dispatch_orchestrator as orch_mod

    dispatch = SimpleNamespace(
        id=10,
        referral_id=20,
        driver_id=3,
        facility_id=1,
        status="ACCEPTED",
    )
    existing_log = SimpleNamespace(id=99, action="momo_escrow")

    session = MagicMock()
    session.scalar = AsyncMock(side_effect=[dispatch, existing_log])
    session.add = MagicMock()
    session.commit = AsyncMock()

    session_cm = MagicMock()
    session_cm.__aenter__ = AsyncMock(return_value=session)
    session_cm.__aexit__ = AsyncMock(return_value=None)
    monkeypatch.setattr(orch_mod, "async_session", lambda: session_cm)

    hospital = MagicMock()
    hospital.notify_pre_arrival = AsyncMock()
    orchestrator = orch_mod.DispatchOrchestrator()
    orchestrator.hospital = hospital

    await orchestrator.run_accept_side_effects(10, 3)

    hospital.notify_pre_arrival.assert_not_awaited()
    session.commit.assert_not_awaited()
