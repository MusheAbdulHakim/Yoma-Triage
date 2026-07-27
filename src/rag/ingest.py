"""
Ingestion script: Loads raw GHS PDFs/Markdown guidelines from data/ghs_protocols/
and populates ChromaDB. Prefer ProtocolRAGEngine.seed_initial_protocols for
demo bootstrap; use this module when adding real PDFs.
"""
from __future__ import annotations

import logging
import os

from langchain_community.document_loaders import DirectoryLoader, PyPDFLoader, TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter

from src.rag.engine import ProtocolRAGEngine

logger = logging.getLogger(__name__)


def ingest_protocols(data_dir: str = "./data/ghs_protocols") -> int:
    """
    Reads protocol files, chunks content, and stores semantic vectors in ChromaDB.
    Returns number of chunks added.
    """
    logger.info("Reading clinical protocols from %s", data_dir)

    if not os.path.exists(data_dir) or not os.listdir(data_dir):
        logger.warning("Directory %s is empty; writing default protocol file", data_dir)
        os.makedirs(data_dir, exist_ok=True)
        with open(os.path.join(data_dir, "ghs_moews_protocol.txt"), "w", encoding="utf-8") as f:
            f.write(
                "GHS MOEWS Referral Standard (2023):\n"
                "1. Systolic BP >= 160 mmHg requires immediate IV Magnesium Sulfate "
                "and urgent referral.\n"
                "2. MOEWS Score >= 6 requires priority 2G SMS dispatch for Motor-King "
                "tricycle ambulances.\n"
                "3. Driver receives 30% Mobile Money fuel advance immediately upon "
                "referral acceptance.\n"
            )

    text_loader = DirectoryLoader(data_dir, glob="*.txt", loader_cls=TextLoader)
    md_loader = DirectoryLoader(data_dir, glob="*.md", loader_cls=TextLoader)
    pdf_loader = DirectoryLoader(data_dir, glob="*.pdf", loader_cls=PyPDFLoader)

    docs = text_loader.load() + md_loader.load() + pdf_loader.load()

    splitter = RecursiveCharacterTextSplitter(chunk_size=300, chunk_overlap=50)
    chunked_docs = splitter.split_documents(docs)

    rag_engine = ProtocolRAGEngine()
    rag_engine.vector_store.add_documents(chunked_docs)
    logger.info(
        "Successfully ingested %s protocol chunks into ChromaDB vector store",
        len(chunked_docs),
    )
    return len(chunked_docs)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    ingest_protocols()
