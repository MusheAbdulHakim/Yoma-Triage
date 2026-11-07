"""Pre-deploy check: every CHPS compound needs an active CHO and an active driver.

    python -m src.admin.check_compounds

Lists each compound with no active registered CHO, or with no active driver, and exits 1
if there are any, so a deploy can stop on it. A compound with no active CHO gets no CHO
alerts at all (alerts go only to the chos table), and one with no active driver can't
dispatch. Read-only, works in every environment, needs only DATABASE_URL, and prints no
phone numbers.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.config import settings
from src.db.database import async_session
from src.db.models import Cho, CHPSCompound, Driver

NO_CHO = "no active CHO"
NO_DRIVER = "no active driver"


@dataclass(frozen=True)
class CompoundGap:
    compound_id: int
    name: str
    missing: tuple[str, ...]


async def find_gaps(session: AsyncSession) -> tuple[int, list[CompoundGap]]:
    """How many compounds there are, and each one missing an active CHO or driver."""
    compounds = list(await session.scalars(select(CHPSCompound).order_by(CHPSCompound.id)))
    with_cho = set(await session.scalars(select(Cho.compound_id).where(Cho.active.is_(True))))
    with_driver = set(
        await session.scalars(select(Driver.chps_compound_id).where(Driver.is_active.is_(True)))
    )
    gaps = []
    for compound in compounds:
        missing = tuple(
            label
            for label, present in (
                (NO_CHO, compound.id in with_cho),
                (NO_DRIVER, compound.id in with_driver),
            )
            if not present
        )
        if missing:
            gaps.append(CompoundGap(compound.id, compound.name, missing))
    return len(compounds), gaps


def report(total: int, gaps: list[CompoundGap]) -> tuple[int, str]:
    """The exit code and what to print."""
    if total == 0:
        return 1, "No CHPS compounds found. Nothing can be referred until they are loaded."
    if not gaps:
        return 0, f"All {total} compounds have an active CHO and an active driver."
    lines = [f"{len(gaps)} of {total} compounds are not ready:"]
    lines += [f"  Compound #{gap.compound_id} {gap.name}: {', '.join(gap.missing)}" for gap in gaps]
    lines.append(
        "Register CHOs with src.admin.add_cho, and add or reactivate drivers, before deploying."
    )
    return 1, "\n".join(lines)


async def _run() -> int:
    async with async_session() as session:
        total, gaps = await find_gaps(session)
    code, text = report(total, gaps)
    print(text, file=sys.stdout if code == 0 else sys.stderr)
    return code


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(
        description="List CHPS compounds with no active CHO or no active driver."
    ).parse_args(argv)
    if not settings.DATABASE_URL.strip():
        print("DATABASE_URL must be set", file=sys.stderr)
        return 1
    return asyncio.run(_run())


if __name__ == "__main__":
    sys.exit(main())
