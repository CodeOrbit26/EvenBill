"""
EvenBill User Profile & Privacy Endpoints
Handles profile retrieval, updates, GDPR/CCPA data export, and right-to-be-forgotten deletion.
"""

from typing import Dict, Any
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserUpdate, UserResponse
from app.schemas.common import APIResponse
from app.services.privacy_service import PrivacyService
from app.core.rate_limit import rate_limit

router = APIRouter(prefix="/users", tags=["Users & Privacy"])


@router.get("/me", response_model=APIResponse[UserResponse])
async def get_user_profile(
    current_user: User = Depends(get_current_user)
):
    is_pro = any(sub.is_pro for sub in current_user.subscriptions)
    user_response = UserResponse(
        id=current_user.id,
        email=current_user.email,
        full_name=current_user.full_name,
        phone_number=current_user.phone_number,
        avatar_url=current_user.avatar_url,
        default_currency=current_user.default_currency,
        is_active=current_user.is_active,
        is_verified=current_user.is_verified,
        has_password=bool(current_user.hashed_password or getattr(current_user, "_token_has_password", False)),
        is_pro=is_pro,
        created_at=current_user.created_at
    )
    return APIResponse(data=user_response)


@router.put("/me", response_model=APIResponse[UserResponse])
async def update_user_profile(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if data.full_name is not None:
        current_user.full_name = data.full_name.strip()
    if data.default_currency is not None:
        current_user.default_currency = data.default_currency.upper().strip()
    if data.avatar_url is not None:
        current_user.avatar_url = data.avatar_url.strip()

    await db.commit()
    await db.refresh(current_user)

    is_pro = any(sub.is_pro for sub in current_user.subscriptions)
    user_response = UserResponse(
        id=current_user.id,
        email=current_user.email,
        full_name=current_user.full_name,
        phone_number=current_user.phone_number,
        avatar_url=current_user.avatar_url,
        default_currency=current_user.default_currency,
        is_active=current_user.is_active,
        is_verified=current_user.is_verified,
        has_password=bool(current_user.hashed_password or getattr(current_user, "_token_has_password", False)),
        is_pro=is_pro,
        created_at=current_user.created_at
    )
    return APIResponse(data=user_response)


@router.post(
    "/me/export",
    response_model=APIResponse[Dict[str, Any]],
    dependencies=[Depends(rate_limit(max_requests=5, window_seconds=3600, scope="user_export"))]
)
async def export_my_data(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Exports complete personal data, transactions, groups, and subscriptions
    under GDPR Article 20 / CCPA data portability requirements.
    """
    export_bundle = await PrivacyService.export_user_data(db, current_user)
    return APIResponse(data=export_bundle)


@router.delete(
    "/me",
    response_model=APIResponse[Dict[str, Any]],
    dependencies=[Depends(rate_limit(max_requests=2, window_seconds=86400, scope="account_deletion"))]
)
async def delete_my_account(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Permanently anonymizes user profile (GDPR Article 17) while safeguarding
    the ledger integrity invariant for group members.
    """
    result = await PrivacyService.delete_and_anonymize_user(db, current_user)
    return APIResponse(data=result)
