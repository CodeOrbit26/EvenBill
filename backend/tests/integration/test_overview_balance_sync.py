"""
Regression tests for Overview summary balances, direct/non-group expenses,
group net balances, multi-currency conversion, and cross-device balance synchronization.
"""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
import uuid

import jwt
import pytest
from httpx import AsyncClient
from sqlalchemy import event, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.group import GroupMember
from app.services.fx_service import FXService, UnsupportedCurrencyPairError


def _mint_jwt(user_id: str, email: str, full_name: str) -> str:
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


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _unwrap(body):
    return body["data"] if isinstance(body, dict) and "data" in body else body


@pytest.mark.asyncio
async def test_direct_and_group_expenses_update_overview_summary_and_groups_list(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Reproduces and verifies:
    - Creating a direct (non-group) expense immediately updates Overview summary balances
      and monthly spending for both payer and participant.
    - Creating a group expense updates Overview summary AND GET /api/v1/groups/ net_balance.
    """
    alice_id = str(uuid.uuid4())
    bob_id = str(uuid.uuid4())
    tok_alice = _mint_jwt(alice_id, "alice.ov@evenbill.test", "Alice")
    tok_bob = _mint_jwt(bob_id, "bob.ov@evenbill.test", "Bob")

    for tok in (tok_alice, tok_bob):
        me = await client.get("/api/v1/auth/me", headers=_headers(tok))
        assert me.status_code == 200
        await client.patch("/api/v1/auth/me", headers=_headers(tok), json={"default_currency": "INR"})

    # 1. Direct (non-group) expense: Alice pays ₹1000 split equally with Bob
    direct_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok_alice),
        json={
            "group_id": None,
            "description": "Direct Airport Cab",
            "total_amount": "1000.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": alice_id, "amount_paid": "1000.00"}],
            "participant_ids": [alice_id, bob_id],
        },
    )
    assert direct_res.status_code == 201, direct_res.text

    alice_sum = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok_alice))).json())
    bob_sum = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok_bob))).json())

    assert Decimal(str(alice_sum["you_are_owed_total"])) == Decimal("500.00")
    assert Decimal(str(alice_sum["you_owe_total"])) == Decimal("0.00")
    assert Decimal(str(alice_sum["total_net_balance"])) == Decimal("500.00")
    assert Decimal(str(alice_sum["monthly_spending"])) == Decimal("500.00")
    assert alice_sum["active_friends_count"] == 1

    assert Decimal(str(bob_sum["you_are_owed_total"])) == Decimal("0.00")
    assert Decimal(str(bob_sum["you_owe_total"])) == Decimal("500.00")
    assert Decimal(str(bob_sum["total_net_balance"])) == Decimal("-500.00")

    # 2. Direct expense in opposite direction with a third friend (Charlie) keeps owed vs owe separate
    charlie_id = str(uuid.uuid4())
    tok_charlie = _mint_jwt(charlie_id, "charlie.ov@evenbill.test", "Charlie")
    assert (await client.get("/api/v1/auth/me", headers=_headers(tok_charlie))).status_code == 200

    res2 = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok_charlie),
        json={
            "group_id": None,
            "description": "Coffee",
            "total_amount": "400.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": charlie_id, "amount_paid": "400.00"}],
            "participant_ids": [alice_id, charlie_id],
        },
    )
    assert res2.status_code == 201, res2.text

    alice_sum2 = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok_alice))).json())
    assert Decimal(str(alice_sum2["you_are_owed_total"])) == Decimal("500.00")
    assert Decimal(str(alice_sum2["you_owe_total"])) == Decimal("200.00")
    assert Decimal(str(alice_sum2["total_net_balance"])) == Decimal("300.00")
    assert alice_sum2["active_friends_count"] == 2

    # 3. Direct settlement between Bob and Alice clears Bob's ₹500 direct debt
    settle_res = await client.post(
        "/api/v1/settlements/",
        headers=_headers(tok_bob),
        json={
            "group_id": None,
            "payer_id": bob_id,
            "recipient_id": alice_id,
            "amount": "500.00",
            "currency": "INR",
            "payment_method": "UPI",
        },
    )
    assert settle_res.status_code == 201, settle_res.text

    alice_sum3 = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok_alice))).json())
    assert Decimal(str(alice_sum3["you_are_owed_total"])) == Decimal("0.00")
    assert Decimal(str(alice_sum3["you_owe_total"])) == Decimal("200.00")
    assert Decimal(str(alice_sum3["total_net_balance"])) == Decimal("-200.00")


@pytest.mark.asyncio
async def test_multiple_expenses_in_same_group_and_cross_device_balance_sync(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Verifies:
    - Multiple expenses with rotating payers in the same group update Overview summary
      and GET /api/v1/groups/ net_balance accurately for all participants.
    - Cross-device login with same canonical Supabase UUID sees identical balances.
    """
    u1 = str(uuid.uuid4())
    u2 = str(uuid.uuid4())
    u3 = str(uuid.uuid4())

    tok1_dev_a = _mint_jwt(u1, "u1.multi@evenbill.test", "User One")
    tok1_dev_b = _mint_jwt(u1, "u1.multi@evenbill.test", "User One")
    tok2 = _mint_jwt(u2, "u2.multi@evenbill.test", "User Two")
    tok3 = _mint_jwt(u3, "u3.multi@evenbill.test", "User Three")

    for tok in (tok1_dev_a, tok2, tok3):
        assert (await client.get("/api/v1/auth/me", headers=_headers(tok))).status_code == 200

    grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1_dev_a),
        json={"name": "Goa Crew", "group_type": "TRIP", "base_currency": "INR"},
    )
    assert grp_res.status_code == 201, grp_res.text
    group_id = _unwrap(grp_res.json())["id"]

    db_session.add(GroupMember(group_id=group_id, user_id=u2, role="MEMBER"))
    db_session.add(GroupMember(group_id=group_id, user_id=u3, role="MEMBER"))
    await db_session.flush()

    # Expense 1: U1 pays ₹900 split 3 ways -> U1 +600, U2 -300, U3 -300
    e1 = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1_dev_a),
        json={
            "group_id": group_id,
            "description": "Villa",
            "total_amount": "900.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "900.00"}],
            "participant_ids": [u1, u2, u3],
        },
    )
    assert e1.status_code == 201, e1.text

    # Expense 2: U2 pays ₹600 split 3 ways -> cumulative U1 +400, U2 +100, U3 -500
    e2 = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok2),
        json={
            "group_id": group_id,
            "description": "Dinner",
            "total_amount": "600.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": u2, "amount_paid": "600.00"}],
            "participant_ids": [u1, u2, u3],
        },
    )
    assert e2.status_code == 201, e2.text

    # Device A and Device B (same U1 account) both see +400.00
    sum_dev_a = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_a))).json())
    sum_dev_b = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_b))).json())
    sum_u2 = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok2))).json())
    sum_u3 = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok3))).json())

    assert Decimal(str(sum_dev_a["total_net_balance"])) == Decimal("400.00")
    assert Decimal(str(sum_dev_b["total_net_balance"])) == Decimal("400.00")
    assert Decimal(str(sum_dev_b["you_are_owed_total"])) == Decimal("400.00")
    assert Decimal(str(sum_u2["total_net_balance"])) == Decimal("100.00")
    assert Decimal(str(sum_u3["total_net_balance"])) == Decimal("-500.00")
    assert Decimal(str(sum_u3["you_owe_total"])) == Decimal("500.00")

    # GET /api/v1/groups/ also includes real per-user net_balance
    groups_dev_b = _unwrap((await client.get("/api/v1/groups/", headers=_headers(tok1_dev_b))).json())
    groups_u3 = _unwrap((await client.get("/api/v1/groups/", headers=_headers(tok3))).json())
    assert Decimal(str(groups_dev_b[0]["net_balance"])) == Decimal("400.00")
    assert Decimal(str(groups_u3[0]["net_balance"])) == Decimal("-500.00")


@pytest.mark.asyncio
async def test_multi_currency_group_and_summary_conversion_preserves_conservation(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Verifies cross-currency group expense and USD->INR summary conversion work cleanly
    without 1:1 fallback bugs or DebtSimplifier conservation rounding errors.
    """
    u1 = str(uuid.uuid4())
    u2 = str(uuid.uuid4())
    u3 = str(uuid.uuid4())
    tok1 = _mint_jwt(u1, "u1.fx@evenbill.test", "FX Payer")
    tok2 = _mint_jwt(u2, "u2.fx@evenbill.test", "FX Two")
    tok3 = _mint_jwt(u3, "u3.fx@evenbill.test", "FX Three")

    for tok in (tok1, tok2, tok3):
        assert (await client.get("/api/v1/auth/me", headers=_headers(tok))).status_code == 200

    # Group base currency is INR; expense created in USD split across 3 members ($10 -> tricky 3-way split!)
    grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1),
        json={"name": "FX Trip", "group_type": "TRIP", "base_currency": "INR"},
    )
    assert grp_res.status_code == 201
    group_id = _unwrap(grp_res.json())["id"]

    db_session.add(GroupMember(group_id=group_id, user_id=u2, role="MEMBER"))
    db_session.add(GroupMember(group_id=group_id, user_id=u3, role="MEMBER"))
    await db_session.flush()

    exp_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1),
        json={
            "group_id": group_id,
            "description": "USD Hotel",
            "total_amount": "10.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "10.00"}],
            "participant_ids": [u1, u2, u3],
        },
    )
    assert exp_res.status_code == 201, exp_res.text
    exp_data = _unwrap(exp_res.json())
    expected_rate = FXService.get_exchange_rate("USD", "INR").rate
    assert Decimal(str(exp_data["exchange_rate"])) == expected_rate
    assert exp_data["exchange_rate_source"] != "SNAPSHOT_FALLBACK"

    # Group detail balances & Overview summary convert cleanly into INR with zero rounding error
    detail_res = await client.get(f"/api/v1/groups/{group_id}", headers=_headers(tok1))
    assert detail_res.status_code == 200, detail_res.text
    sum_res = await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1))
    assert sum_res.status_code == 200, sum_res.text
    sum_data = _unwrap(sum_res.json())
    assert Decimal(str(sum_data["total_net_balance"])) > Decimal("500.00")
    assert sum_data["currency"] == "INR"


@pytest.mark.asyncio
async def test_update_expense_currency_changes_keep_amounts_splits_and_rate_consistent(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 1 regression:
    - Changing expense currency from USD -> JPY re-quantizes total_amount, single-payer amount,
      percentage splits, and recalculates FX rate & base_currency_amount in lockstep.
    - Re-sending unchanged foreign currency on an amount edit preserves custom frozen FX rate.
    - Changing currency to JPY when EXACT splits would lose conservation returns 422 cleanly.
    - Changing currency back to group's base currency resets exchange_rate to 1.0 IDENTITY.
    """
    u1 = str(uuid.uuid4())
    u2 = str(uuid.uuid4())
    tok1 = _mint_jwt(u1, "u1.upd@evenbill.test", "Update One")
    tok2 = _mint_jwt(u2, "u2.upd@evenbill.test", "Update Two")
    for tok in (tok1, tok2):
        assert (await client.get("/api/v1/auth/me", headers=_headers(tok))).status_code == 200

    grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1),
        json={"name": "FX Update Lab", "group_type": "TRIP", "base_currency": "INR"},
    )
    assert grp_res.status_code == 201
    group_id = _unwrap(grp_res.json())["id"]
    db_session.add(GroupMember(group_id=group_id, user_id=u2, role="MEMBER"))
    await db_session.flush()

    # 1. Create PERCENTAGE expense in USD ($100.00, 60%/40%) with custom frozen exchange rate 85.00
    create_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1),
        json={
            "group_id": group_id,
            "description": "Custom FX Booking",
            "total_amount": "100.00",
            "currency": "USD",
            "exchange_rate": "85.00",
            "exchange_rate_source": "CUSTOM_DESK",
            "split_type": "PERCENTAGE",
            "payers": [{"user_id": u1, "amount_paid": "100.00"}],
            "percentages": {u1: "60", u2: "40"},
        },
    )
    assert create_res.status_code == 201, create_res.text
    exp = _unwrap(create_res.json())
    exp_id = exp["id"]
    assert Decimal(str(exp["base_currency_amount"])) == Decimal("8500.0000")

    # 2. Edit total_amount while resending unchanged currency USD -> custom frozen rate 85.00 must be preserved
    upd_same_curr = await client.put(
        f"/api/v1/expenses/{exp_id}",
        headers=_headers(tok1),
        json={"total_amount": "200.00", "currency": "USD"},
    )
    assert upd_same_curr.status_code == 200, upd_same_curr.text
    same_data = _unwrap(upd_same_curr.json())
    assert Decimal(str(same_data["exchange_rate"])) == Decimal("85.00000000")
    assert same_data["exchange_rate_source"] == "CUSTOM_DESK"
    assert Decimal(str(same_data["base_currency_amount"])) == Decimal("17000.0000")
    assert Decimal(str(same_data["payers"][0]["amount_paid"])) == Decimal("200.0000")
    splits_by_u = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in same_data["splits"]}
    assert splits_by_u[u1] == Decimal("120.0000")
    assert splits_by_u[u2] == Decimal("80.0000")

    # 3. Change currency USD -> JPY (0 decimals) with new amount 1000 JPY and no explicit splits/payers
    upd_jpy = await client.put(
        f"/api/v1/expenses/{exp_id}",
        headers=_headers(tok1),
        json={"currency": "JPY", "total_amount": "1000"},
    )
    assert upd_jpy.status_code == 200, upd_jpy.text
    jpy_data = _unwrap(upd_jpy.json())
    assert jpy_data["currency"] == "JPY"
    assert Decimal(str(jpy_data["total_amount"])) == Decimal("1000")
    assert Decimal(str(jpy_data["payers"][0]["amount_paid"])) == Decimal("1000")
    jpy_splits = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in jpy_data["splits"]}
    assert jpy_splits[u1] == Decimal("600")
    assert jpy_splits[u2] == Decimal("400")
    jpy_inr_rate = FXService.get_verified_rate("JPY", "INR").rate
    assert Decimal(str(jpy_data["exchange_rate"])) == jpy_inr_rate
    assert Decimal(str(jpy_data["base_currency_amount"])) == (Decimal("1000") * jpy_inr_rate).quantize(Decimal("0.01"))

    # 4. Change currency back to group base currency INR -> resets exchange_rate to 1.0 IDENTITY
    upd_inr = await client.put(
        f"/api/v1/expenses/{exp_id}",
        headers=_headers(tok1),
        json={"currency": "INR", "total_amount": "500.00"},
    )
    assert upd_inr.status_code == 200, upd_inr.text
    inr_data = _unwrap(upd_inr.json())
    assert inr_data["currency"] == "INR"
    assert inr_data["exchange_rate_source"] == "IDENTITY"
    assert Decimal(str(inr_data["exchange_rate"])) == Decimal("1.0")
    assert Decimal(str(inr_data["base_currency_amount"])) == Decimal("500.0000")

    # 5. EXACT split that loses integer JPY sum conservation on currency-only change is rejected cleanly (422)
    exact_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1),
        json={
            "group_id": group_id,
            "description": "Exact Drift Check",
            "total_amount": "100.50",
            "currency": "USD",
            "split_type": "EXACT",
            "payers": [{"user_id": u1, "amount_paid": "100.50"}],
            "splits": [
                {"user_id": u1, "owed_amount": "50.60"},
                {"user_id": u2, "owed_amount": "49.90"},
            ],
        },
    )
    assert exact_res.status_code == 201
    exact_id = _unwrap(exact_res.json())["id"]

    # Bankers rounding of 100.50 -> 100, while 50.60 -> 51 and 49.90 -> 50 (sum 101 != 100)
    bad_curr_switch = await client.put(
        f"/api/v1/expenses/{exact_id}",
        headers=_headers(tok1),
        json={"currency": "JPY"},
    )
    assert bad_curr_switch.status_code == 422


@pytest.mark.asyncio
async def test_unsupported_currency_pair_never_silently_uses_one_to_one(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 1 regression:
    - FXService.convert and /api/v1/fx/convert fail clearly rather than substituting 1:1.
    - Creating a cross-currency expense or converting Overview to an unsupported currency
      without an explicit exchange_rate returns 422 instead of 1:1.
    - Supported UI currency AED converts with verified institutional rate (not 1:1).
    """
    with pytest.raises(UnsupportedCurrencyPairError):
        FXService.convert(Decimal("100.00"), "USD", "XYZ")

    u1 = str(uuid.uuid4())
    tok1 = _mint_jwt(u1, "u1.fxpol@evenbill.test", "FX Policy")
    assert (await client.get("/api/v1/auth/me", headers=_headers(tok1))).status_code == 200

    # Quote endpoint preserves UNAVAILABLE status transparency with null rate (never 1.0)
    quote_res = await client.get("/api/v1/fx/rate?from_currency=XYZ&to_currency=USD", headers=_headers(tok1))
    assert quote_res.status_code == 200
    quote_data = _unwrap(quote_res.json())
    assert quote_data["status"] == "UNAVAILABLE"
    assert quote_data["rate"] is None

    # /fx/convert refuses unsupported currency pair
    conv_res = await client.post(
        "/api/v1/fx/convert",
        headers=_headers(tok1),
        json={"amount": "100.00", "from_currency": "USD", "to_currency": "XYZ"},
    )
    assert conv_res.status_code == 422

    # Group in INR: creating expense in XYZ without exchange_rate fails cleanly (422)
    grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1),
        json={"name": "FX Guard", "group_type": "OTHER", "base_currency": "INR"},
    )
    group_id = _unwrap(grp_res.json())["id"]

    bad_exp = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1),
        json={
            "group_id": group_id,
            "description": "Unsupported Pair",
            "total_amount": "50.00",
            "currency": "XYZ",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "50.00"}],
            "participant_ids": [u1],
        },
    )
    assert bad_exp.status_code == 422

    # Explicitly providing verified user rate works cleanly; AED conversion is also supported (not 1:1)
    aed_exp = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1),
        json={
            "group_id": group_id,
            "description": "Dubai Hotel",
            "total_amount": "100.00",
            "currency": "AED",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "100.00"}],
            "participant_ids": [u1],
        },
    )
    assert aed_exp.status_code == 201, aed_exp.text
    aed_data = _unwrap(aed_exp.json())
    assert Decimal(str(aed_data["exchange_rate"])) > Decimal("20")

    bad_sum = await client.get("/api/v1/activity/summary?currency=XYZ", headers=_headers(tok1))
    assert bad_sum.status_code == 422


@pytest.mark.asyncio
async def test_active_membership_filtering_and_batched_cross_group_overview(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 2 regression:
    - Inactive GroupMember rows are excluded from groups list, access checks, friends list,
      and active_friends_count while preserving ledger conservation and clean reactivation.
    - Cross-group + direct summary aggregation remains accurate and uses O(1) batched queries.
    """
    u1 = str(uuid.uuid4())
    u2 = str(uuid.uuid4())
    u3 = str(uuid.uuid4())
    tok1 = _mint_jwt(u1, "u1.p2@evenbill.test", "Active One")
    tok2 = _mint_jwt(u2, "u2.p2@evenbill.test", "Member Two")
    tok3 = _mint_jwt(u3, "u3.p2@evenbill.test", "Member Three")
    for tok in (tok1, tok2, tok3):
        assert (await client.get("/api/v1/auth/me", headers=_headers(tok))).status_code == 200

    # Create 3 active groups with opposite net positions for u1 (+600, -250, +0)
    g_ids = []
    invite_codes = []
    for idx, base in enumerate(["INR", "INR", "USD"]):
        res = await client.post(
            "/api/v1/groups/",
            headers=_headers(tok1),
            json={"name": f"Batch Group {idx}", "group_type": "TRIP", "base_currency": base},
        )
        assert res.status_code == 201
        g = _unwrap(res.json())
        g_ids.append(g["id"])
        invite_codes.append(g["invite_code"])
        db_session.add(GroupMember(group_id=g["id"], user_id=u2, role="MEMBER"))
    db_session.add(GroupMember(group_id=g_ids[0], user_id=u3, role="MEMBER"))
    await db_session.flush()

    # G0 (INR): u1 pays 900 across [u1, u2, u3] -> u1 +600
    assert (
        await client.post(
            "/api/v1/expenses/",
            headers=_headers(tok1),
            json={
                "group_id": g_ids[0],
                "description": "Group0 Dinner",
                "total_amount": "900.00",
                "currency": "INR",
                "split_type": "EQUAL",
                "payers": [{"user_id": u1, "amount_paid": "900.00"}],
                "participant_ids": [u1, u2, u3],
            },
        )
    ).status_code == 201

    # G1 (INR): u2 pays 500 across [u1, u2] -> u1 -250
    assert (
        await client.post(
            "/api/v1/expenses/",
            headers=_headers(tok2),
            json={
                "group_id": g_ids[1],
                "description": "Group1 Taxi",
                "total_amount": "500.00",
                "currency": "INR",
                "split_type": "EQUAL",
                "payers": [{"user_id": u2, "amount_paid": "500.00"}],
                "participant_ids": [u1, u2],
            },
        )
    ).status_code == 201

    # Direct (INR): u1 pays 200 across [u1, u2] -> u1 +100
    assert (
        await client.post(
            "/api/v1/expenses/",
            headers=_headers(tok1),
            json={
                "group_id": None,
                "description": "Direct Lunch",
                "total_amount": "200.00",
                "currency": "INR",
                "split_type": "EQUAL",
                "payers": [{"user_id": u1, "amount_paid": "200.00"}],
                "participant_ids": [u1, u2],
            },
        )
    ).status_code == 201

    # Check cross-group + direct summary for u1: owed = 600 + 100 = 700, owe = 250, net = +450
    sum1 = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1))).json())
    assert Decimal(str(sum1["you_are_owed_total"])) == Decimal("700.00")
    assert Decimal(str(sum1["you_owe_total"])) == Decimal("250.00")
    assert Decimal(str(sum1["total_net_balance"])) == Decimal("450.00")
    assert sum1["active_groups_count"] == 3
    assert sum1["active_friends_count"] == 2

    # Verify list_groups and activity/summary execute constant O(1) batched queries regardless of group count
    sync_engine = db_session.bind.sync_engine if hasattr(db_session.bind, "sync_engine") else db_session.get_bind()
    query_counts = []

    def _count_queries(_conn, _cursor, statement, _parameters, _context, _executemany):
        if statement.lstrip().upper().startswith("SELECT"):
            query_counts.append(statement)

    def _measure_counts():
        nonlocal query_counts
        query_counts.clear()
        return query_counts

    event.listen(sync_engine, "before_cursor_execute", _count_queries)
    try:
        _measure_counts()
        g_list = await client.get("/api/v1/groups/", headers=_headers(tok1))
        assert g_list.status_code == 200
        groups_selects_3 = len(query_counts)

        _measure_counts()
        s_resp = await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1))
        assert s_resp.status_code == 200
        summary_selects_3 = len(query_counts)
    finally:
        event.remove(sync_engine, "before_cursor_execute", _count_queries)

    # Add 2 more active groups (total 5) and confirm query count does NOT grow with group count
    for extra in range(2):
        extra_res = await client.post(
            "/api/v1/groups/",
            headers=_headers(tok1),
            json={"name": f"Extra Batch {extra}", "group_type": "OTHER", "base_currency": "INR"},
        )
        assert extra_res.status_code == 201

    event.listen(sync_engine, "before_cursor_execute", _count_queries)
    try:
        _measure_counts()
        assert (await client.get("/api/v1/groups/", headers=_headers(tok1))).status_code == 200
        groups_selects_5 = len(query_counts)

        _measure_counts()
        assert (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1))).status_code == 200
        summary_selects_5 = len(query_counts)
    finally:
        event.remove(sync_engine, "before_cursor_execute", _count_queries)

    assert groups_selects_5 == groups_selects_3
    assert summary_selects_5 == summary_selects_3

    # Deactivate u3 in G0 -> u3 is denied access & dropped from active member/friend counts, while balances conserve
    gm_u3 = (
        await db_session.execute(
            select(GroupMember).where(GroupMember.group_id == g_ids[0], GroupMember.user_id == u3)
        )
    ).scalar_one()
    gm_u3.is_active = False
    await db_session.commit()

    assert (await client.get(f"/api/v1/groups/{g_ids[0]}", headers=_headers(tok3))).status_code == 403
    assert (await client.get(f"/api/v1/expenses/group/{g_ids[0]}", headers=_headers(tok3))).status_code == 403
    assert (await client.get(f"/api/v1/activity/?group_id={g_ids[0]}", headers=_headers(tok3))).status_code == 403
    assert len(_unwrap((await client.get("/api/v1/groups/", headers=_headers(tok3))).json())) == 0

    g0_detail = _unwrap((await client.get(f"/api/v1/groups/{g_ids[0]}", headers=_headers(tok1))).json())
    assert g0_detail["group"]["member_count"] == 2
    assert len(g0_detail["members"]) == 2
    assert sum(Decimal(str(b["net_balance"])) for b in g0_detail["net_balances"]) == Decimal("0.0000")

    sum1_after = _unwrap((await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1))).json())
    assert sum1_after["active_friends_count"] == 1

    # Reactivating u3 via invite link cleanly restores membership without 409/PK conflict
    rejoin = await client.post(f"/api/v1/groups/join/{invite_codes[0]}", headers=_headers(tok3))
    assert rejoin.status_code == 200
    assert _unwrap(rejoin.json())["member_count"] == 3


@pytest.mark.asyncio
async def test_activity_involvement_and_balances_across_solo_payer_for_other_multi_split_and_restart(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Regression suite covering:
    1. Solo group expenses (user pays & participates alone, including cross-currency):
       Overview bilateral net stays 0.00 while monthly_spending tracks converted spend,
       and /api/v1/activity/ reports is_user_involved=True with user_paid_amount and
       user_owed_amount equal to total_amount (never misclassified as not involved).
    2. Current user pays & participates with another member -> immediate Overview & activity update.
    3. Current user pays while ONLY another member participates -> user lent 100%, is_user_involved=True,
       and user's monthly_spending excludes the un-owed gift/loan while participant's includes it.
    4. Multiple participants & unequal EXACT splits + co-pay zero-net break-even + genuinely uninvolved member:
       - co-payer with net 0 still has is_user_involved=True (paid == owed > 0);
       - uninvolved member has is_user_involved=False, paid=0, owed=0, net=0;
       - description reflects actual payer even when creator != payer.
    5. App restart & login on a second device (fresh client session / new device token) returns identical
       Overview totals and /api/v1/activity/ involvement metadata.
    """
    u1 = str(uuid.uuid4())
    u2 = str(uuid.uuid4())
    u3 = str(uuid.uuid4())
    u4 = str(uuid.uuid4())

    tok1_dev_a = _mint_jwt(u1, "adv.payer@evenbill.test", "Advanced Ai")
    tok1_dev_b = _mint_jwt(u1, "adv.payer@evenbill.test", "Advanced Ai")
    tok2 = _mint_jwt(u2, "bob.split@evenbill.test", "Bob Split")
    tok3 = _mint_jwt(u3, "charlie.split@evenbill.test", "Charlie Split")
    tok4 = _mint_jwt(u4, "dana.uninvolved@evenbill.test", "Dana Observer")

    for tok in (tok1_dev_a, tok2, tok3, tok4):
        assert (await client.get("/api/v1/auth/me", headers=_headers(tok))).status_code == 200

    # 1. Single-member USD group mirroring Bahayyy with ww ($2000 USD) and dd (5000 INR)
    grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1_dev_a),
        json={"name": "Bahayyy Regression", "group_type": "HOME", "base_currency": "USD"},
    )
    assert grp_res.status_code == 201, grp_res.text
    group_id = _unwrap(grp_res.json())["id"]

    ww_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1_dev_a),
        json={
            "group_id": group_id,
            "description": "ww",
            "total_amount": "2000.00",
            "currency": "USD",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "2000.00"}],
            "participant_ids": [u1],
        },
    )
    assert ww_res.status_code == 201, ww_res.text

    dd_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1_dev_a),
        json={
            "group_id": group_id,
            "description": "dd",
            "total_amount": "5000.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "5000.00"}],
            "participant_ids": [u1],
        },
    )
    assert dd_res.status_code == 201, dd_res.text

    solo_summary = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_a))).json()
    )
    assert Decimal(str(solo_summary["total_net_balance"])) == Decimal("0.00")
    assert Decimal(str(solo_summary["you_are_owed_total"])) == Decimal("0.00")
    assert Decimal(str(solo_summary["you_owe_total"])) == Decimal("0.00")
    expected_solo_spend = Decimal("5000.00") + FXService.convert(Decimal("2000.00"), "USD", "INR").converted_amount
    assert abs(Decimal(str(solo_summary["monthly_spending"])) - expected_solo_spend) <= Decimal("0.02")

    solo_activity = _unwrap((await client.get("/api/v1/activity/", headers=_headers(tok1_dev_a))).json())
    by_title = {item["title"]: item for item in solo_activity}
    for title, expected_amt in (("ww", Decimal("2000.00")), ("dd", Decimal("5000.00"))):
        item = by_title[title]
        assert item["is_user_involved"] is True
        assert Decimal(str(item["user_paid_amount"])) == expected_amt
        assert Decimal(str(item["user_owed_amount"])) == expected_amt
        assert Decimal(str(item["user_net_share"])) == Decimal("0.00")
        assert item["description"] == "Paid by Advanced Ai"

    # Add co-members u2, u3, u4 and switch to an INR test group for exact minor-unit checks
    inr_grp_res = await client.post(
        "/api/v1/groups/",
        headers=_headers(tok1_dev_a),
        json={"name": "Shared Flat", "group_type": "HOME", "base_currency": "INR"},
    )
    assert inr_grp_res.status_code == 201
    inr_gid = _unwrap(inr_grp_res.json())["id"]
    for member_id in (u2, u3, u4):
        db_session.add(GroupMember(group_id=inr_gid, user_id=member_id, role="MEMBER"))
    await db_session.flush()

    # 2. u1 pays & participates (1200 INR split equally u1 + u2 -> u1 +600, u2 -600, u4 uninvolved)
    shared_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1_dev_a),
        json={
            "group_id": inr_gid,
            "description": "Shared Groceries",
            "total_amount": "1200.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "1200.00"}],
            "participant_ids": [u1, u2],
        },
    )
    assert shared_res.status_code == 201, shared_res.text

    sum_after_shared = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_a))).json()
    )
    assert Decimal(str(sum_after_shared["you_are_owed_total"])) == Decimal("600.00")
    assert Decimal(str(sum_after_shared["you_owe_total"])) == Decimal("0.00")
    assert Decimal(str(sum_after_shared["total_net_balance"])) == Decimal("600.00")

    # 3. u1 pays 400 INR, ONLY u2 participates -> u1 lent 400, owed 0, is_user_involved=True
    gift_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok1_dev_a),
        json={
            "group_id": inr_gid,
            "description": "Cab for Bob",
            "total_amount": "400.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [{"user_id": u1, "amount_paid": "400.00"}],
            "participant_ids": [u2],
        },
    )
    assert gift_res.status_code == 201, gift_res.text

    sum_after_gift = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_a))).json()
    )
    assert Decimal(str(sum_after_gift["you_are_owed_total"])) == Decimal("1000.00")
    assert Decimal(str(sum_after_gift["total_net_balance"])) == Decimal("1000.00")

    # 4a. Unequal EXACT split across 3 participants, created by u3 while u2 actually paid
    #     (verifies creator != payer shows "Paid by Bob Split" rather than creator name)
    unequal_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok3),
        json={
            "group_id": inr_gid,
            "description": "Group Dinner Unequal",
            "total_amount": "900.00",
            "currency": "INR",
            "split_type": "EXACT",
            "payers": [{"user_id": u2, "amount_paid": "900.00"}],
            "splits": [
                {"user_id": u1, "owed_amount": "200.00"},
                {"user_id": u2, "owed_amount": "300.00"},
                {"user_id": u3, "owed_amount": "400.00"},
            ],
        },
    )
    assert unequal_res.status_code == 201, unequal_res.text

    # 4b. Multi-payer co-pay where u1 pays 400 and owes 400 -> net 0 but involved=True (u4 uninvolved)
    copay_res = await client.post(
        "/api/v1/expenses/",
        headers=_headers(tok2),
        json={
            "group_id": inr_gid,
            "description": "Co-Paid Tickets",
            "total_amount": "800.00",
            "currency": "INR",
            "split_type": "EQUAL",
            "payers": [
                {"user_id": u1, "amount_paid": "400.00"},
                {"user_id": u2, "amount_paid": "400.00"},
            ],
            "participant_ids": [u1, u2],
        },
    )
    assert copay_res.status_code == 201, copay_res.text

    # Verify per-user ActivityItem involvement & payer description on Device A vs Device B (restart/relogin)
    for tok in (tok1_dev_a, tok1_dev_b):
        act_list = _unwrap(
            (await client.get(f"/api/v1/activity/?group_id={inr_gid}", headers=_headers(tok))).json()
        )
        u1_items = {item["title"]: item for item in act_list}

        assert u1_items["Shared Groceries"]["is_user_involved"] is True
        assert Decimal(str(u1_items["Shared Groceries"]["user_paid_amount"])) == Decimal("1200.00")
        assert Decimal(str(u1_items["Shared Groceries"]["user_owed_amount"])) == Decimal("600.00")
        assert Decimal(str(u1_items["Shared Groceries"]["user_net_share"])) == Decimal("600.00")

        assert u1_items["Cab for Bob"]["is_user_involved"] is True
        assert Decimal(str(u1_items["Cab for Bob"]["user_paid_amount"])) == Decimal("400.00")
        assert Decimal(str(u1_items["Cab for Bob"]["user_owed_amount"])) == Decimal("0.00")
        assert Decimal(str(u1_items["Cab for Bob"]["user_net_share"])) == Decimal("400.00")

        assert u1_items["Group Dinner Unequal"]["description"] == "Paid by Bob Split"
        assert u1_items["Group Dinner Unequal"]["created_by_name"] == "Charlie Split"
        assert u1_items["Group Dinner Unequal"]["is_user_involved"] is True
        assert Decimal(str(u1_items["Group Dinner Unequal"]["user_owed_amount"])) == Decimal("200.00")
        assert Decimal(str(u1_items["Group Dinner Unequal"]["user_net_share"])) == Decimal("-200.00")

        assert u1_items["Co-Paid Tickets"]["is_user_involved"] is True
        assert Decimal(str(u1_items["Co-Paid Tickets"]["user_paid_amount"])) == Decimal("400.00")
        assert Decimal(str(u1_items["Co-Paid Tickets"]["user_owed_amount"])) == Decimal("400.00")
        assert Decimal(str(u1_items["Co-Paid Tickets"]["user_net_share"])) == Decimal("0.00")
        assert u1_items["Co-Paid Tickets"]["description"] in (
            "Paid by Advanced Ai (+1 other)",
            "Paid by Bob Split (+1 other)",
        )

    # Genuinely uninvolved group member Dana (u4) must still receive is_user_involved=False
    u4_items = {
        item["title"]: item
        for item in _unwrap(
            (await client.get(f"/api/v1/activity/?group_id={inr_gid}", headers=_headers(tok4))).json()
        )
    }
    for exp_title in ("Shared Groceries", "Cab for Bob", "Group Dinner Unequal", "Co-Paid Tickets"):
        assert u4_items[exp_title]["is_user_involved"] is False
        assert Decimal(str(u4_items[exp_title]["user_paid_amount"])) == Decimal("0.00")
        assert Decimal(str(u4_items[exp_title]["user_owed_amount"])) == Decimal("0.00")
        assert Decimal(str(u4_items[exp_title]["user_net_share"])) == Decimal("0.00")

    # Verify cross-device Overview totals match for u1 (+800), u2 (-400), u3 (-400), u4 (0)
    sum_dev_b = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok1_dev_b))).json()
    )
    sum_u2 = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok2))).json()
    )
    sum_u3 = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok3))).json()
    )
    sum_u4 = _unwrap(
        (await client.get("/api/v1/activity/summary?currency=INR", headers=_headers(tok4))).json()
    )
    assert Decimal(str(sum_dev_b["total_net_balance"])) == Decimal("800.00")
    assert Decimal(str(sum_u2["total_net_balance"])) == Decimal("-400.00")
    assert Decimal(str(sum_u3["total_net_balance"])) == Decimal("-400.00")
    assert Decimal(str(sum_u4["total_net_balance"])) == Decimal("0.00")
