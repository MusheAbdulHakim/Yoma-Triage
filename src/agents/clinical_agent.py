"""
Clinical reasoning node (MOEWS-first). Disabled and outside the request path.

POST /api/v1/referral doesn't use this. It stays in the repo behind RAG_ENABLED, and
needs requirements-rag.txt.

Risk level is ALWAYS from deterministic MOEWS. RAG cites GHS-aligned demo
protocols; Gemini (if GEMINI_API_KEY set) may only add an advisory
`protocol_assist` string — never override risk. Without Gemini/RAG the
referral path still completes with a structured template summary.
"""
from __future__ import annotations

import logging
from typing import Any

from src.agents.state import ReferralState
from src.config import settings
from src.tools.moews_calculator import score_vitals

logger = logging.getLogger(__name__)

rag_engine: Any = None
llm: Any = None

_UNKNOWN_RESULT = {
    "moews_score": None,
    "risk_level": "UNKNOWN",
    "triggered_flags": ["assessment_error"],
}


def _get_rag_engine() -> Any:
    """Initialize local RAG only when an assessment needs it and RAG_ENABLED is set."""
    global rag_engine
    if not settings.RAG_ENABLED:
        return None
    if rag_engine is None:
        try:
            from src.rag.engine import ProtocolRAGEngine

            rag_engine = ProtocolRAGEngine(persist_directory=settings.VECTOR_STORE_DIR)
            rag_engine.seed_initial_protocols()
        except (OSError, ImportError, RuntimeError, ValueError) as exc:
            logger.warning("RAG engine unavailable: %s", exc)
            return None
    return rag_engine


def _get_llm() -> Any:
    """Return Gemini only when RAG_ENABLED is set, configured and importable."""
    global llm
    if not settings.RAG_ENABLED:
        return None
    if llm is None and settings.GEMINI_API_KEY:
        try:
            from langchain_google_genai import ChatGoogleGenerativeAI

            llm = ChatGoogleGenerativeAI(
                model=settings.DEFAULT_GEMINI_MODEL,
                google_api_key=settings.GEMINI_API_KEY,
                temperature=0.2,
                max_retries=1,
                timeout=10,
            )
        except (ImportError, OSError, RuntimeError, ValueError) as exc:
            logger.warning("Gemini LLM unavailable: %s", exc)
            return None
    return llm


def _consciousness_code(value: Any) -> str | None:
    """Normalize AVPU. None means not measured and must stay None, never Alert."""
    if value is None or not str(value).strip():
        return None
    return "A" if str(value).strip().upper() in {"A", "ALERT"} else str(value)


def _structured_summary(
    state: ReferralState,
    moews_result: dict[str, Any],
    citations: list[str],
) -> str:
    """Deterministic hospital-facing summary; MOEWS is authoritative."""
    ga = state.get("gestational_weeks", "unknown")
    flags = moews_result.get("triggered_flags") or []
    flag_bit = f" Flags: {', '.join(flags)}." if flags else ""
    cite_bit = ""
    if citations:
        snippet = citations[0][:180].rstrip()
        cite_bit = f" Protocol: {snippet}"
        if len(citations[0]) > 180:
            cite_bit += "…"
    score = moews_result.get("moews_score")
    score_txt = "n/a" if score is None else str(score)
    missing = moews_result.get("missing_vitals") or []
    missing_bit = f" Not measured: {', '.join(missing)}." if missing else ""
    return (
        f"Maternal referral assessment: {moews_result['risk_level']} risk "
        f"(MOEWS {score_txt}).{missing_bit} "
        f"Gestational age: {ga} weeks.{flag_bit}{cite_bit}"
    )


def _optional_protocol_assist(
    vitals: dict[str, Any],
    state: ReferralState,
    moews_result: dict[str, Any],
    citations: list[str],
) -> str | None:
    """
    Non-authoritative Gemini assist. Prefixed so callers never treat it as risk.
    """
    model = _get_llm()
    if not model:
        return None
    prompt = (
        "You assist Ghana Health Service emergency referral. "
        "MOEWS risk is already fixed and MUST NOT be contradicted. "
        "In at most 2 short sentences, restate relevant protocol actions from the "
        "GHS context for the receiving hospital. Do not invent diagnoses. "
        "Do not change or restate a different risk colour.\n\n"
        f"Fixed MOEWS: score={moews_result.get('moews_score')} "
        f"risk={moews_result.get('risk_level')}\n"
        f"Vitals: SBP={vitals.get('systolic_bp')} DBP={vitals.get('diastolic_bp')} "
        f"HR={vitals.get('heart_rate')} GA={state.get('gestational_weeks', 'unknown')}\n"
        f"GHS context: {citations[:2]}\n"
    )
    try:
        raw = model.invoke(prompt).content
        text = raw if isinstance(raw, str) else str(raw)
        text = text.strip()
        if not text:
            return None
        return f"[advisory protocol assist] {text}"
    except Exception as exc:
        logger.warning("Gemini protocol assist failed: %s", exc)
        return None


def run_clinical_assessment(state: ReferralState) -> ReferralState:
    """
    MOEWS → optional RAG citations → structured summary → optional Gemini assist.
    Never blocks on RAG/LLM failure; never lets LLM set risk_level.
    """
    vitals = state.get("vitals") or {}
    errors = list(state.get("errors") or [])

    try:
        moews_result = score_vitals(
            vitals.get("systolic_bp"),
            vitals.get("diastolic_bp"),
            vitals.get("heart_rate"),
            vitals.get("respiratory_rate"),
            vitals.get("temperature"),
            vitals.get("spo2"),
            _consciousness_code(vitals.get("consciousness_level")),
        )
    except (TypeError, ValueError, KeyError, RuntimeError) as exc:
        logger.exception("MOEWS assessment failed: %s", exc)
        moews_result = dict(_UNKNOWN_RESULT)
        errors.append("moews_assessment_failed")
        state["moews_score"] = None
        state["risk_level"] = "UNKNOWN"
        state["retrieved_protocol_citations"] = []
        state["clinical_summary"] = (
            "Clinical assessment unavailable — use clinical judgment (UNKNOWN risk)."
        )
        state["protocol_assist"] = None
        state["errors"] = errors
        return state

    query_str = (
        f"MOEWS risk {moews_result['risk_level']} score {moews_result['moews_score']} "
        "pregnant referral protocol eclampsia haemorrhage transport"
    )
    retrieved_docs: list[str] = []
    engine = _get_rag_engine()
    if engine:
        try:
            retrieved_docs = engine.query_protocols(query_str, k=2)
        except (OSError, RuntimeError, ValueError) as exc:
            logger.warning("RAG query failed: %s", exc)
            retrieved_docs = []
            errors.append("rag_query_failed")

    summary = _structured_summary(state, moews_result, retrieved_docs)
    assist = _optional_protocol_assist(vitals, state, moews_result, retrieved_docs)

    state["moews_score"] = moews_result.get("moews_score")
    state["risk_level"] = moews_result.get("risk_level") or "UNKNOWN"
    state["missing_vitals"] = moews_result.get("missing_vitals") or []
    state["retrieved_protocol_citations"] = retrieved_docs
    state["clinical_summary"] = summary
    state["protocol_assist"] = assist
    state["errors"] = errors
    return state
