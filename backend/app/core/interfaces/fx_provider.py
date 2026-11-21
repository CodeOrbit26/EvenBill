"""
Exchange Rate Provider Interface
Defines the contract for retrieving foreign exchange rates with provenance metadata.
"""

from abc import ABC, abstractmethod
from datetime import date, datetime
from decimal import Decimal
from pydantic import BaseModel


class FXRateResult(BaseModel):
    source_currency: str
    target_currency: str
    rate: Decimal
    provider: str
    rate_status: str  # LIVE, STALE_FALLBACK, FIXTURE_TEST_RATE, UNAVAILABLE
    effective_date: date
    retrieved_at: datetime


class IFXRateProvider(ABC):
    @abstractmethod
    async def get_exchange_rate(
        self, source_currency: str, target_currency: str, rate_date: date
    ) -> FXRateResult:
        """Fetch foreign exchange conversion rate between source and target currencies."""
        pass

