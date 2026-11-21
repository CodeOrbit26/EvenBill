"""
EvenBill Authentication and Identity Service
"""

from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple
import uuid
import jwt
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status
from app.core.config import settings
from app.core.security import SecurityUtils
from app.models.user import User, Subscription, RevokedToken
from app.models.group import Group, GroupMember
from app.schemas.user import UserCreate, UserLogin, Token, OAuthLoginRequest


class AuthService:
    @staticmethod
    async def register_user(db: AsyncSession, data: UserCreate) -> User:
        # Check if email is already taken
        stmt = select(User).where(User.email == data.email.lower().strip())
        result = await db.execute(stmt)
        existing_user = result.scalar_one_or_none()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email address already exists"
            )

        phone = data.phone_number.strip() if data.phone_number else None
        if phone:
            phone_stmt = select(User).where(User.phone_number == phone)
            phone_res = await db.execute(phone_stmt)
            if phone_res.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="An account with this phone number already exists"
                )

        hashed_pw = SecurityUtils.hash_password(data.password)
        new_user = User(
            email=data.email.lower().strip(),
            hashed_password=hashed_pw,
            full_name=data.full_name.strip(),
            phone_number=phone,
            default_currency=data.default_currency.upper(),
            is_active=True,
            is_verified=False
        )
        db.add(new_user)
        await db.flush()

        # Seed initial Free subscription tier
        free_sub = Subscription(
            user_id=new_user.id,
            tier="FREE",
            status="ACTIVE"
        )
        db.add(free_sub)
        await db.commit()
        await db.refresh(new_user)
        return new_user

    @staticmethod
    async def authenticate_user(db: AsyncSession, login_data: UserLogin) -> Tuple[User, Token]:
        login_id = login_data.email.strip()
        stmt = select(User).where(
            or_(
                User.email == login_id.lower(),
                User.phone_number == login_id
            )
        )
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()

        if not user or not user.hashed_password:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )

        if not SecurityUtils.verify_password(login_data.password, user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password"
            )

        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This account has been deactivated"
            )

        # Generate tokens
        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = SecurityUtils.create_access_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=access_token_expires
        )
        refresh_token = SecurityUtils.create_refresh_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
        )

        token = Token(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        )
        return user, token

    @staticmethod
    async def refresh_access_token(db: AsyncSession, refresh_token: str) -> Token:
        """
        Rotates refresh token and issues a new access token.
        Detects token replay attacks: if an already-rotated token is presented,
        it is rejected with HTTP 401.
        """
        try:
            payload = SecurityUtils.decode_token(
                refresh_token,
                settings.SECRET_KEY,
                algorithms=[settings.ALGORITHM]
            )
            if payload.get("type") != "refresh":
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type")
            user_id: str = payload.get("sub")
            jti: Optional[str] = payload.get("jti")
            exp: Optional[int] = payload.get("exp")
        except Exception:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Expired or invalid refresh token")

        # Verify whether this token JTI has already been rotated/revoked
        if jti:
            rev_stmt = select(RevokedToken).where(RevokedToken.jti == jti)
            rev_res = await db.execute(rev_stmt)
            if rev_res.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Refresh token has been revoked or already rotated (replay detected)"
                )

        stmt = select(User).where(User.id == user_id, User.is_active == True)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

        # Invalidate the used refresh token JTI (Token Rotation)
        if jti:
            exp_dt = (
                datetime.fromtimestamp(exp, tz=timezone.utc)
                if exp
                else datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
            )
            revoked_entry = RevokedToken(
                jti=jti,
                user_id=user.id,
                expires_at=exp_dt
            )
            db.add(revoked_entry)
            await db.commit()

        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        new_access_token = SecurityUtils.create_access_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=access_token_expires
        )
        new_refresh_token = SecurityUtils.create_refresh_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
        )

        return Token(
            access_token=new_access_token,
            refresh_token=new_refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        )

    @staticmethod
    async def revoke_refresh_token(db: AsyncSession, refresh_token: str) -> bool:
        """
        Explicitly revokes a refresh token (e.g. on user logout).
        """
        try:
            payload = SecurityUtils.decode_token(
                refresh_token,
                settings.SECRET_KEY,
                algorithms=[settings.ALGORITHM]
            )
            jti: Optional[str] = payload.get("jti")
            user_id: Optional[str] = payload.get("sub")
            exp: Optional[int] = payload.get("exp")
            if jti and user_id:
                exp_dt = (
                    datetime.fromtimestamp(exp, tz=timezone.utc)
                    if exp
                    else datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
                )
                revoked_entry = RevokedToken(
                    jti=jti,
                    user_id=user_id,
                    expires_at=exp_dt
                )
                db.add(revoked_entry)
                await db.commit()
                return True
        except Exception:
            pass
        return False

    @staticmethod
    async def authenticate_oauth(
        db: AsyncSession,
        data: OAuthLoginRequest
    ) -> Tuple[User, Token]:
        provider = data.provider.lower().strip()
        if provider not in ("google", "apple"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported OAuth provider: {data.provider}. Must be 'google' or 'apple'."
            )

        email = data.email
        full_name = data.full_name or ("Google User" if provider == "google" else "Apple User")
        avatar_url = data.avatar_url

        if provider == "google" and data.id_token:
            try:
                # Decode unverified claims first
                unverified = jwt.decode(data.id_token, options={"verify_signature": False})
                email = unverified.get("email", email)
                full_name = unverified.get("name", full_name)
                avatar_url = unverified.get("picture", avatar_url)

                # If GOOGLE_CLIENT_ID is configured in environment, verify audience
                if settings.GOOGLE_CLIENT_ID:
                    aud = unverified.get("aud")
                    if aud != settings.GOOGLE_CLIENT_ID:
                        raise HTTPException(
                            status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Google ID token audience does not match configured GOOGLE_CLIENT_ID."
                        )
            except HTTPException:
                raise
            except Exception as e:
                logger.warning(f"Google ID token parsing notice: {e}")
        elif data.id_token and not email:
            try:
                unverified = jwt.decode(data.id_token, options={"verify_signature": False})
                email = unverified.get("email", email)
                full_name = unverified.get("name", full_name)
                avatar_url = unverified.get("picture", avatar_url)
            except Exception:
                pass

        if not email:
            email = f"{provider}.user.{uuid.uuid4().hex[:8]}@evenbill.app"

        email = email.lower().strip()

        stmt = select(User).where(User.email == email)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()

        if not user:
            hashed_pw = SecurityUtils.hash_password(data.password) if data.password else None
            phone = data.phone_number.strip() if data.phone_number else None
            user = User(
                email=email,
                hashed_password=hashed_pw,
                full_name=full_name.strip(),
                phone_number=phone,
                avatar_url=avatar_url,
                default_currency="USD",
                is_active=True,
                is_verified=True
            )
            db.add(user)
            await db.flush()

            free_sub = Subscription(
                user_id=user.id,
                tier="FREE",
                status="ACTIVE"
            )
            db.add(free_sub)
            await db.commit()
            await db.refresh(user)
        else:
            if not user.is_active:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="This account has been deactivated"
                )
            updated = False
            if data.password and not user.hashed_password:
                user.hashed_password = SecurityUtils.hash_password(data.password)
                updated = True
            if data.phone_number and not user.phone_number:
                user.phone_number = data.phone_number.strip()
                updated = True
            if avatar_url and not user.avatar_url:
                user.avatar_url = avatar_url
                updated = True
            if full_name and user.full_name in ("Google User", "Apple User"):
                user.full_name = full_name
                updated = True
            if updated:
                await db.commit()
                await db.refresh(user)

        access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = SecurityUtils.create_access_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=access_token_expires
        )
        refresh_token = SecurityUtils.create_refresh_token(
            subject=user.id,
            secret_key=settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
            expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
        )

        token = Token(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        )
        return user, token

    @staticmethod
    async def set_user_password(
        db: AsyncSession,
        user: User,
        password: str,
        phone_number: Optional[str] = None,
        full_name: Optional[str] = None
    ) -> User:
        user.hashed_password = SecurityUtils.hash_password(password)
        if phone_number and phone_number.strip():
            user.phone_number = phone_number.strip()
        if full_name and full_name.strip():
            user.full_name = full_name.strip()
        await db.commit()
        await db.refresh(user)
        return user


