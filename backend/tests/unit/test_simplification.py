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


def test_pairwise_bilateral_multi_payer_preserves_all_minor_units():
    # Odd minor unit multi-payer expense: $1.01 paid by Alice ($0.51) and Bob ($0.50),
    # split across Carol ($0.51) and Dave ($0.50). Previously floor division lost 2 cents!
    expense_records = [
        {
            "payers": [("alice", Decimal("0.51")), ("bob", Decimal("0.50"))],
            "splits": [("carol", Decimal("0.51")), ("dave", Decimal("0.50"))],
            "total_amount": Decimal("1.01"),
        }
    ]
    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=expense_records,
        settlement_records=[],
        currency="USD",
    )

    net = {"alice": Decimal("0.00"), "bob": Decimal("0.00"), "carol": Decimal("0.00"), "dave": Decimal("0.00")}
    for d in bilateral:
        assert d.amount > Decimal("0.00")
        net[d.debtor_id] -= d.amount
        net[d.creditor_id] += d.amount

    assert net["alice"] == Decimal("0.51")
    assert net["bob"] == Decimal("0.50")
    assert net["carol"] == Decimal("-0.51")
    assert net["dave"] == Decimal("-0.50")
    assert sum(d.amount for d in bilateral) == Decimal("1.01")


def test_pairwise_bilateral_multi_payer_with_overlapping_payer_consumers():
    # 3 participants share $3.00 equally ($1.00 each); Alice pays $2.00, Bob pays $1.00.
    # Bob already paid his own $1.00 share cleanly, so only Carol owes Alice $1.00.
    expense_records = [
        {
            "payers": [("alice", Decimal("2.00")), ("bob", Decimal("1.00"))],
            "splits": [("alice", Decimal("1.00")), ("bob", Decimal("1.00")), ("carol", Decimal("1.00"))],
            "total_amount": Decimal("3.00"),
        }
    ]
    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=expense_records,
        settlement_records=[],
        currency="USD",
    )
    assert len(bilateral) == 1
    assert bilateral[0].debtor_id == "carol"
    assert bilateral[0].creditor_id == "alice"
    assert bilateral[0].amount == Decimal("1.00")


def test_pairwise_bilateral_augmenting_path_rounding_stress():
    # Construct 3 creditors x 3 debtors with odd fractional remainders on BHD (3 decimals)
    expense_records = [
        {
            "payers": [
                ("c1", Decimal("0.334")),
                ("c2", Decimal("0.333")),
                ("c3", Decimal("0.334")),
            ],
            "splits": [
                ("d1", Decimal("0.111")),
                ("d2", Decimal("0.445")),
                ("d3", Decimal("0.445")),
            ],
            "total_amount": Decimal("1.001"),
        }
    ]
    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=expense_records,
        settlement_records=[],
        currency="BHD",
    )
    net = {"c1": Decimal("0"), "c2": Decimal("0"), "c3": Decimal("0"), "d1": Decimal("0"), "d2": Decimal("0"), "d3": Decimal("0")}
    for b in bilateral:
        net[b.debtor_id] -= b.amount
        net[b.creditor_id] += b.amount

    assert net["c1"] == Decimal("0.334")
    assert net["c2"] == Decimal("0.333")
    assert net["c3"] == Decimal("0.334")
    assert net["d1"] == Decimal("-0.111")
    assert net["d2"] == Decimal("-0.445")
    assert net["d3"] == Decimal("-0.445")


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


@given(
    total_minor=st.integers(min_value=10, max_value=10000),
    n_payers=st.integers(min_value=2, max_value=5),
    n_splits=st.integers(min_value=2, max_value=5),
    weights=st.lists(st.integers(min_value=1, max_value=97), min_size=10, max_size=10),
)
@settings(max_examples=50)
def test_hypothesis_multi_payer_bilateral_exact_conservation(
    total_minor: int,
    n_payers: int,
    n_splits: int,
    weights: list,
):
    """
    Verifies every arbitrary multi-payer multi-split expense conserves every minor unit
    across pairwise bilateral debts without truncation drift.
    """
    from app.core.money import from_minor_units

    def partition(total: int, count: int, w_slice: list[int]) -> list[int]:
        w_sum = sum(w_slice)
        raw = [(total * w) // w_sum for w in w_slice]
        rem = total - sum(raw)
        for idx in range(rem):
            raw[idx % count] += 1
        return [x for x in raw]

    payer_minor_shares = partition(total_minor, n_payers, weights[:n_payers])
    split_minor_shares = partition(total_minor, n_splits, weights[5 : 5 + n_splits])

    payers = [(f"u_{i}", from_minor_units(amt, "USD")) for i, amt in enumerate(payer_minor_shares) if amt > 0]
    # Overlap some users between payers and splits and keep others disjoint
    splits = [(f"u_{j + 1}", from_minor_units(amt, "USD")) for j, amt in enumerate(split_minor_shares) if amt > 0]
    total_amt = from_minor_units(total_minor, "USD")

    bilateral = DebtSimplifier.calculate_pairwise_bilateral_debts(
        expense_records=[{"payers": payers, "splits": splits, "total_amount": total_amt}],
        settlement_records=[],
        currency="USD",
    )

    expected: dict[str, Decimal] = {}
    for uid, amt in payers:
        expected[uid] = expected.get(uid, Decimal("0.00")) + amt
    for uid, amt in splits:
        expected[uid] = expected.get(uid, Decimal("0.00")) - amt

    observed: dict[str, Decimal] = {uid: Decimal("0.00") for uid in expected}
    for b in bilateral:
        assert b.amount > Decimal("0.00")
        observed[b.debtor_id] = observed.get(b.debtor_id, Decimal("0.00")) - b.amount
        observed[b.creditor_id] = observed.get(b.creditor_id, Decimal("0.00")) + b.amount

    for uid, exp_net in expected.items():
        assert observed.get(uid, Decimal("0.00")) == exp_net

