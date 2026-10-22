"""
EvenBill Auth REST Endpoints
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserCreate, UserLogin, UserResponse, Token, RefreshTokenRequest
from app.schemas.common import APIResponse
from app.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=APIResponse[UserResponse], status_code=status.HTTP_201_CREATED)
async def register(
    data: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    user = await AuthService.register_user(db, data)
    user_response = UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone_number=user.phone_number,
        avatar_url=user.avatar_url,
        default_currency=user.default_currency,
        is_active=user.is_active,
        is_verified=user.is_verified,
        is_pro=False,
        created_at=user.created_at
    )
    return APIResponse(data=user_response)


@router.post("/login", response_model=APIResponse[Token])
async def login(
    data: UserLogin,
    db: AsyncSession = Depends(get_db)
):
    _, token = await AuthService.authenticate_user(db, data)
    return APIResponse(data=token)


@router.post("/refresh", response_model=APIResponse[Token])
async def refresh_token(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    token = await AuthService.refresh_access_token(db, data.refresh_token)
    return APIResponse(data=token)


@router.get("/me", response_model=APIResponse[UserResponse])
async def get_me(
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
        is_pro=is_pro,
        created_at=current_user.created_at
    )
    return APIResponse(data=user_response)
