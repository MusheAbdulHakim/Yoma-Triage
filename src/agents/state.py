"""
Defines the shared state for the LangGraph multi-agent workflow.
"""
from typing import TypedDict, List, Dict, Any, Optional

class PatientVitals(TypedDict):
    systolic_bp: int
    diastolic_bp: int
    heart_rate: int
    respiratory_rate: int
    temperature: float
    consciousness_level: str  # 'alert', 'voice', 'pain', 'unresponsive'

class ReferralState(TypedDict):
    # Context
    chps_id: str
    patient_hash: str
    gestational_weeks: int
    vitals: PatientVitals
    
    # Clinical Agent Outputs
    moews_score: Optional[int]
    risk_level: Optional[str]  # 'NORMAL', 'MEDIUM', 'HIGH', 'CRITICAL'
    clinical_summary: Optional[str]
    retrieved_protocol_citations: Optional[List[str]]
    
    # Dispatch Agent Outputs
    assigned_driver_id: Optional[str]
    escrow_status: Optional[str]  # 'PENDING', 'INITIAL_DISBURSED', 'COMPLETED'
    compressed_sms_payload: Optional[str]
    
    # Execution Tracking
    next_node: Optional[str]
    errors: List[str]