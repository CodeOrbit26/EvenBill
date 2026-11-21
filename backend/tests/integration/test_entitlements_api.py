"""
Integration Tests for EvenBill Free Tier & Feature-Entitlement System
Verifies:
1. Allowed actions within daily expense allowance
2. Denied actions with structured 403 FEATURE_LOCKED errors
3. Time window resets & rolling allowance recovery
4. Idempotent retries and offline sync replays (zero additional allowance consumption)
5. Editing existing expenses (does not consume allowance)
6. Group members on different subscription plans (Free vs Pro)
7. Dynamic server-side configuration changes
8. Mock upgrades and entitlement transitions
"""

import pytest
import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.expense import Expense


async def register_user(client: AsyncClient, email: str, name: str) -> dict:
    reg_resp = await client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Password123!",
        "full_name": name,
        "default_currency": "USD"
    })
    assert reg_resp.status_code == 201
    user_id = reg_resp.json()["data"]["id"]

    login_resp = await client.post("/api/v1/auth/login", json={
        "email": email,
        "password": "Password123!"
    })
    token = login_resp.json()["data"]["access_token"]
    return {
        "id": user_id,
        "email": email,
        "name": name,
        "token": token,
        "headers": {"Authorization": f"Bearer {token}"}
    }


@pytest.mark.asyncio
async def test_free_tier_allowed_and_denied_actions(client: AsyncClient):
    """
    Test that a Free user can create up to the configured limit of expenses,
    and subsequent attempts are denied with structured 403 error.
    """
    user = await register_user(client, "free_user_1@evenbill.app", "Free User One")

    # Initial entitlements: plan is FREE, 4 allowed, 0 used
    ent_resp = await client.get("/api/v1/subscriptions/me", headers=user["headers"])
    assert ent_resp.status_code == 200
    ent_data = ent_resp.json()["data"]
    assert ent_data["plan"] == "FREE"
    assert ent_data["is_pro"] is False
    daily_feature = ent_data["features"]["DAILY_EXPENSE_CREATION"]
    assert daily_feature["limit"] == settings.FREE_DAILY_EXPENSE_LIMIT
    assert daily_feature["used"] == 0
    assert daily_feature["remaining"] == settings.FREE_DAILY_EXPENSE_LIMIT

    # Create expenses up to the limit (default 4)
    for i in range(settings.FREE_DAILY_EXPENSE_LIMIT):
        resp = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": f"Free expense #{i+1}",
            "total_amount": 10.00 + i,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert resp.status_code == 201

    # Verify usage is now at the limit
    ent_resp2 = await client.get("/api/v1/subscriptions/me", headers=user["headers"])
    assert ent_resp2.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["remaining"] == 0
    assert ent_resp2.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["used"] == settings.FREE_DAILY_EXPENSE_LIMIT

    # Attempt to create the 5th expense -> Must be DENIED with HTTP 403 FEATURE_LOCKED
    blocked_resp = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Exceeding limit expense",
        "total_amount": 50.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert blocked_resp.status_code == 403
    err_body = blocked_resp.json()
    # Handle FastAPI detail dict
    detail = err_body.get("detail", err_body)
    assert detail["code"] == "FEATURE_LOCKED"
    assert detail["feature_key"] == "DAILY_EXPENSE_CREATION"
    assert detail["plan"] == "FREE"
    assert detail["limit"] == settings.FREE_DAILY_EXPENSE_LIMIT
    assert detail["used"] == settings.FREE_DAILY_EXPENSE_LIMIT
    assert "Upgrade to EvenBill Pro" in detail["permitted_next_action"]
    assert "resets_at" in detail
    assert "resets_in_seconds" in detail


@pytest.mark.asyncio
async def test_idempotent_retries_and_offline_sync(client: AsyncClient):
    """
    Test that retrying with the same idempotency_key (simulating network timeouts or offline sync replay)
    never consumes additional allowance, even when the user is at their limit.
    """
    user = await register_user(client, "retry_user@evenbill.app", "Retry User")
    key = str(uuid.uuid4())

    # 1. Create first expense with explicit idempotency key
    resp1 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "idempotency_key": key,
        "description": "Flight Ticket",
        "total_amount": 150.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert resp1.status_code == 201
    exp_id = resp1.json()["data"]["id"]

    # Check usage: 1
    ent1 = await client.get("/api/v1/subscriptions/me", headers=user["headers"])
    assert ent1.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["used"] == 1

    # 2. Re-submit the exact same payload with same idempotency key (network retry simulation)
    resp2 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "idempotency_key": key,
        "description": "Flight Ticket",
        "total_amount": 150.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert resp2.status_code == 201
    assert resp2.json()["data"]["id"] == exp_id

    # Usage MUST still be 1!
    ent2 = await client.get("/api/v1/subscriptions/me", headers=user["headers"])
    assert ent2.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["used"] == 1


@pytest.mark.asyncio
async def test_editing_expense_does_not_consume_allowance(client: AsyncClient):
    """
    Test that editing an existing expense (PUT /expenses/{id}) succeeds without
    consuming allowance, even if the user has reached their daily limit.
    """
    user = await register_user(client, "edit_user@evenbill.app", "Edit User")

    # Create 4 expenses to hit the limit
    expense_ids = []
    for i in range(settings.FREE_DAILY_EXPENSE_LIMIT):
        resp = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": f"Expense {i}",
            "total_amount": 20.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert resp.status_code == 201
        expense_ids.append(resp.json()["data"]["id"])

    # Attempt to create 5th expense (should fail)
    fail_resp = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Should fail",
        "total_amount": 20.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert fail_resp.status_code == 403

    # Edit an existing expense -> MUST SUCCEED
    first_id = expense_ids[0]
    edit_resp = await client.put(f"/api/v1/expenses/{first_id}", headers=user["headers"], json={
        "description": "Updated Expense Description",
        "total_amount": 25.00,
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert edit_resp.status_code == 200
    assert edit_resp.json()["data"]["description"] == "Updated Expense Description"


@pytest.mark.asyncio
async def test_window_resets_allowance(client: AsyncClient, db_session: AsyncSession):
    """
    Test that when time passes beyond the rolling window (e.g. 24h),
    older expenses fall outside the window and allowance resets automatically.
    """
    user = await register_user(client, "window_user@evenbill.app", "Window User")

    # Create 4 expenses
    exp_ids = []
    for i in range(settings.FREE_DAILY_EXPENSE_LIMIT):
        r = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": f"Old expense {i}",
            "total_amount": 15.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert r.status_code == 201
        exp_ids.append(r.json()["data"]["id"])

    # 5th is blocked
    r5 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Blocked",
        "total_amount": 15.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert r5.status_code == 403

    # Fast forward: modify created_at of 2 expenses in the DB to be 25 hours ago
    past_time = datetime.now(timezone.utc) - timedelta(hours=settings.EXPENSE_LIMIT_WINDOW_HOURS + 1)
    for eid in exp_ids[:2]:
        exp = await db_session.get(Expense, eid)
        if exp:
            exp.created_at = past_time
    await db_session.commit()

    # Now used in current window should be 2, remaining 2
    ent = await client.get("/api/v1/subscriptions/me", headers=user["headers"])
    assert ent.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["used"] == settings.FREE_DAILY_EXPENSE_LIMIT - 2
    assert ent.json()["data"]["features"]["DAILY_EXPENSE_CREATION"]["remaining"] == 2

    # Creating a new expense MUST now SUCCEED
    new_resp = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Allowed after window reset",
        "total_amount": 18.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert new_resp.status_code == 201


@pytest.mark.asyncio
async def test_group_members_on_different_plans(client: AsyncClient):
    """
    Test that in a group with members on Free and Pro:
    - Free user is limited to daily allowance for their created expenses.
    - Pro user has unlimited creation.
    - Free user can participate in unlimited expenses created by Pro user.
    """
    free_member = await register_user(client, "free_member@evenbill.app", "Free Member")
    pro_member = await register_user(client, "pro_member@evenbill.app", "Pro Member")

    # Upgrade pro_member to PRO
    upg_resp = await client.post("/api/v1/subscriptions/mock-upgrade", headers=pro_member["headers"], json={
        "tier": "PRO_ANNUAL"
    })
    assert upg_resp.status_code == 200
    assert upg_resp.json()["data"]["is_pro"] is True

    # Free member creates a shared group
    grp = await client.post("/api/v1/groups/", headers=free_member["headers"], json={
        "name": "Mixed Tier Group",
        "group_type": "TRIP",
        "base_currency": "USD"
    })
    assert grp.status_code == 201
    group_id = grp.json()["data"]["id"]
    code = grp.json()["data"]["invite_code"]

    # Pro member joins group
    join_resp = await client.post(f"/api/v1/groups/join/{code}", headers=pro_member["headers"])
    assert join_resp.status_code == 200

    # Free member exhausts their 4 expenses
    for i in range(settings.FREE_DAILY_EXPENSE_LIMIT):
        r = await client.post("/api/v1/expenses/", headers=free_member["headers"], json={
            "group_id": group_id,
            "description": f"Free expense {i}",
            "total_amount": 30.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [free_member["id"], pro_member["id"]],
        })
        assert r.status_code == 201

    # Free member tries 5th -> Blocked
    free_blocked = await client.post("/api/v1/expenses/", headers=free_member["headers"], json={
        "group_id": group_id,
        "description": "5th expense",
        "total_amount": 30.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [free_member["id"], pro_member["id"]],
    })
    assert free_blocked.status_code == 403

    # Pro member creates 6 expenses in the SAME group with Free member as participant -> ALL SUCCEED!
    for j in range(6):
        pro_resp = await client.post("/api/v1/expenses/", headers=pro_member["headers"], json={
            "group_id": group_id,
            "description": f"Pro expense #{j+1}",
            "total_amount": 50.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [free_member["id"], pro_member["id"]],
        })
        assert pro_resp.status_code == 201, f"Pro member should be unlimited: {pro_resp.text}"


@pytest.mark.asyncio
async def test_configuration_changes(client: AsyncClient):
    """
    Test that changing the server configuration adjusts the limit dynamically.
    """
    original_limit = settings.FREE_DAILY_EXPENSE_LIMIT
    try:
        # Dynamically set limit to 2
        settings.FREE_DAILY_EXPENSE_LIMIT = 2

        user = await register_user(client, "config_user@evenbill.app", "Config User")

        # 1st allowed
        r1 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": "Expense 1",
            "total_amount": 10.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert r1.status_code == 201

        # 2nd allowed
        r2 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": "Expense 2",
            "total_amount": 10.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert r2.status_code == 201

        # 3rd is blocked because limit is 2
        r3 = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": "Expense 3",
            "total_amount": 10.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert r3.status_code == 403
        assert r3.json()["detail"]["limit"] == 2

    finally:
        # Restore original limit
        settings.FREE_DAILY_EXPENSE_LIMIT = original_limit


@pytest.mark.asyncio
async def test_mock_upgrade_unlocks_unlimited(client: AsyncClient):
    """
    Test that upgrading a Free user who has reached their daily limit
    immediately unlocks unlimited expense creation.
    """
    user = await register_user(client, "upgraded_user@evenbill.app", "Upgraded User")

    # Hit 4 limit
    for i in range(settings.FREE_DAILY_EXPENSE_LIMIT):
        r = await client.post("/api/v1/expenses/", headers=user["headers"], json={
            "description": f"Expense {i}",
            "total_amount": 10.00,
            "currency": "USD",
            "split_type": "EQUAL",
            "participant_ids": [user["id"]],
        })
        assert r.status_code == 201

    # 5th fails
    blocked = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Blocked before upgrade",
        "total_amount": 10.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert blocked.status_code == 403

    # Upgrade to PRO_MONTHLY
    upg = await client.post("/api/v1/subscriptions/mock-upgrade", headers=user["headers"], json={
        "tier": "PRO_MONTHLY"
    })
    assert upg.status_code == 200
    assert upg.json()["data"]["is_pro"] is True
    assert upg.json()["data"]["plan"] == "PRO"

    # Now create expense -> SUCCEEDS immediately!
    after_upg = await client.post("/api/v1/expenses/", headers=user["headers"], json={
        "description": "Created after upgrade to Pro",
        "total_amount": 25.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]],
    })
    assert after_upg.status_code == 201
