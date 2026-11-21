"""
EvenBill Debt Simplification & Minimal Cash Flow Engine
Reduces complex O(N^2) pairwise debts into an optimal O(N) settlement graph using bipartite netting.
Guarantees deterministic matching and absolute conservation of net balance invariants.
"""

from decimal import Decimal
from typing import Dict, List, Tuple, Set
from dataclasses import dataclass
from app.core.money import quantize_currency, to_minor_units, from_minor_units


@dataclass(frozen=True)
class SimplifiedDebt:
    debtor_id: str
    creditor_id: str
    amount: Decimal
    currency: str


@dataclass(frozen=True)
class BilateralDebt:
    debtor_id: str
    creditor_id: str
    amount: Decimal
    currency: str


class DebtSimplifier:
    """
    Minimizes transaction transfers while strictly preserving each participant's net balance.
    """

    @staticmethod
    def simplify_net_balances(
        net_balances: Dict[str, Decimal],
        currency: str
    ) -> List[SimplifiedDebt]:
        """
        Takes a mapping of user_id -> net_balance.
        Positive = user is owed money (creditor).
        Negative = user owes money (debtor).
        Returns the minimal list of debt transfer edges (at most N - 1 edges).
        Deterministic tie-breaking uses sorted user IDs.
        """
        minor_balances: Dict[str, int] = {}
        for user_id, amount in net_balances.items():
            minor = to_minor_units(amount, currency)
            if minor != 0:
                minor_balances[user_id] = minor

        # Conservation Invariant: sum(net_balances) == 0
        net_sum = sum(minor_balances.values())
        if net_sum != 0:
            raise ValueError(
                f"Net balance sum invariant violated: total net balance is {net_sum} minor units (must be 0)"
            )

        creditors: List[Tuple[int, str]] = []  # (amount, user_id)
        debtors: List[Tuple[int, str]] = []    # (amount, user_id)

        for user_id, balance in minor_balances.items():
            if balance > 0:
                creditors.append((balance, user_id))
            elif balance < 0:
                debtors.append((-balance, user_id))

        # Deterministic sorting: largest amount first, tie-break by user_id alphabetically
        creditors.sort(key=lambda x: (-x[0], x[1]))
        debtors.sort(key=lambda x: (-x[0], x[1]))

        simplified_debts: List[SimplifiedDebt] = []

        c_idx = 0
        d_idx = 0

        while c_idx < len(creditors) and d_idx < len(debtors):
            cred_amt, cred_id = creditors[c_idx]
            debt_amt, debt_id = debtors[d_idx]

            transfer_amt = min(cred_amt, debt_amt)

            simplified_debts.append(
                SimplifiedDebt(
                    debtor_id=debt_id,
                    creditor_id=cred_id,
                    amount=from_minor_units(transfer_amt, currency),
                    currency=currency
                )
            )

            remaining_cred = cred_amt - transfer_amt
            remaining_debt = debt_amt - transfer_amt

            if remaining_cred == 0:
                c_idx += 1
            else:
                creditors[c_idx] = (remaining_cred, cred_id)

            if remaining_debt == 0:
                d_idx += 1
            else:
                debtors[d_idx] = (remaining_debt, debt_id)

        # Invariant Verification: resulting effective balances must equal original net balances
        effective_minor: Dict[str, int] = {u: 0 for u in minor_balances}
        for d in simplified_debts:
            transfer_minor = to_minor_units(d.amount, currency)
            effective_minor[d.debtor_id] -= transfer_minor
            effective_minor[d.creditor_id] += transfer_minor

        for u, original_m in minor_balances.items():
            if effective_minor[u] != original_m:
                raise AssertionError(
                    f"Simplification invariant violated for user {u}: "
                    f"effective {effective_minor[u]} != original {original_m}"
                )

        return simplified_debts

    @staticmethod
    def calculate_pairwise_bilateral_debts(
        expense_records: List[Dict],
        settlement_records: List[Dict],
        currency: str
    ) -> List[BilateralDebt]:
        """
        Calculates exact bilateral pairwise debts without simplification.
        For each pair (A, B), determines whether A owes B or B owes A and the exact net debt.
        Never double-counts the payer's own share.
        
        expense_records format:
        [
          {
            "payers": [(user_id, amount_paid), ...],
            "splits": [(user_id, owed_amount), ...],
            "total_amount": Decimal
          },
          ...
        ]
        """
        # Pairwise raw balance: pairwise[debtor][creditor] = amount
        # Net bilateral matrix: net_pairwise[(u1, u2)] where u1 < u2
        pairwise_raw: Dict[Tuple[str, str], int] = {}  # (from_user, to_user) in minor units

        def add_raw_debt(debtor: str, creditor: str, minor_amt: int):
            if debtor == creditor or minor_amt <= 0:
                return
            key = (debtor, creditor)
            pairwise_raw[key] = pairwise_raw.get(key, 0) + minor_amt

        for exp in expense_records:
            payers = exp["payers"]
            splits = exp["splits"]
            total_amt = exp["total_amount"]
            total_minor = to_minor_units(total_amt, currency)

            if total_minor == 0:
                continue

            # Each payer funded a fraction of each participant's split
            # Fraction funded by payer p: amount_paid_p / total_amt
            for p_uid, p_amt in payers:
                p_minor = to_minor_units(p_amt, currency)
                if p_minor <= 0:
                    continue

                for s_uid, s_amt in splits:
                    if s_uid == p_uid:
                        # Payer paying their own share: NEVER creates a debt!
                        continue
                    s_minor = to_minor_units(s_amt, currency)
                    if s_minor <= 0:
                        continue

                    # Portion of s_uid's split funded by p_uid
                    debt_portion = (s_minor * p_minor) // total_minor
                    add_raw_debt(debtor=s_uid, creditor=p_uid, minor_amt=debt_portion)

        # Apply settlements
        for s in settlement_records:
            payer_id = s["payer_id"]
            recipient_id = s["recipient_id"]
            amt_minor = to_minor_units(s["amount"], currency)
            # Payer paying recipient reduces recipient's claim on payer (or creates debt from recipient to payer)
            # Equivalent to payer becoming creditor to recipient for this amount
            add_raw_debt(debtor=recipient_id, creditor=payer_id, minor_amt=amt_minor)

        # Net out bilateral pairs (A owes B vs B owes A)
        all_pairs: Set[Tuple[str, str]] = set()
        for (u1, u2) in pairwise_raw:
            sorted_pair = (min(u1, u2), max(u1, u2))
            all_pairs.add(sorted_pair)

        bilateral_results: List[BilateralDebt] = []

        for u1, u2 in sorted(all_pairs):
            u1_to_u2 = pairwise_raw.get((u1, u2), 0)
            u2_to_u1 = pairwise_raw.get((u2, u1), 0)
            net_minor = u1_to_u2 - u2_to_u1

            if net_minor > 0:
                # u1 owes u2
                bilateral_results.append(
                    BilateralDebt(
                        debtor_id=u1,
                        creditor_id=u2,
                        amount=from_minor_units(net_minor, currency),
                        currency=currency
                    )
                )
            elif net_minor < 0:
                # u2 owes u1
                bilateral_results.append(
                    BilateralDebt(
                        debtor_id=u2,
                        creditor_id=u1,
                        amount=from_minor_units(-net_minor, currency),
                        currency=currency
                    )
                )

        return bilateral_results

    @staticmethod
    def calculate_group_net_balances(
        payers: List[Tuple[str, Decimal]],
        splits: List[Tuple[str, Decimal]],
        settlements: List[Tuple[str, str, Decimal]],
        currency: str
    ) -> Dict[str, Decimal]:
        """
        Calculates the net balance for each user in a group:
        Net = (Sum of amounts paid for expenses)
            - (Sum of amounts owed in expense splits)
            + (Settlements received as recipient)
            - (Settlements paid as payer)
        """
        balances: Dict[str, Decimal] = {}

        def add(uid: str, amt: Decimal):
            balances[uid] = balances.get(uid, Decimal("0")) + amt

        for uid, amt in payers:
            add(uid, amt)

        for uid, amt in splits:
            add(uid, -amt)

        for payer_id, recipient_id, amt in settlements:
            add(payer_id, amt)
            add(recipient_id, -amt)

        return {
            uid: quantize_currency(amt, currency)
            for uid, amt in sorted(balances.items(), key=lambda x: x[0])
        }
