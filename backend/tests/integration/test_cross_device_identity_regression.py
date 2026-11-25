"""
Regression tests for cross-device identity restoration, UUID validation, and
multi-member expense creation across backend auth, group, and ledger APIs.
"""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
import uuid

import jwt
import pytest
from httpx import AsyncClient
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.endpoints.split_templates import SplitAllocationItem
from app.core.config import settings
from app.models.group import GroupMember
from app.models.user import Subscription, User


def _mint_supabase_jwt(
    *,
    user_id: str,
    email: str,
    full_name: str = "EvenBill User",
) -> str:
    now = datetime.now(timezone.utc)
    secret = settings.SUPABASE_JWT_SECRET or settings.SECRET_KEY
    payload = {
        "sub": user_id,
        "aud": settings.SUPABASE_AUDIENCE,
        "iss": settings.supabase_issuer,
        "email": email,
        "email_verified": True,
        "user_metadata": {"full_name": full_name},
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=1)).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _unwrap(body):
    if isinstance(body, dict) and "data" in body:
        return body["data"]
    return body


@pytest.mark.asyncio
async def test_expense_creation_with_authenticated_uuid_and_multiple_members(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Criteria 1 & 2: Creating expenses with the authenticated user's actual UUID
    and multiple group members succeeds and records exact UUIDs across payers and splits.
    """
    user1_id = str(uuid.uuid4())
    user2_id = str(uuid.uuid4())
    user3_id = str(uuid.uuid4())

    tok1 = _mint_supabase_jwt(user_id=user1_id, email="u1@evenbill.test", full_name="Alice")
    tok2 = _mint_supabase_jwt(user_id=user2_id, email="u2@evenbill.test", full_name="Bob")
    tok3 = _mint_supabase_jwt(user_id=user3_id, email="u3@evenbill.test", full_name="Charlie")

    for tok, expected_id in ((tok1, user1_id), (tok2, user2_id), (tok3, user3_id)):
        me_resp = await client.get("/api/v1/auth/me", headers=_auth_headers(tok))
        assert me_resp.status_code == 200, me_resp.text
        assert _unwrap(me_resp.json())["id"] == expected_id

    # User 1 creates a group and adds User 2 & User 3
    grp_resp = await client.post(
        "/api/v1/groups/",
        headers=_auth_headers(tok1),
        json={"name": "Goa Villa", "group_type": "TRIP", "base_currency": "USD"},
    )
    assert grp_resp.status_code == 201, grp_resp.text
    group_id = _unwrap(grp_resp.json())["id"]

    db_session.add(GroupMember(group_id=group_id, user_id=user2_id, role="MEMBER"))
    db_session.add(GroupMember(group_id=group_id, user_id=user3_id, role="MEMBER"))
    await db_session.flush()

    # Equal split across all 3 members with User 1 paying
    exp_resp = await client.post(
        "/api/v1/expenses/",
        headers=_auth_headers(tok1),
        json={
            "group_id": group_id,
            "description": "Villa Stay",
            "total_amount": "90.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": user1_id, "amount_paid": "90.00"}],
            "participant_ids": [user1_id, user2_id, user3_id],
        },
    )
    assert exp_resp.status_code == 201, exp_resp.text
    exp_data = _unwrap(exp_resp.json())
    assert [p["user_id"] for p in exp_data["payers"]] == [user1_id]
    assert {s["user_id"] for s in exp_data["splits"]} == {user1_id, user2_id, user3_id}
    assert all(Decimal(str(s["owed_amount"])) == Decimal("30.00") for s in exp_data["splits"])

    # Percentage split using UUID dict keys
    pct_resp = await client.post(
        "/api/v1/expenses/",
        headers=_auth_headers(tok2),
        json={
            "group_id": group_id,
            "description": "Dinner",
            "total_amount": "100.00",
            "currency": "USD",
            "split_type": "PERCENTAGE",
            "payers": [{"user_id": user2_id, "amount_paid": "100.00"}],
            "percentages": {user1_id: "50", user2_id: "25", user3_id: "25"},
        },
    )
    assert pct_resp.status_code == 201, pct_resp.text


@pytest.mark.asyncio
async def test_same_supabase_account_on_two_devices_restores_data_without_duplicates(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Criteria 3, 4 & 7: Same Supabase user signing in on a second device resolves
    the exact same profile UUID, restores all groups and expenses, and creates no duplicate profiles.
    """
    canonical_uuid = str(uuid.uuid4())
    email = "crossdevice@evenbill.test"

    # Phone 1 session
    phone1_token = _mint_supabase_jwt(user_id=canonical_uuid, email=email, full_name="Primary Phone")
    me1 = await client.get("/api/v1/auth/me", headers=_auth_headers(phone1_token))
    assert me1.status_code == 200, me1.text
    assert _unwrap(me1.json())["id"] == canonical_uuid

    grp = await client.post(
        "/api/v1/groups/",
        headers=_auth_headers(phone1_token),
        json={"name": "Shared Flat", "group_type": "HOME", "base_currency": "USD"},
    )
    assert grp.status_code == 201, grp.text
    group_id = _unwrap(grp.json())["id"]

    exp = await client.post(
        "/api/v1/expenses/",
        headers=_auth_headers(phone1_token),
        json={
            "group_id": group_id,
            "description": "Internet Bill",
            "total_amount": "45.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": canonical_uuid, "amount_paid": "45.00"}],
            "participant_ids": [canonical_uuid],
        },
    )
    assert exp.status_code == 201, exp.text

    # Phone 2 obtains a fresh JWT for the exact same Supabase `sub`
    phone2_token = _mint_supabase_jwt(user_id=canonical_uuid, email=email, full_name="Primary Phone")
    me2 = await client.get("/api/v1/auth/me", headers=_auth_headers(phone2_token))
    assert me2.status_code == 200, me2.text
    assert _unwrap(me2.json())["id"] == canonical_uuid

    groups_resp = await client.get("/api/v1/groups/", headers=_auth_headers(phone2_token))
    assert groups_resp.status_code == 200, groups_resp.text
    groups = _unwrap(groups_resp.json())
    assert [g["id"] for g in groups] == [group_id]
    assert groups[0]["name"] == "Shared Flat"

    expenses_resp = await client.get(
        f"/api/v1/expenses/group/{group_id}",
        headers=_auth_headers(phone2_token),
    )
    assert expenses_resp.status_code == 200, expenses_resp.text
    expenses = _unwrap(expenses_resp.json())
    assert len(expenses) == 1
    assert expenses[0]["description"] == "Internet Bill"

    # Re-verify zero duplicate profile or subscription rows exist
    profile_count = await db_session.scalar(
        select(func.count()).select_from(User).where(User.email == email)
    )
    sub_count = await db_session.scalar(
        select(func.count()).select_from(Subscription).where(Subscription.user_id == canonical_uuid)
    )
    assert profile_count == 1
    assert sub_count == 1


@pytest.mark.asyncio
async def test_email_collision_across_different_supabase_uuids_preserves_financial_data(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Section D safety: Never silently merge or overwrite an existing profile when a
    different Supabase `sub` presents the same email address; reject with HTTP 409.
    """
    existing_uuid = str(uuid.uuid4())
    different_uuid = str(uuid.uuid4())
    shared_email = "protected@evenbill.test"

    existing_token = _mint_supabase_jwt(user_id=existing_uuid, email=shared_email, full_name="Original")
    assert (await client.get("/api/v1/auth/me", headers=_auth_headers(existing_token))).status_code == 200

    grp = await client.post(
        "/api/v1/groups/",
        headers=_auth_headers(existing_token),
        json={"name": "Protected Ledger", "group_type": "OTHER", "base_currency": "USD"},
    )
    assert grp.status_code == 201, grp.text

    colliding_token = _mint_supabase_jwt(user_id=different_uuid, email=shared_email, full_name="Duplicate")
    collision_resp = await client.get("/api/v1/auth/me", headers=_auth_headers(colliding_token))
    assert collision_resp.status_code == 409

    # Existing user and group remain untouched
    check_resp = await client.get("/api/v1/groups/", headers=_auth_headers(existing_token))
    assert check_resp.status_code == 200
    assert len(_unwrap(check_resp.json())) == 1
    profile_count = await db_session.scalar(
        select(func.count()).select_from(User).where(User.email == shared_email)
    )
    assert profile_count == 1


@pytest.mark.asyncio
async def test_rejects_placeholder_and_invalid_uuids_across_endpoints(
    client: AsyncClient,
):
    """
    Criteria 6: Placeholders ('current_user', 'usr_me') and malformed UUIDs are rejected
    with HTTP 422, while unknown or non-member UUIDs are rejected before persisting.
    """
    user_id = str(uuid.uuid4())
    outsider_id = str(uuid.uuid4())
    unknown_id = str(uuid.uuid4())

    tok = _mint_supabase_jwt(user_id=user_id, email="validator@evenbill.test")
    outsider_tok = _mint_supabase_jwt(user_id=outsider_id, email="outsider@evenbill.test")
    assert (await client.get("/api/v1/auth/me", headers=_auth_headers(tok))).status_code == 200
    assert (await client.get("/api/v1/auth/me", headers=_auth_headers(outsider_tok))).status_code == 200

    grp = await client.post(
        "/api/v1/groups/",
        headers=_auth_headers(tok),
        json={"name": "Strict UUID Group", "group_type": "OTHER", "base_currency": "USD"},
    )
    assert grp.status_code == 201
    group_id = _unwrap(grp.json())["id"]

    invalid_payloads = [
        {
            "group_id": group_id,
            "description": "Placeholder payer",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": "current_user", "amount_paid": "10.00"}],
            "participant_ids": [user_id],
        },
        {
            "group_id": group_id,
            "description": "Placeholder participant",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": user_id, "amount_paid": "10.00"}],
            "participant_ids": ["usr_me"],
        },
        {
            "group_id": group_id,
            "description": "Placeholder percentages key",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "PERCENTAGE",
            "payers": [{"user_id": user_id, "amount_paid": "10.00"}],
            "percentages": {"current_user": "100"},
        },
        {
            "group_id": group_id,
            "description": "Placeholder shares key",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "SHARES",
            "payers": [{"user_id": user_id, "amount_paid": "10.00"}],
            "shares": {"not-a-uuid": 1},
        },
        {
            "group_id": group_id,
            "description": "Placeholder adjustments key",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "ADJUSTMENT",
            "payers": [{"user_id": user_id, "amount_paid": "10.00"}],
            "adjustments": {"usr_current": "0"},
        },
    ]

    for payload in invalid_payloads:
        res = await client.post("/api/v1/expenses/", headers=_auth_headers(tok), json=payload)
        assert res.status_code == 422, f"Expected 422 for {payload['description']}, got {res.status_code}: {res.text}"

    # Settlement schema also rejects placeholder UUIDs
    settle_bad = await client.post(
        "/api/v1/settlements/",
        headers=_auth_headers(tok),
        json={
            "group_id": group_id,
            "payer_id": "current_user",
            "recipient_id": user_id,
            "amount": "10.00",
            "currency": "USD",
        },
    )
    assert settle_bad.status_code == 422

    # SplitAllocationItem validates UUIDStr
    with pytest.raises(ValidationError):
        SplitAllocationItem(user_id="current_user", value=50.0)

    # Unknown UUID returns 404; non-group-member returns 400
    unknown_res = await client.post(
        "/api/v1/expenses/",
        headers=_auth_headers(tok),
        json={
            "group_id": group_id,
            "description": "Unknown UUID",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": unknown_id, "amount_paid": "10.00"}],
            "participant_ids": [user_id],
        },
    )
    assert unknown_res.status_code == 404

    outsider_res = await client.post(
        "/api/v1/expenses/",
        headers=_auth_headers(tok),
        json={
            "group_id": group_id,
            "description": "Outsider UUID",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": outsider_id, "amount_paid": "10.00"}],
            "participant_ids": [user_id],
        },
    )
    assert outsider_res.status_code == 400
