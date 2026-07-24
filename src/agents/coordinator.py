"""
LangGraph DAG assembling the Care Coordinator, Clinical Validator, and Dispatcher.
"""
from langgraph.graph import END, StateGraph

from src.agents.clinical_agent import run_clinical_assessment
from src.agents.state import ReferralState
from src.tools.sms_codec import compress_referral_payload

RISK_CODE_MAP = {"GREEN": 0, "YELLOW": 1, "RED": 2, "UNKNOWN": 3}


def prepare_dispatch_node(state: ReferralState) -> ReferralState:
    """Encode dispatch telemetry; external dispatch happens after persistence."""
    # Compress telemetry for 2G SMS dispatch
    vitals = state.get("vitals", {})
    chps_id = str(state.get("chps_id", "0"))
    chps_numeric_id = int("".join(filter(str.isdigit, chps_id)) or "0")
    compressed = compress_referral_payload.invoke({
        "chps_id_int": chps_numeric_id,
        "moews_score": state.get("moews_score") or 0,
        "risk_code": RISK_CODE_MAP.get(state.get("risk_level"), 3),
        "hr": vitals.get("heart_rate") or 0,
        "sbp": vitals.get("systolic_bp") or 0,
    })

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
relayai_graph = workflow.compile()
