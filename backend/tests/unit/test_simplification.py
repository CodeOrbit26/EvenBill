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


# -----------------------------------------------------------------------------
# Bilateral Pairwise Tests (Without Simplification)
# -----------------------------------------------------------------------------

def test_pairwise_bilateral_debts_no_self_double_counting():
    # Expense: Alice pays $100 for Alice and Bob ($50 each).
    # Expected: Bob owes Alice $50. Alice does NOT owe herself or Bob anything.
    expense_records = [
        {
            "payers": [("alice", Decimal("100.00"))],
            "splits": [("alice", Decimal("50.00")), ("bob", Decimal("50.00"))],
            "total_amount": Decimal("100.00")
        }
    ]
    settlement_records = []
    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=expense_records,
        settlement_records=settlement_records,
        currency="USD"
    )

    assert len(bilateral) == 1
    assert bilateral[0].debtor_id == "bob"
    assert bilateral[0].creditor_id == "alice"
    assert bilateral[0].amount == Decimal("50.00")


def test_pairwise_bilateral_with_mutual_expenses_and_settlement():
    # 1. Alice pays $100 for Alice, Bob, Carol ($33.34, $33.33, $33.33)
    #    Bob owes Alice 33.33, Carol owes Alice 33.33.
    # 2. Bob pays $60 for Alice and Bob ($30 each)
    #    Alice owes Bob 30.00.
    # Net bilateral between Alice and Bob:
    #    Bob owed Alice 33.33, Alice owed Bob 30.00 -> Net: Bob owes Alice 3.33.
    # 3. Settlement: Bob pays Alice $3.33
    # Net bilateral between Alice and Bob resolves to $0.00!
    expense_records = [
        {
            "payers": [("alice", Decimal("100.00"))],
            "splits": [("alice", Decimal("33.34")), ("bob", Decimal("33.33")), ("carol", Decimal("33.33"))],
            "total_amount": Decimal("100.00")
        },
        {
            "payers": [("bob", Decimal("60.00"))],
            "splits": [("alice", Decimal("30.00")), ("bob", Decimal("30.00"))],
            "total_amount": Decimal("60.00")
        }
    ]
    settlement_records = [
        {"payer_id": "bob", "recipient_id": "alice", "amount": Decimal("3.33")}
    ]

    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=expense_records,
        settlement_records=settlement_records,
        currency="USD"
    )

    # Bob-Alice debt is fully settled! Only Carol owes Alice 33.33.
    assert len(bilateral) == 1
    assert bilateral[0].debtor_id == "carol"
    assert bilateral[0].creditor_id == "alice"
    assert bilateral[0].amount == Decimal("33.33")


# -----------------------------------------------------------------------------
# Precision Tests (JPY, BHD)
# -----------------------------------------------------------------------------

def test_simplification_jpy_zero_decimals():
    # 3 people in Tokyo: Tanaka +3000 JPY, Sato -2000 JPY, Suzuki -1000 JPY
    net_balances = {
        "Tanaka": Decimal("3000"),
        "Sato": Decimal("-2000"),
        "Suzuki": Decimal("-1000")
    }
    simplified = DebtSimplifier.simplify_net_balances(net_balances, "JPY")

    assert len(simplified) == 2
    for debt in simplified:
        assert debt.amount == debt.amount.quantize(Decimal("1"))
        assert debt.creditor_id == "Tanaka"


def test_simplification_bhd_three_decimals():
    # 3 people in Bahrain: Ali +45.500 BHD, Tariq -30.250 BHD, Zain -15.250 BHD
    net_balances = {
        "Ali": Decimal("45.500"),
        "Tariq": Decimal("-30.250"),
        "Zain": Decimal("-15.250")
    }
    simplified = DebtSimplifier.simplify_net_balances(net_balances, "BHD")

    assert len(simplified) == 2
    for debt in simplified:
        assert debt.currency == "BHD"
        assert debt.creditor_id == "Ali"
    total_transfer = sum(d.amount for d in simplified)
    assert total_transfer == Decimal("45.500")


# -----------------------------------------------------------------------------
# Property-Based Invariant Tests with Hypothesis
# -----------------------------------------------------------------------------

from hypothesis import given, strategies as st, settings


@given(
    debtor_amounts=st.lists(
        st.integers(min_value=1, max_value=50000),
        min_size=1,
        max_size=8
    )
)
@settings(max_examples=50)
def test_hypothesis_debt_simplification_invariants(debtor_amounts: list):
    """
    Generates arbitrary net debtors and balances them with an equal net creditor pool,
    verifying that:
    1. Resulting transfers preserve each person's exact net balance.
    2. Total number of transactions never exceeds (N - 1).
    3. All transfer amounts are strictly positive.
    """
    n_debtors = len(debtor_amounts)
    total_debt = sum(debtor_amounts)

    net_balances: Dict[str, Decimal] = {}
    for i, amt in enumerate(debtor_amounts):
        net_balances[f"debtor_{i}"] = Decimal(-amt) / Decimal("100")

    # Split the creditor side among 1-3 creditors
    n_creditors = min(3, max(1, n_debtors))
    base_cred = total_debt // n_creditors
    rem = total_debt % n_creditors

    for j in range(n_creditors):
        cred_amt = base_cred + (1 if j < rem else 0)
        net_balances[f"creditor_{j}"] = Decimal(cred_amt) / Decimal("100")

    # Invariant: Net balance sum must be 0
    assert sum(net_balances.values()) == Decimal("0.00")

    simplified = DebtSimplifier.simplify_net_balances(net_balances, "USD")

    # Invariant 1: Max transactions <= N - 1
    total_participants = len(net_balances)
    assert len(simplified) <= total_participants - 1

    # Invariant 2: All amounts strictly positive
    for d in simplified:
        assert d.amount > Decimal("0.00")

    # Invariant 3: Net positions are strictly conserved
    reconstructed = {u: Decimal("0.00") for u in net_balances}
    for d in simplified:
        reconstructed[d.debtor_id] -= d.amount
        reconstructed[d.creditor_id] += d.amount

    for user, target in net_balances.items():
        assert reconstructed[user] == target, f"User {user} reconstructed {reconstructed[user]} != target {target}"

