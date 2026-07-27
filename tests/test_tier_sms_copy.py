"""Tier escalation SMS copy for Motor-King / personal vehicle / NAS."""
from __future__ import annotations

from src.services.dispatch_orchestrator import (
    build_cho_escalation_message,
    build_driver_offer_message,
)


def test_tier1_motor_king_offer_message():
    msg = build_driver_offer_message(
        tier=1,
        compound_id=1,
        referral_id=42,
        vehicle_label="Motor-King",
        ussd_code="*384*99193#",
    )
    assert "Motor-King" in msg
    assert "Ref #42" in msg
    assert "*384*99193#" in msg
    assert "CHPS #1" in msg


def test_tier2_personal_vehicle_offer_message():
    msg = build_driver_offer_message(
        tier=2,
        compound_id=1,
        referral_id=42,
        vehicle_label="Personal vehicle",
        ussd_code="*384*99193#",
    )
    assert "Personal vehicle" in msg or "backup" in msg.lower()
    assert "Ref #42" in msg
    assert "*384*99193#" in msg


def test_offer_message_without_configured_code_keeps_generic_ussd():
    msg = build_driver_offer_message(
        tier=1,
        compound_id=1,
        referral_id=7,
        vehicle_label="Motor-King",
        ussd_code="",
    )
    assert "Dial USSD to ACCEPT." in msg


def test_tier3_cho_nas_escalation_message():
    msg = build_cho_escalation_message(referral_id=42, compound_id=1)
    assert "Ref #42" in msg
    assert "NAS" in msg or "manual" in msg.lower() or "ambulance" in msg.lower()
    assert "coordinate" in msg.lower() or "Escalate" in msg
