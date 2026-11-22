"""
Regression and Integration Tests for EvenBill Registration Flow
Verifies user registration, input validation, duplicate conflict handling,
and PostgreSQL auth.users synchronization with foreign key integrity.
"""

import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.services.auth_service import AuthService
from app.schemas.user import UserCreate
from app.models.user import User, Subscription
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_registration_success(client: AsyncClient):
    payload = {
        "email": f"newuser_{uuid.uuid4().hex[:6]}@evenbill.app",
        "password": "ValidPassword123!",
        "full_name": "New Valid User",
        "phone_number": "+12025550199",
        "default_currency": "USD"
    }
    resp = await client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 201
    data = resp.json()
    assert data["success"] is True
    assert data["data"]["email"] == payload["email"]
    assert data["data"]["full_name"] == payload["full_name"]
    assert data["data"]["phone_number"] == payload["phone_number"]
    assert data["data"]["default_currency"] == "USD"
    assert data["data"]["is_pro"] is False
    assert data["data"]["has_password"] is True
    assert "id" in data["data"]


@pytest.mark.asyncio
async def test_registration_duplicate_email(client: AsyncClient):
    email = f"dupe_{uuid.uuid4().hex[:6]}@evenbill.app"
    payload = {
        "email": email,
        "password": "ValidPassword123!",
        "full_name": "First User",
        "default_currency": "USD"
    }
    resp1 = await client.post("/api/v1/auth/register", json=payload)
    assert resp1.status_code == 201

    # Second registration with same email
    payload2 = {
        "email": email.upper(),  # Test case-insensitivity
        "password": "AnotherPassword456!",
        "full_name": "Second User",
        "default_currency": "EUR"
    }
    resp2 = await client.post("/api/v1/auth/register", json=payload2)
    assert resp2.status_code == 409
    err = resp2.json()["detail"]
    assert "already exists" in err.lower()


@pytest.mark.asyncio
async def test_registration_duplicate_phone(client: AsyncClient):
    phone = "+14155550188"
    payload1 = {
        "email": f"user_a_{uuid.uuid4().hex[:6]}@evenbill.app",
        "password": "ValidPassword123!",
        "full_name": "User Phone A",
        "phone_number": phone,
        "default_currency": "USD"
    }
    resp1 = await client.post("/api/v1/auth/register", json=payload1)
    assert resp1.status_code == 201

    payload2 = {
        "email": f"user_b_{uuid.uuid4().hex[:6]}@evenbill.app",
        "password": "ValidPassword123!",
        "full_name": "User Phone B",
        "phone_number": phone,
        "default_currency": "USD"
    }
    resp2 = await client.post("/api/v1/auth/register", json=payload2)
    assert resp2.status_code == 409
    err = resp2.json()["detail"]
    assert "phone number already exists" in err.lower()


@pytest.mark.asyncio
async def test_registration_invalid_email(client: AsyncClient):
    payload = {
        "email": "not-an-email",
        "password": "ValidPassword123!",
        "full_name": "Invalid Email User"
    }
    resp = await client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_registration_weak_password(client: AsyncClient):
    payload = {
        "email": f"weak_{uuid.uuid4().hex[:6]}@evenbill.app",
        "password": "short",
        "full_name": "Weak Pass User"
    }
    resp = await client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_registration_currency_normalization(client: AsyncClient):
    payload = {
        "email": f"curr_{uuid.uuid4().hex[:6]}@evenbill.app",
        "password": "ValidPassword123!",
        "full_name": "Currency Test",
        "default_currency": "eur"
    }
    resp = await client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 201
    assert resp.json()["data"]["default_currency"] == "EUR"


@pytest.mark.asyncio
async def test_postgres_auth_users_and_fk_profiles_sync():
    """
    Directly tests registration against PostgreSQL if local test DB is available.
    Verifies that:
    1. No asyncpg DatatypeMismatchError occurs (UUID binary parameter binding).
    2. fk_profiles_auth_users foreign key is satisfied by inserting into auth.users.
    3. Profiles row created by handle_new_user() trigger is updated with password and fields.
    4. Free tier subscription is seeded.
    """
    pg_url = "postgresql+asyncpg://abhay@localhost:5432/evenbill_test_l2_security"
    try:
        engine = create_async_engine(pg_url)
        async with engine.connect() as conn:
            check = await conn.execute(text("SELECT to_regclass('auth.users') IS NOT NULL"))
            has_table = bool(check.scalar())
            if not has_table:
                pytest.skip("auth.users table not present in test postgres DB")
    except Exception:
        pytest.skip("Local postgresql instance not reachable")

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as db:
        unique_suffix = uuid.uuid4().hex[:8]
        reg_data = UserCreate(
            email=f"pg_sync_{unique_suffix}@example.com",
            password="SecurePostgresPass123!",
            full_name=f"PG User {unique_suffix}",
            phone_number=f"+1555{unique_suffix[:7]}",
            default_currency="USD"
        )

        user = await AuthService.register_user(db, reg_data)
        assert user is not None
        assert user.email == reg_data.email.lower()
        assert user.full_name == reg_data.full_name

        # Verify auth.users entry exists
        auth_row = await db.execute(
            text("SELECT id, email FROM auth.users WHERE CAST(id AS text) = :uid"),
            {"uid": user.id}
        )
        auth_user = auth_row.fetchone()
        assert auth_user is not None
        assert str(auth_user[0]) == user.id

        # Verify profiles entry exists
        p_row = await db.execute(
            text("SELECT id, email, hashed_password FROM public.profiles WHERE CAST(id AS text) = :uid"),
            {"uid": user.id}
        )
        p_user = p_row.fetchone()
        assert p_user is not None
        assert p_user[2] is not None  # hashed_password is set

        # Verify subscription was seeded
        sub_row = await db.execute(
            text("SELECT tier, status FROM public.subscriptions WHERE CAST(user_id AS text) = :uid"),
            {"uid": user.id}
        )
        sub = sub_row.fetchone()
        assert sub is not None
        assert sub[0] == "FREE"
        assert sub[1] == "ACTIVE"

        # Verify duplicate email conflict in Postgres
        with pytest.raises(HTTPException) as exc_info:
            await AuthService.register_user(db, reg_data)
        assert exc_info.value.status_code == 409
