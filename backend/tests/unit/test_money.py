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
