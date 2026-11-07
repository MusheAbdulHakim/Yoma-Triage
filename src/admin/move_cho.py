"""Move a CHO to another compound. Works in every environment.

    python -m src.admin.move_cho --phone 0240000100 --compound-id 2

Needs only DATABASE_URL. Writes the change and an audit_log row in one transaction. The
CHO's app returns to setup the next time it syncs.
"""
from __future__ import annotations

import argparse
import asyncio
import getpass
import sys

from sqlalchemy.ext.asyncio import AsyncSession

from src.admin.add_cho import AddChoError, find_registered
from src.config import settings
from src.db.database import async_session
from src.db.models import AuditLog, Cho, CHPSCompound


async def move_cho(session: AsyncSession, *, phone: str, compound_id: int, actor: str) -> Cho:
    """Add the change and its audit row to the caller's transaction."""
    cho = await find_registered(session, phone)
    if not cho.active:
        raise AddChoError(f"CHO #{cho.id} is inactive, so can't be moved")
    if await session.get(CHPSCompound, compound_id) is None:
        raise AddChoError(f"No CHPS compound with id {compound_id}")
    if cho.compound_id == compound_id:
        raise AddChoError(f"CHO #{cho.id} is already at compound {compound_id}")
    previous = cho.compound_id
    cho.compound_id = compound_id
    session.add(
        AuditLog(
            entity_type="cho",
            entity_id=str(cho.id),
            action="cho_moved",
            actor_id=actor,
            metadata_json={
                "from_compound_id": previous,
                "to_compound_id": compound_id,
                "source": "src.admin.move_cho",
            },
        )
    )
    return cho


async def _run(args: argparse.Namespace) -> int:
    async with async_session() as session:
        cho = await move_cho(
            session, phone=args.phone, compound_id=args.compound_id, actor=getpass.getuser()
        )
        await session.commit()
        print(f"Moved CHO #{cho.id} ({cho.name}) to compound {cho.compound_id}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Move a Community Health Officer.")
    parser.add_argument("--phone", required=True)
    parser.add_argument("--compound-id", type=int, required=True)
    args = parser.parse_args(argv)
    if not settings.DATABASE_URL.strip():
        print("DATABASE_URL must be set", file=sys.stderr)
        return 1
    try:
        return asyncio.run(_run(args))
    except AddChoError as exc:
        print(f"Could not move CHO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
