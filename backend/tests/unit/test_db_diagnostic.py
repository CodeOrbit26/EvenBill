"""
Unit Tests for Database Diagnostic Module
Verifies non-sensitive URL parsing, sanitization, anomaly detection, and zero credentials exposure.
"""

from app.core.db_diagnostic import diagnose_database_url


def test_diagnose_valid_postgres_url(capsys):
    url = "postgresql+asyncpg://postgres.testref:mypassword123@aws-0-ap-south-1.pooler.supabase.com:5432/postgres"
    result = diagnose_database_url(url)

    assert result["driver"] == "postgresql+asyncpg"
    assert result["host"] == "aws-0-ap-south-1.pooler.supabase.com"
    assert result["port"] == 5432
    assert result["username"] == "postgres.testref"
    assert result["has_password"] is True
    assert result["success"] is True

    captured = capsys.readouterr().out
    # Confirm password is NEVER in stdout
    assert "mypassword123" not in captured
    assert "aws-0-ap-south-1.pooler.supabase.com" in captured
    assert "Parsed Username:    postgres.testref" in captured
    assert "Password Present:   True" in captured


def test_diagnose_detects_unescaped_at_in_host(capsys):
    # Password has unescaped @ which splits host into pass@aws-0...
    url = "postgresql+asyncpg://postgres.testref:my@pass@aws-0-ap-south-1.pooler.supabase.com:5432/postgres"
    result = diagnose_database_url(url)

    captured = capsys.readouterr().out
    assert "CRITICAL ANOMALY: Parsed hostname contains '@'" in captured
    assert "my@pass" not in captured


def test_diagnose_detects_surrounding_quotes(capsys):
    url = '"postgresql+asyncpg://postgres.testref:secret@aws-0-ap-south-1.pooler.supabase.com:5432/postgres"'
    result = diagnose_database_url(url)

    captured = capsys.readouterr().out
    assert "WARNING: DATABASE_URL contains surrounding quotes" in captured
    assert "secret" not in captured
    assert result["host"] == "aws-0-ap-south-1.pooler.supabase.com"


def test_diagnose_sqlite_url(capsys):
    url = "sqlite+aiosqlite:///./evenbill.db"
    result = diagnose_database_url(url)

    assert result["driver"] == "sqlite+aiosqlite"
    assert result["success"] is True
    captured = capsys.readouterr().out
    assert "DNS Resolution:     SKIPPED (Local file / SQLite database)" in captured
