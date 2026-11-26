"""
EvenBill Financial Precision Engine
Implements exact monetary arithmetic using Python Decimal and deterministic remainder distribution.
No binary floating-point arithmetic is permitted.
"""

from decimal import Decimal, ROUND_HALF_EVEN, ROUND_FLOOR
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, field
from pydantic import BaseModel, Field

# ISO-4217 Currency Decimals Specification
CURRENCY_DECIMALS: Dict[str, int] = {
    "USD": 2, "EUR": 2, "GBP": 2, "INR": 2,
    "CAD": 2, "AUD": 2, "CHF": 2, "SGD": 2,
    "NZD": 2, "HKD": 2, "SEK": 2, "NOK": 2,
    "MXN": 2, "BRL": 2, "ZAR": 2, "AED": 2, "CNY": 2,
    "JPY": 0, "KRW": 0, "VND": 0, "IDR": 0, "CLP": 0,
    "BHD": 3, "KWD": 3, "OMR": 3, "JOD": 3, "TND": 3,
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
    item_breakdown: Optional[Dict[str, Decimal]] = None


@dataclass
class ItemizedEntry:
    description: str
    amount: Decimal
    participant_ids: List[str]


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
        for uid, amt in quantized_splits.items():
            if amt < Decimal("0"):
                raise ValueError(f"Exact amount for participant {uid} cannot be negative")

        split_sum = sum(quantized_splits.values())

        if split_sum != quantized_total:
            difference = quantized_total - split_sum
            raise ValueError(
                f"Sum of exact amounts ({split_sum}) does not match total amount ({quantized_total}). "
                f"Discrepancy: {difference} {currency}"
            )

        return [
            SplitResult(user_id=uid, amount=amt)
            for uid, amt in sorted(quantized_splits.items(), key=lambda x: x[0])
        ]

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
        for uid, pct in percentages.items():
            if pct < Decimal("0"):
                raise ValueError(f"Percentage for participant {uid} cannot be negative")

        total_pct = sum(percentages.values())
        if abs(total_pct - Decimal("100")) > Decimal("0.0001"):
            raise ValueError(f"Percentages must sum to exactly 100. Current sum: {total_pct}")

        total_minor = to_minor_units(total_amount, currency)
        
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
            for item in sorted(calculated, key=lambda x: x["user_id"])
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
        Divides total_amount based on arbitrary positive share weights (e.g. 2 shares, 1.5 shares).
        """
        total_shares = sum(shares.values())
        if total_shares <= Decimal("0"):
            raise ValueError("Total shares must be strictly greater than zero")

        for uid, share in shares.items():
            if share < Decimal("0"):
                raise ValueError(f"Share weight for participant {uid} cannot be negative")

        total_minor = to_minor_units(total_amount, currency)
        calculated = []
        accumulated_integer_minor = 0

        for user_id, share in shares.items():
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
            for item in sorted(calculated, key=lambda x: x["user_id"])
        ]

        allocated_sum = sum(r.amount for r in results)
        if allocated_sum != quantize_currency(total_amount, currency):
            raise AssertionError(f"Shares allocation invariant violated: {allocated_sum} != {total_amount}")

        return results

    @staticmethod
    def split_with_adjustments(
        total_amount: Decimal,
        currency: str,
        participant_ids: List[str],
        adjustments: Dict[str, Decimal]
    ) -> List[SplitResult]:
        """
        Divides total_amount equally among participants with individual adjustments (offsets).
        Example: Alice ordered an extra dessert (+$10), Bob skipped drinks (-$5).
        Base share is calculated from (total_amount - sum(adjustments)) / len(participants),
        and each participant's adjustment is added to their base share.
        """
        if not participant_ids:
            raise ValueError("Participant list cannot be empty")
        
        quantized_total = quantize_currency(total_amount, currency)
        quantized_adjustments = {
            uid: quantize_currency(amt, currency)
            for uid, amt in adjustments.items()
        }

        # Check for unknown participants in adjustments
        for uid in quantized_adjustments:
            if uid not in participant_ids:
                raise ValueError(f"Adjustment specified for non-participant user: {uid}")

        sum_adjustments = sum(quantized_adjustments.values())
        base_split_pool = quantized_total - sum_adjustments

        if base_split_pool < Decimal("0"):
            raise ValueError(
                f"Sum of adjustments ({sum_adjustments}) exceeds total expense amount ({quantized_total})"
            )

        # Equal split of base pool (if pool > 0)
        base_shares: Dict[str, Decimal] = {}
        if base_split_pool > Decimal("0"):
            equal_results = MoneyEngine.split_equally(
                total_amount=base_split_pool,
                currency=currency,
                participant_ids=participant_ids
            )
            for r in equal_results:
                base_shares[r.user_id] = r.amount
        else:
            for uid in participant_ids:
                base_shares[uid] = Decimal("0")

        # Combine base share + adjustment
        final_splits: List[SplitResult] = []
        for uid in sorted(participant_ids):
            adj = quantized_adjustments.get(uid, Decimal("0"))
            final_owed = base_shares[uid] + adj
            if final_owed < Decimal("0"):
                raise ValueError(
                    f"Adjustment for participant {uid} ({adj}) results in a negative owed amount ({final_owed})"
                )
            final_splits.append(
                SplitResult(
                    user_id=uid,
                    amount=quantize_currency(final_owed, currency),
                    share_value=adj
                )
            )

        # Invariant Verification
        allocated_sum = sum(s.amount for s in final_splits)
        if allocated_sum != quantized_total:
            raise AssertionError(f"Adjustments allocation invariant violated: {allocated_sum} != {quantized_total}")

        return final_splits

    @staticmethod
    def split_itemized(
        currency: str,
        items: List[ItemizedEntry],
        tax: Decimal = Decimal("0"),
        tip: Decimal = Decimal("0"),
        fee: Decimal = Decimal("0"),
        discount: Decimal = Decimal("0")
    ) -> Tuple[Decimal, List[SplitResult]]:
        """
        Splits an itemized expense where each item belongs to specific participants.
        Taxes, tips, and fees are distributed proportionally based on each participant's item subtotal.
        Discounts reduce participant shares proportionally.
        Returns: (total_bill_amount, list_of_split_results).
        """
        if not items:
            raise ValueError("Itemized expense must contain at least one item")

        # 1. Quantize all item amounts and split items among their tagged participants
        user_item_subtotals: Dict[str, Decimal] = {}

        for item in items:
            q_amount = quantize_currency(item.amount, currency)
            if q_amount <= Decimal("0"):
                raise ValueError(f"Item '{item.description}' amount must be strictly positive")
            if not item.participant_ids:
                raise ValueError(f"Item '{item.description}' must have at least one assigned participant")

            item_splits = MoneyEngine.split_equally(
                total_amount=q_amount,
                currency=currency,
                participant_ids=item.participant_ids
            )
            for sp in item_splits:
                user_item_subtotals[sp.user_id] = (
                    user_item_subtotals.get(sp.user_id, Decimal("0")) + sp.amount
                )

        items_subtotal = sum(user_item_subtotals.values())

        # 2. Compute Extra Surcharges / Reductions
        q_tax = quantize_currency(tax, currency)
        q_tip = quantize_currency(tip, currency)
        q_fee = quantize_currency(fee, currency)
        q_discount = quantize_currency(discount, currency)

        if q_tax < Decimal("0") or q_tip < Decimal("0") or q_fee < Decimal("0") or q_discount < Decimal("0"):
            raise ValueError("Taxes, tips, fees, and discounts cannot be negative")

        net_surcharges = q_tax + q_tip + q_fee - q_discount
        total_bill = items_subtotal + net_surcharges

        if total_bill <= Decimal("0"):
            raise ValueError(f"Total bill amount ({total_bill}) must be strictly positive")

        # 3. Proportional Distribution of Surcharges / Discounts using Largest Remainder Method
        surcharge_minor = to_minor_units(net_surcharges, currency)
        all_participants = sorted(user_item_subtotals.keys())

        if surcharge_minor == 0 or items_subtotal == Decimal("0"):
            # No surcharges or 0 items
            final_results = [
                SplitResult(
                    user_id=uid,
                    amount=quantize_currency(user_item_subtotals[uid], currency),
                    share_value=user_item_subtotals[uid]
                )
                for uid in all_participants
            ]
        else:
            calculated = []
            accumulated_minor = 0

            for uid in all_participants:
                user_sub = user_item_subtotals[uid]
                # Proportion of items
                ideal = (Decimal(surcharge_minor) * user_sub) / items_subtotal
                integer_part = int(ideal.quantize(Decimal("1"), rounding=ROUND_FLOOR))
                fractional_part = ideal - Decimal(integer_part)
                accumulated_minor += integer_part
                calculated.append({
                    "user_id": uid,
                    "integer_minor": integer_part,
                    "fraction": fractional_part,
                    "subtotal": user_sub
                })

            remainder_minor = surcharge_minor - accumulated_minor
            # Sort by largest fractional remainder descending
            calculated.sort(key=lambda x: (-x["fraction"], x["user_id"]))

            for i in range(remainder_minor):
                calculated[i]["integer_minor"] += 1

            final_results = []
            for item in sorted(calculated, key=lambda x: x["user_id"]):
                user_surcharge = from_minor_units(item["integer_minor"], currency)
                final_owed = item["subtotal"] + user_surcharge
                if final_owed < Decimal("0"):
                    raise ValueError(f"Discount results in negative owed balance for participant {item['user_id']}")
                final_results.append(
                    SplitResult(
                        user_id=item["user_id"],
                        amount=quantize_currency(final_owed, currency),
                        share_value=item["subtotal"]
                    )
                )

        # Invariant Verification
        allocated_total = sum(r.amount for r in final_results)
        if allocated_total != quantize_currency(total_bill, currency):
            raise AssertionError(f"Itemized allocation invariant violated: {allocated_total} != {total_bill}")

        return quantize_currency(total_bill, currency), final_results
