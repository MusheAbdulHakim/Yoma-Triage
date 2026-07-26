"""Hospital SMS must never include raw patient names."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio

from src.db.models import Referral
from src.services.hospital_notifier import HospitalNotifier

VALID_PATIENT_HASH = "a1b2c3d4" * 8


@pytest_asyncio.fixture
async def seeded_referral_with_name(db_session, seeded_db):
    """Referral with a real-looking name that must never appear in SMS."""
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash=VALID_PATIENT_HASH,
        patient_name="Ama Mensah",
        emergency_type="Obstetric haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
    )
    db_session.add(referral)
    await db_session.flush()
    return referral


@pytest.fixture
def driver():
    return SimpleNamespace(id=1, name="Ibrahim", phone="+233240000001")


@pytest.fixture
def facility():
    return SimpleNamespace(id=1, name="Tamale Teaching Hospital", phone="+233240000200")


@pytest.mark.asyncio
async def test_hospital_sms_omits_patient_name(
    db_session, seeded_referral_with_name, driver, facility
):
    class SpyGateway:
        def __init__(self) -> None:
            self.messages: list[str] = []

        async def send_sms(self, to, message, dispatch_id, role):
            self.messages.append(message)
            return {"status": "MOCKED"}

    spy = SpyGateway()
    notifier = HospitalNotifier(spy)
    await notifier.notify_pre_arrival(
        db_session, seeded_referral_with_name, driver, facility, dispatch_id=1
    )

    assert spy.messages
    body = spy.messages[0]
    assert seeded_referral_with_name.patient_name not in body
    assert f"Patient token: {VALID_PATIENT_HASH[:12]}" in body


@pytest.mark.asyncio
async def test_driver_dispatch_sms_omits_patient_name(
    db_session, seeded_db, monkeypatch
):
    from src.services.dispatch_orchestrator import DispatchOrchestrator

    monkeypatch.setattr(
        DispatchOrchestrator, "schedule_tier_timeouts", lambda self, *a, **k: None
    )

    captured: list[str] = []

    class SpyGateway:
        async def send_sms(self, to, message, dispatch_id, role):
            captured.append(message)
            return {"status": "MOCKED"}

    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash=VALID_PATIENT_HASH,
        patient_name="Ama Mensah",
        emergency_type="Obstetric haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
        client_request_id="ffffffff-ffff-ffff-ffff-ffffffffffff",
    )
    db_session.add(referral)
    await db_session.flush()

    orch = DispatchOrchestrator(gateway=SpyGateway())
    await orch.initiate_dispatch(db_session, referral.id)

    assert captured
    assert "Ama Mensah" not in captured[0]
    assert "Patient token" not in captured[0]
