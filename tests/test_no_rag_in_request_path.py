"""POST /referral is deterministic, and the API runs without the RAG packages (B4)."""
from __future__ import annotations

import json
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

from src.tools.clinical_summary import build_clinical_summary

REPO = Path(__file__).resolve().parents[1]
HEAVY = (
    "torch", "sentence_transformers", "chromadb", "langgraph", "langchain",
    "langchain_core", "langchain_chroma", "langchain_huggingface",
    "langchain_google_genai", "transformers", "tiktoken",
)
VITALS = {
    "systolic_bp": 60,
    "diastolic_bp": 80,
    "heart_rate": 80,
    "respiratory_rate": 18,
    "temperature": None,
    "spo2": 98,
    "consciousness_level": "A",
}


def test_importing_the_app_loads_no_rag_package():
    code = (
        "import json, sys, main\n"
        f"print(json.dumps([m for m in {HEAVY!r} if m in sys.modules]))\n"
    )
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        cwd=REPO,
        timeout=120,
        check=True,
    )
    assert json.loads(result.stdout.strip().splitlines()[-1]) == []


def test_a_referral_loads_no_rag_package():
    code = """
import asyncio, json, sys, uuid
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool
import main
from src.db.database import Base, get_db
from src.db.models import CHPSCompound, Facility

async def run():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", poolclass=StaticPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with sessions() as session:
        session.add(CHPSCompound(id=1, name="C", zone="Z", cho_phone="+1"))
        session.add(Facility(id=1, name="H", phone="+2", district="D"))
        await session.commit()
    async def override():
        async with sessions() as session:
            yield session
    main.app.dependency_overrides[get_db] = override
    async with AsyncClient(transport=ASGITransport(app=main.app), base_url="http://t") as client:
        response = await client.post("/api/v1/referral", json={
            "chps_compound_id": 1, "facility_id": 1, "patient_hash": "0" * 64,
            "emergency_type": "pph", "client_request_id": str(uuid.uuid4()),
            "vitals": {"systolic_bp": 60},
        })
    print(json.dumps({"status": response.status_code,
                      "loaded": [m for m in HEAVY if m in sys.modules]}))
asyncio.run(run())
""".replace("HEAVY", repr(HEAVY))
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        cwd=REPO,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    outcome = json.loads(result.stdout.strip().splitlines()[-1])
    assert outcome == {"status": 201, "loaded": []}


def test_requirements_have_no_rag_packages():
    lines = (REPO / "requirements.txt").read_text().lower()
    for package in ("torch", "sentence-transformers", "chromadb", "langgraph", "langchain", "genai"):
        assert package not in lines, package


def test_rag_packages_moved_to_their_own_file():
    lines = (REPO / "requirements-rag.txt").read_text().lower()
    for package in ("sentence-transformers", "chromadb", "langgraph", "langchain", "genai"):
        assert package in lines, package


def test_rag_code_is_still_in_the_repo():
    assert (REPO / "src/rag/engine.py").exists()
    assert (REPO / "src/agents/clinical_agent.py").exists()


def test_rag_flag_is_off_by_default():
    code = "from src.config import settings; print(settings.RAG_ENABLED)"
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        cwd=REPO,
        timeout=60,
        check=True,
    )
    assert result.stdout.strip().splitlines()[-1] == "False"


def test_disabled_flag_returns_no_rag_and_no_llm(monkeypatch):
    from src.agents import clinical_agent

    monkeypatch.setattr("src.config.settings.RAG_ENABLED", False)
    monkeypatch.setattr("src.config.settings.GEMINI_API_KEY", "key")
    assert clinical_agent._get_rag_engine() is None
    assert clinical_agent._get_llm() is None


def test_summary_is_built_from_type_risk_and_vitals():
    assert build_clinical_summary(
        emergency_type="pph", risk_level="RED", moews_score=3, vitals=VITALS
    ) == (
        "Emergency: pph. Risk: RED (MOEWS 3). "
        "Vitals: SBP 60, DBP 80, HR 80, RR 18, SpO2 98, AVPU A. Not measured: temperature."
    )


def test_summary_when_vitals_were_not_taken():
    assert build_clinical_summary(
        emergency_type="eclampsia",
        risk_level="UNKNOWN",
        moews_score=None,
        vitals={},
        vitals_taken=False,
    ) == "Emergency: eclampsia. Risk: UNKNOWN. Vitals not taken."


def test_summary_is_repeatable():
    first = build_clinical_summary(
        emergency_type="pph", risk_level="RED", moews_score=3, vitals=VITALS
    )
    second = build_clinical_summary(
        emergency_type="pph", risk_level="RED", moews_score=3, vitals=VITALS
    )
    assert first == second


@pytest.mark.parametrize(
    "emergency_type",
    ["respiratory_distress", "pph", "neonatal_asphyxia", "eclampsia", "other"],
)
def test_summary_never_contains_treatment_advice(emergency_type):
    summary = build_clinical_summary(
        emergency_type=emergency_type, risk_level="RED", moews_score=21, vitals=VITALS
    ).lower()
    for word in (
        "magnesium", "mgso4", "fluids", "antibiotic", "oxytocin", "dose", "administer",
        "give ", "start ", "treat", "protocol", "guideline", "should",
    ):
        assert word not in summary, word


@pytest.mark.asyncio
async def test_api_stores_the_template_summary(client, seeded_db):
    response = await client.post(
        "/api/v1/referral",
        json={
            "chps_compound_id": 1,
            "facility_id": 1,
            "patient_hash": "0" * 64,
            "emergency_type": "pph",
            "client_request_id": str(uuid.uuid4()),
            "vitals": VITALS,
        },
    )
    assert response.status_code == 201, response.text
    summary = response.json()["referral"]["clinical_summary"]
    assert summary.startswith("Emergency: pph. Risk: RED (MOEWS 3).")
    assert "Not measured: temperature." in summary
