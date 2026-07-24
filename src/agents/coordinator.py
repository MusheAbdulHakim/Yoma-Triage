"""
LangGraph DAG assembling the Care Coordinator, Clinical Validator, and Dispatcher.
"""
from langgraph.graph import StateGraph, END
from src.agents.state import ReferralState
from src.tools.moews_calculator import calculate_moews
from src.tools.sms_codec import compress_referral_payload
from src.rag.engine import ProtocolRAGEngine

# Initialize RAG Engine
rag_engine = ProtocolRAGEngine()
rag_engine.seed_initial_protocols()

def clinical_node(state: ReferralState) -> ReferralState:
    """Node responsible for MOEWS calculation and RAG protocol grounding."""
    vitals = state["vitals"]
    
    # 1. Deterministic Calculation
    moews_res = calculate_moews.invoke({
        "sbp": vitals["systolic_bp"],
        "dbp": vitals["diastolic_bp"],
        "hr": vitals["heart_rate"],
        "rr": vitals["respiratory_rate"],
        "temp": vitals["temperature"]
    })
    
    # 2. Retrieve GHS Guidelines
    citations = rag_engine.query_protocols(f"MOEWS score {moews_res['moews_score']} pregnant triage")
    
    state["moews_score"] = moews_res["moews_score"]
    state["risk_level"] = moews_res["risk_level"]
    state["retrieved_protocol_citations"] = citations
    state["clinical_summary"] = f"Patient classified as {moews_res['risk_level']} (MOEWS: {moews_res['moews_score']}). Protocols retrieved."
    return state

def dispatch_node(state: ReferralState) -> ReferralState:
    """Node responsible for compression and dispatch initialization."""
    # Compress telemetry for 2G SMS dispatch
    risk_code_map = {"NORMAL": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
    compressed = compress_referral_payload.invoke({
        "chps_id_int": int(state["chps_id"].replace("CHPS-", "")),
        "moews_score": state["moews_score"],
        "risk_code": risk_code_map.get(state["risk_level"], 1),
        "hr": state["vitals"]["heart_rate"],
        "sbp": state["vitals"]["systolic_bp"]
    })
    
    state["compressed_sms_payload"] = compressed
    state["assigned_driver_id"] = "DRIVER-MK-88"
    state["escrow_status"] = "INITIAL_DISBURSED"
    return state

# Construct the Workflow Graph
workflow = StateGraph(ReferralState)
workflow.add_node("clinical_assessment", clinical_node)
workflow.add_node("emergency_dispatch", dispatch_node)

# Set Graph Edges
workflow.set_entry_point("clinical_assessment")
workflow.add_edge("clinical_assessment", "emergency_dispatch")
workflow.add_edge("emergency_dispatch", END)

# Compile Executable Graph
relayai_graph = workflow.compile()