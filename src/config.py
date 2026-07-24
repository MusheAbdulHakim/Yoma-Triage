"""Central configuration management loading from environment variables."""
import os

from dotenv import load_dotenv

load_dotenv()

class Settings:
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEFAULT_GEMINI_MODEL: str = "gemini-1.5-flash"
    VECTOR_STORE_DIR: str = os.getenv("VECTOR_STORE_DIR", "./data/vector_store")
    MOMO_API_URL: str = os.getenv("MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MOMO_PRIMARY_KEY: str = os.getenv("MOMO_PRIMARY_KEY", "")
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/relayai",
    )
    AT_API_KEY: str = os.getenv("AT_API_KEY", "")
    AT_USERNAME: str = os.getenv("AT_USERNAME", "sandbox")
    AT_SENDER_ID: str = os.getenv("AT_SENDER_ID", "RELAYAI")
    CASCADE_TIER_SECONDS: int = int(os.getenv("CASCADE_TIER_SECONDS", "5"))

    @property
    def at_configured(self) -> bool:
        return bool(self.AT_API_KEY and self.AT_USERNAME)

settings = Settings()
