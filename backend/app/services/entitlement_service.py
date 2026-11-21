"""
EvenBill Feature-Entitlement and Subscription Engine
Provides server-side enforcement of subscription tiers, configurable plan limits,
feature gates, and detailed error responses for locked capabilities.
"""

from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Optional, Tuple
from decimal import Decimal
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.core.config import settings
from app.models.user import User, Subscription
from app.models.expense import Expense


class FeatureKey:
    DAILY_EXPENSE_CREATION = "DAILY_EXPENSE_CREATION"
    RECEIPT_OCR = "RECEIPT_OCR"
    CROSS_GROUP_SIMPLIFICATION = "CROSS_GROUP_SIMPLIFICATION"
    ADVANCED_ANALYTICS_EXPORT = "ADVANCED_ANALYTICS_EXPORT"
    RECURRING_EXPENSES = "RECURRING_EXPENSES"
    MULTI_CURRENCY_CONVERSION = "MULTI_CURRENCY_CONVERSION"
    SEARCH_AND_FILTER = "SEARCH_AND_FILTER"
    SAVED_SPLIT_TEMPLATES = "SAVED_SPLIT_TEMPLATES"
    AD_FREE = "AD_FREE"
    BANK_IMPORT = "BANK_IMPORT"


class PlanTier:
    FREE = "FREE"
    PRO = "PRO"


class FeatureLockedException(HTTPException):
    def __init__(
        self,
        feature_key: str,
        detail: str,
        plan: str,
        limit: Optional[int] = None,
        used: Optional[int] = None,
        resets_at: Optional[datetime] = None,
        resets_in_seconds: Optional[int] = None,
        permitted_next_action: str = "Upgrade to EvenBill Pro for unlimited access."
    ):
        error_dict = {
            "code": "FEATURE_LOCKED",
            "feature_key": feature_key,
            "detail": detail,
            "plan": plan,
            "permitted_next_action": permitted_next_action,
        }
        if limit is not None:
            error_dict["limit"] = limit
        if used is not None:
            error_dict["used"] = used
            error_dict["remaining"] = max(0, limit - used) if limit is not None else None
        if resets_at is not None:
            error_dict["resets_at"] = resets_at.isoformat()
        if resets_in_seconds is not None:
            error_dict["resets_in_seconds"] = resets_in_seconds

        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=error_dict
        )


class EntitlementService:
    @staticmethod
    async def get_user_plan(db: AsyncSession, user: User) -> str:
        """
        Resolves the active subscription tier for a user.
        Checks active subscriptions and overrides in the database.
        """
        stmt = (
            select(Subscription)
            .where(
                Subscription.user_id == user.id,
                Subscription.status.in_(["ACTIVE", "IN_GRACE_PERIOD"])
            )
            .order_by(Subscription.created_at.desc())
        )
        res = await db.execute(stmt)
        subscriptions = res.scalars().all()

        for sub in subscriptions:
            if sub.is_pro:
                return PlanTier.PRO

        return PlanTier.FREE

    @staticmethod
    async def get_daily_expense_usage(
        db: AsyncSession,
        user_id: str,
        window_hours: Optional[int] = None
    ) -> Tuple[int, Optional[datetime], int]:
        """
        Calculates the number of new non-deleted expenses created by user_id
        within the rolling time window.
        Returns: (used_count, resets_at, resets_in_seconds)
        """
        effective_window = window_hours or settings.EXPENSE_LIMIT_WINDOW_HOURS
        now = datetime.now(timezone.utc)
        window_start = now - timedelta(hours=effective_window)

        # Count expenses created by user in window
        count_stmt = select(func.count(Expense.id)).where(
            Expense.created_by == user_id,
            Expense.is_deleted == False,
            Expense.created_at >= window_start
        )
        res = await db.execute(count_stmt)
        used_count = res.scalar() or 0

        # Find the oldest expense in the window to determine when an allowance slot reopens
        oldest_stmt = (
            select(Expense.created_at)
            .where(
                Expense.created_by == user_id,
                Expense.is_deleted == False,
                Expense.created_at >= window_start
            )
            .order_by(Expense.created_at.asc())
            .limit(1)
        )
        oldest_res = await db.execute(oldest_stmt)
        oldest_created_at = oldest_res.scalar_one_or_none()

        resets_at = None
        resets_in_seconds = 0
        if oldest_created_at:
            # Ensure timezone awareness
            if oldest_created_at.tzinfo is None:
                oldest_created_at = oldest_created_at.replace(tzinfo=timezone.utc)
            resets_at = oldest_created_at + timedelta(hours=effective_window)
            resets_in_seconds = max(0, int((resets_at - now).total_seconds()))

        return used_count, resets_at, resets_in_seconds

    @classmethod
    async def check_expense_creation_allowance(
        cls,
        db: AsyncSession,
        creator: User,
        idempotency_key: Optional[str] = None
    ) -> None:
        """
        Enforces daily expense creation limits for Free tier users.
        Idempotent retries and Pro subscribers pass without consuming allowance.
        """
        # 1. Check if user is Pro
        plan = await cls.get_user_plan(db, creator)
        if plan == PlanTier.PRO:
            return  # Pro users have unlimited expense creation

        # 2. Check for idempotent retry or replay
        # If an expense with this idempotency key already exists, this is a retry/sync replay,
        # not a newly consumed expense allowance.
        if idempotency_key:
            existing_stmt = select(Expense.id).where(Expense.idempotency_key == idempotency_key)
            existing_res = await db.execute(existing_stmt)
            if existing_res.scalar_one_or_none():
                return  # Idempotent replay, do not count or block

        # 3. Check current usage against limit (only enforced if limit > 0)
        limit = settings.FREE_DAILY_EXPENSE_LIMIT
        if limit > 0:
            used, resets_at, resets_in_seconds = await cls.get_daily_expense_usage(db, creator.id)

            if used >= limit:
                raise FeatureLockedException(
                    feature_key=FeatureKey.DAILY_EXPENSE_CREATION,
                    detail=f"You have reached your daily limit of {limit} new expenses on the Free plan.",
                    plan=PlanTier.FREE,
                    limit=limit,
                    used=used,
                    resets_at=resets_at,
                    resets_in_seconds=resets_in_seconds,
                    permitted_next_action="Upgrade to EvenBill Pro for unlimited expenses or wait until your daily allowance resets."
                )

    @classmethod
    async def get_user_entitlements_summary(
        cls,
        db: AsyncSession,
        user: User
    ) -> Dict[str, Any]:
        """
        Produces a comprehensive entitlements summary for the mobile and web clients.
        """
        plan = await cls.get_user_plan(db, user)
        is_pro = (plan == PlanTier.PRO)

        used, resets_at, resets_in_seconds = await cls.get_daily_expense_usage(db, user.id)
        limit = None if (is_pro or settings.FREE_DAILY_EXPENSE_LIMIT < 0) else settings.FREE_DAILY_EXPENSE_LIMIT
        remaining = None if (is_pro or settings.FREE_DAILY_EXPENSE_LIMIT < 0) else max(0, limit - used)

        return {
            "plan": plan,
            "is_pro": is_pro,
            "features": {
                FeatureKey.DAILY_EXPENSE_CREATION: {
                    "limit": limit,
                    "used": used,
                    "remaining": remaining,
                    "resets_at": resets_at.isoformat() if resets_at else None,
                    "resets_in_seconds": resets_in_seconds if resets_at else None,
                    "window_hours": settings.EXPENSE_LIMIT_WINDOW_HOURS,
                },
                FeatureKey.RECEIPT_OCR: {
                    "enabled": is_pro,
                    "limit": None if is_pro else settings.FREE_OCR_LIMIT_MONTHLY,
                },
                FeatureKey.CROSS_GROUP_SIMPLIFICATION: {
                    "enabled": is_pro,
                },
                FeatureKey.ADVANCED_ANALYTICS_EXPORT: {
                    "enabled": True,  # Available to all tiers
                },
                FeatureKey.RECURRING_EXPENSES: {
                    "enabled": True,  # Available to all tiers
                },
                FeatureKey.MULTI_CURRENCY_CONVERSION: {
                    "enabled": True,  # Available to all tiers
                },
                FeatureKey.SEARCH_AND_FILTER: {
                    "enabled": is_pro,
                },
                FeatureKey.SAVED_SPLIT_TEMPLATES: {
                    "enabled": is_pro,
                },
                FeatureKey.AD_FREE: {
                    "enabled": is_pro,
                },
                FeatureKey.BANK_IMPORT: {
                    "enabled": is_pro,
                    "provider_approved": False,
                    "supported_jurisdictions": ["US", "GB", "EU"],
                },
            },
            "upgrade_options": [
                {
                    "tier": "PRO_MONTHLY",
                    "price_usd": str(settings.PRO_PRICE_MONTHLY_USD),
                    "billing_period": "monthly",
                    "label": "Monthly ($4.99/mo)"
                },
                {
                    "tier": "PRO_ANNUAL",
                    "price_usd": str(settings.PRO_PRICE_ANNUAL_USD),
                    "billing_period": "annual",
                    "savings_pct": 33,
                    "label": "Annual ($39.99/yr) - Save 33%"
                }
            ]
        }

    @staticmethod
    async def override_subscription(
        db: AsyncSession,
        user_id: str,
        tier: str,
        status: str = "ACTIVE",
        expires_at: Optional[datetime] = None
    ) -> Subscription:
        """
        Creates or updates a user's subscription tier.
        Used for mock upgrades and testing subscription transitions without real billing.
        """
        stmt = (
            select(Subscription)
            .where(Subscription.user_id == user_id)
            .order_by(Subscription.created_at.desc())
        )
        res = await db.execute(stmt)
        sub = res.scalars().first()

        if sub:
            sub.tier = tier.upper()
            sub.status = status.upper()
            sub.expires_at = expires_at
        else:
            sub = Subscription(
                user_id=user_id,
                tier=tier.upper(),
                status=status.upper(),
                expires_at=expires_at,
                store="MOCK_TEST_STORE"
            )
            db.add(sub)

        await db.commit()
        await db.refresh(sub)
        return sub
