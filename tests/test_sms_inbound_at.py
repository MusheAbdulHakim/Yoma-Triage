"""Africa's Talking inbound SMS form webhook + bare CONFIRM replies."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Dispatch, Referral


@pytest.mark.asyncio
async def test_at_form_confirmed_resolves_open_dispatch_for_driver(
    client, seeded_db, db_session: AsyncSession
):
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="0123456789abcdef" * 4,
        emergency_type="Haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id,
        facility_id=1,
        driver_id=1,
        status="HOSPITAL_NOTIFIED",
        current_tier=1,
        declined_driver_ids=[],
    )
    db_session.add(dispatch)
    await db_session.commit()

    # Seeded driver 1 phone is +233240000001 in fixtures (may be remapped in live DB).
    from src.db.models import Driver

    driver = await db_session.get(Driver, 1)
    assert driver is not None

    res = await client.post(
        "/api/v1/sms/inbound",
        data={
            "linkId": "8d34f3d1-11ef-46a5-a018-22c818736d3e",
            "text": "confirmed",
            "to": "99193",
            "id": "b7ae3b48-b51f-4777-9912-8c5eeb452ba8",
            "date": "2026-07-27 17:41:41",
            "from": driver.phone,
        },
    )
    assert res.status_code == 200, res.text
    assert res.headers["content-type"].startswith("text/plain")
    assert res.text.startswith("GOOD")

    await db_session.refresh(dispatch)
    assert dispatch.status == "HOSPITAL_CONFIRMED"


@pytest.mark.asyncio
async def test_json_confirm_with_id_still_works(client, seeded_db, db_session: AsyncSession):
    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="0123456789abcdef" * 4,
        emergency_type="Haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id,
        facility_id=1,
        driver_id=1,
        status="HOSPITAL_NOTIFIED",
        current_tier=1,
        declined_driver_ids=[],
    )
    db_session.add(dispatch)
    await db_session.commit()

    res = await client.post(
        "/api/v1/sms/inbound",
        json={"from": "+233240000200", "text": f"CONFIRM {dispatch.id}"},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "CONFIRMED"
    assert body["dispatch_id"] == dispatch.id


@pytest.mark.asyncio
async def test_parse_confirmed_alias():
    from src.api.sms_webhook import _parse_command

    assert _parse_command("confirmed") == ("CONFIRM", None, None)
    assert _parse_command("CONFIRM 9") == ("CONFIRM", 9, None)
    assert _parse_command("DIVERT 9 2") == ("DIVERT", 9, 2)


@pytest.mark.asyncio
async def test_divert_updates_destination_and_notifies(monkeypatch):
    from src.api import sms_webhook

    dispatch = MagicMock(id=11, referral_id=21, facility_id=1, status="ACCEPTED", driver_id=3)
    referral = MagicMock(id=21, facility_id=1, patient_name="Ama", chps_compound_id=1)
    current_facility = MagicMock(id=1, phone="020 000 0001")
    destination = MagicMock(id=2, phone="+233200000002", name="Alt Hospital")
    compound = MagicMock(cho_phone="+233200000001")
    driver = MagicMock(phone="+233200000003")
    session = MagicMock()
    session.get = AsyncMock(
        side_effect=[
            dispatch,  # find by id
            referral,
            current_facility,  # auth facility
            destination,
            compound,
            driver,
        ]
    )
    session.add = MagicMock()
    session.commit = AsyncMock()
    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "MOCKED"})
    monkeypatch.setattr(sms_webhook, "MessagingGateway", lambda: gateway)

    result = await sms_webhook.process_inbound_sms(
        session, "+233 200 000 001", "DIVERT 11 2"
    )

    assert result["status"] == "DIVERTED"
    assert referral.facility_id == 2
    assert dispatch.status == "DIVERTED"
    assert gateway.send_sms.await_count == 2


@pytest.mark.asyncio
async def test_form_confirmed_with_no_open_dispatch_replies_and_returns_good(
    client, seeded_db, monkeypatch
):
    from src.api import sms_webhook

    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "MOCKED"})
    monkeypatch.setattr(sms_webhook, "MessagingGateway", lambda: gateway)

    res = await client.post(
        "/api/v1/sms/inbound",
        data={
            "text": "confirmed",
            "to": "99193",
            "from": "+233599999999",
        },
    )
    assert res.status_code == 200
    assert res.text.startswith("GOOD")
    gateway.send_sms.assert_awaited_once()
    assert "No open referral" in gateway.send_sms.await_args.args[1]


@pytest.mark.asyncio
async def test_confirmed_when_already_en_route_replies_status(
    client, seeded_db, db_session: AsyncSession, monkeypatch
):
    from src.api import sms_webhook
    from src.db.models import Driver

    referral = Referral(
        chps_compound_id=1,
        facility_id=1,
        patient_hash="0123456789abcdef" * 4,
        emergency_type="Haemorrhage",
        severity="RED",
        risk_level="RED",
        status="CONFIRMED",
    )
    db_session.add(referral)
    await db_session.flush()
    dispatch = Dispatch(
        referral_id=referral.id,
        facility_id=1,
        driver_id=1,
        status="HOSPITAL_CONFIRMED",
        current_tier=1,
        declined_driver_ids=[],
    )
    db_session.add(dispatch)
    await db_session.commit()

    driver = await db_session.get(Driver, 1)
    assert driver is not None

    gateway = MagicMock()
    gateway.send_sms = AsyncMock(return_value={"status": "MOCKED"})
    monkeypatch.setattr(sms_webhook, "MessagingGateway", lambda: gateway)

    res = await client.post(
        "/api/v1/sms/inbound",
        json={"from": driver.phone, "text": "confirmed"},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ALREADY_CONFIRMED"
    gateway.send_sms.assert_awaited_once()
    assert "already confirmed" in gateway.send_sms.await_args.args[1].lower()
    assert "on the way" in gateway.send_sms.await_args.args[1].lower()
