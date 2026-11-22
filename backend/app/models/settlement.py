"""
EvenBill Settlement ORM Model
Records payments between members that reduce active debt balances.
Supports idempotency protection against duplicate submissions.
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, Numeric, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base, UID_TYPE


class Settlement(Base):
    __tablename__ = "settlements"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, unique=True, index=True)
    group_id: Mapped[Optional[str]] = mapped_column(UID_TYPE, ForeignKey("groups.id", ondelete="CASCADE"), nullable=True, index=True)
    payer_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False, index=True)
    recipient_id: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    payment_method: Mapped[str] = mapped_column(String(32), default="CASH", nullable=False)  # CASH, UPI, PAYPAL, VENMO, WISE, IN_APP
    transaction_reference: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_by: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    settled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    group = relationship("Group", back_populates="settlements")
    payer = relationship("Profile", foreign_keys=[payer_id])
    recipient = relationship("Profile", foreign_keys=[recipient_id])
    creator = relationship("Profile", foreign_keys=[created_by])
