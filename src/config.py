"""Central configuration management loading from environment variables."""
import os

from dotenv import load_dotenv

load_dotenv()

class Settings:
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEFAULT_GEMINI_MODEL: str = "gemini-2.0-flash"
    VECTOR_STORE_DIR: str = os.getenv("VECTOR_STORE_DIR", "./data/vector_store")
    MOMO_API_URL: str = os.getenv("MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MOMO_PRIMARY_KEY: str = os.getenv("MOMO_PRIMARY_KEY", "")
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/yoma_triage",
    )
    AT_API_KEY: str = os.getenv("AT_API_KEY", "")
    AT_USERNAME: str = os.getenv("AT_USERNAME", "sandbox")
    AT_SENDER_ID: str = os.getenv("AT_SENDER_ID", "YOMATRIAGE")
    # USSD shortcode registered with Africa's Talking (e.g. *384*99193#).
    # Used in driver SMS copy and optional callback validation — never hardcode in app logic.
    AT_USSD_SERVICE_CODE: str = os.getenv("AT_USSD_SERVICE_CODE", "")
    # Override SMS API host. Empty → sandbox host when username is "sandbox", else live.
    AT_API_BASE_URL: str = os.getenv("AT_API_BASE_URL", "")
    # Public HTTPS origin for Africa's Talking callbacks (ngrok/staging). Never hardcode tunnels.
    # Example: https://abcd-1-2-3-4.ngrok-free.app  (no trailing slash required)
    PUBLIC_BASE_URL: str = os.getenv("PUBLIC_BASE_URL", "")
    # Local/demo API client base (scripts/demo_flow.py). Defaults to loopback.
    DEMO_API_BASE_URL: str = os.getenv("DEMO_API_BASE_URL", "http://127.0.0.1:8000")
    # Demo default is 5s; field/pilot should use minutes (e.g. 60–180) via env.
    CASCADE_TIER_SECONDS: int = int(os.getenv("CASCADE_TIER_SECONDS", "5"))
    CORS_ORIGINS: str = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://localhost:5000,http://127.0.0.1:5000,"
        "http://localhost:7357,http://127.0.0.1:7357",
    )

    @property
    def public_base_url(self) -> str:
        return self.PUBLIC_BASE_URL.strip().rstrip("/")

    @property
    def ussd_callback_url(self) -> str | None:
        if not self.public_base_url:
            return None
        return f"{self.public_base_url}/ussd/callback"

    @property
    def sms_inbound_url(self) -> str | None:
        if not self.public_base_url:
            return None
        return f"{self.public_base_url}/api/v1/sms/inbound"

    @property
    def cors_origins(self) -> list[str]:
        origins = [
            origin.strip()
            for origin in self.CORS_ORIGINS.split(",")
            if origin.strip()
        ]
        # If Flutter (or judges) hit the API via the same public tunnel, allow it.
        if self.public_base_url and self.public_base_url not in origins:
            origins.append(self.public_base_url)
        return origins

    @property
    def at_configured(self) -> bool:
        return bool(self.AT_API_KEY and self.AT_USERNAME)

    @property
    def at_api_base_url(self) -> str:
        if self.AT_API_BASE_URL.strip():
            return self.AT_API_BASE_URL.rstrip("/")
        if self.AT_USERNAME.strip().lower() == "sandbox":
            return "https://api.sandbox.africastalking.com"
        return "https://api.africastalking.com"

    @property
    def at_sms_bulk_url(self) -> str:
        return f"{self.at_api_base_url}/version1/messaging/bulk"

settings = Settings()
