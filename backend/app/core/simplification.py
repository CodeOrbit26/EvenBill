"""
EvenBill Debt Simplification & Minimal Cash Flow Engine
Reduces complex O(N^2) pairwise debts into an optimal O(N) settlement graph using bipartite netting.
Guarantees deterministic matching and absolute conservation of net balance invariants.
"""

from collections import deque
from decimal import Decimal
from typing import Dict, List, Optional, Tuple, Set
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
    def _allocate_expense_bilateral_flows(
        payers: List[Tuple[str, Decimal]],
        splits: List[Tuple[str, Decimal]],
        currency: str,
    ) -> List[Tuple[str, str, int]]:
        """
        Allocates bilateral (debtor_uid, creditor_uid, minor_amt) edges for a single
        expense while preserving every minor currency unit of every participant's net
        balance (paid - owed). Single-payer and single-debtor cases are direct; multi-payer
        multi-debtor expenses use proportional floor + exact 0-1 residual flow rounding.
        """
        paid_minor: Dict[str, int] = {}
        split_minor: Dict[str, int] = {}
        for p_uid, p_amt in payers:
            m = to_minor_units(p_amt, currency)
            if m > 0:
                paid_minor[p_uid] = paid_minor.get(p_uid, 0) + m
        for s_uid, s_amt in splits:
            m = to_minor_units(s_amt, currency)
            if m > 0:
                split_minor[s_uid] = split_minor.get(s_uid, 0) + m

        total_paid = sum(paid_minor.values())
        total_split = sum(split_minor.values())
        if total_paid != total_split:
            raise ValueError(
                f"Expense conservation invariant violated: payers {total_paid} != splits {total_split} minor units"
            )
        if total_paid == 0:
            return []

        creditors: List[Tuple[str, int]] = []
        debtors: List[Tuple[str, int]] = []
        for uid in sorted(set(paid_minor.keys()) | set(split_minor.keys())):
            net = paid_minor.get(uid, 0) - split_minor.get(uid, 0)
            if net > 0:
                creditors.append((uid, net))
            elif net < 0:
                debtors.append((uid, -net))

        if not creditors or not debtors:
            return []
        if len(creditors) == 1:
            cred_uid, _ = creditors[0]
            return [(d_uid, cred_uid, d_amt) for d_uid, d_amt in debtors]
        if len(debtors) == 1:
            deb_uid, _ = debtors[0]
            return [(deb_uid, c_uid, c_amt) for c_uid, c_amt in creditors]

        pool = sum(c_amt for _, c_amt in creditors)
        nd = len(debtors)
        nc = len(creditors)

        alloc = [[0] * nc for _ in range(nd)]
        rem_num = [[0] * nc for _ in range(nd)]
        row_rem = [debtors[i][1] for i in range(nd)]
        col_rem = [creditors[j][1] for j in range(nc)]

        for i, (_, d_amt) in enumerate(debtors):
            for j, (_, c_amt) in enumerate(creditors):
                prod = d_amt * c_amt
                base = prod // pool
                alloc[i][j] = base
                rem_num[i][j] = prod % pool
                row_rem[i] -= base
                col_rem[j] -= base

        delta = [[0] * nc for _ in range(nd)]
        fractional_cells = [
            (rem_num[i][j], i, j)
            for i in range(nd)
            for j in range(nc)
            if rem_num[i][j] > 0
        ]
        fractional_cells.sort(key=lambda item: (-item[0], item[1], item[2]))
        for _, i, j in fractional_cells:
            if row_rem[i] > 0 and col_rem[j] > 0:
                delta[i][j] = 1
                row_rem[i] -= 1
                col_rem[j] -= 1

        while any(r > 0 for r in row_rem):
            q: deque = deque()
            parent_cred: List[Optional[int]] = [None] * nc
            parent_deb: List[Optional[int]] = [None] * nd
            vis_deb = [False] * nd
            vis_cred = [False] * nc
            for i in range(nd):
                if row_rem[i] > 0:
                    q.append(("D", i))
                    vis_deb[i] = True

            found_cred: Optional[int] = None
            while q and found_cred is None:
                kind, idx = q.popleft()
                if kind == "D":
                    cand_j = sorted(
                        (j for j in range(nc) if not vis_cred[j] and delta[idx][j] == 0 and rem_num[idx][j] > 0),
                        key=lambda j: (-rem_num[idx][j], j),
                    )
                    for j in cand_j:
                        vis_cred[j] = True
                        parent_cred[j] = idx
                        if col_rem[j] > 0:
                            found_cred = j
                            break
                        q.append(("C", j))
                else:
                    cand_i = sorted(
                        (i for i in range(nd) if not vis_deb[i] and delta[i][idx] == 1),
                        key=lambda i: (rem_num[i][idx], i),
                    )
                    for i in cand_i:
                        vis_deb[i] = True
                        parent_deb[i] = idx
                        q.append(("D", i))

            if found_cred is None:
                raise AssertionError("Failed to find augmenting rounding path for multi-payer bilateral allocation")

            curr_c = found_cred
            col_rem[curr_c] -= 1
            while True:
                curr_d = parent_cred[curr_c]
                assert curr_d is not None
                delta[curr_d][curr_c] = 1
                prev_c = parent_deb[curr_d]
                if prev_c is None:
                    row_rem[curr_d] -= 1
                    break
                delta[curr_d][prev_c] = 0
                curr_c = prev_c

        flows: List[Tuple[str, str, int]] = []
        for i, (d_uid, d_amt) in enumerate(debtors):
            row_sum = 0
            for j, (c_uid, _) in enumerate(creditors):
                val = alloc[i][j] + delta[i][j]
                row_sum += val
                if val > 0:
                    flows.append((d_uid, c_uid, val))
            if row_sum != d_amt:
                raise AssertionError(f"Debtor {d_uid} bilateral allocation {row_sum} != {d_amt}")

        for j, (c_uid, c_amt) in enumerate(creditors):
            col_sum = sum(alloc[i][j] + delta[i][j] for i in range(nd))
            if col_sum != c_amt:
                raise AssertionError(f"Creditor {c_uid} bilateral allocation {col_sum} != {c_amt}")

        return flows

    @staticmethod
    def calculate_pairwise_bilateral_debts(
        expense_records: List[Dict],
        settlement_records: List[Dict],
        currency: str
    ) -> List[BilateralDebt]:
        """
        Calculates exact bilateral pairwise debts without simplification.
        For each pair (A, B), determines whether A owes B or B owes A and the exact net debt.
        Never double-counts the payer's own share and preserves every minor unit across multi-payer expenses.

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
        pairwise_raw: Dict[Tuple[str, str], int] = {}  # (from_user, to_user) in minor units

        def add_raw_debt(debtor: str, creditor: str, minor_amt: int):
            if debtor == creditor or minor_amt <= 0:
                return
            key = (debtor, creditor)
            pairwise_raw[key] = pairwise_raw.get(key, 0) + minor_amt

        for exp in expense_records:
            total_minor = to_minor_units(exp["total_amount"], currency)
            if total_minor == 0:
                continue

            for d_uid, c_uid, flow_minor in DebtSimplifier._allocate_expense_bilateral_flows(
                payers=exp["payers"],
                splits=exp["splits"],
                currency=currency,
            ):
                add_raw_debt(debtor=d_uid, creditor=c_uid, minor_amt=flow_minor)

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
            + (Settlements paid out as payer)
            - (Settlements received as recipient)
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
