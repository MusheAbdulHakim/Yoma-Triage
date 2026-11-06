"""
Disabled and outside the request path; needs requirements-rag.txt.

LangGraph DAG assembling the Care Coordinator, Clinical Validator, and Dispatcher.
"""
from langgraph.graph import END, StateGraph

from src.agents.clinical_agent import run_clinical_assessment
from src.agents.state import ReferralState
from src.tools.sms_codec import encode_referral_payload_or_none


def prepare_dispatch_node(state: ReferralState) -> ReferralState:
    """Encode dispatch telemetry; external dispatch happens after persistence."""
    # Compress telemetry for 2G SMS dispatch
    vitals = state.get("vitals", {})
    chps_id = str(state.get("chps_id", "0"))
    chps_numeric_id = int("".join(filter(str.isdigit, chps_id)) or "0")
    compressed = encode_referral_payload_or_none(
        chps_id_int=chps_numeric_id,
        moews_score=state.get("moews_score") or 0,
        risk_level=state.get("risk_level") or "UNKNOWN",
        hr=vitals.get("heart_rate"),
        sbp=vitals.get("systolic_bp"),
    )
    if compressed is None:
        state["errors"] = [*(state.get("errors") or []), "sms_payload_encode_failed"]
    state["compressed_sms_payload"] = compressed
    return state

# Construct the Workflow Graph
workflow = StateGraph(ReferralState)
workflow.add_node("clinical_assessment", run_clinical_assessment)
workflow.add_node("prepare_dispatch", prepare_dispatch_node)

# Set Graph Edges
workflow.set_entry_point("clinical_assessment")
workflow.add_edge("clinical_assessment", "prepare_dispatch")
workflow.add_edge("prepare_dispatch", END)

# Compile Executable Graph
yoma_graph = workflow.compile()
