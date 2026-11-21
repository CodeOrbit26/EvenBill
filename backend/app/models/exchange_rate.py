"""
EvenBill Exchange Rate Snapshot ORM Model
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal
from sqlalchemy import String, Numeric, DateTime
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base


class ExchangeRateSnapshot(Base):
    __tablename__ = "exchange_rate_snapshots"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    base_currency: Mapped[str] = mapped_column(String(3), nullable=False, index=True)
    target_currency: Mapped[str] = mapped_column(String(3), nullable=False, index=True)
    rate: Mapped[Decimal] = mapped_column(Numeric(18, 8), nullable=False)
    provider: Mapped[str] = mapped_column(String(64), default="ECB", nullable=False)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False
    )
