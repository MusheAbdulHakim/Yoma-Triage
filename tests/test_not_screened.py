"""A referral made without a breathing check (acoustic builds) says so to the hospital."""

from unittest.mock import MagicMock

import pytest


async def _notice(db_session, ai_screen_result):
    from src.db.models import Referral
    from src.services.hospital_notifier import HospitalNotifier
    from tests.conftest import queued_sms

    referral = Referral(
        patient_hash="b" * 64,
        chps_compound_id=1,
        emergency_type="pph",
        risk_level="GREEN",
        vitals_json={"systolic_bp": 120},
        ai_screen_result=ai_screen_result,
    )
    await HospitalNotifier().notify_pre_arrival(
        db_session,
        referral,
        MagicMock(),
        MagicMock(id=1, phone="+233240000200", latitude=None, longitude=None),
        7,
        code="4821",
    )
    await db_session.flush()
    return (await queued_sms(db_session))[0].body


@pytest.mark.asyncio
async def test_not_screened_is_in_the_hospital_notice(db_session):
    body = await _notice(db_session, "NOT_SCREENED")
    assert "Breathing check: not screened" in body
    assert "NOT_SCREENED" not in body, "never the raw code"


@pytest.mark.asyncio
@pytest.mark.parametrize("label", [None, "RED", "INCONCLUSIVE"])
async def test_other_results_do_not_add_the_line(db_session, label):
    body = await _notice(db_session, label)
    assert "not screened" not in body
