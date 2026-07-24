import os

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_huggingface import HuggingFaceEmbeddings


class ProtocolRAGEngine:
    def __init__(self, persist_directory: str = "./data/vector_store"):
        self.persist_directory = persist_directory

        # Local, free, keyless embedding model
        self.embeddings = HuggingFaceEmbeddings(model_name="sentence-transformers/all-MiniLM-L6-v2")

        os.makedirs(self.persist_directory, exist_ok=True)

        # Modern Chroma vector store initialization
        self.vector_store = Chroma(
            collection_name="ghs_protocols",
            embedding_function=self.embeddings,
            persist_directory=self.persist_directory
        )

    def seed_initial_protocols(self):
        """Seeds default GHS Referral Protocols if vector store is empty."""
        try:
            count = self.vector_store._collection.count()
        except Exception:
            count = 0

        if count == 0:
            sample_protocols = [
                Document(
                    page_content="GHS Guideline: Any pregnant woman with MOEWS score >= 6 or Systolic BP >= 160 mmHg must be immediately referred to a District Hospital with IV Magnesium Sulfate loading dose initiated at CHPS.",
                    metadata={"source": "GHS_MNCH_Guidelines_2023.pdf", "section": "Eclampsia Protocol"}
                ),
                Document(
                    page_content="GHS Emergency Transport: Motor-King tricycle ambulances operating in Northern Region must be dispatched via USSD when MOEWS is HIGH or CRITICAL. Initial fuel stipend disburses automatically via MoMo.",
                    metadata={"source": "GHS_NoP_Transport_Standard.pdf", "section": "Logistics"}
                )
            ]
            self.vector_store.add_documents(sample_protocols)

    def query_protocols(self, query: str, k: int = 2) -> list[str]:
        """Retrieves relevant GHS clinical guidelines for prompt augmentation."""
        results = self.vector_store.similarity_search(query, k=k)
        return [doc.page_content for doc in results]
