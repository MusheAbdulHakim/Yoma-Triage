"""Central configuration management loading from environment variables."""
import os

from dotenv import load_dotenv

from src import parameters

load_dotenv()

class Settings:
    # Anything other than exactly "development" gets production behaviour.
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "production")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    # Off: POST /referral never uses RAG or an LLM. This only gates the code left in
    # src/agents and src/rag, which also needs requirements-rag.txt.
    RAG_ENABLED: bool = os.getenv("RAG_ENABLED", "false").strip().lower() == "true"
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEFAULT_GEMINI_MODEL: str = "gemini-2.0-flash"
    VECTOR_STORE_DIR: str = os.getenv("VECTOR_STORE_DIR", "./data/vector_store")
    MOMO_API_URL: str = os.getenv("MOMO_API_URL", "https://sandbox.momodeveloper.mtn.com")
    MOMO_PRIMARY_KEY: str = os.getenv("MOMO_PRIMARY_KEY", "")
    # No default: a credential in code is one nobody remembers to change.
    DATABASE_URL: str = os.getenv("DATABASE_URL", "")
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
    # Staging/production refuse to start below parameters.MIN_FIELD_CASCADE_TIER_SECONDS.
    CASCADE_TIER_SECONDS: int = int(
        os.getenv("CASCADE_TIER_SECONDS", str(parameters.CASCADE_TIER_SECONDS))
    )
    WORKER_POLL_SECONDS: float = float(
        os.getenv("WORKER_POLL_SECONDS", str(parameters.WORKER_POLL_SECONDS))
    )
    OUTBOX_POLL_SECONDS: float = float(
        os.getenv("OUTBOX_POLL_SECONDS", str(parameters.OUTBOX_POLL_SECONDS))
    )
    OUTBOX_SEND_CONCURRENCY: int = int(
        os.getenv("OUTBOX_SEND_CONCURRENCY", str(parameters.OUTBOX_SEND_CONCURRENCY))
    )
    OUTBOX_SEND_TIMEOUT_SECONDS: float = float(
        os.getenv("OUTBOX_SEND_TIMEOUT_SECONDS", str(parameters.OUTBOX_SEND_TIMEOUT_SECONDS))
    )
    # How long after dispatch start a notified driver can still claim a FAILED dispatch.
    LATE_CLAIM_WINDOW_MINUTES: int = int(
        os.getenv("LATE_CLAIM_WINDOW_MINUTES", str(parameters.LATE_CLAIM_WINDOW_MINUTES))
    )
    # A referral queued on the phone for longer than this waits for the CHO to confirm it.
    STALE_AFTER_MINUTES: int = int(
        os.getenv("STALE_AFTER_MINUTES", str(parameters.STALE_AFTER_MINUTES))
    )
    # An unanswered stale referral is closed after this long.
    EXPIRE_UNCONFIRMED_HOURS: float = float(
        os.getenv("EXPIRE_UNCONFIRMED_HOURS", str(parameters.EXPIRE_UNCONFIRMED_HOURS))
    )
    # CHO/API shared secret (header X-API-Key). Empty + development → open for local demo.
    # Every other environment refuses to start without it.
    API_KEY: str = os.getenv("API_KEY", "")
    # Africa's Talking webhook shared secret (query ?secret= or X-Webhook-Secret).
    AT_WEBHOOK_SECRET: str = os.getenv("AT_WEBHOOK_SECRET", "")
    CORS_ORIGINS: str = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:8080,http://127.0.0.1:8080,"
        "http://localhost:5000,http://127.0.0.1:5000,"
        "http://localhost:7357,http://127.0.0.1:7357",
    )

    @property
    def is_development(self) -> bool:
        """The only insecure mode, and it has to be asked for by name."""
        return self.ENVIRONMENT.strip().lower() == "development"

    def startup_errors(self) -> list[str]:
        """Configuration that makes this environment unsafe to serve."""
        errors = [] if self.DATABASE_URL.strip() else ["DATABASE_URL must be set"]
        # In every environment: zero concurrency would silently never send an SMS.
        if self.OUTBOX_SEND_CONCURRENCY < 1:
            errors.append("OUTBOX_SEND_CONCURRENCY must be at least 1")
        if self.OUTBOX_SEND_TIMEOUT_SECONDS <= 0:
            errors.append("OUTBOX_SEND_TIMEOUT_SECONDS must be above 0")
        # Zero would close every stale referral before the CHO could answer.
        if self.EXPIRE_UNCONFIRMED_HOURS <= 0:
            errors.append("EXPIRE_UNCONFIRMED_HOURS must be above 0")
        if self.is_development:
            return errors
        errors += [
            f"{name} must be set"
            for name, value in (
                ("API_KEY", self.API_KEY),
                ("AT_WEBHOOK_SECRET", self.AT_WEBHOOK_SECRET),
                ("AT_API_KEY", self.AT_API_KEY),
                ("AT_USERNAME", self.AT_USERNAME),
                # Without it the USSD callback rejects every driver.
                ("AT_USSD_SERVICE_CODE", self.AT_USSD_SERVICE_CODE),
            )
            if not value.strip()
        ]
        # The sandbox accepts sends but never reaches real phones.
        if (
            self.AT_USERNAME.strip().lower() == "sandbox"
            and self.ENVIRONMENT.strip().lower() != "staging"
        ):
            errors.append("AT_USERNAME must not be sandbox")
        if self.CASCADE_TIER_SECONDS < parameters.MIN_FIELD_CASCADE_TIER_SECONDS:
            errors.append(
                "CASCADE_TIER_SECONDS must be at least "
                f"{parameters.MIN_FIELD_CASCADE_TIER_SECONDS}"
            )
        return errors

    def validate_for_startup(self) -> None:
        errors = self.startup_errors()
        if errors:
            raise RuntimeError("Refusing to start: " + "; ".join(errors))

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
