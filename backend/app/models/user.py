"""
EvenBill Profile and User Models
Maps to public.profiles referencing Supabase auth.users(id).
Preserves full backwards-compatibility with User alias and subscription relationships.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Index, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base, UID_TYPE


class Profile(Base):
    __tablename__ = "profiles"

    # UUID matching auth.users.id from Supabase Auth
    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)  # Optional for legacy/dev tests
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone_number: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    avatar_url: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    default_currency: Mapped[str] = mapped_column(String(3), default="USD", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_pro: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    mfa_secret: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    mfa_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    subscriptions = relationship("Subscription", back_populates="user", cascade="all, delete-orphan")
    group_memberships = relationship("GroupMember", back_populates="user", cascade="all, delete-orphan")
    notification_preferences = relationship("NotificationPreference", back_populates="user", uselist=False, cascade="all, delete-orphan")


# Alias User to Profile for seamless backwards compatibility
User = Profile


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    tier: Mapped[str] = mapped_column(String(32), default="FREE", nullable=False)  # FREE, PRO_MONTHLY, PRO_ANNUAL
    status: Mapped[str] = mapped_column(String(32), default="ACTIVE", nullable=False)  # ACTIVE, CANCELED, PAST_DUE, IN_GRACE_PERIOD, REFUNDED, EXPIRED
    original_transaction_id: Mapped[Optional[str]] = mapped_column(String(128), nullable=True, unique=True)
    store: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)  # APPLE_APP_STORE, GOOGLE_PLAY, STRIPE, REVENUECAT
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    grace_period_until: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    cancel_at_period_end: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    refunded_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    is_sandbox: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    user = relationship("Profile", back_populates="subscriptions")

    @property
    def is_pro(self) -> bool:
        if self.tier in ("PRO", "PRO_MONTHLY", "PRO_ANNUAL"):
            now = datetime.now(timezone.utc)
            exp = self.expires_at
            if exp is not None and exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
            gp = self.grace_period_until
            if gp is not None and gp.tzinfo is None:
                gp = gp.replace(tzinfo=timezone.utc)

            if self.status == "ACTIVE":
                if exp is None or exp > now:
                    return True
            elif self.status == "IN_GRACE_PERIOD":
                if gp and gp > now:
                    return True
        return False


class SubscriptionWebhookEvent(Base):
    __tablename__ = "subscription_webhook_events"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    event_id: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    store: Mapped[str] = mapped_column(String(32), nullable=False)  # REVENUECAT, APPLE, GOOGLE, STRIPE
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    user_id: Mapped[Optional[str]] = mapped_column(UID_TYPE, ForeignKey("profiles.id", ondelete="SET NULL"), nullable=True)
    payload: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    payload_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    processed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )


class RevokedToken(Base):
    __tablename__ = "revoked_tokens"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    jti: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    user_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    revoked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
