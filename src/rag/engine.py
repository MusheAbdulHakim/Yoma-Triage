"""
GHS protocol RAG for clinical assessment grounding.

Hackathon note: DEMO_PROTOCOL_DOCUMENTS are illustrative MNCH/referral snippets
aligned with public GHS MOEWS practice — not a substitute for official PDF
ingest. Place real PDFs/Markdown under data/ghs_protocols/ and re-seed, or run
`python -m src.rag.ingest`.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_huggingface import HuggingFaceEmbeddings

from src.config import settings

logger = logging.getLogger(__name__)

DEMO_PROTOCOL_DOCUMENTS: list[Document] = [
    Document(
        page_content=(
            "GHS MNCH Guideline: Any pregnant woman with MOEWS score >= 6 or "
            "Systolic BP >= 160 mmHg must be immediately referred to a District "
            "Hospital. If hypertensive emergency / eclampsia risk, initiate IV "
            "Magnesium Sulfate loading dose at CHPS before transfer when stock "
            "and skilled attendant allow."
        ),
        metadata={
            "source": "GHS_MNCH_Guidelines_demo.md",
            "section": "Eclampsia / Hypertensive Emergency",
        },
    ),
    Document(
        page_content=(
            "GHS MOEWS Referral Standard: Heart rate >= 120 bpm, respiratory rate "
            ">= 30, SpO2 < 92%, or non-alert consciousness are red-flag triggers. "
            "Total MOEWS >= 6 is CRITICAL — do not delay transport for non-essential "
            "investigations at CHPS."
        ),
        metadata={
            "source": "GHS_MOEWS_Referral_demo.md",
            "section": "Red-flag vitals",
        },
    ),
    Document(
        page_content=(
            "GHS Emergency Transport (Networks of Practice): Motor-King tricycle "
            "ambulances in Northern Region are dispatched via USSD when MOEWS is "
            "HIGH or CRITICAL. Initial MoMo fuel stipend (30%) disburses on driver "
            "accept; remaining balance on hospital arrival handshake."
        ),
        metadata={
            "source": "GHS_NoP_Transport_Standard_demo.md",
            "section": "Logistics",
        },
    ),
    Document(
        page_content=(
            "GHS Obstetric Haemorrhage: For suspected PPH or antepartum bleeding "
            "with shock signs (low SBP, tachycardia), start IV fluids, keep warm, "
            "and urgent referral. Do not wait for laboratory confirmation at CHPS."
        ),
        metadata={
            "source": "GHS_Haemorrhage_Protocol_demo.md",
            "section": "Haemorrhage",
        },
    ),
]


def _load_protocol_files(protocols_dir: Path) -> list[Document]:
    """Load .md / .txt protocol files if present (PDF ingest via src.rag.ingest)."""
    if not protocols_dir.is_dir():
        return []
    docs: list[Document] = []
    for path in sorted(protocols_dir.iterdir()):
        if path.suffix.lower() not in {".md", ".txt"}:
            continue
        try:
            text = path.read_text(encoding="utf-8").strip()
        except OSError as exc:
            logger.warning("Skipping protocol file %s: %s", path, exc)
            continue
        if text:
            docs.append(
                Document(
                    page_content=text,
                    metadata={"source": path.name, "section": "file"},
                )
            )
    return docs


class ProtocolRAGEngine:
    def __init__(self, persist_directory: str | None = None):
        self.persist_directory = persist_directory or settings.VECTOR_STORE_DIR
        self.embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/all-MiniLM-L6-v2"
        )
        os.makedirs(self.persist_directory, exist_ok=True)
        self.vector_store = Chroma(
            collection_name="ghs_protocols",
            embedding_function=self.embeddings,
            persist_directory=self.persist_directory,
        )

    def seed_initial_protocols(
        self, protocols_dir: str | Path = "./data/ghs_protocols"
    ) -> int:
        """Seed demo + on-disk protocol docs when the vector store is empty."""
        try:
            count = self.vector_store._collection.count()
        except (AttributeError, RuntimeError, ValueError):
            count = 0

        if count > 0:
            return 0

        file_docs = _load_protocol_files(Path(protocols_dir))
        # Prefer richer on-disk corpus when present; always include DEMO fallback.
        to_add = file_docs if file_docs else list(DEMO_PROTOCOL_DOCUMENTS)
        if file_docs:
            # Merge unique demo snippets that files may not cover.
            existing_text = {d.page_content for d in file_docs}
            for demo in DEMO_PROTOCOL_DOCUMENTS:
                if demo.page_content not in existing_text:
                    to_add.append(demo)

        self.vector_store.add_documents(to_add)
        logger.info("Seeded %s GHS protocol chunks into vector store", len(to_add))
        return len(to_add)

    def query_protocols(self, query: str, k: int = 2) -> list[str]:
        """Retrieve relevant GHS clinical guidelines for prompt augmentation."""
        results = self.vector_store.similarity_search(query, k=k)
        return [doc.page_content for doc in results]
