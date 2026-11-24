"""
EvenBill Auth REST Endpoints
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.user import UserCreate, UserLogin, UserUpdate, UserResponse, Token, RefreshTokenRequest, OAuthLoginRequest, SetPasswordRequest
from app.schemas.common import APIResponse
from app.services.auth_service import AuthService

from app.core.rate_limit import rate_limit

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=APIResponse[UserResponse],
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit(max_requests=60, window_seconds=60, scope="auth_register"))]
)
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
        has_password=bool(user.hashed_password),
        is_pro=False,
        created_at=user.created_at
    )
    return APIResponse(data=user_response)


@router.post(
    "/login",
    response_model=APIResponse[Token],
    dependencies=[Depends(rate_limit(max_requests=60, window_seconds=60, scope="auth_login"))]
)
async def login(
    data: UserLogin,
    db: AsyncSession = Depends(get_db)
):
    _, token = await AuthService.authenticate_user(db, data)
    return APIResponse(data=token)


@router.post(
    "/oauth",
    response_model=APIResponse[Token],
    dependencies=[Depends(rate_limit(max_requests=60, window_seconds=60, scope="auth_oauth"))]
)
async def oauth_login(
    data: OAuthLoginRequest,
    db: AsyncSession = Depends(get_db)
):
    _, token = await AuthService.authenticate_oauth(db, data)
    return APIResponse(data=token)


@router.post("/refresh", response_model=APIResponse[Token])
async def refresh_token(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    token = await AuthService.refresh_access_token(db, data.refresh_token)
    return APIResponse(data=token)


@router.post("/logout", response_model=APIResponse[dict])
async def logout(
    data: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    revoked = await AuthService.revoke_refresh_token(db, data.refresh_token)
    return APIResponse(data={"logged_out": True, "token_revoked": revoked})


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
        has_password=bool(current_user.hashed_password or getattr(current_user, "_token_has_password", False)),
        is_pro=is_pro,
        created_at=current_user.created_at
    )
    return APIResponse(data=user_response)


@router.put("/me", response_model=APIResponse[UserResponse])
async def update_me(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if data.full_name is not None:
        current_user.full_name = data.full_name.strip()
    if data.phone_number is not None:
        current_user.phone_number = data.phone_number.strip()
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


@router.post("/set-password", response_model=APIResponse[UserResponse])
async def set_password(
    data: SetPasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Sets or updates direct login password and phone number for an authenticated user
    (e.g., users who registered/signed in via Google OAuth).
    """
    updated_user = await AuthService.set_user_password(
        db=db,
        user=current_user,
        password=data.password,
        phone_number=data.phone_number,
        full_name=data.full_name
    )
    is_pro = any(sub.is_pro for sub in updated_user.subscriptions)
    return APIResponse(data=UserResponse(
        id=updated_user.id,
        email=updated_user.email,
        full_name=updated_user.full_name,
        phone_number=updated_user.phone_number,
        avatar_url=updated_user.avatar_url,
        default_currency=updated_user.default_currency,
        is_active=updated_user.is_active,
        is_verified=updated_user.is_verified,
        has_password=True,
        is_pro=is_pro,
        created_at=updated_user.created_at
    ))

