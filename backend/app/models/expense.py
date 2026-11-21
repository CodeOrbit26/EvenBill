"""
EvenBill Expense, Payer, Split, Allocation, and Receipt ORM Models
Uses Numeric(18, 4) for zero floating-point loss.
Supports Idempotency, Refunds/Reimbursements, and Multi-Currency exchange records.
"""

import uuid
from datetime import datetime, timezone, date
from decimal import Decimal
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, Date, Numeric, Text, Integer, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base


class Expense(Base):
    __tablename__ = "expenses"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, unique=True, index=True)
    transaction_type: Mapped[str] = mapped_column(String(32), default="EXPENSE", nullable=False)  # EXPENSE, REIMBURSEMENT, REFUND
    original_expense_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("expenses.id", ondelete="SET NULL"), nullable=True)

    group_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("groups.id", ondelete="CASCADE"), nullable=True, index=True)
    created_by: Mapped[str] = mapped_column(String(36), ForeignKey("profiles.id"), nullable=False, index=True)
    description: Mapped[str] = mapped_column(String(255), nullable=False)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)

    # Frozen Multi-Currency Conversion Snapshot
    base_currency_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    exchange_rate: Mapped[Decimal] = mapped_column(Numeric(18, 8), default=Decimal("1.0"), nullable=False)
    exchange_rate_source: Mapped[str] = mapped_column(String(64), default="DEFAULT", nullable=False)
    exchange_rate_timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    split_type: Mapped[str] = mapped_column(String(32), default="EQUAL", nullable=False)  # EQUAL, EXACT, PERCENTAGE, SHARES, ADJUSTMENT, ITEMIZED
    category: Mapped[str] = mapped_column(String(64), default="GENERAL", nullable=False)
    expense_date: Mapped[date] = mapped_column(Date, default=lambda: datetime.now(timezone.utc).date(), nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

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
    group = relationship("Group", back_populates="expenses")
    payers = relationship("ExpensePayer", back_populates="expense", cascade="all, delete-orphan")
    splits = relationship("ExpenseSplit", back_populates="expense", cascade="all, delete-orphan")
    receipts = relationship("Receipt", back_populates="expense", cascade="all, delete-orphan")
    comments = relationship("ExpenseComment", back_populates="expense", cascade="all, delete-orphan")
    creator = relationship("Profile", foreign_keys=[created_by])


class ExpensePayer(Base):
    __tablename__ = "expense_payers"
    __table_args__ = (
        UniqueConstraint("expense_id", "user_id", name="uq_expense_payer"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    expense_id: Mapped[str] = mapped_column(String(36), ForeignKey("expenses.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("profiles.id"), nullable=False, index=True)
    amount_paid: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)

    # Relationships
    expense = relationship("Expense", back_populates="payers")
    user = relationship("Profile")


class ExpenseSplit(Base):
    __tablename__ = "expense_splits"
    __table_args__ = (
        UniqueConstraint("expense_id", "user_id", name="uq_expense_split"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    expense_id: Mapped[str] = mapped_column(String(36), ForeignKey("expenses.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("profiles.id"), nullable=False, index=True)
    owed_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    share_quantity: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4), nullable=True)

    # Relationships
    expense = relationship("Expense", back_populates="splits")
    user = relationship("Profile")


# Aliases for unified nomenclature
ExpenseAllocation = ExpenseSplit


class ExpenseParticipant(Base):
    __tablename__ = "expense_participants"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    expense_id: Mapped[str] = mapped_column(String(36), ForeignKey("expenses.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=True, index=True)
    pending_participant_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("pending_participants.id", ondelete="CASCADE"), nullable=True, index=True)
    share_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False)
    share_percentage: Mapped[Optional[Decimal]] = mapped_column(Numeric(7, 4), nullable=True)

    expense = relationship("Expense")
    user = relationship("Profile", foreign_keys=[user_id])


class Receipt(Base):
    __tablename__ = "receipts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    expense_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("expenses.id", ondelete="CASCADE"), nullable=True, index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    s3_key: Mapped[str] = mapped_column(String(512), nullable=False)
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    file_size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    content_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, index=True)  # SHA-256 for duplicate detection

    ocr_status: Mapped[str] = mapped_column(String(32), default="NONE", nullable=False)  # NONE, PENDING, COMPLETED, FAILED
    raw_ocr_payload: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    extracted_merchant: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    extracted_total: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 4), nullable=True)
    extracted_currency: Mapped[Optional[str]] = mapped_column(String(3), nullable=True)
    extracted_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )

    # Relationships
    expense = relationship("Expense", back_populates="receipts")
    user = relationship("Profile")


ReceiptMetadata = Receipt
