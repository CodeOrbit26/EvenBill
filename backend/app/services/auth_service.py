"""
EvenBill Authentication and Identity Service
"""

import json
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple, Set
import uuid
import jwt
from sqlalchemy import select, or_, text
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status
from app.core.config import settings
from app.core.security import SecurityUtils
from app.models.user import User, Subscription, RevokedToken
from app.models.group import Group, GroupMember
from app.schemas.user import UserCreate, UserLogin, Token, OAuthLoginRequest


class AuthService:
    _has_auth_users: Optional[bool] = None
    _auth_users_columns: Optional[Set[str]] = None

    @classmethod
    async def _check_auth_users_exists(cls, db: AsyncSession) -> bool:
        bind = db.bind
        if bind is not None and bind.dialect.name != "postgresql":
            return False
        if cls._has_auth_users is not None:
            return cls._has_auth_users
        try:
            res = await db.execute(text("SELECT to_regclass('auth.users') IS NOT NULL"))
            exists = bool(res.scalar())
            cls._has_auth_users = exists
            return exists
        except Exception:
            return False

    @classmethod
    async def _get_auth_users_columns(cls, db: AsyncSession) -> Set[str]:
        if cls._auth_users_columns is not None:
            return cls._auth_users_columns
        try:
            res = await db.execute(text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = 'auth' AND table_name = 'users'"
            ))
            cols = {row[0] for row in res.fetchall()}
            cls._auth_users_columns = cols
            return cols
        except Exception:
            return set()

    @classmethod
    async def _insert_auth_user(
        cls,
        db: AsyncSession,
        user_id: str,
        email: str,
        hashed_pw: Optional[str],
        full_name: str,
        default_currency: str = "USD"
    ) -> None:
        avail_cols = await cls._get_auth_users_columns(db)
        insert_cols = ["id", "email"]
        insert_vals = ["CAST(:user_id AS uuid)", ":email"]
        params: dict = {"user_id": user_id, "email": email}

        if "encrypted_password" in avail_cols and hashed_pw:
            insert_cols.append("encrypted_password")
            insert_vals.append(":encrypted_password")
            params["encrypted_password"] = hashed_pw

        if "raw_user_meta_data" in avail_cols:
            insert_cols.append("raw_user_meta_data")
            insert_vals.append("CAST(:user_meta AS jsonb)")
            params["user_meta"] = json.dumps({"full_name": full_name, "default_currency": default_currency})

        if "raw_app_meta_data" in avail_cols:
            insert_cols.append("raw_app_meta_data")
            insert_vals.append("CAST(:app_meta AS jsonb)")
            params["app_meta"] = json.dumps({"provider": "email", "providers": ["email"]})

        if "aud" in avail_cols:
            insert_cols.append("aud")
            insert_vals.append("'authenticated'")

        if "role" in avail_cols:
            insert_cols.append("role")
            insert_vals.append("'authenticated'")

        if "email_confirmed_at" in avail_cols:
            insert_cols.append("email_confirmed_at")
            insert_vals.append("now()")

        if "created_at" in avail_cols:
            insert_cols.append("created_at")
            insert_vals.append("now()")

        if "updated_at" in avail_cols:
            insert_cols.append("updated_at")
            insert_vals.append("now()")

        sql = f"INSERT INTO auth.users ({', '.join(insert_cols)}) VALUES ({', '.join(insert_vals)})"
        await db.execute(text(sql), params)

    @classmethod
    async def register_user(cls, db: AsyncSession, data: UserCreate) -> User:
        clean_email = data.email.lower().strip()
        # Check if email is already taken
        stmt = select(User).where(User.email == clean_email)
        result = await db.execute(stmt)
        existing_user = result.scalar_one_or_none()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email address already exists"
            )

        has_auth = await cls._check_auth_users_exists(db)
        if has_auth:
            auth_stmt = text("SELECT 1 FROM auth.users WHERE lower(email) = :email")
            auth_res = await db.execute(auth_stmt, {"email": clean_email})
            if auth_res.scalar_one_or_none():
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

        user_id = str(uuid.uuid4())
        hashed_pw = SecurityUtils.hash_password(data.password)

        if has_auth:
            await cls._insert_auth_user(
                db=db,
                user_id=user_id,
                email=clean_email,
                hashed_pw=hashed_pw,
                full_name=data.full_name.strip(),
                default_currency=data.default_currency.upper()
            )

        # In Supabase, on_auth_user_created trigger may have created public.profiles row
        p_stmt = select(User).where(User.id == user_id)
        p_res = await db.execute(p_stmt)
        user = p_res.scalar_one_or_none()

        if user:
            user.hashed_password = hashed_pw
            user.full_name = data.full_name.strip()
            user.phone_number = phone
            user.default_currency = data.default_currency.upper()
            user.is_active = True
            user.is_verified = False
        else:
            user = User(
                id=user_id,
                email=clean_email,
                hashed_password=hashed_pw,
                full_name=data.full_name.strip(),
                phone_number=phone,
                default_currency=data.default_currency.upper(),
                is_active=True,
                is_verified=False
            )
            db.add(user)

        await db.flush()

        # Seed initial Free subscription tier
        sub_stmt = select(Subscription).where(Subscription.user_id == user.id)
        sub_res = await db.execute(sub_stmt)
        if not sub_res.scalar_one_or_none():
            free_sub = Subscription(
                user_id=user.id,
                tier="FREE",
                status="ACTIVE"
            )
            db.add(free_sub)

        await db.commit()
        await db.refresh(user)
        return user

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

    @classmethod
    async def authenticate_oauth(
        cls,
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
            user_id = str(uuid.uuid4())
            has_auth = await cls._check_auth_users_exists(db)
            if has_auth:
                await cls._insert_auth_user(
                    db=db,
                    user_id=user_id,
                    email=email,
                    hashed_pw=hashed_pw,
                    full_name=full_name.strip(),
                    default_currency="USD"
                )

            p_stmt = select(User).where(User.id == user_id)
            p_res = await db.execute(p_stmt)
            user = p_res.scalar_one_or_none()

            if user:
                user.hashed_password = hashed_pw
                user.full_name = full_name.strip()
                user.phone_number = phone
                user.avatar_url = avatar_url
                user.default_currency = "USD"
                user.is_active = True
                user.is_verified = True
            else:
                user = User(
                    id=user_id,
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

            sub_stmt = select(Subscription).where(Subscription.user_id == user.id)
            sub_res = await db.execute(sub_stmt)
            if not sub_res.scalar_one_or_none():
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


