"""B3: a cancelled dispatch keeps its stipend ledger entry, marked cancelled."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from src.db.models import DispatchLog, Wallet
from src.parameters import FUEL_STIPEND_GHS
from tests.test_stale_referrals import _accept, _cancel, _dispatch


async def _stipends(session, dispatch_id: int) -> list[Wallet]:
    rows = await session.scalars(
        select(Wallet).where(Wallet.dispatch_id == dispatch_id).execution_options(
            populate_existing=True
        )
    )
    return list(rows)


async def _log_actions(session, dispatch_id: int) -> list[str]:
    rows = await session.scalars(
        select(DispatchLog.action).where(DispatchLog.dispatch_id == dispatch_id)
    )
    return list(rows)


@pytest.mark.asyncio
async def test_cancel_after_accept_keeps_the_entry_marked_cancelled(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _accept(db_session, dispatch["id"])
    [before] = await _stipends(db_session, dispatch["id"])
    assert before.status == "INITIAL_DISBURSED"

    response = await _cancel(client, dispatch["id"])
    assert response.status_code == 200, response.text

    [after] = await _stipends(db_session, dispatch["id"])
    assert after.id == before.id, "the same row, not deleted and replaced"
    assert after.status == "CANCELLED"
    assert after.amount == FUEL_STIPEND_GHS
    assert after.transaction_id == before.transaction_id
    assert "momo_escrow_cancelled" in await _log_actions(db_session, dispatch["id"])


@pytest.mark.asyncio
async def test_cancel_before_accept_has_no_entry_to_mark(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    assert (await _cancel(client, dispatch["id"])).status_code == 200
    assert await _stipends(db_session, dispatch["id"]) == []
    assert "momo_escrow_cancelled" not in await _log_actions(db_session, dispatch["id"])


@pytest.mark.asyncio
async def test_a_second_cancel_records_nothing_more(client, seeded_db, db_session):
    dispatch = await _dispatch(client)
    await _accept(db_session, dispatch["id"])
    await _cancel(client, dispatch["id"])
    await _cancel(client, dispatch["id"])

    [stipend] = await _stipends(db_session, dispatch["id"])
    assert stipend.status == "CANCELLED"
    actions = await _log_actions(db_session, dispatch["id"])
    assert actions.count("momo_escrow_cancelled") == 1
