"""
EvenBill Financial Precision Engine
Implements exact monetary arithmetic using Python Decimal and deterministic remainder distribution.
No floating-point arithmetic is permitted.
"""

from decimal import Decimal, ROUND_HALF_EVEN, ROUND_FLOOR
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass
from pydantic import BaseModel, Field

# ISO-4217 Currency Decimals Specification
CURRENCY_DECIMALS: Dict[str, int] = {
    "USD": 2, "EUR": 2, "GBP": 2, "INR": 2,
    "CAD": 2, "AUD": 2, "CHF": 2, "SGD": 2,
    "JPY": 0, "KRW": 0, "VND": 0, "IDR": 0,
    "BHD": 3, "KWD": 3, "OMR": 3, "JOD": 3,
}

DEFAULT_DECIMALS = 2

def get_currency_decimals(currency: str) -> int:
    return CURRENCY_DECIMALS.get(currency.upper(), DEFAULT_DECIMALS)

def to_minor_units(amount: Decimal, currency: str) -> int:
    """Converts a Decimal amount into integer minor units (e.g. cents)."""
    decimals = get_currency_decimals(currency)
    factor = Decimal(10 ** decimals)
    quantized = (amount * factor).quantize(Decimal("1"), rounding=ROUND_HALF_EVEN)
    return int(quantized)

def from_minor_units(minor_units: int, currency: str) -> Decimal:
    """Converts integer minor units back to a Decimal."""
    decimals = get_currency_decimals(currency)
    factor = Decimal(10 ** decimals)
    return (Decimal(minor_units) / factor).quantize(Decimal(f"1e-{decimals}"), rounding=ROUND_HALF_EVEN)

def quantize_currency(amount: Decimal, currency: str) -> Decimal:
    """Quantizes an amount to the currency's exact decimal precision using bankers rounding."""
    decimals = get_currency_decimals(currency)
    quantum = Decimal(f"1e-{decimals}")
    return amount.quantize(quantum, rounding=ROUND_HALF_EVEN)


@dataclass(frozen=True)
class SplitResult:
    user_id: str
    amount: Decimal
    share_value: Optional[Decimal] = None


class MoneyEngine:
    """
    Mathematical engine ensuring zero fractional loss across all split workflows.
    """

    @staticmethod
    def split_equally(
        total_amount: Decimal,
        currency: str,
        participant_ids: List[str],
        sort_by_id: bool = True
    ) -> List[SplitResult]:
        """
        Divides total_amount equally among participants using the Hare-Niemeyer / Largest Remainder algorithm.
        Guarantees that sum(individual_amounts) == total_amount down to the smallest integer minor unit.
        """
        if not participant_ids:
            raise ValueError("Participant list cannot be empty")
        if total_amount <= Decimal("0"):
            raise ValueError("Total amount must be strictly positive")

        n = len(participant_ids)
        total_minor = to_minor_units(total_amount, currency)
        base_minor = total_minor // n
        remainder = total_minor % n

        # Deterministic sorting to ensure idempotent remainder assignment
        ordered_ids = sorted(participant_ids) if sort_by_id else list(participant_ids)

        results: List[SplitResult] = []
        for index, user_id in enumerate(ordered_ids):
            # Distribute 1 extra minor unit to the first 'remainder' participants
            extra = 1 if index < remainder else 0
            user_minor = base_minor + extra
            results.append(
                SplitResult(
                    user_id=user_id,
                    amount=from_minor_units(user_minor, currency),
                    share_value=Decimal("1")
                )
            )

        # Verification Invariant
        allocated_sum = sum(r.amount for r in results)
        if allocated_sum != quantize_currency(total_amount, currency):
            raise AssertionError(f"Allocation invariant violated: {allocated_sum} != {total_amount}")

        return results

    @staticmethod
    def split_by_percentages(
        total_amount: Decimal,
        currency: str,
        percentages: Dict[str, Decimal]
    ) -> List[SplitResult]:
        """
        Divides total_amount based on percentages summing to 100%.
        Uses Largest Remainder Method on fractional minor units.
        """
        total_pct = sum(percentages.values())
        if abs(total_pct - Decimal("100")) > Decimal("0.0001"):
            raise ValueError(f"Percentages must sum to exactly 100. Current sum: {total_pct}")

        total_minor = to_minor_units(total_amount, currency)
        
        # Calculate ideal continuous minor units and integer parts
        calculated = []
        accumulated_integer_minor = 0

        for user_id, pct in percentages.items():
            ideal = (Decimal(total_minor) * pct) / Decimal("100")
            integer_part = int(ideal.quantize(Decimal("1"), rounding=ROUND_FLOOR))
            fractional_part = ideal - Decimal(integer_part)
            accumulated_integer_minor += integer_part
            calculated.append({
                "user_id": user_id,
                "integer_minor": integer_part,
                "fraction": fractional_part,
                "pct": pct
            })

        remainder_minor = total_minor - accumulated_integer_minor

        # Sort by largest fractional remainder descending; tiebreak deterministically by user_id
        calculated.sort(key=lambda x: (-x["fraction"], x["user_id"]))

        for i in range(remainder_minor):
            calculated[i]["integer_minor"] += 1

        results = [
            SplitResult(
                user_id=item["user_id"],
                amount=from_minor_units(item["integer_minor"], currency),
                share_value=item["pct"]
            )
            for item in calculated
        ]

        allocated_sum = sum(r.amount for r in results)
        if allocated_sum != quantize_currency(total_amount, currency):
            raise AssertionError(f"Percentage allocation invariant violated: {allocated_sum} != {total_amount}")

        return results

    @staticmethod
    def split_by_shares(
        total_amount: Decimal,
        currency: str,
        shares: Dict[str, Decimal]
    ) -> List[SplitResult]:
        """
        Divides total_amount based on arbitrary positive share units (e.g. 2 shares, 1.5 shares).
        """
        total_shares = sum(shares.values())
        if total_shares <= Decimal("0"):
            raise ValueError("Total shares must be greater than zero")

        total_minor = to_minor_units(total_amount, currency)
        calculated = []
        accumulated_integer_minor = 0

        for user_id, share in shares.items():
            if share < Decimal("0"):
                raise ValueError("Individual shares must be non-negative")
            ideal = (Decimal(total_minor) * share) / total_shares
            integer_part = int(ideal.quantize(Decimal("1"), rounding=ROUND_FLOOR))
            fractional_part = ideal - Decimal(integer_part)
            accumulated_integer_minor += integer_part
            calculated.append({
                "user_id": user_id,
                "integer_minor": integer_part,
                "fraction": fractional_part,
                "share": share
            })

        remainder_minor = total_minor - accumulated_integer_minor
        calculated.sort(key=lambda x: (-x["fraction"], x["user_id"]))

        for i in range(remainder_minor):
            calculated[i]["integer_minor"] += 1

        results = [
            SplitResult(
                user_id=item["user_id"],
                amount=from_minor_units(item["integer_minor"], currency),
                share_value=item["share"]
            )
            for item in calculated
        ]

        allocated_sum = sum(r.amount for r in results)
        if allocated_sum != quantize_currency(total_amount, currency):
            raise AssertionError(f"Shares allocation invariant violated: {allocated_sum} != {total_amount}")

        return results

    @staticmethod
    def validate_exact_splits(
        total_amount: Decimal,
        currency: str,
        exact_amounts: Dict[str, Decimal]
    ) -> List[SplitResult]:
        """
        Validates that the sum of exact split inputs equals total_amount to the exact currency precision.
        """
        quantized_total = quantize_currency(total_amount, currency)
        quantized_splits = {
            uid: quantize_currency(amt, currency)
            for uid, amt in exact_amounts.items()
        }
        split_sum = sum(quantized_splits.values())

        if split_sum != quantized_total:
            difference = quantized_total - split_sum
            raise ValueError(
                f"Sum of exact amounts ({split_sum}) does not match total amount ({quantized_total}). "
                f"Discrepancy: {difference} {currency}"
            )

        return [
            SplitResult(user_id=uid, amount=amt)
            for uid, amt in quantized_splits.items()
        ]
