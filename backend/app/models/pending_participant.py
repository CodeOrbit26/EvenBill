"""
EvenBill GroupPendingParticipant ORM Model
Represents non-account participants who can participate in group expense allocations
and debt balances before creating an account.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base


class GroupPendingParticipant(Base):
    __tablename__ = "pending_participants"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    group_id: Mapped[str] = mapped_column(String(36), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True)
    display_name: Mapped[str] = mapped_column(String(150), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
    phone_number: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="ACTIVE", nullable=False)  # ACTIVE, CLAIMED, REMOVED
    claimed_by_user_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("profiles.id", ondelete="SET NULL"), nullable=True, index=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    claimed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True
    )

    # Relationships
    group = relationship("Group", back_populates="pending_participants")
    claimed_by_user = relationship("Profile", foreign_keys=[claimed_by_user_id])


PendingParticipant = GroupPendingParticipant
