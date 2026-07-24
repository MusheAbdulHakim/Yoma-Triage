"""
Compatibility wrapper for the graph's pure dispatch-preparation node.
"""
from src.agents.state import ReferralState
from src.agents.coordinator import prepare_dispatch_node

def run_dispatch_coordination(state: ReferralState) -> ReferralState:
    """Prepare telemetry without initiating payment or external transport calls."""
    return prepare_dispatch_node(state)