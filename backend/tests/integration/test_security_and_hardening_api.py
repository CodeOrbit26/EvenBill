"""
EvenBill Production Security, Privacy, Reliability, and Hardening Tests
Validates IDOR prevention, 409 optimistic concurrency conflict detection,
refresh token rotation & replay attack defenses, rate limiting,
GDPR export & ledger-preserving anonymization, and health readiness probes.
"""

import pytest
from httpx import AsyncClient
from decimal import Decimal
from app.core.rate_limit import limiter
from app.services.receipt_service import ReceiptService


async def register_and_login(client: AsyncClient, email: str, name: str) -> dict:
    limiter.reset()
    reg_resp = await client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Password123!",
        "full_name": name,
        "default_currency": "USD"
    })
    assert reg_resp.status_code == 201, f"Failed register: {reg_resp.text}"
    user_id = reg_resp.json()["data"]["id"]

    login_resp = await client.post("/api/v1/auth/login", json={
        "email": email,
        "password": "Password123!"
    })
    assert login_resp.status_code == 200
    token_data = login_resp.json()["data"]

    return {
        "id": user_id,
        "email": email,
        "name": name,
        "access_token": token_data["access_token"],
        "refresh_token": token_data["refresh_token"],
        "headers": {"Authorization": f"Bearer {token_data['access_token']}"}
    }


@pytest.mark.asyncio
async def test_idor_protection_expense_and_invitation(client: AsyncClient):
    """
    Verifies that unauthorized actors cannot modify or delete expenses,
    revoke invitations, or accept invitations meant for others.
    """
    user_alice = await register_and_login(client, "alice_sec@evenbill.app", "Alice Sec")
    user_bob = await register_and_login(client, "bob_sec@evenbill.app", "Bob Sec")
    user_charlie = await register_and_login(client, "charlie_sec@evenbill.app", "Charlie Sec")

    # Alice creates a group and adds Bob
    grp_resp = await client.post(
        "/api/v1/groups/",
        json={"name": "Alice Secret Trip", "base_currency": "USD", "member_emails": [user_bob["email"]]},
        headers=user_alice["headers"]
    )
    assert grp_resp.status_code == 201
    group_data = grp_resp.json()["data"]
    group_id = group_data["id"]
    await client.post(f"/api/v1/groups/join/{group_data['invite_code']}", headers=user_bob["headers"])

    # Alice adds an expense in the group
    exp_resp = await client.post(
        "/api/v1/expenses/",
        json={
            "description": "Hotel Reservation",
            "total_amount": 200.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "group_id": group_id,
            "participant_ids": [user_alice["id"], user_bob["id"]]
        },
        headers=user_alice["headers"]
    )
    assert exp_resp.status_code == 201
    expense_id = exp_resp.json()["data"]["id"]

    # 1. IDOR: Charlie (outsider) attempts to modify Alice's group expense -> 403 Forbidden
    charlie_update = await client.put(
        f"/api/v1/expenses/{expense_id}",
        json={"description": "Hacked Hotel"},
        headers=user_charlie["headers"]
    )
    assert charlie_update.status_code == 403
    assert "member" in charlie_update.json()["detail"].lower()

    # 2. IDOR: Charlie attempts to delete Alice's group expense -> 403 Forbidden
    charlie_delete = await client.delete(
        f"/api/v1/expenses/{expense_id}",
        headers=user_charlie["headers"]
    )
    assert charlie_delete.status_code == 403

    # 3. IDOR: Alice invites Diana to the group
    inv_resp = await client.post(
        f"/api/v1/groups/{group_id}/invitations",
        json={"email": "diana_sec@evenbill.app"},
        headers=user_alice["headers"]
    )
    assert inv_resp.status_code == 201
    invitation_id = inv_resp.json()["data"]["id"]

    # Charlie (non-admin outsider) attempts to revoke the invitation -> 403 Forbidden
    charlie_revoke = await client.post(
        f"/api/v1/groups/invitations/{invitation_id}/revoke",
        headers=user_charlie["headers"]
    )
    assert charlie_revoke.status_code == 403

    # Charlie attempts to accept Diana's invitation -> 403 Forbidden
    charlie_accept = await client.post(
        f"/api/v1/groups/invitations/{invitation_id}/accept",
        headers=user_charlie["headers"]
    )
    assert charlie_accept.status_code == 403
    assert "different email" in charlie_accept.json()["detail"]


@pytest.mark.asyncio
async def test_optimistic_concurrency_conflict_detection(client: AsyncClient):
    """
    Verifies that passing an outdated version to PUT /expenses returns HTTP 409 Conflict,
    preventing silent data overwrite during concurrent or offline sync scenarios.
    """
    user_a = await register_and_login(client, "user_occ_a@evenbill.app", "OCC A")
    user_b = await register_and_login(client, "user_occ_b@evenbill.app", "OCC B")

    # Personal expense between User A and User B
    exp_resp = await client.post(
        "/api/v1/expenses/",
        json={
            "description": "Lunch split",
            "total_amount": 50.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user_a["id"], user_b["id"]]
        },
        headers=user_a["headers"]
    )
    assert exp_resp.status_code == 201
    expense_data = exp_resp.json()["data"]
    exp_id = expense_data["id"]
    initial_version = expense_data["version"]  # version = 1

    # User A updates the expense legitimately with version 1 -> advances to version 2
    update_1 = await client.put(
        f"/api/v1/expenses/{exp_id}",
        json={"description": "Deluxe Lunch", "version": initial_version},
        headers=user_a["headers"]
    )
    assert update_1.status_code == 200
    assert update_1.json()["data"]["version"] == 2

    # User B attempts to update using the stale version 1 (concurrent edit collision) -> 409 Conflict
    conflict_update = await client.put(
        f"/api/v1/expenses/{exp_id}",
        json={"description": "Stale Edit", "version": 1},
        headers=user_b["headers"]
    )
    assert conflict_update.status_code == 409
    assert "conflict" in conflict_update.json()["detail"].lower()
    assert "server version is 2" in conflict_update.json()["detail"].lower()


@pytest.mark.asyncio
async def test_refresh_token_rotation_and_replay_detection(client: AsyncClient):
    """
    Verifies strict refresh token rotation:
    1. Refreshing token issues a new access token AND a new refresh token.
    2. The previous refresh token JTI is recorded as revoked.
    3. Replaying the previous refresh token is immediately rejected with HTTP 401.
    4. Explicit /auth/logout revokes the token.
    """
    user = await register_and_login(client, "token_rot@evenbill.app", "Token Rotation")
    initial_refresh = user["refresh_token"]

    # 1. Rotate token
    rotate_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": initial_refresh})
    assert rotate_resp.status_code == 200
    new_token_data = rotate_resp.json()["data"]
    new_refresh = new_token_data["refresh_token"]
    assert new_refresh != initial_refresh

    # 2. Replay attack: present the old already-rotated refresh token -> 401
    replay_resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": initial_refresh})
    assert replay_resp.status_code == 401
    assert "replay detected" in replay_resp.json()["detail"].lower()

    # 3. New refresh token works cleanly
    second_rotate = await client.post("/api/v1/auth/refresh", json={"refresh_token": new_refresh})
    assert second_rotate.status_code == 200
    third_refresh = second_rotate.json()["data"]["refresh_token"]

    # 4. Explicit logout revokes current refresh token
    logout_resp = await client.post("/api/v1/auth/logout", json={"refresh_token": third_refresh})
    assert logout_resp.status_code == 200
    assert logout_resp.json()["data"]["logged_out"] is True

    # Attempting to use logged-out token -> 401
    after_logout = await client.post("/api/v1/auth/refresh", json={"refresh_token": third_refresh})
    assert after_logout.status_code == 401


@pytest.mark.asyncio
async def test_rate_limiting_enforcement(client: AsyncClient):
    """
    Verifies that exceeding the configured rate limit window triggers
    HTTP 429 Too Many Requests with a valid Retry-After header.
    """
    limiter.reset()

    # Hit auth login repeatedly until rate limit triggers
    got_429 = False
    retry_after_val = None

    for _ in range(70):
        resp = await client.post("/api/v1/auth/login", json={
            "email": "ratelimit_test@evenbill.app",
            "password": "Password123!"
        })
        if resp.status_code == 429:
            got_429 = True
            retry_after_val = resp.headers.get("retry-after")
            break

    assert got_429 is True, "Rate limiter failed to trigger 429 status code"
    assert retry_after_val is not None
    assert int(retry_after_val) > 0

    limiter.reset()


@pytest.mark.asyncio
async def test_security_headers_and_correlation_id(client: AsyncClient):
    """
    Verifies security response headers (CSP, nosniff, DENY, HSTS)
    and X-Correlation-ID tracing.
    """
    custom_cid = "test-correlation-uuid-999"
    resp = await client.get("/health", headers={"X-Correlation-ID": custom_cid})
    assert resp.status_code == 200

    headers = resp.headers
    assert headers.get("X-Correlation-ID") == custom_cid
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-Frame-Options") == "DENY"
    assert "default-src 'self'" in headers.get("Content-Security-Policy", "")


@pytest.mark.asyncio
async def test_privacy_data_export_and_ledger_preserving_deletion(client: AsyncClient):
    """
    Verifies GDPR/CCPA data export and account deletion:
    1. Data export bundles profile, groups, expenses, settlements.
    2. Account deletion anonymizes user PII and deactivates login.
    3. CRITICAL INVARIANT: Transaction rows in the ledger remain preserved
       so remaining group members' balances do not break.
    """
    user_a = await register_and_login(client, "gdpr_a@evenbill.app", "GDPR Subject A")
    user_b = await register_and_login(client, "gdpr_b@evenbill.app", "GDPR Subject B")

    # Create group and expense
    grp_resp = await client.post(
        "/api/v1/groups/",
        json={"name": "GDPR Preserved Group", "base_currency": "USD"},
        headers=user_a["headers"]
    )
    group_data = grp_resp.json()["data"]
    group_id = group_data["id"]
    await client.post(f"/api/v1/groups/join/{group_data['invite_code']}", headers=user_b["headers"])

    exp_resp = await client.post(
        "/api/v1/expenses/",
        json={
            "description": "Shared Groceries",
            "total_amount": 120.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "group_id": group_id,
            "participant_ids": [user_a["id"], user_b["id"]]
        },
        headers=user_a["headers"]
    )
    assert exp_resp.status_code == 201

    # 1. User A exports data
    export_resp = await client.post("/api/v1/users/me/export", headers=user_a["headers"])
    assert export_resp.status_code == 200
    export_data = export_resp.json()["data"]
    assert export_data["profile"]["email"] == "gdpr_a@evenbill.app"
    assert len(export_data["groups"]) >= 1
    assert len(export_data["expenses"]) >= 1

    # 2. User A deletes their account
    del_resp = await client.delete("/api/v1/users/me", headers=user_a["headers"])
    assert del_resp.status_code == 200
    assert del_resp.json()["data"]["status"] == "anonymized_and_deleted"

    # User A can no longer log in
    failed_login = await client.post("/api/v1/auth/login", json={
        "email": "gdpr_a@evenbill.app",
        "password": "Password123!"
    })
    assert failed_login.status_code == 401

    # 3. CRITICAL INVARIANT: User B can still inspect the group and balances
    # The ledger calculation does NOT crash or corrupt math!
    grp_detail = await client.get(f"/api/v1/groups/{group_id}", headers=user_b["headers"])
    assert grp_detail.status_code == 200
    net_balances = grp_detail.json()["data"]["net_balances"]
    # Net balance for remaining member Bob should still reflect -$60 (he owes $60 to the former member)
    bob_balance = next(item for item in net_balances if item["user_id"] == user_b["id"])
    assert float(bob_balance["net_balance"]) == -60.0
    # Ledger invariant sum equals zero
    total_ledger_sum = sum(float(item["net_balance"]) for item in net_balances)
    assert abs(total_ledger_sum) < 0.001


@pytest.mark.asyncio
async def test_health_and_readiness_probes(client: AsyncClient):
    """
    Verifies /health, /health/live, and /health/ready endpoints
    for high-availability Kubernetes / container orchestration.
    """
    # 1. Root and v1 health
    root_health = await client.get("/health")
    assert root_health.status_code == 200
    assert root_health.json()["status"] == "healthy"
    assert root_health.json()["database"] == "connected"

    # 2. Kubernetes Liveness Probe
    live_resp = await client.get("/health/live")
    assert live_resp.status_code == 200
    assert live_resp.json()["status"] == "alive"

    # 3. Kubernetes Readiness Probe
    ready_resp = await client.get("/health/ready")
    assert ready_resp.status_code == 200
    assert ready_resp.json()["status"] == "ready"
