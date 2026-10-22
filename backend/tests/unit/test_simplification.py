"""
Unit Tests for EvenBill Debt Simplification Engine
Validates minimal cash flow reduction, circular debt cancellation, and net balance invariants.
"""

import pytest
from decimal import Decimal
from app.core.simplification import DebtSimplifier, SimplifiedDebt


def test_circular_debt_cancellation():
    # A owes B $10, B owes C $10, C owes A $10
    # Net balances:
    # A: +10 (lent to C) - 10 (borrowed from B) = 0
    # B: +10 (lent to A) - 10 (borrowed from C) = 0
    # C: +10 (lent to B) - 10 (borrowed from A) = 0
    net_balances = {
        "A": Decimal("0.00"),
        "B": Decimal("0.00"),
        "C": Decimal("0.00")
    }
    simplified = DebtSimplifier.simplify_net_balances(net_balances, "USD")
    # All circular debt resolves to 0 transfers
    assert len(simplified) == 0


def test_four_party_debt_minimization():
    # Net balances in a 4-person group:
    # Alice: +$60.00 (creditor)
    # Bob:   +$40.00 (creditor)
    # Carol: -$50.00 (debtor)
    # Dave:  -$50.00 (debtor)
    # Net sum: 60 + 40 - 50 - 50 = 0
    net_balances = {
        "Alice": Decimal("60.00"),
        "Bob": Decimal("40.00"),
        "Carol": Decimal("-50.00"),
        "Dave": Decimal("-50.00")
    }
    simplified = DebtSimplifier.simplify_net_balances(net_balances, "USD")

    # Invariant: Maximum number of transactions is at most N - 1 = 3
    assert len(simplified) <= 3

    # Total volume of settled cash
    total_transfer = sum(d.amount for d in simplified)
    assert total_transfer == Decimal("100.00")

    # Verify that each participant's resulting balance from the simplified transfers matches their net balance
    effective_balances = {k: Decimal("0.00") for k in net_balances}
    for debt in simplified:
        effective_balances[debt.debtor_id] -= debt.amount
        effective_balances[debt.creditor_id] += debt.amount

    for user, net in net_balances.items():
        assert effective_balances[user] == net, f"User {user} effective balance {effective_balances[user]} != net {net}"


def test_unbalanced_net_raises_error():
    # If sum of net balances is non-zero, it must raise a ValueError
    net_balances = {
        "Alice": Decimal("50.00"),
        "Bob": Decimal("-40.00")
    }
    with pytest.raises(ValueError) as excinfo:
        DebtSimplifier.simplify_net_balances(net_balances, "USD")
    assert "invariant violated" in str(excinfo.value)
