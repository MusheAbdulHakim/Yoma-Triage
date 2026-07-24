"""
Clinical Reasoning Node: Validates patient vitals using MOEWS, pulls GHS guidance via RAG,
and synthesizes a triage summary using Google Gemini.
"""
from langchain_google_genai import ChatGoogleGenerativeAI
from src.config import settings
from src.agents.state import ReferralState
from src.tools.moews_calculator import calculate_moews
from src.rag.engine import ProtocolRAGEngine

# Initialize RAG Engine and Gemini LLM
rag_engine = ProtocolRAGEngine()

llm = ChatGoogleGenerativeAI(
    model=settings.DEFAULT_GEMINI_MODEL,
    google_api_key=settings.GEMINI_API_KEY,
    temperature=0.2
)

def run_clinical_assessment(state: ReferralState) -> ReferralState:
    """
    Evaluates maternal vitals, calculates deterministic MOEWS score,
    pulls relevant GHS clinical protocols, and uses Gemini for clinical summarization.
    """
    vitals = state["vitals"]
    
    # 1. Execute deterministic MOEWS scoring tool
    moews_result = calculate_moews.invoke({
        "sbp": vitals["systolic_bp"],
        "dbp": vitals["diastolic_bp"],
        "hr": vitals["heart_rate"],
        "rr": vitals["respiratory_rate"],
        "temp": vitals["temperature"]
    })
    
    # 2. Query vector DB for GHS referral guidelines
    query_str = f"MOEWS risk {moews_result['risk_level']} score {moews_result['moews_score']} pregnant referral protocol"
    retrieved_docs = rag_engine.query_protocols(query_str, k=2)
    
    # 3. Prompt Gemini for a clinical summary using the retrieved context
    prompt = f"""
    You are an emergency maternal care AI assistant for Ghana Health Service (GHS).
    Synthesize a 2-sentence concise clinical assessment for the receiving hospital.

    Patient Vitals: SBP {vitals['systolic_bp']} mmHg, DBP {vitals['diastolic_bp']} mmHg, HR {vitals['heart_rate']} bpm, Gestational Weeks {state['gestational_weeks']}.
    Calculated MOEWS Score: {moews_result['moews_score']} ({moews_result['risk_level']} Risk).
    GHS Guidelines Context: {retrieved_docs}

    Provide only a professional, structured clinical triage summary:
    """
    
    llm_response = llm.invoke(prompt)
    
    # 4. Update LangGraph state
    state["moews_score"] = moews_result["moews_score"]
    state["risk_level"] = moews_result["risk_level"]
    state["retrieved_protocol_citations"] = retrieved_docs
    state["clinical_summary"] = llm_response.content
    
    return state