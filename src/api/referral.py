"""Referral creation and read APIs."""

from __future__ import annotations

import logging
import re
import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src import parameters
from src.api import errors
from src.api.cho import NOT_ACTIVE, NOT_REGISTERED, find_cho
from src.api.deps import require_api_key
from src.api.errors import ApiError
from src.config import settings
from src.db.database import get_db
from src.db.models import (
    AuditLog,
    Cho,
    CHPSCompound,
    Dispatch,
    DispatchLog,
    Driver,
    Facility,
    Referral,
)
from src.services.dispatch_orchestrator import DispatchNotCancellableError, DispatchOrchestrator
from src.tools.clinical_summary import build_clinical_summary
from src.tools.moews_calculator import missing_vitals, score_vitals
from src.tools.sms_codec import encode_referral_payload_or_none

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1",
    tags=["Referrals"],
    dependencies=[Depends(require_api_key)],
)

PATIENT_HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")



def _vital_range(vital: str) -> Any:
    """The app enforces the same limits: a referral rejected here would otherwise sit in
    the outbox retrying forever. They catch typos; they are not clinical thresholds."""
    low, high = parameters.VITAL_RANGES[vital]
    return Field(ge=low, le=high)


SYSTOLIC_BP = _vital_range("systolic_bp")
DIASTOLIC_BP = _vital_range("diastolic_bp")
HEART_RATE = _vital_range("heart_rate")
RESPIRATORY_RATE = _vital_range("respiratory_rate")
TEMPERATURE = _vital_range("temperature")
SPO2 = _vital_range("spo2")

EmergencyType = Literal[
    # Offered by the CHO app today.
    "respiratory_distress",
    "pph",
    "neonatal_asphyxia",
    "eclampsia",
    # Listed in spec 7.1.2.
    "maternal_hemorrhage",
    "neonatal_sepsis",
    "severe_malaria",
    "other",
]
DbInt = Annotated[int, Field(ge=1, le=2_147_483_647)]
AVPU = {"A": "A", "ALERT": "A", "V": "V", "VOICE": "V", "P": "P", "PAIN": "P",
        "U": "U", "UNRESPONSIVE": "U"}


class VitalsInput(BaseModel):
    systolic_bp: Annotated[int, SYSTOLIC_BP] | None = None
    diastolic_bp: Annotated[int, DIASTOLIC_BP] | None = None
    heart_rate: Annotated[int, HEART_RATE] | None = None
    respiratory_rate: Annotated[int, RESPIRATORY_RATE] | None = None
    temperature: Annotated[float, TEMPERATURE] | None = None
    spo2: Annotated[int, SPO2] | None = None
    consciousness_level: str | None = None

    @field_validator("consciousness_level")
    @classmethod
    def validate_consciousness(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = AVPU.get(value.strip().upper())
        if normalized is None:
            raise ValueError("consciousness_level must be one of A, V, P, U")
        return normalized


class ReferralCreate(BaseModel):
    chps_compound_id: DbInt
    facility_id: DbInt
    # The registered CHO sending this. OTP will verify it later.
    cho_phone: str = Field(min_length=1, max_length=32)
    patient_hash: str = Field(min_length=64, max_length=64)
    emergency_type: EmergencyType
    vitals: VitalsInput = Field(default_factory=VitalsInput)
    # False for "Emergency: skip vitals": dispatch at once, no clinical assessment.
    vitals_taken: bool = True
    gestational_weeks: int = Field(default=0, ge=0, le=parameters.GESTATIONAL_WEEKS_MAX)
    client_request_id: str | None = Field(default=None, max_length=36)
    # How long this waited on the phone, by the phone's own clock. An elapsed time rather
    # than a timestamp, so a phone clock set to the wrong date can't skew it.
    queue_age_seconds: int = Field(default=0, ge=0, le=2_147_483_647)
    ai_screen_result: str | None = Field(default=None, max_length=32)
    ai_confidence: float | None = Field(default=None, ge=0, le=1)
    ai_model_version: str | None = Field(default=None, max_length=64)

    @field_validator("patient_hash")
    @classmethod
    def validate_patient_hash(cls, value: str) -> str:
        if not PATIENT_HASH_PATTERN.match(value):
            raise ValueError("patient_hash must be exactly 64 lowercase hex characters")
        return value

    @model_validator(mode="after")
    def validate_vitals_taken(self) -> ReferralCreate:
        if not self.vitals_taken and any(
            value is not None for value in self.vitals.model_dump().values()
        ):
            raise ValueError("vitals_taken=false cannot be sent with vitals")
        return self


AWAITING_CONFIRMATION = "AWAITING_CONFIRMATION"
CONFIRMED = "CONFIRMED"
MANUALLY_HANDLED = "MANUALLY_HANDLED"
CANCELLED = "CANCELLED"
RESOLUTIONS = {
    "send_now": CONFIRMED,
    "already_handled": MANUALLY_HANDLED,
    "cancel": CANCELLED,
}
WRONG_COMPOUND = "This CHO does not belong to this CHPS compound."


class ReferralResolve(BaseModel):
    action: Literal["send_now", "already_handled", "cancel"]
    cho_phone: str = Field(min_length=1, max_length=32)


class DispatchCancel(BaseModel):
    cho_phone: str = Field(min_length=1, max_length=32)


def _referral_response(referral: Referral) -> dict[str, Any]:
    return {
        "id": referral.id,
        "chps_compound_id": referral.chps_compound_id,
        "facility_id": referral.facility_id,
        "cho_id": referral.cho_id,
        "patient_hash": referral.patient_hash,
        "emergency_type": referral.emergency_type,
        "severity": referral.severity,
        "moews_score": referral.moews_score,
        "risk_level": referral.risk_level,
        "clinical_summary": referral.clinical_summary,
        "compressed_sms_payload": referral.compressed_sms_payload,
        "status": referral.status,
        "vitals": referral.vitals_json,
        "missing_vitals": missing_vitals(referral.vitals_json),
        "vitals_taken": (referral.vitals_json or {}).get("vitals_taken", True),
        "client_request_id": referral.client_request_id,
        "queue_age_seconds": referral.queue_age_seconds,
        "ai_screen_result": referral.ai_screen_result,
        "ai_confidence": referral.ai_confidence,
        "ai_model_version": referral.ai_model_version,
    }


async def _dispatch_response(session: AsyncSession, dispatch: Dispatch) -> dict[str, Any]:
    driver_name = None
    eta_minutes = None
    if dispatch.driver_id is not None:
        driver = await session.get(Driver, dispatch.driver_id)
        if driver:
            driver_name = driver.name
            # Demo ETA once a driver has claimed the trip.
            if dispatch.status in {
                "ACCEPTED",
                "HOSPITAL_NOTIFIED",
                "HOSPITAL_CONFIRMED",
            }:
                eta_minutes = parameters.PLACEHOLDER_ETA_MINUTES
    return {
        "id": dispatch.id,
        "referral_id": dispatch.referral_id,
        "facility_id": dispatch.facility_id,
        "driver_id": dispatch.driver_id,
        "driver_name": driver_name,
        "eta_minutes": eta_minutes,
        "status": dispatch.status,
        "current_tier": dispatch.current_tier,
    }


def _assess(payload: ReferralCreate) -> dict[str, Any]:
    """Score locally: no I/O, no LLM, and no failure here can stop dispatch."""
    vitals = payload.vitals
    risk_level, moews_score = "UNKNOWN", None
    if payload.vitals_taken:
        try:
            result = score_vitals(
                vitals.systolic_bp,
                vitals.diastolic_bp,
                vitals.heart_rate,
                vitals.respiratory_rate,
                vitals.temperature,
                vitals.spo2,
                vitals.consciousness_level,
            )
            risk_level, moews_score = result["risk_level"], result["moews_score"]
        except Exception:
            logger.exception("MOEWS scoring failed; dispatching with UNKNOWN risk")
    return {
        "risk_level": risk_level,
        "moews_score": moews_score,
        "clinical_summary": build_clinical_summary(
            emergency_type=payload.emergency_type,
            risk_level=risk_level,
            moews_score=moews_score,
            vitals=vitals.model_dump(),
            vitals_taken=payload.vitals_taken,
        ),
        "compressed_sms_payload": (
            encode_referral_payload_or_none(
                chps_id_int=payload.chps_compound_id,
                moews_score=moews_score,
                risk_level=risk_level,
                hr=vitals.heart_rate,
                sbp=vitals.systolic_bp,
            )
            if payload.vitals_taken
            else None
        ),
    }


async def _registered_cho(session: AsyncSession, phone: str) -> Cho:
    cho = await find_cho(session, phone)
    if cho is None:
        raise ApiError(status.HTTP_403_FORBIDDEN, errors.CHO_NOT_REGISTERED, NOT_REGISTERED)
    return cho


async def _active_cho_of(session: AsyncSession, phone: str, compound_id: int) -> Cho:
    """The check for anything that starts a dispatch."""
    cho = await _registered_cho(session, phone)
    if not cho.active:
        raise ApiError(status.HTTP_403_FORBIDDEN, errors.CHO_NOT_ACTIVE, NOT_ACTIVE)
    if cho.compound_id != compound_id:
        raise ApiError(status.HTTP_403_FORBIDDEN, errors.CHO_WRONG_COMPOUND, WRONG_COMPOUND)
    return cho


async def _cho_who_may_stop(session: AsyncSession, phone: str, referral: Referral) -> Cho:
    """The check for standing transport down.

    A CHO who has since been deactivated or moved may still do this for a referral they
    sent: stopping a trip that is no longer needed is always safe, and otherwise nobody
    may be left able to.
    """
    cho = await _registered_cho(session, phone)
    if cho.id != referral.cho_id and cho.compound_id != referral.chps_compound_id:
        raise ApiError(status.HTTP_403_FORBIDDEN, errors.CHO_WRONG_COMPOUND, WRONG_COMPOUND)
    return cho


@router.post("/referral", status_code=status.HTTP_201_CREATED)
async def create_referral(
    payload: ReferralCreate, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """Create the CHO-confirmed referral before initiating external dispatch."""
    if not await session.get(CHPSCompound, payload.chps_compound_id):
        raise ApiError(404, errors.COMPOUND_NOT_FOUND, "CHPS compound not found")
    if not await session.get(Facility, payload.facility_id):
        raise ApiError(404, errors.FACILITY_NOT_FOUND, "Facility not found")

    client_request_id = payload.client_request_id or str(uuid.uuid4())

    existing = await session.scalar(
        select(Referral).where(Referral.client_request_id == client_request_id)
    )
    if existing:
        dispatch = await session.scalar(select(Dispatch).where(Dispatch.referral_id == existing.id))
        return {
            "referral": _referral_response(existing),
            "dispatch": await _dispatch_response(session, dispatch) if dispatch else None,
            "idempotent": True,
        }

    vitals_json = payload.vitals.model_dump()
    if not payload.vitals_taken:
        vitals_json["vitals_taken"] = False
    # After the idempotency check, so a retry of a referral that was already accepted
    # still gets its dispatch back even if the CHO has since been deactivated.
    cho = await _active_cho_of(session, payload.cho_phone, payload.chps_compound_id)

    assessed = _assess(payload)
    stale = payload.queue_age_seconds > settings.STALE_AFTER_MINUTES * 60

    referral = Referral(
        chps_compound_id=payload.chps_compound_id,
        facility_id=payload.facility_id,
        cho_id=cho.id,
        patient_hash=payload.patient_hash,
        patient_name="Unknown",
        emergency_type=payload.emergency_type,
        severity=assessed["risk_level"],
        moews_score=assessed["moews_score"],
        risk_level=assessed["risk_level"],
        clinical_summary=assessed["clinical_summary"],
        compressed_sms_payload=assessed["compressed_sms_payload"],
        vitals_json=vitals_json,
        status=AWAITING_CONFIRMATION if stale else CONFIRMED,
        client_request_id=client_request_id,
        queue_age_seconds=payload.queue_age_seconds,
        ai_screen_result=payload.ai_screen_result,
        ai_confidence=payload.ai_confidence,
        ai_model_version=payload.ai_model_version,
    )
    session.add(referral)
    await session.flush()
    # A stale referral is stored, but drivers are told only if the CHO says it's still needed.
    dispatch = (
        None if stale else await DispatchOrchestrator().initiate_dispatch(session, referral.id)
    )
    await session.commit()
    return {
        "referral": _referral_response(referral),
        "dispatch": await _dispatch_response(session, dispatch) if dispatch else None,
    }


@router.post("/referral/{referral_id}/resolve")
async def resolve_referral(
    referral_id: int, payload: ReferralResolve, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """The CHO's answer to "Still needs transport?" for a stale referral."""
    # Locked so a double tap can't start two dispatches.
    referral = await session.scalar(
        select(Referral)
        .where(Referral.id == referral_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if referral is None:
        raise ApiError(404, errors.REFERRAL_NOT_FOUND, "Referral not found")
    outcome = RESOLUTIONS[payload.action]
    if payload.action == "send_now":
        cho = await _active_cho_of(session, payload.cho_phone, referral.chps_compound_id)
    else:
        cho = await _cho_who_may_stop(session, payload.cho_phone, referral)

    if referral.status == AWAITING_CONFIRMATION:
        referral.status = outcome
        session.add(
            AuditLog(
                entity_type="referral",
                entity_id=str(referral.id),
                action=f"referral_{payload.action}",
                actor_id=str(cho.id),
                metadata_json={"queue_age_seconds": referral.queue_age_seconds},
            )
        )
        await session.flush()
        if payload.action == "send_now":
            await DispatchOrchestrator().initiate_dispatch(session, referral.id)
        await session.commit()
    elif referral.status != outcome:
        raise ApiError(
            status.HTTP_409_CONFLICT,
            errors.REFERRAL_ALREADY_RESOLVED,
            f"This referral was already recorded as {referral.status}.",
        )
    dispatch = await session.scalar(select(Dispatch).where(Dispatch.referral_id == referral.id))
    return {
        "referral": _referral_response(referral),
        "dispatch": await _dispatch_response(session, dispatch) if dispatch else None,
    }


@router.post("/dispatch/{dispatch_id}/cancel")
async def cancel_dispatch(
    dispatch_id: int, payload: DispatchCancel, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """Stop the cascade and tell whoever was already told."""
    dispatch = await session.get(Dispatch, dispatch_id)
    if dispatch is None:
        raise ApiError(404, errors.DISPATCH_NOT_FOUND, "Dispatch not found")
    referral = await session.get_one(Referral, dispatch.referral_id)
    cho = await _cho_who_may_stop(session, payload.cho_phone, referral)
    try:
        dispatch = await DispatchOrchestrator().cancel_dispatch(session, dispatch_id, cho.id)
    except DispatchNotCancellableError as exc:
        raise ApiError(
            status.HTTP_409_CONFLICT,
            errors.DISPATCH_NOT_CANCELLABLE,
            f"This dispatch is already {exc.status}.",
        ) from exc
    await session.commit()
    return await _dispatch_response(session, dispatch)


@router.get("/referral/{referral_id}")
async def get_referral(referral_id: int, session: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    referral = await session.get(Referral, referral_id)
    if not referral:
        raise ApiError(404, errors.REFERRAL_NOT_FOUND, "Referral not found")
    return _referral_response(referral)


@router.get("/dispatch/{dispatch_id}")
async def get_dispatch(dispatch_id: int, session: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    dispatch = await session.get(Dispatch, dispatch_id)
    if not dispatch:
        raise ApiError(404, errors.DISPATCH_NOT_FOUND, "Dispatch not found")
    return await _dispatch_response(session, dispatch)


@router.get("/dispatch/{dispatch_id}/logs")
async def get_dispatch_logs(
    dispatch_id: int, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """Return the dispatch audit trail used by the local demo timeline."""
    logs = await session.scalars(
        select(DispatchLog).where(DispatchLog.dispatch_id == dispatch_id).order_by(DispatchLog.id)
    )
    return {
        "dispatch_id": dispatch_id,
        "logs": [
            {
                "id": log.id,
                "action": log.action,
                "target_phone": log.target_phone,
                "target_role": log.target_role,
                "response": log.response,
                "metadata": log.metadata_json,
                "created_at": log.created_at,
            }
            for log in logs
        ],
    }
