"""
EvenBill Configuration Management
Uses Pydantic v2 BaseSettings to parse environment variables with type validation and defaults.
"""

from typing import List, Optional
from decimal import Decimal
from pydantic import Field
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

    # Database
    # Defaults to async SQLite for local lightweight development and testing; easily switched to PostgreSQL
    DATABASE_URL: str = Field(
        default="sqlite+aiosqlite:///./evenbill.db",
        validation_alias="DATABASE_URL"
    )

    # Redis Cache & Message Broker
    REDIS_URL: str = Field(default="redis://localhost:6379/0", validation_alias="REDIS_URL")

    # S3 Object Storage (Receipts & Exports)
    S3_ENDPOINT: Optional[str] = None
    S3_BUCKET: str = "evenbill-receipts"
    S3_ACCESS_KEY: Optional[str] = None
    S3_SECRET_KEY: Optional[str] = None
    S3_REGION: str = "us-east-1"

    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8000", "*"]

    # Plan Limits & Monetization
    FREE_OCR_LIMIT_MONTHLY: int = 3
    PRO_PRICE_MONTHLY_USD: Decimal = Decimal("4.99")
    PRO_PRICE_ANNUAL_USD: Decimal = Decimal("39.99")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore"
    )


settings = Settings()
