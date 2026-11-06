"""Register a Community Health Officer. Works in every environment.

    python -m src.admin.add_cho --name "Abiba" --phone 0240000100 --compound-id 1

Needs only DATABASE_URL. Writes the CHO and an audit_log row in one transaction.
"""
from __future__ import annotations

import argparse
import asyncio
import getpass
import sys

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.config import settings
from src.db.database import async_session
from src.db.models import AuditLog, Cho, CHPSCompound
from src.utils.phones import is_valid_ghana_phone, normalize_ghana_phone


class AddChoError(Exception):
    """A problem the operator can fix, reported without a traceback."""


async def add_cho(
    session: AsyncSession, *, name: str, phone: str, compound_id: int, actor: str
) -> Cho:
    """Add the CHO and its audit row to the caller's transaction."""
    name = name.strip()
    if not name:
        raise AddChoError("Name must not be empty")
    normalized = normalize_ghana_phone(phone)
    if not is_valid_ghana_phone(normalized):
        raise AddChoError(f"Not a valid Ghana phone number: {phone}")
    if await session.get(CHPSCompound, compound_id) is None:
        raise AddChoError(f"No CHPS compound with id {compound_id}")
    if await session.scalar(select(Cho.id).where(Cho.phone == normalized)) is not None:
        raise AddChoError(f"A CHO with phone {normalized} is already registered")

    cho = Cho(name=name, phone=normalized, compound_id=compound_id, active=True)
    session.add(cho)
    await session.flush()
    # The phone number stays out of the audit trail; the id points back to the CHO.
    session.add(
        AuditLog(
            entity_type="cho",
            entity_id=str(cho.id),
            action="cho_added",
            actor_id=actor,
            metadata_json={"compound_id": compound_id, "source": "src.admin.add_cho"},
        )
    )
    return cho


async def _run(args: argparse.Namespace) -> int:
    async with async_session() as session:
        cho = await add_cho(
            session,
            name=args.name,
            phone=args.phone,
            compound_id=args.compound_id,
            actor=getpass.getuser(),
        )
        await session.commit()
        print(f"Added CHO #{cho.id} ({cho.name}) to compound {cho.compound_id}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Register a Community Health Officer.")
    parser.add_argument("--name", required=True)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--compound-id", type=int, required=True)
    args = parser.parse_args(argv)
    if not settings.DATABASE_URL.strip():
        print("DATABASE_URL must be set", file=sys.stderr)
        return 1
    try:
        return asyncio.run(_run(args))
    except AddChoError as exc:
        print(f"Could not add CHO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
