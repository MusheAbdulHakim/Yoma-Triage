from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import BackgroundTasks


@pytest.mark.asyncio
async def test_double_accept_returns_the_same_terminal_response():
    from src.api.ussd import process_ussd

    driver = SimpleNamespace(id=3, chps_compound_id=1)
    dispatch = SimpleNamespace(id=10, status="TIER1_NOTIFIED", driver_id=None)
    session = MagicMock()
    session.scalar = AsyncMock(
        side_effect=[driver, dispatch, dispatch, driver, dispatch, dispatch]
    )
    session.commit = AsyncMock()
    session.add = MagicMock()
    background_tasks = BackgroundTasks()

    first = await process_ussd(session, background_tasks, "+233240000001", "1")
    second = await process_ussd(session, background_tasks, "+233240000001", "1")

    assert first.body == b"END Accepted! Fuel stipend queued. Proceed to CHPS."
    assert second.body == first.body
    assert len(background_tasks.tasks) == 1
