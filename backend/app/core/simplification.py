"""
EvenBill Debt Simplification & Minimal Cash Flow Engine
Reduces complex O(N^2) pairwise debts into an optimal O(N) settlement graph using bipartite netting.
"""

from decimal import Decimal
from typing import Dict, List, Tuple
from dataclasses import dataclass
from app.core.money import quantize_currency, to_minor_units, from_minor_units


@dataclass(frozen=True)
class SimplifiedDebt:
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
        Takes a mapping of user_id -> net_balance (positive means user is owed money, negative means user owes money).
        Returns the minimal list of debt transfer edges.
        """
        # Convert to integer minor units to eliminate floating-point drift
        minor_balances: Dict[str, int] = {}
        for user_id, amount in net_balances.items():
            minor = to_minor_units(amount, currency)
            if minor != 0:
                minor_balances[user_id] = minor

        # Check conservation of value: sum of all net balances must be zero
        net_sum = sum(minor_balances.values())
        if net_sum != 0:
            raise ValueError(
                f"Net balance sum invariant violated: total net balance is {net_sum} minor units (must be 0)"
            )

        # Separate into creditors and debtors
        # Priority queues or sorted lists of [amount, user_id]
        creditors: List[Tuple[int, str]] = []  # positive balances
        debtors: List[Tuple[int, str]] = []    # negative balances (stored as positive debt)

        for user_id, balance in minor_balances.items():
            if balance > 0:
                creditors.append((balance, user_id))
            elif balance < 0:
                debtors.append((-balance, user_id))

        simplified_debts: List[SimplifiedDebt] = []

        # Sort so we match largest debtor with largest creditor
        creditors.sort(key=lambda x: x[0], reverse=True)
        debtors.sort(key=lambda x: x[0], reverse=True)

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

            # Update remaining amounts
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

        return simplified_debts

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
            + (Settlements received)
            - (Settlements paid)
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

        # Quantize all balances
        return {
            uid: quantize_currency(amt, currency)
            for uid, amt in balances.items()
        }
