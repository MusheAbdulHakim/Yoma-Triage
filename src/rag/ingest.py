"""
Ingestion script: Loads raw GHS PDFs/Markdown guidelines from data/ghs_protocols/ and populates ChromaDB.
"""
import os

from langchain_community.document_loaders import DirectoryLoader, PyPDFLoader, TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter

from src.rag.engine import ProtocolRAGEngine


def ingest_protocols(data_dir: str = "./data/ghs_protocols"):
    """
    Reads protocol files, chunks content, and stores semantic vectors in ChromaDB.
    """
    print(f"Reading clinical protocols from {data_dir}...")

    if not os.path.exists(data_dir) or not os.listdir(data_dir):
        print(f"Directory {data_dir} is empty. Creating default protocol files...")
        os.makedirs(data_dir, exist_ok=True)
        with open(os.path.join(data_dir, "ghs_moews_protocol.txt"), "w") as f:
            f.write(
                "GHS MOEWS Referral Standard (2023):\n"
                "1. Systolic BP >= 160 mmHg requires immediate IV Magnesium Sulfate and urgent referral.\n"
                "2. MOEWS Score >= 6 requires priority 2G SMS dispatch for Motor-King tricycle ambulances.\n"
                "3. Driver receives 30% Mobile Money fuel advance immediately upon referral acceptance."
            )

    # Load text and PDF files
    text_loader = DirectoryLoader(data_dir, glob="*.txt", loader_cls=TextLoader)
    pdf_loader = DirectoryLoader(data_dir, glob="*.pdf", loader_cls=PyPDFLoader)

    docs = text_loader.load() + pdf_loader.load()

    # Chunk protocols keeping clinical context intact
    splitter = RecursiveCharacterTextSplitter(chunk_size=300, chunk_overlap=50)
    chunked_docs = splitter.split_documents(docs)

    # Store in ChromaDB
    rag_engine = ProtocolRAGEngine()
    rag_engine.vector_store.add_documents(chunked_docs)
    print(f"Successfully ingested {len(chunked_docs)} protocol chunks into ChromaDB vector store.")

if __name__ == "__main__":
    ingest_protocols()
