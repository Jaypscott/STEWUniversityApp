import os
from functools import cached_property

from dotenv import load_dotenv


load_dotenv()


class Settings:
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    ai_daily_limit = int(os.getenv("AI_DAILY_LIMIT", "20"))
    ai_daily_window_seconds = int(os.getenv("AI_DAILY_WINDOW_SECONDS", "86400"))
    ai_burst_limit = int(os.getenv("AI_BURST_LIMIT", "5"))
    ai_burst_window_seconds = int(os.getenv("AI_BURST_WINDOW_SECONDS", "60"))
    ai_max_output_tokens = int(os.getenv("AI_MAX_OUTPUT_TOKENS", "600"))

    # Band persistence and public routing.
    database_url = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///./band-dev.db")
    public_base_url = os.getenv(
        "PUBLIC_BASE_URL", "https://stew-university-backend.onrender.com"
    ).rstrip("/")
    app_jwt_secret = os.getenv("APP_JWT_SECRET", "local-development-only-change-me")
    apple_token_encryption_key = os.getenv("APPLE_TOKEN_ENCRYPTION_KEY", "")

    # Sign in with Apple and APNs. Secret values stay in Render environment variables.
    apple_bundle_id = os.getenv("APPLE_BUNDLE_ID", "com.stewuniversity.ios")
    apple_team_id = os.getenv("APPLE_TEAM_ID", "")
    apple_key_id = os.getenv("APPLE_KEY_ID", "")
    apple_private_key = os.getenv("APPLE_PRIVATE_KEY", "").replace("\\n", "\n")
    apns_environment = os.getenv("APNS_ENVIRONMENT", "sandbox")
    apns_key_id = os.getenv("APNS_KEY_ID", "")
    apns_private_key = os.getenv("APNS_PRIVATE_KEY", "").replace("\\n", "\n")

    # Private Cloudflare R2 media storage.
    r2_account_id = os.getenv("R2_ACCOUNT_ID", "")
    r2_access_key_id = os.getenv("R2_ACCESS_KEY_ID", "")
    r2_secret_access_key = os.getenv("R2_SECRET_ACCESS_KEY", "")
    r2_bucket_name = os.getenv("R2_BUCKET_NAME", "")

    # App-facing legal and support destinations.
    terms_url = os.getenv("TERMS_URL", f"{public_base_url}/legal/terms")
    privacy_url = os.getenv("PRIVACY_URL", f"{public_base_url}/legal/privacy")
    support_url = os.getenv("SUPPORT_URL", f"{public_base_url}/support")
    safety_contact_url = os.getenv("SAFETY_CONTACT_URL", f"{public_base_url}/safety")
    terms_version = os.getenv("TERMS_VERSION", "2026-07-20")

    band_inline_jobs = os.getenv("BAND_INLINE_JOBS", "false").lower() == "true"
    band_auto_create_db = os.getenv("BAND_AUTO_CREATE_DB", "false").lower() == "true"
    progress_sync_enabled = os.getenv("PROGRESS_SYNC_ENABLED", "false").lower() == "true"

    @cached_property
    def platform_admin_apple_subjects(self) -> set[str]:
        return {
            value.strip()
            for value in os.getenv("PLATFORM_ADMIN_APPLE_SUBJECTS", "").split(",")
            if value.strip()
        }

    @cached_property
    def objectionable_words(self) -> set[str]:
        defaults = "pornography,terrorist threat,kill yourself"
        return {
            value.strip().casefold()
            for value in os.getenv("OBJECTIONABLE_TEXT", defaults).split(",")
            if value.strip()
        }

    @property
    def r2_endpoint(self) -> str:
        return f"https://{self.r2_account_id}.r2.cloudflarestorage.com"

    @property
    def r2_configured(self) -> bool:
        return all(
            (
                self.r2_account_id,
                self.r2_access_key_id,
                self.r2_secret_access_key,
                self.r2_bucket_name,
            )
        )

    @property
    def apns_configured(self) -> bool:
        return all((self.apple_team_id, self.apns_key_id, self.apns_private_key))


settings = Settings()
