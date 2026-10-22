"""
EvenBill Authentication and Identity Service
"""

from datetime import timedelta
from typing import Optional, Tuple
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status
from app.core.config import settings
from app.core.security import SecurityUtils
from app.models.user import User, Subscription
from app.schemas.user import UserCreate, UserLogin, Token


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

        hashed_pw = SecurityUtils.hash_password(data.password)
        new_user = User(
            email=data.email.lower().strip(),
            hashed_password=hashed_pw,
            full_name=data.full_name.strip(),
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
        stmt = select(User).where(User.email == login_data.email.lower().strip())
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
        try:
            payload = SecurityUtils.decode_token(
                refresh_token,
                settings.SECRET_KEY,
                algorithms=[settings.ALGORITHM]
            )
            if payload.get("type") != "refresh":
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type")
            user_id: str = payload.get("sub")
        except Exception:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Expired or invalid refresh token")

        stmt = select(User).where(User.id == user_id, User.is_active == True)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

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
