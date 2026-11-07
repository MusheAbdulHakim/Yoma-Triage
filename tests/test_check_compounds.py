"""B1: the pre-deploy check for compounds with no active CHO or no active driver."""
from __future__ import annotations

import asyncio

import pytest
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.admin.check_compounds import NO_CHO, NO_DRIVER, CompoundGap, find_gaps, report
from src.db.database import Base
from src.db.models import Cho, CHPSCompound, Driver
from tests.conftest import SEEDED_CHO_PHONE
from tests.test_cho_admin import _run


@pytest.mark.asyncio
async def test_a_ready_compound_passes(db_session, seeded_db):
    total, gaps = await find_gaps(db_session)
    assert (total, gaps) == (1, [])
    assert report(total, gaps) == (0, "All 1 compounds have an active CHO and an active driver.")


@pytest.mark.asyncio
async def test_a_compound_with_neither_is_listed_with_both(db_session, seed_second_compound):
    total, gaps = await find_gaps(db_session)
    assert total == 2
    assert gaps == [CompoundGap(2, "Other CHPS", (NO_CHO, NO_DRIVER))]


@pytest.mark.asyncio
async def test_an_inactive_cho_does_not_count(db_session, seeded_db):
    await db_session.execute(update(Cho).values(active=False))
    _, gaps = await find_gaps(db_session)
    assert gaps == [CompoundGap(1, "Tamale South CHPS", (NO_CHO,))]


@pytest.mark.asyncio
async def test_inactive_drivers_do_not_count(db_session, seeded_db):
    await db_session.execute(update(Driver).values(is_active=False))
    _, gaps = await find_gaps(db_session)
    assert gaps == [CompoundGap(1, "Tamale South CHPS", (NO_DRIVER,))]


@pytest.mark.asyncio
async def test_a_cho_at_another_compound_does_not_count(db_session, seed_second_compound):
    await db_session.execute(update(Cho).values(compound_id=2))
    _, gaps = await find_gaps(db_session)
    assert [(gap.compound_id, gap.missing) for gap in gaps] == [(1, (NO_CHO,)), (2, (NO_DRIVER,))]


def test_no_compounds_at_all_fails():
    code, text = report(0, [])
    assert code == 1
    assert "No CHPS compounds" in text


def test_the_report_names_each_gap_and_what_to_do():
    code, text = report(3, [CompoundGap(2, "Other CHPS", (NO_CHO, NO_DRIVER))])
    assert code == 1
    assert "1 of 3 compounds are not ready" in text
    assert "Compound #2 Other CHPS: no active CHO, no active driver" in text
    assert "src.admin.add_cho" in text


def _database(tmp_path, *, cho: bool, driver: bool) -> str:
    url = f"sqlite+aiosqlite:///{tmp_path}/check.db"

    async def prepare():
        engine = create_async_engine(url)
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        async with async_sessionmaker(engine, class_=AsyncSession)() as session:
            session.add(CHPSCompound(id=1, name="A CHPS", zone="Z", cho_phone="+233240000010"))
            await session.flush()
            if cho:
                session.add(Cho(name="Abiba", phone=SEEDED_CHO_PHONE, compound_id=1))
            if driver:
                session.add(
                    Driver(
                        name="Ibrahim",
                        phone="+233240000001",
                        vehicle_type="motor_king",
                        chps_compound_id=1,
                    )
                )
            await session.commit()
        await engine.dispose()

    asyncio.run(prepare())
    return url


@pytest.mark.parametrize("environment", ["production", "staging", "development"])
def test_the_command_passes_when_ready_in_every_environment(tmp_path, environment):
    result = _run(
        "src.admin.check_compounds",
        _database(tmp_path, cho=True, driver=True),
        environment=environment,
    )
    assert result.returncode == 0, result.stderr
    assert "All 1 compounds" in result.stdout


@pytest.mark.parametrize(("cho", "driver"), [(False, True), (True, False), (False, False)])
def test_the_command_exits_non_zero_on_any_gap(tmp_path, cho, driver):
    result = _run("src.admin.check_compounds", _database(tmp_path, cho=cho, driver=driver))
    assert result.returncode == 1
    assert "Compound #1 A CHPS" in result.stderr
    assert (NO_CHO in result.stderr) is not cho
    assert (NO_DRIVER in result.stderr) is not driver
    # Read-only and private: no phone numbers in what it prints.
    assert "+2332" not in result.stdout + result.stderr
