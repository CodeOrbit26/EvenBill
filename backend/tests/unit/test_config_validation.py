"""
Unit Tests for Production Configuration Fail-Safe Validation
"""

import pytest
from app.core.config import Settings


def test_production_fails_when_database_is_sqlite():
    with pytest.raises(ValueError, match="Silent fallback to SQLite"):
        Settings(
            ENVIRONMENT="production",
            DATABASE_URL="sqlite+aiosqlite:///./evenbill.db",
            SECRET_KEY="a" * 64,
            CORS_ORIGINS=["https://evenbill.app"],
            STORAGE_PROVIDER="LOCAL",
            EMAIL_PROVIDER="MOCK"
        )


def test_production_fails_when_cors_has_wildcard():
    with pytest.raises(ValueError, match="CORS_ORIGINS cannot contain wildcard"):
        Settings(
            ENVIRONMENT="production",
            DATABASE_URL="postgresql+asyncpg://evenbill_user:pass@host:5432/evenbill_prod",
            SECRET_KEY="a" * 64,
            CORS_ORIGINS=["*"],
            STORAGE_PROVIDER="LOCAL",
            EMAIL_PROVIDER="MOCK"
        )


def test_production_fails_when_secret_key_is_default_insecure():
    with pytest.raises(ValueError, match="Default insecure SECRET_KEY"):
        Settings(
            ENVIRONMENT="production",
            DATABASE_URL="postgresql+asyncpg://evenbill_user:pass@host:5432/evenbill_prod",
            SECRET_KEY="insecure-dev-secret-key-change-in-production-1234567890",
            CORS_ORIGINS=["https://evenbill.app"],
            STORAGE_PROVIDER="LOCAL",
            EMAIL_PROVIDER="MOCK"
        )


def test_production_fails_when_storage_is_localhost_minio():
    with pytest.raises(ValueError, match="Development storage provider 'MINIO'"):
        Settings(
            ENVIRONMENT="production",
            DATABASE_URL="postgresql+asyncpg://evenbill_user:pass@host:5432/evenbill_prod",
            SECRET_KEY="a" * 64,
            CORS_ORIGINS=["https://evenbill.app"],
            STORAGE_PROVIDER="MINIO",
            S3_ENDPOINT="http://localhost:9000",
            EMAIL_PROVIDER="MOCK"
        )


def test_production_fails_when_email_is_localhost_mailpit():
    with pytest.raises(ValueError, match="Development email provider 'MAILPIT'"):
        Settings(
            ENVIRONMENT="production",
            DATABASE_URL="postgresql+asyncpg://evenbill_user:pass@host:5432/evenbill_prod",
            SECRET_KEY="a" * 64,
            CORS_ORIGINS=["https://evenbill.app"],
            STORAGE_PROVIDER="LOCAL",
            EMAIL_PROVIDER="MAILPIT",
            SMTP_HOST="localhost"
        )


def test_production_valid_configuration_and_url_normalization():
    settings = Settings(
        ENVIRONMENT="production",
        DATABASE_URL="postgres://evenbill_user:pass@host:5432/evenbill_prod",
        SECRET_KEY="a" * 64,
        CORS_ORIGINS=["https://evenbill.app", "https://api.evenbill.app"],
        STORAGE_PROVIDER="LOCAL",
        EMAIL_PROVIDER="MOCK"
    )
    # Confirms auto-normalization of postgres:// to postgresql+asyncpg://
    assert settings.DATABASE_URL == "postgresql+asyncpg://evenbill_user:pass@host:5432/evenbill_prod"
    assert settings.ENVIRONMENT == "production"
    assert "*" not in settings.CORS_ORIGINS

