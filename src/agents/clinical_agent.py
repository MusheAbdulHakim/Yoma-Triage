"""
Clinical Reasoning Node: Validates patient vitals using MOEWS, pulls GHS guidance via RAG,
and synthesizes a triage summary using Google Gemini.
"""
from typing import Any

from src.config import settings
from src.agents.state import ReferralState
from src.tools.moews_calculator import calculate_moews
from src.rag.engine import ProtocolRAGEngine

rag_engine: ProtocolRAGEngine | None = None
llm: Any = None


def _get_rag_engine() -> ProtocolRAGEngine | None:
    """Initialize local RAG only when an assessment needs it."""
    global rag_engine
    if rag_engine is None:
        try:
            rag_engine = ProtocolRAGEngine()
            rag_engine.seed_initial_protocols()
        except Exception:
            return None
    return rag_engine


def _get_llm() -> Any:
    """Return Gemini only when it is configured and available."""
    global llm
    if llm is None and settings.GEMINI_API_KEY:
        try:
            from langchain_google_genai import ChatGoogleGenerativeAI

            llm = ChatGoogleGenerativeAI(
                model=settings.DEFAULT_GEMINI_MODEL,
                google_api_key=settings.GEMINI_API_KEY,
                temperature=0.2,
            )
        except Exception:
            return None
    return llm


def _consciousness_code(value: Any) -> str:
    return "A" if str(value or "A").strip().upper() in {"A", "ALERT"} else str(value)


def _template_summary(state: ReferralState, moews_result: dict) -> str:
    return (
        f"Maternal referral assessment: {moews_result['risk_level']} risk "
        f"(MOEWS {moews_result['moews_score']}). "
        f"Gestational age: {state.get('gestational_weeks', 'unknown')} weeks."
    )

def run_clinical_assessment(state: ReferralState) -> ReferralState:
    """
    Evaluates maternal vitals, calculates deterministic MOEWS score,
    pulls relevant GHS clinical protocols, and uses Gemini for clinical summarization.
    """
    vitals = state.get("vitals", {})
    
    # 1. Execute deterministic MOEWS scoring tool
    moews_result = calculate_moews.invoke({
        "sbp": vitals.get("systolic_bp"),
        "dbp": vitals.get("diastolic_bp"),
        "hr": vitals.get("heart_rate"),
        "rr": vitals.get("respiratory_rate"),
        "temp": vitals.get("temperature"),
        "spo2": vitals.get("spo2"),
        "consciousness": _consciousness_code(vitals.get("consciousness_level")),
    })
    
    # 2. Query vector DB for GHS referral guidelines
    query_str = f"MOEWS risk {moews_result['risk_level']} score {moews_result['moews_score']} pregnant referral protocol"
    retrieved_docs: list[str] = []
    engine = _get_rag_engine()
    if engine:
        try:
            retrieved_docs = engine.query_protocols(query_str, k=2)
        except Exception:
            retrieved_docs = []
    
    # 3. Prompt Gemini for a clinical summary using the retrieved context
    prompt = f"""
    You are an emergency maternal care AI assistant for Ghana Health Service (GHS).
    Synthesize a 2-sentence concise clinical assessment for the receiving hospital.

    Patient Vitals: SBP {vitals.get('systolic_bp')} mmHg, DBP {vitals.get('diastolic_bp')} mmHg, HR {vitals.get('heart_rate')} bpm, Gestational Weeks {state.get('gestational_weeks', 'unknown')}.
    Calculated MOEWS Score: {moews_result['moews_score']} ({moews_result['risk_level']} Risk).
    GHS Guidelines Context: {retrieved_docs}

    Provide only a professional, structured clinical triage summary:
    """
    
    summary = _template_summary(state, moews_result)
    model = _get_llm()
    if model:
        try:
            summary = model.invoke(prompt).content
        except Exception:
            pass
    
    # 4. Update LangGraph state
    state["moews_score"] = moews_result["moews_score"]
    state["risk_level"] = moews_result["risk_level"]
    state["retrieved_protocol_citations"] = retrieved_docs
    state["clinical_summary"] = summary
    
    return state