"""Shared test fixtures for RelayAI backend tests."""
from __future__ import annotations

import asyncio
from typing import AsyncGenerator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import create_engine, event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from src.db.database import Base, get_db
from src.db.models import CHPSCompound, Driver, Facility


# ---------------------------------------------------------------------------
# Event loop fixture (session-scoped for speed)
# ---------------------------------------------------------------------------
@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


# ---------------------------------------------------------------------------
# Database fixtures (in-memory SQLite for tests)
# ---------------------------------------------------------------------------
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture(scope="function")
async def db_engine():
    """Create an async engine with in-memory SQLite."""
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture(scope="function")
async def db_session(db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Provide a transactional database session for tests."""
    session_factory = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        yield session
        await session.rollback()


# ---------------------------------------------------------------------------
# Seed data fixtures
# ---------------------------------------------------------------------------
@pytest_asyncio.fixture
async def seed_compounds(db_session: AsyncSession):
    """Seed CHPS compounds for testing."""
    compounds = [
        CHPSCompound(
            id=1,
            name="Tamale South CHPS",
            zone="Tamale South",
            latitude=9.4034,
            longitude=-0.8393,
            cho_phone="+233240000010",
        ),
        CHPSCompound(
            id=2,
            name="Navrongo CHPS",
            zone="Kassena-Nankana East",
            latitude=10.8833,
            longitude=-0.8500,
            cho_phone="+233240000011",
        ),
    ]
    db_session.add_all(compounds)
    await db_session.flush()
    return compounds


@pytest_asyncio.fixture
async def seed_drivers(db_session: AsyncSession, seed_compounds):
    """Seed drivers for testing."""
    drivers = [
        Driver(
            id=1,
            name="Ibrahim",
            phone="+233240000001",
            vehicle_type="Motor-King",
            vehicle_desc="Red tricycle",
            chps_compound_id=1,
            is_motor_king=True,
            is_active=True,
            availability="available",
        ),
        Driver(
            id=2,
            name="Musah",
            phone="+233240000002",
            vehicle_type="Motor-King",
            vehicle_desc="Blue tricycle",
            chps_compound_id=1,
            is_motor_king=True,
            is_active=True,
            availability="available",
        ),
        Driver(
            id=3,
            name="Abdul",
            phone="+233240000003",
            vehicle_type="Personal vehicle",
            vehicle_desc="White sedan",
            chps_compound_id=1,
            is_motor_king=False,
            is_active=True,
            availability="available",
        ),
    ]
    db_session.add_all(drivers)
    await db_session.flush()
    return drivers


@pytest_asyncio.fixture
async def seed_facilities(db_session: AsyncSession):
    """Seed receiving facilities for testing."""
    facilities = [
        Facility(
            id=1,
            name="Tamale Teaching Hospital",
            type="Regional Hospital",
            phone="+233240000200",
            district="Tamale Metro",
            has_maternity=True,
            has_icu=True,
            ),
        Facility(
            id=2,
            name="Navrongo War Memorial Hospital",
            type="District Hospital",
            phone="+233240000201",
            district="Kassena-Nankana East",
            has_maternity=True,
            has_icu=False,
        ),
    ]
    db_session.add_all(facilities)
    await db_session.flush()
    return facilities


@pytest_asyncio.fixture
async def seeded_db(db_session: AsyncSession):
    """Fully seeded database with compounds, drivers, and facilities."""
    compounds = [
        CHPSCompound(
            id=1,
            name="Tamale South CHPS",
            zone="Tamale South",
            latitude=9.4034,
            longitude=-0.8393,
            cho_phone="+233240000010",
        ),
    ]
    drivers = [
        Driver(
            id=1,
            name="Ibrahim",
            phone="+233240000001",
            vehicle_type="Motor-King",
            vehicle_desc="Red tricycle",
            chps_compound_id=1,
            is_motor_king=True,
            is_active=True,
            availability="available",
        ),
        Driver(
            id=2,
            name="Musah",
            phone="+233240000002",
            vehicle_type="Motor-King",
            vehicle_desc="Blue tricycle",
            chps_compound_id=1,
            is_motor_king=True,
            is_active=True,
            availability="available",
        ),
        Driver(
            id=3,
            name="Abdul",
            phone="+233240000003",
            vehicle_type="Personal vehicle",
            vehicle_desc="White sedan",
            chps_compound_id=1,
            is_motor_king=False,
            is_active=True,
            availability="available",
        ),
    ]
    facilities = [
        Facility(
            id=1,
            name="Tamale Teaching Hospital",
            type="Regional Hospital",
            phone="+233240000200",
            district="Tamale Metro",
            has_maternity=True,
            has_icu=True,
        ),
        Facility(
            id=2,
            name="Navrongo War Memorial Hospital",
            type="District Hospital",
            phone="+233240000201",
            district="Kassena-Nankana East",
            has_maternity=True,
            has_icu=False,
        ),
    ]
    db_session.add_all(compounds + drivers + facilities)
    await db_session.flush()
    return {"compounds": compounds, "drivers": drivers, "facilities": facilities}


# ---------------------------------------------------------------------------
# HTTP client fixture
# ---------------------------------------------------------------------------
@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Provide an async HTTP client for testing FastAPI endpoints."""
    from main import app

    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Sample data fixtures
# ---------------------------------------------------------------------------
@pytest.fixture
def sample_vitals():
    """Sample vitals for a critical patient."""
    return {
        "systolic_bp": 70,
        "diastolic_bp": 50,
        "heart_rate": 140,
        "respiratory_rate": 35,
        "temperature": 37.0,
        "spo2": 92,
        "consciousness_level": "V",
    }


@pytest.fixture
def sample_normal_vitals():
    """Sample vitals for a normal patient."""
    return {
        "systolic_bp": 120,
        "diastolic_bp": 80,
        "heart_rate": 80,
        "respiratory_rate": 18,
        "temperature": 37.0,
        "spo2": 98,
        "consciousness_level": "A",
    }


@pytest.fixture
def sample_referral_payload():
    """Sample referral creation payload."""
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": "demo-test-hash",
        "patient_name": "Test Patient",
        "emergency_type": "Obstetric haemorrhage",
        "gestational_weeks": 38,
        "client_request_id": "11111111-1111-1111-1111-111111111111",
        "vitals": {
            "systolic_bp": 70,
            "diastolic_bp": 50,
            "heart_rate": 140,
            "respiratory_rate": 35,
            "temperature": 37.0,
            "spo2": 92,
            "consciousness_level": "V",
        },
    }
