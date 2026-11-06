"""Background worker loop. Runs in the FastAPI lifespan for now, single process."""
from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Awaitable, Callable

logger = logging.getLogger(__name__)


async def run_worker_loop(
    name: str,
    step: Callable[[], Awaitable[object]],
    poll_seconds: float,
    stop: asyncio.Event,
) -> None:
    """Run ``step`` now and then every ``poll_seconds`` until ``stop`` is set.

    The first run is immediate, so anything overdue after a restart is handled on
    startup. A failed run is logged and retried on the next poll.
    """
    while not stop.is_set():
        try:
            await step()
        except Exception:
            logger.exception("%s worker step failed", name)
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(stop.wait(), timeout=poll_seconds)
