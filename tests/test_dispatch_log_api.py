from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


@pytest.mark.asyncio
async def test_get_dispatch_logs_serializes_dispatch_audit_entries():
    from src.api.referral import get_dispatch_logs

    log = SimpleNamespace(
        id=8,
        dispatch_id=4,
        action="momo_escrow",
        target_phone="+233240000001",
        target_role="driver",
        response="INITIAL_DISBURSED",
        metadata_json={"amount_ghs": 22.5},
        created_at=None,
    )
    session = SimpleNamespace(scalars=AsyncMock(return_value=[log]))

    assert await get_dispatch_logs(4, session) == {
        "dispatch_id": 4,
        "logs": [
            {
                "id": 8,
                "action": "momo_escrow",
                "target_phone": "+233240000001",
                "target_role": "driver",
                "response": "INITIAL_DISBURSED",
                "metadata": {"amount_ghs": 22.5},
                "created_at": None,
            }
        ],
    }
