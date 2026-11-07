"""What a hospital texts back, in the form its notice asks for."""
from __future__ import annotations

from src.db.models import Dispatch


async def hospital_code(session, dispatch_id: int) -> str:
    dispatch = await session.get(Dispatch, dispatch_id)
    await session.refresh(dispatch)
    assert dispatch.hospital_code, "the hospital hasn't been told about this dispatch"
    return dispatch.hospital_code


async def confirm_text(session, dispatch_id: int) -> str:
    return f"CONFIRM {await hospital_code(session, dispatch_id)}"


async def divert_text(session, dispatch_id: int, facility_id: int) -> str:
    return f"DIVERT {await hospital_code(session, dispatch_id)} {facility_id}"
