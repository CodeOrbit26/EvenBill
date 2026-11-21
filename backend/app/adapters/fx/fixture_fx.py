"""
Deterministic Fixture FX Rate Provider
Provides predictable exchange rates for automated testing and offline development.
Explicitly flags all responses with 'FIXTURE_TEST_RATE' so they are never mistaken for live market rates.
"""

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Dict
from app.core.interfaces.fx_provider import IFXRateProvider, FXRateResult


class DeterministicFixtureFXAdapter(IFXRateProvider):
    # Standard base rates relative to EUR
    BASE_EUR_RATES: Dict[str, Decimal] = {
        "EUR": Decimal("1.0"),
        "USD": Decimal("1.0850"),
        "GBP": Decimal("0.8550"),
        "INR": Decimal("90.25"),
        "JPY": Decimal("165.50"),
        "CAD": Decimal("1.4850"),
        "AUD": Decimal("1.6600"),
        "CHF": Decimal("0.9700"),
        "SGD": Decimal("1.4600"),
        "BHD": Decimal("0.4080"),
    }

    async def get_exchange_rate(
        self, source_currency: str, target_currency: str, rate_date: date
    ) -> FXRateResult:
        src = source_currency.upper()
        tgt = target_currency.upper()

        if src == tgt:
            rate = Decimal("1.0")
        else:
            eur_to_src = self.BASE_EUR_RATES.get(src, Decimal("1.0"))
            eur_to_tgt = self.BASE_EUR_RATES.get(tgt, Decimal("1.0"))
            # 1 Unit of src in EUR = 1 / eur_to_src
            # Converted to tgt = (1 / eur_to_src) * eur_to_tgt = eur_to_tgt / eur_to_src
            rate = (eur_to_tgt / eur_to_src).quantize(Decimal("0.000001"))

        return FXRateResult(
            source_currency=src,
            target_currency=tgt,
            rate=rate,
            provider="DETERMINISTIC_FIXTURE_ADAPTER",
            rate_status="FIXTURE_TEST_RATE",
            effective_date=rate_date,
            retrieved_at=datetime.now(timezone.utc),
        )

