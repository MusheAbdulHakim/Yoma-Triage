"""Deactivate a CHO. Works in every environment.

    python -m src.admin.deactivate_cho --phone 0240000100

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
from src.db.models import AuditLog, Cho


async def deactivate_cho(session: AsyncSession, *, phone: str, actor: str) -> Cho:
    """Add the change and its audit row to the caller's transaction."""
    cho = await find_registered(session, phone)
    if not cho.active:
        raise AddChoError(f"CHO #{cho.id} is already inactive")
    cho.active = False
    session.add(
        AuditLog(
            entity_type="cho",
            entity_id=str(cho.id),
            action="cho_deactivated",
            actor_id=actor,
            metadata_json={"compound_id": cho.compound_id, "source": "src.admin.deactivate_cho"},
        )
    )
    return cho


async def _run(args: argparse.Namespace) -> int:
    async with async_session() as session:
        cho = await deactivate_cho(session, phone=args.phone, actor=getpass.getuser())
        await session.commit()
        print(f"Deactivated CHO #{cho.id} ({cho.name})")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Deactivate a Community Health Officer.")
    parser.add_argument("--phone", required=True)
    args = parser.parse_args(argv)
    if not settings.DATABASE_URL.strip():
        print("DATABASE_URL must be set", file=sys.stderr)
        return 1
    try:
        return asyncio.run(_run(args))
    except AddChoError as exc:
        print(f"Could not deactivate CHO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
