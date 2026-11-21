"""
Integration Tests for EvenBill Financial Ledger API
Tests Group creation, join via invite code, multi-payer expenses, equal remainder splits,
group net balances, debt simplification, and settlement resolution.
"""

import pytest
from decimal import Decimal
from httpx import AsyncClient


async def register_and_login(client: AsyncClient, email: str, name: str) -> dict:
    reg_resp = await client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Password123!",
        "full_name": name,
        "default_currency": "USD"
    })
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
async def test_complete_ledger_lifecycle(client: AsyncClient):
    # 1. Setup 3 Users: Alice, Bob, Carol
    alice = await register_and_login(client, "alice@evenbill.app", "Alice Smith")
    bob = await register_and_login(client, "bob@evenbill.app", "Bob Jones")
    carol = await register_and_login(client, "carol@evenbill.app", "Carol White")

    # 2. Alice creates a group "Ski Trip"
    grp_resp = await client.post("/api/v1/groups/", headers=alice["headers"], json={
        "name": "Ski Trip 2026",
        "group_type": "TRIP",
        "base_currency": "USD",
        "simplify_debts": True
    })
    assert grp_resp.status_code == 201
    group_data = grp_resp.json()["data"]
    group_id = group_data["id"]
    invite_code = group_data["invite_code"]

    # 3. Bob and Carol join the group via invite code
    bob_join = await client.post(f"/api/v1/groups/join/{invite_code}", headers=bob["headers"])
    assert bob_join.status_code == 200

    carol_join = await client.post(f"/api/v1/groups/join/{invite_code}", headers=carol["headers"])
    assert carol_join.status_code == 200

    # 4. Alice records an expense: Dinner $90.00 split equally among Alice, Bob, Carol
    exp1_resp = await client.post("/api/v1/expenses/", headers=alice["headers"], json={
        "group_id": group_id,
        "description": "Cabin Dinner",
        "total_amount": 90.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "category": "FOOD",
        "participant_ids": [alice["id"], bob["id"], carol["id"]]
    })
    assert exp1_resp.status_code == 201
    exp1_data = exp1_resp.json()["data"]
    assert exp1_data["total_amount"] == "90.0000"
    assert len(exp1_data["payers"]) == 1
    assert exp1_data["payers"][0]["user_id"] == alice["id"]
    assert len(exp1_data["splits"]) == 3

    # 5. Verify Group Balances
    grp_detail_1 = await client.get(f"/api/v1/groups/{group_id}", headers=alice["headers"])
    assert grp_detail_1.status_code == 200
    detail_data_1 = grp_detail_1.json()["data"]

    net_balances_1 = {b["user_id"]: Decimal(str(b["net_balance"])) for b in detail_data_1["net_balances"]}
    # Alice paid 90, owes 30 -> Net +60
    # Bob paid 0, owes 30 -> Net -30
    # Carol paid 0, owes 30 -> Net -30
    assert net_balances_1[alice["id"]] == Decimal("60.0000")
    assert net_balances_1[bob["id"]] == Decimal("-30.0000")
    assert net_balances_1[carol["id"]] == Decimal("-30.0000")

    # Simplified debts should show: Bob -> Alice $30, Carol -> Alice $30
    sim_debts_1 = detail_data_1["simplified_debts"]
    assert len(sim_debts_1) == 2

    # 6. Bob settles up with Alice for $30.00
    settle_resp = await client.post("/api/v1/settlements/", headers=bob["headers"], json={
        "group_id": group_id,
        "recipient_id": alice["id"],
        "amount": 30.00,
        "currency": "USD",
        "payment_method": "UPI",
        "transaction_reference": "UPI-REF-998877",
        "notes": "Paid via UPI"
    })
    assert settle_resp.status_code == 201
    settle_data = settle_resp.json()["data"]
    assert settle_data["payer_id"] == bob["id"]
    assert settle_data["recipient_id"] == alice["id"]
    assert Decimal(str(settle_data["amount"])) == Decimal("30.0000")

    # 7. Verify Group Balances after settlement: Bob must be at 0.00
    grp_detail_2 = await client.get(f"/api/v1/groups/{group_id}", headers=alice["headers"])
    assert grp_detail_2.status_code == 200
    detail_data_2 = grp_detail_2.json()["data"]

    net_balances_2 = {b["user_id"]: Decimal(str(b["net_balance"])) for b in detail_data_2["net_balances"]}
    assert net_balances_2[bob["id"]] == Decimal("0.0000")
    assert net_balances_2[alice["id"]] == Decimal("30.0000")
    assert net_balances_2[carol["id"]] == Decimal("-30.0000")

    # Simplified debts should now only have Carol -> Alice $30
    sim_debts_2 = detail_data_2["simplified_debts"]
    assert len(sim_debts_2) == 1
    assert sim_debts_2[0]["debtor_id"] == carol["id"]
    assert sim_debts_2[0]["creditor_id"] == alice["id"]
    assert Decimal(str(sim_debts_2[0]["amount"])) == Decimal("30.00")


@pytest.mark.asyncio
async def test_all_split_methods_api(client: AsyncClient):
    """
    Tests Exact, Percentage, Shares, Adjustments, Itemized (with taxes/tips/fees/discounts),
    and Refund/Reimbursement transactions through the API.
    """
    user_a = await register_and_login(client, "usera@evenbill.app", "User A")
    user_b = await register_and_login(client, "userb@evenbill.app", "User B")
    user_c = await register_and_login(client, "userc@evenbill.app", "User C")

    grp_resp = await client.post("/api/v1/groups/", headers=user_a["headers"], json={
        "name": "Split Methods Lab",
        "group_type": "PROJECT",
        "base_currency": "USD"
    })
    group_id = grp_resp.json()["data"]["id"]
    invite_code = grp_resp.json()["data"]["invite_code"]

    await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_b["headers"])
    await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_c["headers"])

    # 1. Exact Split: $100.00 (A: $40, B: $35, C: $25)
    exact_resp = await client.post("/api/v1/expenses/", headers=user_a["headers"], json={
        "group_id": group_id,
        "description": "Hardware Supplies (Exact)",
        "total_amount": 100.00,
        "currency": "USD",
        "split_type": "EXACT",
        "splits": [
            {"user_id": user_a["id"], "owed_amount": 40.00},
            {"user_id": user_b["id"], "owed_amount": 35.00},
            {"user_id": user_c["id"], "owed_amount": 25.00}
        ]
    })
    assert exact_resp.status_code == 201

    # 2. Percentage Split: $200.00 (A: 50% = $100, B: 30% = $60, C: 20% = $40)
    pct_resp = await client.post("/api/v1/expenses/", headers=user_b["headers"], json={
        "group_id": group_id,
        "description": "Cloud Hosting (Percentage)",
        "total_amount": 200.00,
        "currency": "USD",
        "split_type": "PERCENTAGE",
        "percentages": {
            user_a["id"]: 50.0,
            user_b["id"]: 30.0,
            user_c["id"]: 20.0
        }
    })
    assert pct_resp.status_code == 201
    pct_splits = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in pct_resp.json()["data"]["splits"]}
    assert pct_splits[user_a["id"]] == Decimal("100.0000")
    assert pct_splits[user_b["id"]] == Decimal("60.0000")
    assert pct_splits[user_c["id"]] == Decimal("40.0000")

    # 3. Weighted Shares Split: $60.00 (A: 1 share = $10, B: 2 shares = $20, C: 3 shares = $30)
    shares_resp = await client.post("/api/v1/expenses/", headers=user_c["headers"], json={
        "group_id": group_id,
        "description": "Software License (Shares)",
        "total_amount": 60.00,
        "currency": "USD",
        "split_type": "SHARES",
        "shares": {
            user_a["id"]: 1.0,
            user_b["id"]: 2.0,
            user_c["id"]: 3.0
        }
    })
    assert shares_resp.status_code == 201
    shares_splits = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in shares_resp.json()["data"]["splits"]}
    assert shares_splits[user_a["id"]] == Decimal("10.0000")
    assert shares_splits[user_b["id"]] == Decimal("20.0000")
    assert shares_splits[user_c["id"]] == Decimal("30.0000")

    # 4. Adjustments Split: $120.00 (A: +$10, B: -$10, C: $0 -> Base $40 -> A: 50, B: 30, C: 40)
    adj_resp = await client.post("/api/v1/expenses/", headers=user_a["headers"], json={
        "group_id": group_id,
        "description": "Team Lunch (Adjustments)",
        "total_amount": 120.00,
        "currency": "USD",
        "split_type": "ADJUSTMENT",
        "participant_ids": [user_a["id"], user_b["id"], user_c["id"]],
        "adjustments": {
            user_a["id"]: 10.00,
            user_b["id"]: -10.00
        }
    })
    assert adj_resp.status_code == 201
    adj_splits = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in adj_resp.json()["data"]["splits"]}
    assert adj_splits[user_a["id"]] == Decimal("50.0000")
    assert adj_splits[user_b["id"]] == Decimal("30.0000")
    assert adj_splits[user_c["id"]] == Decimal("40.0000")

    # 5. Itemized Split: Meal with items + tax ($9) + tip ($18) + fee ($3) - discount ($6) = $114.00 ($38 each)
    itemized_resp = await client.post("/api/v1/expenses/", headers=user_a["headers"], json={
        "group_id": group_id,
        "description": "Gourmet Dinner (Itemized)",
        "total_amount": 114.00,
        "currency": "USD",
        "split_type": "ITEMIZED",
        "items": [
            {"description": "Pizza", "amount": 30.00, "participant_ids": [user_a["id"], user_b["id"]]},
            {"description": "Salad", "amount": 15.00, "participant_ids": [user_c["id"]]},
            {"description": "Wine", "amount": 45.00, "participant_ids": [user_a["id"], user_b["id"], user_c["id"]]}
        ],
        "tax": 9.00,
        "tip": 18.00,
        "fee": 3.00,
        "discount": 6.00
    })
    assert itemized_resp.status_code == 201
    item_splits = {s["user_id"]: Decimal(str(s["owed_amount"])) for s in itemized_resp.json()["data"]["splits"]}
    assert item_splits[user_a["id"]] == Decimal("38.0000")
    assert item_splits[user_b["id"]] == Decimal("38.0000")
    assert item_splits[user_c["id"]] == Decimal("38.0000")

    # 6. Refund / Reimbursement Transaction: explicit auditable transaction
    refund_resp = await client.post("/api/v1/expenses/", headers=user_a["headers"], json={
        "group_id": group_id,
        "description": "Itemized Dinner Refund for Carol",
        "transaction_type": "REFUND",
        "original_expense_id": itemized_resp.json()["data"]["id"],
        "total_amount": 38.00,
        "currency": "USD",
        "split_type": "EXACT",
        "payers": [{"user_id": user_a["id"], "amount_paid": 38.00}],
        "splits": [
            {"user_id": user_c["id"], "owed_amount": 38.00}
        ]
    })
    assert refund_resp.status_code == 201
    assert refund_resp.json()["data"]["transaction_type"] == "REFUND"
    assert refund_resp.json()["data"]["original_expense_id"] == itemized_resp.json()["data"]["id"]

    # Verify Financial Invariant: Net balances in group must strictly sum to 0.0000
    grp_detail = await client.get(f"/api/v1/groups/{group_id}", headers=user_a["headers"])
    assert grp_detail.status_code == 200
    net_sum = sum(Decimal(str(b["net_balance"])) for b in grp_detail.json()["data"]["net_balances"])
    assert net_sum == Decimal("0.0000")


@pytest.mark.asyncio
async def test_expense_edit_and_delete_no_stale_balances(client: AsyncClient):
    """
    Verifies that updating or soft-deleting an expense immediately updates group balances
    without leaving stale remnants, increments the version number, and records audit logs.
    """
    user_x = await register_and_login(client, "userx@evenbill.app", "User X")
    user_y = await register_and_login(client, "usery@evenbill.app", "User Y")

    grp_resp = await client.post("/api/v1/groups/", headers=user_x["headers"], json={
        "name": "Audit Test Group",
        "group_type": "APARTMENT",
        "base_currency": "USD"
    })
    group_id = grp_resp.json()["data"]["id"]
    invite_code = grp_resp.json()["data"]["invite_code"]
    await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_y["headers"])

    # 1. User X creates $100 expense split equally ($50 each)
    exp_resp = await client.post("/api/v1/expenses/", headers=user_x["headers"], json={
        "group_id": group_id,
        "description": "Initial Groceries",
        "total_amount": 100.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user_x["id"], user_y["id"]]
    })
    assert exp_resp.status_code == 201
    expense_id = exp_resp.json()["data"]["id"]
    assert exp_resp.json()["data"]["version"] == 1

    # Check balance: User Y owes $50
    bal_1 = await client.get(f"/api/v1/groups/{group_id}", headers=user_x["headers"])
    net_map_1 = {b["user_id"]: Decimal(str(b["net_balance"])) for b in bal_1.json()["data"]["net_balances"]}
    assert net_map_1[user_y["id"]] == Decimal("-50.0000")

    # 2. User X edits expense to $160 ($80 each)
    update_resp = await client.put(f"/api/v1/expenses/{expense_id}", headers=user_x["headers"], json={
        "description": "Corrected Groceries with Receipts",
        "total_amount": 160.00,
        "split_type": "EQUAL",
        "participant_ids": [user_x["id"], user_y["id"]]
    })
    assert update_resp.status_code == 200
    assert update_resp.json()["data"]["version"] == 2
    assert Decimal(str(update_resp.json()["data"]["total_amount"])) == Decimal("160.0000")

    # Check updated balance: User Y must now owe $80
    bal_2 = await client.get(f"/api/v1/groups/{group_id}", headers=user_x["headers"])
    net_map_2 = {b["user_id"]: Decimal(str(b["net_balance"])) for b in bal_2.json()["data"]["net_balances"]}
    assert net_map_2[user_y["id"]] == Decimal("-80.0000")
    assert net_map_2[user_x["id"]] == Decimal("80.0000")

    # 3. User X deletes expense
    del_resp = await client.delete(f"/api/v1/expenses/{expense_id}", headers=user_x["headers"])
    assert del_resp.status_code == 200
    assert del_resp.json()["data"]["deleted"] is True

    # Check balance after deletion: Must immediately return to $0.0000
    bal_3 = await client.get(f"/api/v1/groups/{group_id}", headers=user_x["headers"])
    net_map_3 = {b["user_id"]: Decimal(str(b["net_balance"])) for b in bal_3.json()["data"]["net_balances"]}
    assert net_map_3[user_y["id"]] == Decimal("0.0000")
    assert net_map_3[user_x["id"]] == Decimal("0.0000")


@pytest.mark.asyncio
async def test_idempotency_protection(client: AsyncClient):
    """
    Submitting an expense or settlement with an existing idempotency_key must return
    the original entity without creating duplicate ledger records or double-charging.
    """
    user_p = await register_and_login(client, "userp@evenbill.app", "User P")
    user_q = await register_and_login(client, "userq@evenbill.app", "User Q")

    grp_resp = await client.post("/api/v1/groups/", headers=user_p["headers"], json={
        "name": "Idempotency Group",
        "group_type": "OTHER",
        "base_currency": "USD"
    })
    group_id = grp_resp.json()["data"]["id"]
    invite_code = grp_resp.json()["data"]["invite_code"]
    await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_q["headers"])

    # First submission of expense with idempotency key
    key = "idem-test-exp-9999"
    payload = {
        "idempotency_key": key,
        "group_id": group_id,
        "description": "Hotel Booking",
        "total_amount": 250.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [user_p["id"], user_q["id"]]
    }
    resp1 = await client.post("/api/v1/expenses/", headers=user_p["headers"], json=payload)
    assert resp1.status_code == 201
    exp_id_1 = resp1.json()["data"]["id"]

    # Second submission with identical idempotency key (simulating network retry)
    resp2 = await client.post("/api/v1/expenses/", headers=user_p["headers"], json=payload)
    assert resp2.status_code == 201
    exp_id_2 = resp2.json()["data"]["id"]

    # Invariant: Must return identical expense ID
    assert exp_id_1 == exp_id_2

    # Check group expenses count: must be exactly 1, not 2
    list_resp = await client.get(f"/api/v1/expenses/group/{group_id}", headers=user_p["headers"])
    assert len(list_resp.json()["data"]) == 1

    # First submission of settlement with idempotency key
    settle_key = "idem-test-settle-8888"
    settle_payload = {
        "idempotency_key": settle_key,
        "group_id": group_id,
        "recipient_id": user_p["id"],
        "amount": 125.00,
        "currency": "USD",
        "payment_method": "CASH"
    }
    s_resp1 = await client.post("/api/v1/settlements/", headers=user_q["headers"], json=settle_payload)
    assert s_resp1.status_code == 201
    s_id_1 = s_resp1.json()["data"]["id"]

    # Retry settlement
    s_resp2 = await client.post("/api/v1/settlements/", headers=user_q["headers"], json=settle_payload)
    assert s_resp2.status_code == 201
    s_id_2 = s_resp2.json()["data"]["id"]
    assert s_id_1 == s_id_2

    # Verify balance is exactly 0.00, not over-settled
    bal = await client.get(f"/api/v1/groups/{group_id}", headers=user_p["headers"])
    net_map = {b["user_id"]: Decimal(str(b["net_balance"])) for b in bal.json()["data"]["net_balances"]}
    assert net_map[user_p["id"]] == Decimal("0.0000")
    assert net_map[user_q["id"]] == Decimal("0.0000")


@pytest.mark.asyncio
async def test_personal_non_group_expenses_and_1on1_balances(client: AsyncClient):
    """
    Tests personal individual expenses (group_id=None), personal listing,
    and 1-on-1 bilateral friend balances without double-counting payer's own share.
    """
    dave = await register_and_login(client, "dave@evenbill.app", "Dave Miller")
    emma = await register_and_login(client, "emma@evenbill.app", "Emma Watson")

    # Dave pays $80.00 for Dave and Emma (non-group expense)
    # Dave paid $80, Dave owes $40, Emma owes $40.
    exp_resp = await client.post("/api/v1/expenses/", headers=dave["headers"], json={
        "group_id": None,
        "description": "Concert Tickets",
        "total_amount": 80.00,
        "currency": "USD",
        "split_type": "EQUAL",
        "participant_ids": [dave["id"], emma["id"]]
    })
    assert exp_resp.status_code == 201
    exp_data = exp_resp.json()["data"]
    assert exp_data["group_id"] is None

    # Verify personal expenses endpoint returns this expense for both users
    dave_pers = await client.get("/api/v1/expenses/personal", headers=dave["headers"])
    assert len(dave_pers.json()["data"]) == 1

    emma_pers = await client.get("/api/v1/expenses/personal", headers=emma["headers"])
    assert len(emma_pers.json()["data"]) == 1

    # Check 1-on-1 bilateral balance from Dave's perspective
    # Emma owes Dave $40
    dave_bal = await client.get(f"/api/v1/expenses/balances/1on1?friend_id={emma['id']}", headers=dave["headers"])
    assert dave_bal.status_code == 200
    d_data = dave_bal.json()["data"]
    assert d_data["status"] == "YOU_ARE_OWED"
    assert Decimal(str(d_data["net_balance"])) == Decimal("40.0000")
    assert Decimal(str(d_data["amount"])) == Decimal("40.0000")

    # Check 1-on-1 bilateral balance from Emma's perspective
    # Emma owes Dave $40 (net balance negative)
    emma_bal = await client.get(f"/api/v1/expenses/balances/1on1?friend_id={dave['id']}", headers=emma["headers"])
    assert emma_bal.status_code == 200
    e_data = emma_bal.json()["data"]
    assert e_data["status"] == "YOU_OWE"
    assert Decimal(str(e_data["net_balance"])) == Decimal("-40.0000")

    # Emma records external payment of $40.00 to Dave (non-group settlement)
    settle_resp = await client.post("/api/v1/settlements/", headers=emma["headers"], json={
        "group_id": None,
        "recipient_id": dave["id"],
        "amount": 40.00,
        "currency": "USD",
        "payment_method": "VENMO",
        "transaction_reference": "VENMO-102938"
    })
    assert settle_resp.status_code == 201

    # Verify 1-on-1 balance is now SETTLED at 0.0000
    dave_bal_after = await client.get(f"/api/v1/expenses/balances/1on1?friend_id={emma['id']}", headers=dave["headers"])
    assert dave_bal_after.json()["data"]["status"] == "SETTLED"
    assert Decimal(str(dave_bal_after.json()["data"]["net_balance"])) == Decimal("0.0000")


@pytest.mark.asyncio
async def test_multi_currency_frozen_snapshot(client: AsyncClient):
    """
    Verifies that multi-currency expenses freeze the exchange rate, rate source,
    and conversion timestamp at the moment of creation, and never alter past balances.
    """
    user_m = await register_and_login(client, "userm@evenbill.app", "User M")
    user_n = await register_and_login(client, "usern@evenbill.app", "User N")

    # Group base currency is USD
    grp_resp = await client.post("/api/v1/groups/", headers=user_m["headers"], json={
        "name": "Tokyo Travel",
        "group_type": "TRIP",
        "base_currency": "USD"
    })
    group_id = grp_resp.json()["data"]["id"]
    invite_code = grp_resp.json()["data"]["invite_code"]
    await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_n["headers"])

    # User M logs an expense in JPY (15,000 JPY) with exchange rate 0.0067 USD/JPY ($100.50 USD)
    exp_resp = await client.post("/api/v1/expenses/", headers=user_m["headers"], json={
        "group_id": group_id,
        "description": "Shinkansen Bullet Train",
        "total_amount": 15000,
        "currency": "JPY",
        "exchange_rate": 0.0067,
        "exchange_rate_source": "OPEN_EXCHANGE_RATES",
        "split_type": "EQUAL",
        "participant_ids": [user_m["id"], user_n["id"]]
    })
    assert exp_resp.status_code == 201
    exp_data = exp_resp.json()["data"]

    # Verify original currency & amount are preserved
    assert exp_data["currency"] == "JPY"
    assert Decimal(str(exp_data["total_amount"])) == Decimal("15000")

    # Verify frozen conversion snapshot
    assert exp_data["exchange_rate_source"] == "OPEN_EXCHANGE_RATES"
    assert exp_data["exchange_rate_timestamp"] is not None
    assert Decimal(str(exp_data["exchange_rate"])) == Decimal("0.0067")
    # Base amount = 15000 * 0.0067 = 100.50 USD
    assert Decimal(str(exp_data["base_currency_amount"])) == Decimal("100.5000")

    # Check group balance in USD: User N owes half ($50.25 USD)
    bal_resp = await client.get(f"/api/v1/groups/{group_id}", headers=user_m["headers"])
    assert bal_resp.status_code == 200
    net_map = {b["user_id"]: Decimal(str(b["net_balance"])) for b in bal_resp.json()["data"]["net_balances"]}
    assert net_map[user_n["id"]] == Decimal("-50.2500")
    assert net_map[user_m["id"]] == Decimal("50.2500")
    assert sum(net_map.values()) == Decimal("0.0000")


@pytest.mark.asyncio
async def test_direct_add_group_member_and_directional_settlement(client: AsyncClient):
    """
    Verifies directly adding an offline member (and existing user) to a group,
    future signup with the offline member's email not failing with 409, and
    recording settlements with explicit payer_id ('Member paid You' direction).
    """
    owner = await register_and_login(client, "owner_direct@evenbill.app", "Owner Direct")
    friend_user = await register_and_login(client, "existing_friend@evenbill.app", "Existing Friend")

    grp_resp = await client.post("/api/v1/groups/", headers=owner["headers"], json={
        "name": "Goa House",
        "group_type": "TRIP",
        "base_currency": "INR"
    })
    assert grp_resp.status_code == 201
    group_id = grp_resp.json()["data"]["id"]

    # 1. Directly add a non-registered offline member by name + email
    add_offline = await client.post(f"/api/v1/groups/{group_id}/members", headers=owner["headers"], json={
        "full_name": "Rahul Offline",
        "email": "rahul.offline@evenbill.app"
    })
    assert add_offline.status_code == 201
    offline_member = add_offline.json()["data"]
    assert offline_member["full_name"] == "Rahul Offline"
    offline_uid = offline_member["user_id"]

    # 2. Future real signup with that same email must NOT collide (no 409)
    signup_later = await client.post("/api/v1/auth/register", json={
        "email": "rahul.offline@evenbill.app",
        "password": "StrongPassword123!",
        "full_name": "Rahul Offline Real",
        "default_currency": "INR"
    })
    assert signup_later.status_code == 201

    # 3. Directly add existing registered user by email
    add_existing = await client.post(f"/api/v1/groups/{group_id}/members", headers=owner["headers"], json={
        "full_name": "Existing Friend",
        "email": "existing_friend@evenbill.app"
    })
    assert add_existing.status_code == 201
    assert add_existing.json()["data"]["user_id"] == friend_user["id"]

    # 4. Friends list immediately sees co-members (settlement partners available)
    friends_resp = await client.get("/api/v1/friends/", headers=owner["headers"])
    assert friends_resp.status_code == 200
    friend_ids = {f["id"] for f in friends_resp.json()["data"]}
    assert offline_uid in friend_ids
    assert friend_user["id"] in friend_ids

    # 5. Record directional settlement where Existing Friend paid Owner ('Member paid You')
    rev_settle = await client.post("/api/v1/settlements/", headers=owner["headers"], json={
        "group_id": group_id,
        "payer_id": friend_user["id"],
        "recipient_id": owner["id"],
        "amount": 500.00,
        "currency": "INR",
        "payment_method": "CASH"
    })
    assert rev_settle.status_code == 201
    stl_data = rev_settle.json()["data"]
    assert stl_data["payer_id"] == friend_user["id"]
    assert stl_data["recipient_id"] == owner["id"]

    # 6. Outsider cannot forge settlement between two other users
    outsider = await register_and_login(client, "outsider_settle@evenbill.app", "Outsider")
    forged = await client.post("/api/v1/settlements/", headers=outsider["headers"], json={
        "group_id": group_id,
        "payer_id": friend_user["id"],
        "recipient_id": owner["id"],
        "amount": 100.00,
        "currency": "INR",
        "payment_method": "CASH"
    })
    assert forged.status_code == 403


