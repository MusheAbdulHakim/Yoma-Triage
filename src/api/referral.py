"""Referral creation and read APIs."""
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.agents.coordinator import relayai_graph
from src.db.database import get_db
from src.db.models import CHPSCompound, Dispatch, DispatchLog, Facility, Referral
from src.services.dispatch_orchestrator import DispatchOrchestrator

router = APIRouter(prefix="/api/v1", tags=["Referrals"])


class VitalsInput(BaseModel):
    systolic_bp: int | None = None
    diastolic_bp: int | None = None
    heart_rate: int | None = None
    respiratory_rate: int | None = None
    temperature: float | None = None
    spo2: int | None = None
    consciousness_level: str | None = None


class ReferralCreate(BaseModel):
    chps_compound_id: int
    facility_id: int
    patient_hash: str = Field(min_length=1, max_length=64)
    patient_name: str = "Unknown"
    emergency_type: str
    vitals: VitalsInput
    gestational_weeks: int = 0
    client_request_id: str | None = Field(default=None, max_length=36)
    ai_screen_result: str | None = None
    ai_confidence: float | None = None


def _referral_response(referral: Referral) -> dict[str, Any]:
    return {
        "id": referral.id,
        "chps_compound_id": referral.chps_compound_id,
        "facility_id": referral.facility_id,
        "patient_hash": referral.patient_hash,
        "patient_name": referral.patient_name,
        "emergency_type": referral.emergency_type,
        "severity": referral.severity,
        "moews_score": referral.moews_score,
        "risk_level": referral.risk_level,
        "clinical_summary": referral.clinical_summary,
        "compressed_sms_payload": referral.compressed_sms_payload,
        "status": referral.status,
        "vitals": referral.vitals_json,
        "client_request_id": referral.client_request_id,
        "ai_screen_result": referral.ai_screen_result,
        "ai_confidence": referral.ai_confidence,
    }


def _dispatch_response(dispatch: Dispatch) -> dict[str, Any]:
    return {
        "id": dispatch.id,
        "referral_id": dispatch.referral_id,
        "facility_id": dispatch.facility_id,
        "driver_id": dispatch.driver_id,
        "status": dispatch.status,
        "current_tier": dispatch.current_tier,
    }


@router.post("/referral", status_code=status.HTTP_201_CREATED)
async def create_referral(
    payload: ReferralCreate, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """Create the CHO-confirmed referral before initiating external dispatch."""
    if not await session.get(CHPSCompound, payload.chps_compound_id):
        raise HTTPException(status_code=404, detail="CHPS compound not found")
    if not await session.get(Facility, payload.facility_id):
        raise HTTPException(status_code=404, detail="Facility not found")

    if payload.client_request_id:
        existing = await session.scalar(
            select(Referral).where(Referral.client_request_id == payload.client_request_id)
        )
        if existing:
            dispatch = await session.scalar(
                select(Dispatch).where(Dispatch.referral_id == existing.id)
            )
            return {
                "referral": _referral_response(existing),
                "dispatch": _dispatch_response(dispatch) if dispatch else None,
                "idempotent": True,
            }

    state = {
        "chps_id": str(payload.chps_compound_id),
        "patient_hash": payload.patient_hash,
        "gestational_weeks": payload.gestational_weeks,
        "vitals": payload.vitals.model_dump(),
        "errors": [],
    }
    try:
        assessed = relayai_graph.invoke(state)
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Clinical assessment unavailable") from exc

    referral = Referral(
        chps_compound_id=payload.chps_compound_id,
        facility_id=payload.facility_id,
        patient_hash=payload.patient_hash,
        patient_name=payload.patient_name,
        emergency_type=payload.emergency_type,
        severity=assessed.get("risk_level") or "UNKNOWN",
        moews_score=assessed.get("moews_score"),
        risk_level=assessed.get("risk_level") or "UNKNOWN",
        clinical_summary=assessed.get("clinical_summary"),
        compressed_sms_payload=assessed.get("compressed_sms_payload"),
        vitals_json=payload.vitals.model_dump(),
        status="CONFIRMED",
        client_request_id=payload.client_request_id,
        ai_screen_result=payload.ai_screen_result,
        ai_confidence=payload.ai_confidence,
    )
    session.add(referral)
    await session.flush()
    dispatch = await DispatchOrchestrator().initiate_dispatch(session, referral.id)
    await session.commit()
    return {"referral": _referral_response(referral), "dispatch": _dispatch_response(dispatch)}


@router.get("/referral/{referral_id}")
async def get_referral(
    referral_id: int, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    referral = await session.get(Referral, referral_id)
    if not referral:
        raise HTTPException(status_code=404, detail="Referral not found")
    return _referral_response(referral)


@router.get("/dispatch/{dispatch_id}")
async def get_dispatch(
    dispatch_id: int, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    dispatch = await session.get(Dispatch, dispatch_id)
    if not dispatch:
        raise HTTPException(status_code=404, detail="Dispatch not found")
    return _dispatch_response(dispatch)


@router.get("/dispatch/{dispatch_id}/logs")
async def get_dispatch_logs(
    dispatch_id: int, session: AsyncSession = Depends(get_db)
) -> dict[str, Any]:
    """Return the dispatch audit trail used by the local demo timeline."""
    logs = await session.scalars(
        select(DispatchLog)
        .where(DispatchLog.dispatch_id == dispatch_id)
        .order_by(DispatchLog.id)
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
