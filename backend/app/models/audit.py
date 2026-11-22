"""
EvenBill Immutable Financial Audit Log ORM Model
Ensures non-repudiation and complete traceability for all financial mutations.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, DateTime, Text, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base, UID_TYPE


class FinancialAuditLog(Base):
    __tablename__ = "financial_audit_logs"

    id: Mapped[str] = mapped_column(UID_TYPE, primary_key=True, default=lambda: str(uuid.uuid4()))
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)  # EXPENSE, SETTLEMENT, SPLIT
    entity_id: Mapped[str] = mapped_column(UID_TYPE, nullable=False, index=True)
    action: Mapped[str] = mapped_column(String(32), nullable=False)  # CREATE, UPDATE, DELETE
    performed_by: Mapped[str] = mapped_column(UID_TYPE, ForeignKey("profiles.id"), nullable=False)
    previous_state: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    new_state: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    performer = relationship("Profile")
