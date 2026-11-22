"""
EvenBill Configuration Management
Uses Pydantic v2 BaseSettings to parse environment variables with type validation and defaults.
"""

from typing import List, Optional
from decimal import Decimal
from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "EvenBill"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    # Security & Tokens
    SECRET_KEY: str = Field(default="insecure-dev-secret-key-change-in-production-1234567890", validation_alias="SECRET_KEY")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # OAuth Credentials
    GOOGLE_CLIENT_ID: Optional[str] = Field(default="34497581041-32g5m3c4oet10tbf1m6cr03m1eugqc50.apps.googleusercontent.com", validation_alias="GOOGLE_CLIENT_ID")
    GOOGLE_CLIENT_SECRET: Optional[str] = Field(default=None, validation_alias="GOOGLE_CLIENT_SECRET")

    # Supabase Configuration
    SUPABASE_URL: str = Field(
        default="https://aniqkrmuurmhwxkiahxv.supabase.co",
        validation_alias="SUPABASE_URL"
    )
    SUPABASE_ANON_KEY: str = Field(
        default="sb_publishable_GSrWtiv5G3Egh6YjoMz28Q_PXoMt-x5",
        validation_alias="SUPABASE_ANON_KEY"
    )
    SUPABASE_SERVICE_ROLE_KEY: Optional[str] = Field(
        default=None,
        validation_alias="SUPABASE_SERVICE_ROLE_KEY"
    )
    SUPABASE_JWT_SECRET: Optional[str] = Field(
        default=None,
        validation_alias="SUPABASE_JWT_SECRET"
    )
    SUPABASE_AUDIENCE: str = Field(
        default="authenticated",
        validation_alias="SUPABASE_AUDIENCE"
    )

    @property
    def supabase_jwks_url(self) -> str:
        return f"{self.SUPABASE_URL.rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def supabase_issuer(self) -> str:
        return f"{self.SUPABASE_URL.rstrip('/')}/auth/v1"

    # Database
    # Defaults to async SQLite for local lightweight development and testing; easily switched to PostgreSQL
    DATABASE_URL: str = Field(
        default="sqlite+aiosqlite:///./evenbill.db",
        validation_alias="DATABASE_URL"
    )

    # Redis Cache & Message Broker
    REDIS_URL: str = Field(default="redis://localhost:6379/0", validation_alias="REDIS_URL")

    # S3 Object Storage (Receipts & Exports)
    STORAGE_PROVIDER: str = "MINIO"  # MINIO, S3, LOCAL
    S3_ENDPOINT: Optional[str] = "http://localhost:9000"
    S3_BUCKET: str = "evenbill-receipts"
    S3_ACCESS_KEY: Optional[str] = "minioadmin"
    S3_SECRET_KEY: Optional[str] = "minioadmin"
    S3_REGION: str = "us-east-1"
    S3_SECURE: bool = False

    # Email Delivery (Mailpit / SES)
    EMAIL_PROVIDER: str = "MAILPIT"  # MAILPIT, SES, MOCK
    SMTP_HOST: str = "localhost"
    SMTP_PORT: int = 1025
    SMTP_USER: Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None
    EMAILS_FROM_EMAIL: str = "noreply@evenbill.local"
    EMAILS_FROM_NAME: str = "EvenBill Team"

    # Foreign Exchange Rate Provider
    FX_PROVIDER: str = "ECB"  # ECB, FIXTURE
    FX_ALLOW_FIXTURE_FALLBACK: bool = True

    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8000", "*"]

    # Plan Limits & Monetization
    FREE_DAILY_EXPENSE_LIMIT: int = Field(default=4, validation_alias="FREE_DAILY_EXPENSE_LIMIT")
    EXPENSE_LIMIT_WINDOW_HOURS: int = Field(default=24, validation_alias="EXPENSE_LIMIT_WINDOW_HOURS")
    FREE_OCR_LIMIT_MONTHLY: int = 3
    PRO_PRICE_MONTHLY_USD: Decimal = Decimal("4.99")
    PRO_PRICE_ANNUAL_USD: Decimal = Decimal("39.99")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore"
    )

    @model_validator(mode="after")
    def validate_production_configuration(self) -> "Settings":
        env = self.ENVIRONMENT.lower()
        if env in ("production", "staging"):
            # Strip accidental surrounding quotes or whitespace
            if self.DATABASE_URL:
                self.DATABASE_URL = self.DATABASE_URL.strip().strip('"\'')

            # 1. DATABASE_URL must not silently fall back to SQLite in production/staging
            if not self.DATABASE_URL or "sqlite" in self.DATABASE_URL.lower():
                raise ValueError(
                    f"Production/staging environment requires a PostgreSQL connection string. "
                    f"Silent fallback to SQLite ({self.DATABASE_URL}) is strictly forbidden."
                )

            # Auto-normalize standard postgres:// or postgresql:// to postgresql+asyncpg:// for async SQLAlchemy
            if self.DATABASE_URL.startswith("postgres://"):
                self.DATABASE_URL = self.DATABASE_URL.replace("postgres://", "postgresql+asyncpg://", 1)
            elif self.DATABASE_URL.startswith("postgresql://") and not self.DATABASE_URL.startswith("postgresql+"):
                self.DATABASE_URL = self.DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

            # 2. CORS must never contain wildcard '*' in production/staging
            if "*" in self.CORS_ORIGINS:
                raise ValueError(
                    "CORS_ORIGINS cannot contain wildcard '*' in production/staging. "
                    "Explicit allowed origins must be configured to protect user session credentials."
                )

            # 3. Insecure default SECRET_KEY is forbidden in production/staging
            if "insecure-dev-secret-key" in self.SECRET_KEY:
                raise ValueError(
                    "Default insecure SECRET_KEY detected in production/staging. "
                    "A strong cryptographic secret key must be set via the SECRET_KEY environment variable."
                )

            # 4. Storage provider validation: MinIO on localhost cannot be used in production
            if self.STORAGE_PROVIDER == "MINIO" and self.S3_ENDPOINT and ("localhost" in self.S3_ENDPOINT or "127.0.0.1" in self.S3_ENDPOINT):
                raise ValueError(
                    "Development storage provider 'MINIO' on localhost cannot be used in production/staging. "
                    "Configure S3 storage (STORAGE_PROVIDER='S3' with bucket credentials) or STORAGE_PROVIDER='LOCAL'."
                )

            # 5. Email provider validation: Mailpit on localhost cannot be used in production
            if self.EMAIL_PROVIDER == "MAILPIT" and (self.SMTP_HOST in ("localhost", "127.0.0.1")):
                raise ValueError(
                    "Development email provider 'MAILPIT' on localhost cannot be used in production/staging. "
                    "Configure EMAIL_PROVIDER='SES', 'SMTP' (with external host), or 'MOCK'."
                )

        return self


settings = Settings()
