"""
EvenBill Bank Transaction Import Endpoints
Regulated, read-only transaction feeds gated by compliance approvals,
approved financial providers, and EvenBill Pro entitlements.
"""

from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.entitlement_service import EntitlementService, PlanTier, FeatureKey, FeatureLockedException
from app.services.bank_integration_service import (
    BankIntegrationService, BankIntegrationStatus, BankTransactionItem
)

router = APIRouter(prefix="/bank", tags=["Bank Transaction Import (Pro)"])


class SyncBankTransactionsRequest(BaseModel):
    account_id: str = Field(..., description="Connected bank account identifier")
    country_code: str = Field("US", min_length=2, max_length=2, description="2-letter ISO country code")
    is_sandbox: bool = Field(True, description="Sandbox test mode flag")


@router.get("/status", response_model=APIResponse[BankIntegrationStatus])
async def get_bank_integration_status(
    country_code: Optional[str] = Query("US", min_length=2, max_length=2),
    current_user: User = Depends(get_current_user),
):
    """
    Returns the Open Banking compliance status, provider status, and supported countries.
    """
    status_info = BankIntegrationService.get_status(country_code)
    return APIResponse(data=status_info)


@router.post("/sync-transactions", response_model=APIResponse[List[BankTransactionItem]])
async def sync_bank_transactions(
    data: SyncBankTransactionsRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Imports read-only bank transactions for converting into split expenses.
    Requires EvenBill Pro entitlement, user consent, approved provider, and approved jurisdiction.
    """
    plan = await EntitlementService.get_user_plan(db, current_user)
    if plan != PlanTier.PRO:
        raise FeatureLockedException(
            feature_key=FeatureKey.BANK_IMPORT,
            detail="Bank transaction import is an EvenBill Pro feature.",
            plan=plan,
            permitted_next_action="Upgrade to EvenBill Pro to link bank accounts and import transactions."
        )

    # Enforce compliance gate
    BankIntegrationService.assert_import_permitted(data.country_code, allow_sandbox=data.is_sandbox)

    if data.is_sandbox:
        items = BankIntegrationService.get_sandbox_transactions(data.account_id, data.country_code)
        return APIResponse(data=items)

    # In production without live approved credentials, assert_import_permitted raises 403
    return APIResponse(data=[])
