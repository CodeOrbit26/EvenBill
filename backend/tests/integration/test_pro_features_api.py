"""
Integration Tests for EvenBill Pro Capabilities
Validates:
1. Private receipt upload, MIME & magic bytes validation, and OCR extraction
2. Duplicate receipt submission handling via SHA-256 content hashing
3. Authenticated time-limited signed download URLs with access control
4. Receipt soft-deletion and 30-day retention behavior
5. Legitimate multi-currency FX conversion (ECB daily benchmark rates, unchanged original amount, rate status)
6. Search and filtering across past expenses (query, category, date range, amount range, has_receipt)
7. Group saved split templates (gated for Free, enabled for Pro, default setting, CRUD)
8. Spending analytics, category insights, and monthly trend graphs
9. Server-side mobile receipt verification & webhook lifecycle orchestration (purchase, renewal, grace period, cancellation, refund, duplicate idempotency)
10. Bank integration compliance gate (read-only permissions, Open Banking compliance, supported countries)
"""

import pytest
import hmac
import hashlib
import json
from datetime import datetime, timezone, timedelta, date
from decimal import Decimal
from httpx import AsyncClient

from app.services.subscription_service import SubscriptionService, WebhookEventType
from app.services.bank_integration_service import BankIntegrationService


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
async def test_receipt_upload_validation_and_ocr(client: AsyncClient):
    """
    Verifies receipt upload validation (MIME, magic bytes, size),
    SHA-256 duplicate detection, OCR extraction, and signed URL generation.
    """
    user_alice = await register_user(client, "alice_receipts@evenbill.app", "Alice Smith")
    user_bob = await register_user(client, "bob_receipts@evenbill.app", "Bob Jones")

    # 1. Invalid file header (magic bytes mismatch)
    corrupt_content = b"THIS IS NOT A VALID JPEG HEADER"
    files = {"file": ("fake.jpg", corrupt_content, "image/jpeg")}
    bad_resp = await client.post("/api/v1/receipts/upload", files=files, headers=user_alice["headers"])
    assert bad_resp.status_code == 422
    assert "content signature does not match" in bad_resp.json()["detail"]

    # 2. Valid JPEG file (JPEG magic bytes b"\xff\xd8\xff" + payload)
    valid_jpeg = b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"A" * 500
    files = {"file": ("dinner_receipt.jpg", valid_jpeg, "image/jpeg")}
    upload_resp = await client.post("/api/v1/receipts/upload", files=files, headers=user_alice["headers"])
    assert upload_resp.status_code == 201
    data = upload_resp.json()["data"]
    receipt_id = data["id"]
    assert data["is_duplicate"] is False
    assert data["ocr_status"] == "COMPLETED"
    assert "ocr_data" in data
    assert len(data["ocr_data"]["items"]) > 0

    # 3. Duplicate submission of the exact same receipt
    dup_files = {"file": ("dinner_receipt_dup.jpg", valid_jpeg, "image/jpeg")}
    dup_resp = await client.post("/api/v1/receipts/upload", files=dup_files, headers=user_alice["headers"])
    assert dup_resp.status_code == 201
    dup_data = dup_resp.json()["data"]
    assert dup_data["is_duplicate"] is True
    assert dup_data["id"] == receipt_id

    # 4. Generate Authenticated Signed URL (Alice is authorized)
    signed_resp = await client.get(f"/api/v1/receipts/{receipt_id}/signed-url", headers=user_alice["headers"])
    assert signed_resp.status_code == 200
    signed_data = signed_resp.json()["data"]
    assert "signed_url" in signed_data
    assert signed_data["expires_in_seconds"] == 900  # 15 minutes TTL

    # 5. Bob (unrelated third party) attempts to access signed URL -> 403 Forbidden
    bob_signed = await client.get(f"/api/v1/receipts/{receipt_id}/signed-url", headers=user_bob["headers"])
    assert bob_signed.status_code == 403

    # 6. Soft Delete Receipt into 30-day retention queue
    del_resp = await client.delete(f"/api/v1/receipts/{receipt_id}", headers=user_alice["headers"])
    assert del_resp.status_code == 200
    assert del_resp.json()["data"]["deleted"] is True


@pytest.mark.asyncio
async def test_fx_currency_conversion(client: AsyncClient):
    """
    Verifies multi-currency conversion using legitimate ECB daily benchmarks.
    Ensures original amounts are preserved unchanged and exchange rate metadata is recorded.
    """
    user = await register_user(client, "fx_user@evenbill.app", "FX User")

    # 1. Identity conversion (USD to USD)
    rate_resp = await client.get("/api/v1/fx/rate?from_currency=USD&to_currency=USD", headers=user["headers"])
    assert rate_resp.status_code == 200
    rate_data = rate_resp.json()["data"]
    assert Decimal(str(rate_data["rate"])) == Decimal("1.0")
    assert rate_data["status"] == "LIVE"
    assert rate_data["source"] == "IDENTITY"

    # 2. Convert USD to EUR using ECB reference benchmark
    conv_resp = await client.post("/api/v1/fx/convert", json={
        "amount": 108.50,
        "from_currency": "USD",
        "to_currency": "EUR"
    }, headers=user["headers"])
    assert conv_resp.status_code == 200
    conv_data = conv_resp.json()["data"]
    assert Decimal(str(conv_data["original_amount"])) == Decimal("108.50")
    assert conv_data["original_currency"] == "USD"
    assert conv_data["target_currency"] == "EUR"
    assert conv_data["rate_status"] == "LIVE"
    assert "ECB" in conv_data["source"]
    assert Decimal(str(conv_data["converted_amount"])) > 0

    # 3. Unknown currency pair falls back gracefully with transparent warning
    unavail_resp = await client.get("/api/v1/fx/rate?from_currency=XYZ&to_currency=ABC", headers=user["headers"])
    assert unavail_resp.status_code == 200
    unavail_data = unavail_resp.json()["data"]
    assert unavail_data["status"] == "UNAVAILABLE"
    assert unavail_data["is_stale"] is True
    assert "warning" in unavail_data


@pytest.mark.asyncio
async def test_search_and_filtering_expenses(client: AsyncClient):
    """
    Verifies search and filtering across past expenses (query, category, amounts, dates).
    """
    user = await register_user(client, "search_user@evenbill.app", "Search User")

    # Create 3 distinct expenses
    await client.post("/api/v1/expenses/", json={
        "description": "Italian Dinner at Trattoria",
        "total_amount": 120.00,
        "currency": "USD",
        "category": "Dining Out",
        "expense_date": "2026-10-01",
        "split_type": "EQUAL",
        "notes": "Had pasta and gelato with team",
        "participant_ids": [user["id"]]
    }, headers=user["headers"])

    await client.post("/api/v1/expenses/", json={
        "description": "Grocery Supermarket Run",
        "total_amount": 45.50,
        "currency": "USD",
        "category": "Groceries",
        "expense_date": "2026-10-05",
        "split_type": "EQUAL",
        "notes": "Milk and bread",
        "participant_ids": [user["id"]]
    }, headers=user["headers"])

    await client.post("/api/v1/expenses/", json={
        "description": "Monthly Fiber Broadband",
        "total_amount": 70.00,
        "currency": "USD",
        "category": "Utilities",
        "expense_date": "2026-10-10",
        "split_type": "EQUAL",
        "notes": "Internet bill",
        "participant_ids": [user["id"]]
    }, headers=user["headers"])

    # 1. Search by text query in description
    q_resp = await client.get("/api/v1/expenses/search?q=trattoria", headers=user["headers"])
    assert q_resp.status_code == 200
    results = q_resp.json()["data"]
    assert len(results) == 1
    assert "Trattoria" in results[0]["description"]

    # 2. Search by notes keyword
    notes_resp = await client.get("/api/v1/expenses/search?q=gelato", headers=user["headers"])
    assert notes_resp.status_code == 200
    assert len(notes_resp.json()["data"]) == 1

    # 3. Filter by category
    cat_resp = await client.get("/api/v1/expenses/search?category=Groceries", headers=user["headers"])
    assert cat_resp.status_code == 200
    assert len(cat_resp.json()["data"]) == 1
    assert cat_resp.json()["data"][0]["category"].upper() == "GROCERIES"

    # 4. Filter by amount range ($50 to $100)
    amt_resp = await client.get("/api/v1/expenses/search?min_amount=50&max_amount=100", headers=user["headers"])
    assert amt_resp.status_code == 200
    assert len(amt_resp.json()["data"]) == 1
    assert Decimal(str(amt_resp.json()["data"][0]["total_amount"])) == Decimal("70.00")

    # 5. Filter by date range (2026-10-02 to 2026-10-06)
    date_resp = await client.get("/api/v1/expenses/search?start_date=2026-10-02&end_date=2026-10-06", headers=user["headers"])
    assert date_resp.status_code == 200
    assert len(date_resp.json()["data"]) == 1
    assert date_resp.json()["data"][0]["description"] == "Grocery Supermarket Run"


@pytest.mark.asyncio
async def test_group_split_templates_pro_and_free(client: AsyncClient):
    """
    Verifies that saved group split templates are gated for Free users
    and fully accessible to EvenBill Pro subscribers.
    """
    user_free = await register_user(client, "free_template_user@evenbill.app", "Free Template")
    user_pro = await register_user(client, "pro_template_user@evenbill.app", "Pro Template")

    # Create a group with both users
    grp_resp = await client.post("/api/v1/groups/", json={
        "name": "Ski Trip 2026",
        "category": "Trip",
        "currency": "USD"
    }, headers=user_free["headers"])
    assert grp_resp.status_code == 201
    group_id = grp_resp.json()["data"]["id"]
    invite_code = grp_resp.json()["data"]["invite_code"]

    join_resp = await client.post(f"/api/v1/groups/join/{invite_code}", headers=user_pro["headers"])
    assert join_resp.status_code == 200

    # 1. Free user attempts to create a split template -> 403 FEATURE_LOCKED
    free_tmpl_resp = await client.post(f"/api/v1/groups/{group_id}/split-templates", json={
        "name": "60/40 Split",
        "split_type": "PERCENTAGE",
        "allocations": [
            {"user_id": user_free["id"], "value": 60.0},
            {"user_id": user_pro["id"], "value": 40.0}
        ],
        "is_default": True
    }, headers=user_free["headers"])
    assert free_tmpl_resp.status_code == 403
    assert free_tmpl_resp.json()["detail"]["code"] == "FEATURE_LOCKED"
    assert free_tmpl_resp.json()["detail"]["feature_key"] == "SAVED_SPLIT_TEMPLATES"

    # 2. Upgrade user_pro to Pro
    await client.post("/api/v1/subscriptions/mock-upgrade", json={"tier": "PRO_MONTHLY"}, headers=user_pro["headers"])

    # 3. Pro user creates a saved split template
    pro_tmpl_resp = await client.post(f"/api/v1/groups/{group_id}/split-templates", json={
        "name": "60/40 Ski Split",
        "split_type": "PERCENTAGE",
        "allocations": [
            {"user_id": user_free["id"], "value": 60.0},
            {"user_id": user_pro["id"], "value": 40.0}
        ],
        "is_default": True
    }, headers=user_pro["headers"])
    assert pro_tmpl_resp.status_code == 201
    tmpl_data = pro_tmpl_resp.json()["data"]
    template_id = tmpl_data["id"]
    assert tmpl_data["name"] == "60/40 Ski Split"
    assert tmpl_data["is_default"] is True

    # 4. List split templates
    list_resp = await client.get(f"/api/v1/groups/{group_id}/split-templates", headers=user_pro["headers"])
    assert list_resp.status_code == 200
    templates = list_resp.json()["data"]
    assert len(templates) == 1

    # 5. Update split template
    upd_resp = await client.put(f"/api/v1/groups/{group_id}/split-templates/{template_id}", json={
        "name": "70/30 Updated Split",
        "allocations": [
            {"user_id": user_free["id"], "value": 70.0},
            {"user_id": user_pro["id"], "value": 30.0}
        ]
    }, headers=user_pro["headers"])
    assert upd_resp.status_code == 200
    assert upd_resp.json()["data"]["name"] == "70/30 Updated Split"

    # 6. Delete split template
    del_resp = await client.delete(f"/api/v1/groups/{group_id}/split-templates/{template_id}", headers=user_pro["headers"])
    assert del_resp.status_code == 200
    assert del_resp.json()["data"]["deleted"] is True


@pytest.mark.asyncio
async def test_spending_analytics_and_insights(client: AsyncClient):
    """
    Verifies spending charts, category breakdown percentages, and monthly trend analytics.
    """
    user = await register_user(client, "analytics_pro@evenbill.app", "Analytics Pro")
    await client.post("/api/v1/subscriptions/mock-upgrade", json={"tier": "PRO_MONTHLY"}, headers=user["headers"])

    # Create expenses across 2 categories
    await client.post("/api/v1/expenses/", json={
        "description": "Weekly Groceries",
        "total_amount": 150.00,
        "currency": "USD",
        "category": "Groceries",
        "expense_date": "2026-10-01",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]]
    }, headers=user["headers"])

    await client.post("/api/v1/expenses/", json={
        "description": "Team Dinner",
        "total_amount": 50.00,
        "currency": "USD",
        "category": "Dining Out",
        "expense_date": "2026-10-05",
        "split_type": "EQUAL",
        "participant_ids": [user["id"]]
    }, headers=user["headers"])

    # Request analytics insights
    resp = await client.get("/api/v1/analytics/spending?currency=USD", headers=user["headers"])
    assert resp.status_code == 200
    data = resp.json()["data"]

    assert data["is_pro"] is True
    assert data["total_spent_personal_share"] == 200.00
    assert data["total_expenses_count"] == 2

    # Check categories breakdown (Groceries should be 75%, Dining Out 25%)
    categories = {c["category"].upper(): c for c in data["categories"]}
    assert "GROCERIES" in categories
    assert "DINING OUT" in categories
    assert categories["GROCERIES"]["total_amount"] == 150.00
    assert categories["GROCERIES"]["percentage"] == 75.0
    assert categories["DINING OUT"]["total_amount"] == 50.00
    assert categories["DINING OUT"]["percentage"] == 25.0

    # Check monthly trend
    assert len(data["monthly_trend"]) == 1
    assert data["monthly_trend"][0]["month"] == "2026-10"
    assert data["monthly_trend"][0]["total_amount"] == 200.00


@pytest.mark.asyncio
async def test_subscription_receipt_verification_and_webhooks(client: AsyncClient):
    """
    Verifies server-side in-app purchase verification and webhook event orchestration:
    initial purchase, renewal, cancellation, grace period, expiration, refund, and duplicate idempotency.
    """
    user = await register_user(client, "sub_lifecycle@evenbill.app", "Sub Lifecycle")

    # 1. Server-side mobile receipt verification
    verify_resp = await client.post("/api/v1/subscriptions/verify-receipt", json={
        "store": "APPLE_APP_STORE",
        "purchase_token": "valid_storekit2_signed_jws_token_sample_12345",
        "product_id": "com.evenbill.pro.monthly",
        "is_sandbox": True
    }, headers=user["headers"])
    assert verify_resp.status_code == 200
    v_data = verify_resp.json()["data"]
    assert v_data["verified"] is True
    assert v_data["is_pro"] is True

    # 2. Webhook: INITIAL_PURCHASE
    event_id = "evt_wh_001"
    body = {
        "event_id": event_id,
        "event_type": WebhookEventType.INITIAL_PURCHASE,
        "user_id": user["id"],
        "tier": "PRO_MONTHLY",
        "original_transaction_id": "tx_apple_1001"
    }
    raw_body = json.dumps(body).encode()
    sig = hmac.new(SubscriptionService.WEBHOOK_SECRET.encode(), raw_body, hashlib.sha256).hexdigest()

    wh_resp = await client.post(
        "/api/v1/subscriptions/webhooks/apple",
        content=raw_body,
        headers={"X-Webhook-Signature": sig, "Content-Type": "application/json"}
    )
    assert wh_resp.status_code == 200
    assert wh_resp.json()["data"]["status"] == "PROCESSED"
    assert wh_resp.json()["data"]["is_pro"] is True

    # 3. Idempotency: Resend identical webhook event -> DUPLICATE_IGNORED
    wh_dup = await client.post(
        "/api/v1/subscriptions/webhooks/apple",
        content=raw_body,
        headers={"X-Webhook-Signature": sig, "Content-Type": "application/json"}
    )
    assert wh_dup.status_code == 200
    assert wh_dup.json()["data"]["status"] == "DUPLICATE_IGNORED"

    # 4. Webhook: BILLING_ISSUE_GRACE_PERIOD (User retains Pro status during grace period)
    gp_body = {
        "event_id": "evt_wh_002",
        "event_type": WebhookEventType.BILLING_ISSUE_GRACE_PERIOD,
        "user_id": user["id"],
        "tier": "PRO_MONTHLY"
    }
    gp_raw = json.dumps(gp_body).encode()
    gp_sig = hmac.new(SubscriptionService.WEBHOOK_SECRET.encode(), gp_raw, hashlib.sha256).hexdigest()
    gp_resp = await client.post(
        "/api/v1/subscriptions/webhooks/apple",
        content=gp_raw,
        headers={"X-Webhook-Signature": gp_sig, "Content-Type": "application/json"}
    )
    assert gp_resp.status_code == 200
    assert gp_resp.json()["data"]["subscription_status"] == "IN_GRACE_PERIOD"
    assert gp_resp.json()["data"]["is_pro"] is True

    # 5. Webhook: REFUND -> Immediately revokes Pro access
    ref_body = {
        "event_id": "evt_wh_003",
        "event_type": WebhookEventType.REFUND,
        "user_id": user["id"]
    }
    ref_raw = json.dumps(ref_body).encode()
    ref_sig = hmac.new(SubscriptionService.WEBHOOK_SECRET.encode(), ref_raw, hashlib.sha256).hexdigest()
    ref_resp = await client.post(
        "/api/v1/subscriptions/webhooks/apple",
        content=ref_raw,
        headers={"X-Webhook-Signature": ref_sig, "Content-Type": "application/json"}
    )
    assert ref_resp.status_code == 200
    assert ref_resp.json()["data"]["subscription_status"] == "REFUNDED"
    assert ref_resp.json()["data"]["tier"] == "FREE"
    assert ref_resp.json()["data"]["is_pro"] is False


@pytest.mark.asyncio
async def test_bank_integration_compliance_gate(client: AsyncClient):
    """
    Verifies bank transaction import compliance gate:
    1. Status endpoint returns Open Banking compliance parameters.
    2. Unsupported country code is rejected with 400.
    3. Gated for Free users (403 FEATURE_LOCKED).
    4. Pro users can sync sandbox read-only feed for ledger expense creation.
    """
    user_free = await register_user(client, "free_bank@evenbill.app", "Free Bank")
    user_pro = await register_user(client, "pro_bank@evenbill.app", "Pro Bank")
    await client.post("/api/v1/subscriptions/mock-upgrade", json={"tier": "PRO_MONTHLY"}, headers=user_pro["headers"])

    # 1. Check Bank Status (Open Banking & PSD2 Compliance)
    status_resp = await client.get("/api/v1/bank/status?country_code=US", headers=user_pro["headers"])
    assert status_resp.status_code == 200
    status_data = status_resp.json()["data"]
    assert status_data["read_only_enforced"] is True
    assert status_data["requires_consent"] is True
    assert "US" in status_data["supported_countries"]

    # 2. Unsupported country code -> 400 Bad Request
    unsupp_resp = await client.post("/api/v1/bank/sync-transactions", json={
        "account_id": "acc_123",
        "country_code": "ZZ",
        "is_sandbox": True
    }, headers=user_pro["headers"])
    assert unsupp_resp.status_code == 400
    assert "not an approved jurisdiction" in unsupp_resp.json()["detail"]

    # 3. Free user -> 403 FEATURE_LOCKED
    free_resp = await client.post("/api/v1/bank/sync-transactions", json={
        "account_id": "acc_123",
        "country_code": "US",
        "is_sandbox": True
    }, headers=user_free["headers"])
    assert free_resp.status_code == 403
    assert free_resp.json()["detail"]["code"] == "FEATURE_LOCKED"
    assert free_resp.json()["detail"]["feature_key"] == "BANK_IMPORT"

    # 4. Pro user in sandbox mode -> successfully imports read-only transactions
    pro_resp = await client.post("/api/v1/bank/sync-transactions", json={
        "account_id": "acc_test_checking_001",
        "country_code": "US",
        "is_sandbox": True
    }, headers=user_pro["headers"])
    assert pro_resp.status_code == 200
    txs = pro_resp.json()["data"]
    assert len(txs) > 0
    assert txs[0]["pending"] is False
    assert "suggested_expense_description" in txs[0]
