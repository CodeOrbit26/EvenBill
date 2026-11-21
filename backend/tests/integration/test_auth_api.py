"""
Integration Tests for EvenBill Authentication API
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_and_login_flow(client: AsyncClient):
    # 1. Register
    reg_payload = {
        "email": "testuser@evenbill.app",
        "password": "SecurePassword123!",
        "full_name": "Test User",
        "default_currency": "USD"
    }
    reg_resp = await client.post("/api/v1/auth/register", json=reg_payload)
    assert reg_resp.status_code == 201
    reg_json = reg_resp.json()
    assert reg_json["success"] is True
    assert reg_json["data"]["email"] == "testuser@evenbill.app"
    assert reg_json["data"]["full_name"] == "Test User"
    assert reg_json["data"]["default_currency"] == "USD"
    assert reg_json["data"]["is_pro"] is False

    # 2. Duplicate registration should fail
    dup_resp = await client.post("/api/v1/auth/register", json=reg_payload)
    assert dup_resp.status_code == 409

    # 3. Login with wrong password
    bad_login_resp = await client.post("/api/v1/auth/login", json={
        "email": "testuser@evenbill.app",
        "password": "WrongPassword!"
    })
    assert bad_login_resp.status_code == 401

    # 4. Login with correct password
    login_resp = await client.post("/api/v1/auth/login", json={
        "email": "testuser@evenbill.app",
        "password": "SecurePassword123!"
    })
    assert login_resp.status_code == 200
    token_data = login_resp.json()["data"]
    assert "access_token" in token_data
    assert "refresh_token" in token_data
    access_token = token_data["access_token"]
    refresh_token = token_data["refresh_token"]

    # 5. Access /auth/me with Bearer token
    headers = {"Authorization": f"Bearer {access_token}"}
    me_resp = await client.get("/api/v1/auth/me", headers=headers)
    assert me_resp.status_code == 200
    me_data = me_resp.json()["data"]
    assert me_data["email"] == "testuser@evenbill.app"

    # 6. Refresh token
    refresh_resp = await client.post("/api/v1/auth/refresh", json={
        "refresh_token": refresh_token
    })
    assert refresh_resp.status_code == 200
    new_token_data = refresh_resp.json()["data"]
    assert "access_token" in new_token_data
    assert new_token_data["access_token"] != access_token


@pytest.mark.asyncio
async def test_oauth_google_and_apple_flow(client: AsyncClient):
    # 1. Google OAuth login/register
    google_payload = {
        "provider": "google",
        "email": "alex.oauth@gmail.com",
        "full_name": "Alex Google",
        "avatar_url": "https://example.com/avatar.jpg"
    }
    resp = await client.post("/api/v1/auth/oauth", json=google_payload)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert "access_token" in data
    assert "refresh_token" in data

    # Verify user profile created
    token = data["access_token"]
    me_resp = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me_resp.status_code == 200
    me = me_resp.json()["data"]
    assert me["email"] == "alex.oauth@gmail.com"
    assert me["full_name"] == "Alex Google"
    assert me["is_verified"] is True

    # 2. Apple OAuth login
    apple_payload = {
        "provider": "apple",
        "email": "alex.apple@privaterelay.appleid.com",
        "full_name": "Alex Apple"
    }
    apple_resp = await client.post("/api/v1/auth/oauth", json=apple_payload)
    assert apple_resp.status_code == 200
    assert "access_token" in apple_resp.json()["data"]

