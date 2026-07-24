"""
Central configuration management loading from environment variables.
"""
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    # Environment
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    
    # Gemini API Settings
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEFAULT_GEMINI_MODEL: str = "gemini-1.5-flash"
    
    # Vector Database
    VECTOR_STORE_DIR: str = os.getenv("VECTOR_STORE_DIR", "./data/vector_store")
    
    # MoMo Escrow Gateway
    MOMO_API_URL: str = os.getenv("MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MOMO_PRIMARY_KEY: str = os.getenv("MOMO_PRIMARY_KEY", "")

settings = Settings()