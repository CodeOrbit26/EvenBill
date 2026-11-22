"""
EvenBill Group, GroupMember, and Invitation ORM Models
"""

import uuid
import secrets
from datetime import datetime, timezone, timedelta
from sqlalchemy import String, Boolean, DateTime, ForeignKey, UniqueConstraint, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base, UID_TYPE


class Group(Base):
    __tablename__ = "groups"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    group_type: Mapped[str] = mapped_column(String(32), default="OTHER", nullable=False)  # HOME, TRIP, COUPLE, OTHER
    base_currency: Mapped[str] = mapped_column(String(3), default="USD", nullable=False)
    simplify_debts: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    invite_code: Mapped[str] = mapped_column(String(16), unique=True, index=True, nullable=False)
    avatar_url: Mapped[str] = mapped_column(String(512), nullable=True)
    created_by: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False)
    is_archived: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

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
    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")
    pending_participants = relationship("GroupPendingParticipant", back_populates="group", cascade="all, delete-orphan")
    expenses = relationship("Expense", back_populates="group", cascade="all, delete-orphan")
    settlements = relationship("Settlement", back_populates="group", cascade="all, delete-orphan")
    invitations = relationship("GroupInvitation", back_populates="group", cascade="all, delete-orphan")
    split_templates = relationship("GroupSplitTemplate", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    __tablename__ = "group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_user"),
    )

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    group_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    role: Mapped[str] = mapped_column(String(32), default="MEMBER", nullable=False)  # OWNER, ADMIN, MEMBER
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    group = relationship("Group", back_populates="members")
    user = relationship("Profile", back_populates="group_memberships")


class GroupInvitation(Base):
    __tablename__ = "invitations"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    group_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    invited_by: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False)
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True, default=lambda: secrets.token_urlsafe(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="PENDING", nullable=False)  # PENDING, ACCEPTED, EXPIRED, REVOKED
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc) + timedelta(days=7),
        nullable=False
    )

    # Relationships
    group = relationship("Group", back_populates="invitations")
    inviter = relationship("Profile", foreign_keys=[invited_by])


# Alias for backwards compatibility
Invitation = GroupInvitation


class GroupSplitTemplate(Base):
    __tablename__ = "group_split_templates"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    group_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    split_type: Mapped[str] = mapped_column(String(32), default="EQUAL", nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    allocations_json: Mapped[str] = mapped_column(Text, nullable=False)
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
    group = relationship("Group", back_populates="split_templates")
    creator = relationship("Profile", foreign_keys=[created_by])
