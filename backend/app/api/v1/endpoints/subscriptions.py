"""
EvenBill Subscriptions & Entitlement Endpoints
Provides queries for current plan limits, usage tracking, upgrade options,
and sandbox/mock upgrade controls for testing and demonstration.
"""

from typing import Optional, Dict, Any
from datetime import datetime
import uuid
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Request, Header, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.entitlement_service import EntitlementService, PlanTier
from app.services.subscription_service import SubscriptionService, WebhookEventType

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions & Entitlements"])


class MockUpgradeRequest(BaseModel):
    tier: str = Field(default="PRO_MONTHLY", description="Target tier: FREE, PRO_MONTHLY, or PRO_ANNUAL")


class VerifyReceiptRequest(BaseModel):
    store: str = Field(..., description="Store: APPLE_APP_STORE, GOOGLE_PLAY, or REVENUECAT")
    purchase_token: str = Field(..., description="Signed receipt token or JWS payload")
    product_id: str = Field(..., description="In-app product ID, e.g. evenbill_pro_monthly")
    is_sandbox: bool = Field(default=True, description="Sandbox testing flag")


class SubscriptionOverrideRequest(BaseModel):
    user_id: str
    tier: str
    status: str = "ACTIVE"
    expires_at: Optional[datetime] = None


@router.get("/me", response_model=APIResponse[Dict[str, Any]])
async def get_my_entitlements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Retrieve active subscription plan, feature gates, daily expense limits, and usage.
    """
    summary = await EntitlementService.get_user_entitlements_summary(db, current_user)
    return APIResponse(data=summary)


@router.post("/mock-upgrade", response_model=APIResponse[Dict[str, Any]])
async def mock_upgrade_tier(
    data: MockUpgradeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Switch or upgrade subscription tier in mock/sandbox mode without real payment billing.
    Enables testing and verifying Pro vs Free behaviors.
    """
    target_tier = data.tier.upper().strip()
    if target_tier not in ("FREE", "PRO", "PRO_MONTHLY", "PRO_ANNUAL"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid subscription tier: {data.tier}. Valid tiers: FREE, PRO_MONTHLY, PRO_ANNUAL"
        )

    await EntitlementService.override_subscription(
        db=db,
        user_id=current_user.id,
        tier=target_tier,
        status="ACTIVE" if target_tier != "FREE" else "INACTIVE"
    )

    summary = await EntitlementService.get_user_entitlements_summary(db, current_user)
    return APIResponse(data=summary)


@router.post("/override", response_model=APIResponse[Dict[str, Any]])
async def override_user_subscription(
    data: SubscriptionOverrideRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Administrative / testing endpoint to override any user's subscription tier.
    """
    target_tier = data.tier.upper().strip()
    await EntitlementService.override_subscription(
        db=db,
        user_id=data.user_id,
        tier=target_tier,
        status=data.status,
        expires_at=data.expires_at
    )

    # Return updated summary for target user
    user = await db.get(User, data.user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    summary = await EntitlementService.get_user_entitlements_summary(db, user)
    return APIResponse(data=summary)


@router.post("/verify-receipt", response_model=APIResponse[Dict[str, Any]])
async def verify_purchase_receipt(
    data: VerifyReceiptRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Cryptographically validates In-App Purchase token server-side (StoreKit 2 / Google Play / RevenueCat).
    Never trusts client-only local state.
    """
    result = await SubscriptionService.verify_mobile_purchase_receipt(
        db=db,
        user=current_user,
        store=data.store,
        purchase_token=data.purchase_token,
        product_id=data.product_id,
        is_sandbox=data.is_sandbox
    )
    return APIResponse(data=result)


@router.post("/webhooks/{store}", response_model=APIResponse[Dict[str, Any]])
async def process_store_webhook(
    store: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    x_webhook_signature: Optional[str] = Header(None, alias="X-Webhook-Signature"),
    x_revenuecat_signature: Optional[str] = Header(None, alias="X-RevenueCat-Signature"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
):
    """
    Processes verified store lifecycle webhooks (RevenueCat, Apple, Google, Stripe).
    Handles initial purchases, renewals, cancellations, grace periods, refunds, and duplicate idempotency.
    """
    raw_body = await request.body()
    signature = x_webhook_signature or x_revenuecat_signature or authorization
    is_valid = SubscriptionService.verify_webhook_signature(raw_body, signature)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing webhook signature."
        )

    import json
    try:
        payload = json.loads(raw_body)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Malformed JSON webhook body."
        )

    # Normalize fields from payload
    event_data = payload.get("event", payload)
    event_id = str(event_data.get("id") or payload.get("event_id") or uuid.uuid4())
    event_type = event_data.get("type") or payload.get("event_type", "INITIAL_PURCHASE")
    user_id = event_data.get("app_user_id") or payload.get("user_id")
    tier = payload.get("tier", "PRO_MONTHLY")
    orig_tx = event_data.get("original_transaction_id") or payload.get("original_transaction_id")

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Missing user identifier in webhook payload."
        )

    result = await SubscriptionService.process_webhook_event(
        db=db,
        store=store,
        event_id=event_id,
        event_type=event_type,
        user_id=user_id,
        tier=tier,
        original_transaction_id=orig_tx,
        raw_payload=payload
    )
    return APIResponse(data=result)

