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
