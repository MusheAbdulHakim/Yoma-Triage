"""The USSD text a driver's key presses add up to (see the menu map in src/api/ussd.py)."""
from __future__ import annotations

from src.db.models import Dispatch

ROOT = ""
OFFERS = "1"
ARRIVAL = "2"
CONFIRM_ARRIVAL = "2*1"
AVAILABILITY = "3"
SET_AVAILABLE = "3*1"
SET_OFF_DUTY = "3*2"


def offer(ref: int) -> str:
    return f"1*{ref}"


def accept(ref: int) -> str:
    return f"1*{ref}*1"


def decline(ref: int) -> str:
    return f"1*{ref}*2"


async def ref_of(session, dispatch_id: int) -> int:
    """The Ref number a driver sees for a dispatch: its referral's id."""
    dispatch = await session.get(Dispatch, dispatch_id)
    return dispatch.referral_id
