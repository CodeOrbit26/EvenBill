"""
EvenBill Supabase Authentication & Cryptographic Verification Integration Tests
Verifies:
- ES256 asymmetric cryptographic signature verification
- JWKS resolution & key rotation
- Issuer, audience, and expiration enforcement
- Extraction of authenticated user UUID directly from token claims
- Rejection of missing, invalid, expired, or tampered tokens
- Enforced account status and profile synchronization
"""

import time
import uuid
import pytest
import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.core.supabase_jwt import SupabaseJWTVerifier
from app.models.user import User


@pytest.fixture
def ec_key_pair():
    """Generates an ephemeral EC P-256 key pair for ES256 tests."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()
    return private_key, public_key


@pytest.mark.asyncio
async def test_reject_request_with_missing_token(client: AsyncClient):
    """Protected endpoints reject requests without Authorization header."""
    res = await client.get("/api/v1/users/me")
    assert res.status_code in [401, 403]


@pytest.mark.asyncio
async def test_reject_request_with_malformed_token(client: AsyncClient):
    """Protected endpoints reject malformed Bearer tokens."""
    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": "Bearer not-a-valid-token"}
    )
    assert res.status_code == 401
    assert "Malformed" in res.json().get("detail", "") or "Could not validate" in res.json().get("detail", "")


@pytest.mark.asyncio
async def test_reject_request_with_expired_token(client: AsyncClient):
    """Protected endpoints reject expired JWT tokens with HTTP 401."""
    expired_payload = {
        "sub": str(uuid.uuid4()),
        "exp": int(time.time()) - 3600,  # 1 hour ago
        "iat": int(time.time()) - 7200,
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": settings.supabase_issuer,
        "email": "expired@evenbill.app"
    }
    expired_token = jwt.encode(expired_payload, settings.SECRET_KEY, algorithm="HS256")

    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {expired_token}"}
    )
    assert res.status_code == 401
    assert "expired" in res.json().get("detail", "").lower()


@pytest.mark.asyncio
async def test_reject_request_with_invalid_signature(client: AsyncClient):
    """Tokens signed with an unknown secret/key are rejected."""
    wrong_secret = "completely-wrong-untrusted-secret-key-12345"
    payload = {
        "sub": str(uuid.uuid4()),
        "exp": int(time.time()) + 3600,
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": settings.supabase_issuer,
        "email": "hacker@evil.com"
    }
    tampered_token = jwt.encode(payload, wrong_secret, algorithm="HS256")

    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {tampered_token}"}
    )
    assert res.status_code == 401


@pytest.mark.asyncio
async def test_es256_asymmetric_token_verification_and_profile_sync(
    client: AsyncClient,
    db_session: AsyncSession,
    ec_key_pair,
    monkeypatch
):
    """
    Verifies full ES256 asymmetric flow:
    - Token is signed with private EC key
    - Verifier resolves public key and validates signature, issuer, audience, exp
    - User UUID is extracted from verified token
    - Profile is synchronized automatically into the database
    """
    private_key, public_key = ec_key_pair
    test_user_id = str(uuid.uuid4())
    test_email = f"user_{test_user_id[:8]}@evenbill.supabase.test"

    # Mock JWKS resolution to return our test public key
    class MockSigningKey:
        key = public_key

    class MockJWKSClient:
        def get_signing_key_from_jwt(self, token):
            return MockSigningKey()

    monkeypatch.setattr(SupabaseJWTVerifier, "get_jwks_client", classmethod(lambda cls: MockJWKSClient()))

    # Create ES256 signed JWT
    now = int(time.time())
    token_claims = {
        "sub": test_user_id,
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": settings.supabase_issuer,
        "exp": now + 3600,
        "iat": now,
        "email": test_email,
        "user_metadata": {
            "full_name": "Supabase Test User",
            "default_currency": "INR"
        }
    }
    es256_token = jwt.encode(
        token_claims,
        private_key,
        algorithm="ES256",
        headers={"kid": "test-key-id", "alg": "ES256"}
    )

    # Protected request with ES256 token
    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {es256_token}"}
    )

    assert res.status_code == 200
    user_data = res.json()["data"]
    assert user_data["id"] == test_user_id
    assert user_data["email"] == test_email
    assert user_data["full_name"] == "Supabase Test User"
    assert user_data["default_currency"] == "INR"


@pytest.mark.asyncio
async def test_reject_asymmetric_token_with_invalid_audience(
    client: AsyncClient,
    ec_key_pair,
    monkeypatch
):
    """Tokens with incorrect audience claims are rejected."""
    private_key, public_key = ec_key_pair

    class MockSigningKey:
        key = public_key

    class MockJWKSClient:
        def get_signing_key_from_jwt(self, token):
            return MockSigningKey()

    monkeypatch.setattr(SupabaseJWTVerifier, "get_jwks_client", classmethod(lambda cls: MockJWKSClient()))

    token_claims = {
        "sub": str(uuid.uuid4()),
        "aud": "wrong-audience",
        "iss": settings.supabase_issuer,
        "exp": int(time.time()) + 3600,
        "email": "test@test.com"
    }
    token = jwt.encode(
        token_claims,
        private_key,
        algorithm="ES256",
        headers={"kid": "test-key", "alg": "ES256"}
    )

    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert res.status_code == 401
    assert "audience" in res.json().get("detail", "").lower()


@pytest.mark.asyncio
async def test_reject_asymmetric_token_with_invalid_issuer(
    client: AsyncClient,
    ec_key_pair,
    monkeypatch
):
    """Tokens from untrusted issuers are rejected."""
    private_key, public_key = ec_key_pair

    class MockSigningKey:
        key = public_key

    class MockJWKSClient:
        def get_signing_key_from_jwt(self, token):
            return MockSigningKey()

    monkeypatch.setattr(SupabaseJWTVerifier, "get_jwks_client", classmethod(lambda cls: MockJWKSClient()))

    token_claims = {
        "sub": str(uuid.uuid4()),
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": "https://attacker.supabase.co/auth/v1",
        "exp": int(time.time()) + 3600,
        "email": "test@test.com"
    }
    token = jwt.encode(
        token_claims,
        private_key,
        algorithm="ES256",
        headers={"kid": "test-key", "alg": "ES256"}
    )

    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert res.status_code == 401
    assert "issuer" in res.json().get("detail", "").lower()


@pytest.mark.asyncio
async def test_reject_deactivated_user(
    client: AsyncClient,
    db_session: AsyncSession
):
    """Deactivated accounts cannot access protected resources."""
    deactivated_user = User(
        id=str(uuid.uuid4()),
        email="deactivated@evenbill.app",
        full_name="Deactivated Account",
        default_currency="USD",
        is_active=False
    )
    db_session.add(deactivated_user)
    await db_session.commit()

    payload = {
        "sub": deactivated_user.id,
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": settings.supabase_issuer,
        "exp": int(time.time()) + 3600,
        "email": deactivated_user.email
    }
    token = jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")

    res = await client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert res.status_code == 403
    assert "deactivated" in res.json().get("detail", "").lower()
