"""
EvenBill FastAPI Route Dependencies
Handles token extraction, Supabase JWKS cryptographic verification, and user resolution.
"""

from typing import AsyncGenerator
import logging
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.core.supabase_jwt import SupabaseJWTVerifier
from app.db.session import get_db
from app.models.user import User, Subscription

logger = logging.getLogger(__name__)
security_scheme = HTTPBearer(auto_error=True)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Extracts, validates, and resolves the authenticated user:
    1. Receives Bearer token from Authorization header
    2. Cryptographically verifies signature against Supabase JWKS or symmetric secret
    3. Validates issuer, audience, and expiration claims
    4. Resolves authenticated user UUID strictly from token subject (never trusts client user ID)
    5. Syncs profile and default subscription if missing, and verifies account active status
    """
    token = credentials.credentials
    payload = SupabaseJWTVerifier.verify_token(token)

    # Reject refresh tokens presented as access tokens
    if payload.get("type") == "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token cannot be used as an access token",
            headers={"WWW-Authenticate": "Bearer"}
        )

    user_id: str = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token payload missing subject identifier",
            headers={"WWW-Authenticate": "Bearer"}
        )

    stmt = select(User).where(User.id == user_id).options(selectinload(User.subscriptions))
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    # Auto-synchronize profile from verified Supabase token if not yet present
    if not user:
        email = payload.get("email") or payload.get("user_metadata", {}).get("email")
        if email:
            clean_email = email.lower().strip()
            # Security check: verify if an account already exists under this email with a different UUID
            stmt_email = select(User).where(func.lower(User.email) == clean_email).options(selectinload(User.subscriptions))
            result_email = await db.execute(stmt_email)
            user_by_email = result_email.scalar_one_or_none()

            if user_by_email and user_by_email.id != user_id:
                # NEVER link an existing financial account solely because email strings match!
                # Doing so creates an account takeover (ATO) vulnerability and breaks UUID integrity.
                logger.warning(
                    f"Identity conflict: token sub '{user_id}' presented email '{clean_email}' "
                    f"which belongs to existing user '{user_by_email.id}'"
                )
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="An account with this email address already exists. Please sign in with your original authentication provider."
                )

            # Determine verified identity status strictly from trusted token claims
            is_email_verified = bool(
                payload.get("email_confirmed_at")
                or payload.get("user_metadata", {}).get("email_verified") is True
                or payload.get("app_metadata", {}).get("provider") in {"google", "apple"}
            )

            full_name = payload.get("user_metadata", {}).get("full_name") or clean_email.split("@")[0]
            default_currency = payload.get("user_metadata", {}).get("default_currency") or "USD"
            new_user = User(
                id=user_id,
                email=clean_email,
                full_name=full_name,
                default_currency=default_currency,
                is_active=True,
                is_verified=is_email_verified
            )
            try:
                async with db.begin_nested():
                    db.add(new_user)
                    await db.flush()
                await db.commit()
            except IntegrityError:
                await db.rollback()
                # Check if a concurrent request created the colliding email under a different UUID
                stmt_coll = select(User).where(func.lower(User.email) == clean_email)
                res_coll = await db.execute(stmt_coll)
                colliding = res_coll.scalar_one_or_none()
                if colliding and colliding.id != user_id:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="An account with this email address already exists. Please sign in with your original authentication provider."
                    )
            stmt = select(User).where(User.id == user_id).options(selectinload(User.subscriptions))
            result = await db.execute(stmt)
            user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Authenticated user account does not exist"
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is deactivated"
        )

    # Derive password-auth capability from verified JWT metadata without modifying DB schema
    app_meta = payload.get("app_metadata") or {}
    providers = app_meta.get("providers") or []
    if isinstance(providers, str):
        providers = [providers]
    token_has_email_auth = (
        "email" in providers
        or app_meta.get("provider") == "email"
    )
    setattr(user, "_token_has_password", token_has_email_auth)

    # Ensure Free tier subscription exists for authenticated user
    if not user.subscriptions:
        sub_stmt = select(Subscription).where(Subscription.user_id == user.id)
        sub_res = await db.execute(sub_stmt)
        if not sub_res.scalar_one_or_none():
            try:
                async with db.begin_nested():
                    db.add(Subscription(user_id=user.id, tier="FREE", status="ACTIVE"))
                    await db.flush()
                await db.commit()
            except IntegrityError:
                await db.rollback()
            stmt = select(User).where(User.id == user.id).options(selectinload(User.subscriptions))
            result = await db.execute(stmt)
            user = result.scalar_one_or_none() or user

    return user


async def require_pro_user(
    current_user: User = Depends(get_current_user)
) -> User:
    """Enforces server-side Pro subscription entitlement."""
    has_active_pro = any(sub.is_pro for sub in current_user.subscriptions)
    if not has_active_pro:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This feature requires an active EvenBill Pro subscription"
        )
    return current_user
