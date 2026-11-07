"""What a hospital texts back, in the form its notice asks for."""
from __future__ import annotations


async def confirm_text(session, dispatch_id: int) -> str:
    return f"CONFIRM {dispatch_id}"


async def divert_text(session, dispatch_id: int, facility_id: int) -> str:
    return f"DIVERT {dispatch_id} {facility_id}"
