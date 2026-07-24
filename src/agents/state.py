"""
Defines the shared state for the LangGraph multi-agent workflow.
"""
from typing import TypedDict


class PatientVitals(TypedDict, total=False):
    systolic_bp: int
    diastolic_bp: int
    heart_rate: int
    respiratory_rate: int
    temperature: float
    spo2: int | None
    consciousness_level: str  # 'alert', 'voice', 'pain', 'unresponsive'

class ReferralState(TypedDict):
    # Context
    chps_id: str
    patient_hash: str
    gestational_weeks: int
    vitals: PatientVitals

    # Clinical Agent Outputs
    moews_score: int | None
    risk_level: str | None  # 'GREEN', 'YELLOW', 'RED', 'UNKNOWN'
    clinical_summary: str | None
    retrieved_protocol_citations: list[str] | None

    # Dispatch Agent Outputs
    assigned_driver_id: str | None
    escrow_status: str | None  # 'PENDING', 'INITIAL_DISBURSED', 'COMPLETED'
    compressed_sms_payload: str | None

    # Execution Tracking
    next_node: str | None
    errors: list[str]
