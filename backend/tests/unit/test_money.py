"""
Unit Tests for EvenBill Financial Precision Engine
Verifies exact monetary arithmetic, Hare-Niemeyer split algorithms, and invariant preservation.
"""

import pytest
from decimal import Decimal
from app.core.money import (
    MoneyEngine, to_minor_units, from_minor_units,
    quantize_currency, get_currency_decimals
)


def test_minor_units_conversion_usd():
    amount = Decimal("100.55")
    minor = to_minor_units(amount, "USD")
    assert minor == 10055
    restored = from_minor_units(minor, "USD")
    assert restored == amount


def test_minor_units_conversion_jpy():
    amount = Decimal("1250")
    minor = to_minor_units(amount, "JPY")
    assert minor == 1250
    restored = from_minor_units(minor, "JPY")
    assert restored == amount


def test_split_equally_exact_division():
    # $100.00 divided by 4 participants = exactly $25.00 each
    participants = ["user_1", "user_2", "user_3", "user_4"]
    splits = MoneyEngine.split_equally(Decimal("100.00"), "USD", participants)

    assert len(splits) == 4
    for s in splits:
        assert s.amount == Decimal("25.00")
    assert sum(s.amount for s in splits) == Decimal("100.00")


def test_split_equally_with_remainder_conservation():
    # $100.00 divided among 3 participants
    # $100.00 = 10000 cents. 10000 // 3 = 3333 cents with remainder 1 cent.
    # Deterministic assignment gives 1 participant 3334 cents ($33.34) and others 3333 cents ($33.33).
    participants = ["alice", "bob", "carol"]
    splits = MoneyEngine.split_equally(Decimal("100.00"), "USD", participants)

    assert len(splits) == 3
    total = sum(s.amount for s in splits)
    assert total == Decimal("100.00"), f"Expected 100.00, got {total}"

    amounts = [s.amount for s in splits]
    assert amounts.count(Decimal("33.34")) == 1
    assert amounts.count(Decimal("33.33")) == 2


def test_split_equally_odd_amount_seven_people():
    # $77.77 divided among 7 participants
    # 7777 cents // 7 = 1111 cents ($11.11) with remainder 0
    participants = [f"user_{i}" for i in range(7)]
    splits = MoneyEngine.split_equally(Decimal("77.77"), "USD", participants)

    assert len(splits) == 7
    assert sum(s.amount for s in splits) == Decimal("77.77")
    for s in splits:
        assert s.amount == Decimal("11.11")


def test_split_by_percentages():
    # $150.00 split 50%, 30%, 20%
    percentages = {
        "alice": Decimal("50.0"),
        "bob": Decimal("30.0"),
        "carol": Decimal("20.0")
    }
    splits = MoneyEngine.split_by_percentages(Decimal("150.00"), "USD", percentages)

    split_dict = {s.user_id: s.amount for s in splits}
    assert split_dict["alice"] == Decimal("75.00")
    assert split_dict["bob"] == Decimal("45.00")
    assert split_dict["carol"] == Decimal("30.00")
    assert sum(split_dict.values()) == Decimal("150.00")


def test_split_by_percentages_with_rounding():
    # $100.00 split 33.33%, 33.33%, 33.34%
    percentages = {
        "alice": Decimal("33.33"),
        "bob": Decimal("33.33"),
        "carol": Decimal("33.34")
    }
    splits = MoneyEngine.split_by_percentages(Decimal("100.00"), "USD", percentages)
    assert sum(s.amount for s in splits) == Decimal("100.00")


def test_split_by_shares():
    # $60.00 split 1 share, 2 shares, 3 shares (Total = 6 shares -> $10/share)
    shares = {
        "alice": Decimal("1"),
        "bob": Decimal("2"),
        "carol": Decimal("3")
    }
    splits = MoneyEngine.split_by_shares(Decimal("60.00"), "USD", shares)

    split_dict = {s.user_id: s.amount for s in splits}
    assert split_dict["alice"] == Decimal("10.00")
    assert split_dict["bob"] == Decimal("20.00")
    assert split_dict["carol"] == Decimal("30.00")
    assert sum(split_dict.values()) == Decimal("60.00")


def test_validate_exact_splits_valid():
    exact = {
        "alice": Decimal("40.00"),
        "bob": Decimal("35.50"),
        "carol": Decimal("24.50")
    }
    splits = MoneyEngine.validate_exact_splits(Decimal("100.00"), "USD", exact)
    assert sum(s.amount for s in splits) == Decimal("100.00")


def test_validate_exact_splits_mismatch():
    exact = {
        "alice": Decimal("40.00"),
        "bob": Decimal("35.00")
    }
    with pytest.raises(ValueError) as excinfo:
        MoneyEngine.validate_exact_splits(Decimal("100.00"), "USD", exact)
    assert "Discrepancy" in str(excinfo.value)


# -----------------------------------------------------------------------------
# Adjustments Tests
# -----------------------------------------------------------------------------

def test_split_with_adjustments_balanced():
    # $120.00 split among Alice, Bob, Carol.
    # Alice +$10 (extra steak), Bob -$10 (drank water), Carol $0.
    # Base pool: 120 - 0 = 120 / 3 = 40 each.
    # Alice: 40 + 10 = 50. Bob: 40 - 10 = 30. Carol: 40 + 0 = 40.
    participants = ["alice", "bob", "carol"]
    adjustments = {"alice": Decimal("10.00"), "bob": Decimal("-10.00")}
    splits = MoneyEngine.split_with_adjustments(Decimal("120.00"), "USD", participants, adjustments)

    split_dict = {s.user_id: s.amount for s in splits}
    assert split_dict["alice"] == Decimal("50.00")
    assert split_dict["bob"] == Decimal("30.00")
    assert split_dict["carol"] == Decimal("40.00")
    assert sum(split_dict.values()) == Decimal("120.00")


def test_split_with_adjustments_with_remainder():
    # $100.00 split among 3 people.
    # Alice has +$15.00 adjustment, Bob has -$5.00 adjustment. Net adjustments = +$10.00.
    # Base pool = 100 - 10 = $90.00. Base per person = 90 / 3 = $30.00 each.
    # Alice = 30 + 15 = $45.00. Bob = 30 - 5 = $25.00. Carol = $30.00. Total = $100.00.
    participants = ["alice", "bob", "carol"]
    adjustments = {"alice": Decimal("15.00"), "bob": Decimal("-5.00")}
    splits = MoneyEngine.split_with_adjustments(Decimal("100.00"), "USD", participants, adjustments)

    split_dict = {s.user_id: s.amount for s in splits}
    assert split_dict["alice"] == Decimal("45.00")
    assert split_dict["bob"] == Decimal("25.00")
    assert split_dict["carol"] == Decimal("30.00")
    assert sum(split_dict.values()) == Decimal("100.00")


def test_split_with_adjustments_exceeds_total():
    participants = ["alice", "bob"]
    adjustments = {"alice": Decimal("70.00"), "bob": Decimal("50.00")}  # sum = 120 > 100
    with pytest.raises(ValueError) as excinfo:
        MoneyEngine.split_with_adjustments(Decimal("100.00"), "USD", participants, adjustments)
    assert "exceeds total expense amount" in str(excinfo.value)


def test_split_with_adjustments_negative_result():
    participants = ["alice", "bob"]
    # Total $50. Alice -$40 adjustment -> base pool = 50 - (-40) = 90 / 2 = 45. Alice gets 45 - 40 = 5.
    # But if Alice -$60 adjustment -> base pool = 110 / 2 = 55. Alice gets 55 - 60 = -5 (negative!).
    adjustments = {"alice": Decimal("-60.00")}
    with pytest.raises(ValueError) as excinfo:
        MoneyEngine.split_with_adjustments(Decimal("50.00"), "USD", participants, adjustments)
    assert "negative owed amount" in str(excinfo.value)


def test_split_with_adjustments_unknown_participant():
    participants = ["alice", "bob"]
    adjustments = {"carol": Decimal("10.00")}
    with pytest.raises(ValueError) as excinfo:
        MoneyEngine.split_with_adjustments(Decimal("100.00"), "USD", participants, adjustments)
    assert "non-participant user" in str(excinfo.value)


# -----------------------------------------------------------------------------
# Itemized Split Tests (with Tax, Tip, Fees, Discounts)
# -----------------------------------------------------------------------------

def test_split_itemized_full_dining_bill():
    from app.core.money import ItemizedEntry

    # Items:
    # 1. Truffle Pizza: $30.00 shared by Alice & Bob ($15.00 each)
    # 2. Caesar Salad: $15.00 for Carol ($15.00)
    # 3. Bottle of Wine: $45.00 shared by Alice, Bob, Carol ($15.00 each)
    # Subtotal = $90.00 (Alice: 30, Bob: 30, Carol: 30 -> 1/3 each)
    # Tax: $9.00 (10%) -> $3.00 each
    # Tip: $18.00 (20%) -> $6.00 each
    # Service Fee: $3.00 -> $1.00 each
    # Discount: $6.00 -> -$2.00 each
    # Net extra = +$24.00
    # Expected total: $90.00 + $24.00 = $114.00
    # Expected each: $30 + $8 = $38.00 each

    items = [
        ItemizedEntry(description="Truffle Pizza", amount=Decimal("30.00"), participant_ids=["alice", "bob"]),
        ItemizedEntry(description="Caesar Salad", amount=Decimal("15.00"), participant_ids=["carol"]),
        ItemizedEntry(description="Bottle of Wine", amount=Decimal("45.00"), participant_ids=["alice", "bob", "carol"]),
    ]

    total_bill, splits = MoneyEngine.split_itemized(
        currency="USD",
        items=items,
        tax=Decimal("9.00"),
        tip=Decimal("18.00"),
        fee=Decimal("3.00"),
        discount=Decimal("6.00")
    )

    assert total_bill == Decimal("114.00")
    assert sum(s.amount for s in splits) == Decimal("114.00")
    split_map = {s.user_id: s.amount for s in splits}
    assert split_map["alice"] == Decimal("38.00")
    assert split_map["bob"] == Decimal("38.00")
    assert split_map["carol"] == Decimal("38.00")


def test_split_itemized_unequal_surcharge_rounding():
    from app.core.money import ItemizedEntry

    # Alice has $70 item, Bob has $30 item. Subtotal = $100.
    # Tax = $7.77, Tip = $13.33. Total surcharges = $21.10.
    # Alice fraction = 70/100 = 0.7 -> 21.10 * 0.7 = 14.77
    # Bob fraction = 30/100 = 0.3 -> 21.10 * 0.3 = 6.33
    # Total bill = 100 + 21.10 = 121.10
    items = [
        ItemizedEntry(description="Steak", amount=Decimal("70.00"), participant_ids=["alice"]),
        ItemizedEntry(description="Pasta", amount=Decimal("30.00"), participant_ids=["bob"]),
    ]

    total_bill, splits = MoneyEngine.split_itemized(
        currency="USD",
        items=items,
        tax=Decimal("7.77"),
        tip=Decimal("13.33")
    )

    assert total_bill == Decimal("121.10")
    assert sum(s.amount for s in splits) == Decimal("121.10")
    split_map = {s.user_id: s.amount for s in splits}
    assert split_map["alice"] == Decimal("84.77")
    assert split_map["bob"] == Decimal("36.33")


# -----------------------------------------------------------------------------
# Currency Precision Tests (0 decimals, 2 decimals, 3 decimals)
# -----------------------------------------------------------------------------

def test_jpy_zero_decimal_precision():
    # Japanese Yen (0 decimal places)
    # 10,000 JPY split among 3 people
    # 10000 // 3 = 3333, remainder 1
    # 1 person gets 3334, 2 get 3333. Sum strictly equals 10000.
    participants = ["tanaka", "sato", "suzuki"]
    splits = MoneyEngine.split_equally(Decimal("10000"), "JPY", participants)

    assert len(splits) == 3
    assert sum(s.amount for s in splits) == Decimal("10000")
    amounts = [s.amount for s in splits]
    assert amounts.count(Decimal("3334")) == 1
    assert amounts.count(Decimal("3333")) == 2


def test_bhd_three_decimal_precision():
    # Bahraini Dinar (3 decimal places)
    # 100.000 BHD split among 3 people
    # 100000 minor units // 3 = 33333 with remainder 1 (0.001)
    participants = ["user_1", "user_2", "user_3"]
    splits = MoneyEngine.split_equally(Decimal("100.000"), "BHD", participants)

    assert len(splits) == 3
    assert sum(s.amount for s in splits) == Decimal("100.000")
    amounts = [s.amount for s in splits]
    assert amounts.count(Decimal("33.334")) == 1
    assert amounts.count(Decimal("33.333")) == 2


def test_shares_with_jpy_zero_precision():
    # 5,000 JPY split with shares: 2, 1, 1 (Total = 4 shares -> 1250 each)
    shares = {"user_a": Decimal("2"), "user_b": Decimal("1"), "user_c": Decimal("1")}
    splits = MoneyEngine.split_by_shares(Decimal("5000"), "JPY", shares)

    split_map = {s.user_id: s.amount for s in splits}
    assert split_map["user_a"] == Decimal("2500")
    assert split_map["user_b"] == Decimal("1250")
    assert split_map["user_c"] == Decimal("1250")
    assert sum(split_map.values()) == Decimal("5000")


# -----------------------------------------------------------------------------
# Input Validation & Invariant Failures
# -----------------------------------------------------------------------------

def test_shares_negative_or_zero_rejection():
    with pytest.raises(ValueError) as exc1:
        MoneyEngine.split_by_shares(Decimal("50.00"), "USD", {"alice": Decimal("-1"), "bob": Decimal("2")})
    assert "cannot be negative" in str(exc1.value)

    with pytest.raises(ValueError) as exc2:
        MoneyEngine.split_by_shares(Decimal("50.00"), "USD", {"alice": Decimal("0"), "bob": Decimal("0")})
    assert "strictly greater than zero" in str(exc2.value)


def test_percentages_negative_or_not_100_rejection():
    with pytest.raises(ValueError) as exc1:
        MoneyEngine.split_by_percentages(Decimal("50.00"), "USD", {"alice": Decimal("-10"), "bob": Decimal("110")})
    assert "cannot be negative" in str(exc1.value)

    with pytest.raises(ValueError) as exc2:
        MoneyEngine.split_by_percentages(Decimal("50.00"), "USD", {"alice": Decimal("40"), "bob": Decimal("50")})
    assert "must sum to exactly 100" in str(exc2.value)


# -----------------------------------------------------------------------------
# Property-Based Invariant Tests with Hypothesis
# -----------------------------------------------------------------------------

from hypothesis import given, strategies as st, settings


@given(
    amount=st.decimals(min_value=Decimal("0.01"), max_value=Decimal("100000.00"), places=2),
    n_participants=st.integers(min_value=1, max_value=20)
)
@settings(max_examples=50)
def test_hypothesis_equal_split_conservation(amount: Decimal, n_participants: int):
    participants = [f"user_{i}" for i in range(n_participants)]
    splits = MoneyEngine.split_equally(amount, "USD", participants)

    # Invariant 1: Sum of splits strictly equals original total
    assert sum(s.amount for s in splits) == amount
    # Invariant 2: Number of splits equals participant count
    assert len(splits) == n_participants


@given(
    amount=st.decimals(min_value=Decimal("1.00"), max_value=Decimal("10000.00"), places=2),
    weights=st.lists(
        st.decimals(min_value=Decimal("0.1"), max_value=Decimal("10.0"), places=1),
        min_size=2,
        max_size=8
    )
)
@settings(max_examples=50)
def test_hypothesis_shares_split_conservation(amount: Decimal, weights: list):
    shares = {f"user_{i}": w for i, w in enumerate(weights)}
    splits = MoneyEngine.split_by_shares(amount, "USD", shares)

    # Invariant: Sum of splits strictly equals original total down to 1 cent
    assert sum(s.amount for s in splits) == amount
    assert len(splits) == len(weights)

