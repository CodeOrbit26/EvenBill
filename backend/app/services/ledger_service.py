"""
EvenBill Financial Ledger Service
Executes atomic expense mutations, validation invariants, remainder distribution, and balance calculation.
"""

import json
from decimal import Decimal
from typing import List, Dict, Tuple, Optional
from datetime import datetime, timezone
from sqlalchemy import select, and_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.core.money import MoneyEngine, quantize_currency
from app.core.simplification import DebtSimplifier, SimplifiedDebt
from app.models.user import User
from app.models.group import Group, GroupMember
from app.models.expense import Expense, ExpensePayer, ExpenseSplit
from app.models.settlement import Settlement
from app.models.audit import FinancialAuditLog
from app.schemas.expense import ExpenseCreate, PayerItem, SplitItem
from app.schemas.settlement import SettlementCreate


class LedgerService:
    @staticmethod
    async def create_expense(
        db: AsyncSession,
        creator: User,
        data: ExpenseCreate
    ) -> Expense:
        quantized_total = quantize_currency(data.total_amount, data.currency)

        # 1. Group membership validation
        if data.group_id:
            group_stmt = select(Group).where(Group.id == data.group_id, Group.is_archived == False)
            group_res = await db.execute(group_stmt)
            group = group_res.scalar_one_or_none()
            if not group:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found or archived")

            # Verify creator is a member
            member_stmt = select(GroupMember).where(
                GroupMember.group_id == data.group_id,
                GroupMember.user_id == creator.id
            )
            member_res = await db.execute(member_stmt)
            if not member_res.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a member of this group")

        # 2. Payer Processing & Validation
        payers_to_insert: List[Tuple[str, Decimal]] = []
        if not data.payers or len(data.payers) == 0:
            # Single payer default: creator pays 100%
            payers_to_insert.append((creator.id, quantized_total))
        else:
            total_paid = Decimal("0")
            for p in data.payers:
                p_amt = quantize_currency(p.amount_paid, data.currency)
                total_paid += p_amt
                payers_to_insert.append((p.user_id, p_amt))

            if total_paid != quantized_total:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Sum of payer amounts ({total_paid}) does not match total expense amount ({quantized_total})"
                )

        # 3. Split Processing via MoneyEngine
        splits_to_insert: List[Tuple[str, Decimal, Optional[Decimal]]] = []  # (user_id, owed_amount, share_quantity)

        split_type = data.split_type.upper()
        if split_type == "EQUAL":
            participants = data.participant_ids or []
            if not participants:
                if data.group_id:
                    # Default to all group members
                    gm_stmt = select(GroupMember.user_id).where(GroupMember.group_id == data.group_id)
                    gm_res = await db.execute(gm_stmt)
                    participants = [row[0] for row in gm_res.fetchall()]
                else:
                    participants = [creator.id]

            split_results = MoneyEngine.split_equally(
                total_amount=quantized_total,
                currency=data.currency,
                participant_ids=participants
            )
            for sr in split_results:
                splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

        elif split_type == "EXACT":
            if not data.splits:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Exact splits list is required")
            exact_map = {s.user_id: s.owed_amount for s in data.splits}
            try:
                split_results = MoneyEngine.validate_exact_splits(
                    total_amount=quantized_total,
                    currency=data.currency,
                    exact_amounts=exact_map
                )
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

            for sr in split_results:
                splits_to_insert.append((sr.user_id, sr.amount, None))

        elif split_type == "PERCENTAGE":
            if not data.percentages:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Percentages map is required")
            try:
                split_results = MoneyEngine.split_by_percentages(
                    total_amount=quantized_total,
                    currency=data.currency,
                    percentages=data.percentages
                )
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

            for sr in split_results:
                splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

        elif split_type == "SHARES":
            if not data.shares:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Shares map is required")
            try:
                split_results = MoneyEngine.split_by_shares(
                    total_amount=quantized_total,
                    currency=data.currency,
                    shares=data.shares
                )
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

            for sr in split_results:
                splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))
        else:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unsupported split type: {data.split_type}")

        # 4. Invariant Verification: Total Owed == Total Paid == Total Amount
        total_owed = sum(s[1] for s in splits_to_insert)
        if total_owed != quantized_total:
            raise AssertionError(f"Split sum {total_owed} differs from total amount {quantized_total}")

        # 5. Persist Expense Entity
        expense_date = data.expense_date or datetime.now(timezone.utc).date()
        expense = Expense(
            group_id=data.group_id,
            created_by=creator.id,
            description=data.description.strip(),
            total_amount=quantized_total,
            currency=data.currency.upper(),
            base_currency_amount=quantized_total,  # Default 1:1 if same base
            exchange_rate=Decimal("1.0"),
            split_type=split_type,
            category=data.category.upper(),
            expense_date=expense_date,
            notes=data.notes,
            version=1
        )
        db.add(expense)
        await db.flush()

        # Insert Payers
        for uid, amt in payers_to_insert:
            payer = ExpensePayer(
                expense_id=expense.id,
                user_id=uid,
                amount_paid=amt
            )
            db.add(payer)

        # Insert Splits
        for uid, amt, share in splits_to_insert:
            split = ExpenseSplit(
                expense_id=expense.id,
                user_id=uid,
                owed_amount=amt,
                share_quantity=share
            )
            db.add(split)

        # 6. Immutable Financial Audit Log
        audit_payload = {
            "description": expense.description,
            "total_amount": str(expense.total_amount),
            "currency": expense.currency,
            "payers": [{"user_id": uid, "amount": str(amt)} for uid, amt in payers_to_insert],
            "splits": [{"user_id": uid, "amount": str(amt)} for uid, amt, _ in splits_to_insert]
        }
        audit_log = FinancialAuditLog(
            entity_type="EXPENSE",
            entity_id=expense.id,
            action="CREATE",
            performed_by=creator.id,
            new_state=json.dumps(audit_payload)
        )
        db.add(audit_log)

        await db.commit()
        await db.refresh(expense)
        return expense

    @staticmethod
    async def record_settlement(
        db: AsyncSession,
        creator: User,
        data: SettlementCreate
    ) -> Settlement:
        if creator.id == data.recipient_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Payer and recipient cannot be the same user"
            )

        quantized_amount = quantize_currency(data.amount, data.currency)
        if quantized_amount <= Decimal("0"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Settlement amount must be strictly positive"
            )

        # Verify group membership if group_id is specified
        if data.group_id:
            for uid in (creator.id, data.recipient_id):
                gm_stmt = select(GroupMember).where(
                    GroupMember.group_id == data.group_id,
                    GroupMember.user_id == uid
                )
                res = await db.execute(gm_stmt)
                if not res.scalar_one_or_none():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"User {uid} is not a member of group {data.group_id}"
                    )

        settlement = Settlement(
            group_id=data.group_id,
            payer_id=creator.id,
            recipient_id=data.recipient_id,
            amount=quantized_amount,
            currency=data.currency.upper(),
            payment_method=data.payment_method.upper(),
            transaction_reference=data.transaction_reference,
            notes=data.notes,
            created_by=creator.id
        )
        db.add(settlement)
        await db.flush()

        audit_payload = {
            "payer_id": creator.id,
            "recipient_id": data.recipient_id,
            "amount": str(quantized_amount),
            "currency": data.currency.upper(),
            "payment_method": data.payment_method.upper(),
            "group_id": data.group_id
        }
        audit_log = FinancialAuditLog(
            entity_type="SETTLEMENT",
            entity_id=settlement.id,
            action="CREATE",
            performed_by=creator.id,
            new_state=json.dumps(audit_payload)
        )
        db.add(audit_log)

        await db.commit()
        await db.refresh(settlement)
        return settlement

    @staticmethod
    async def get_group_balances(
        db: AsyncSession,
        group_id: str
    ) -> Tuple[Dict[str, Decimal], List[SimplifiedDebt], str]:
        # Fetch group to check base currency and simplify_debts setting
        group_stmt = select(Group).where(Group.id == group_id)
        group_res = await db.execute(group_stmt)
        group = group_res.scalar_one_or_none()
        if not group:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

        currency = group.base_currency

        # Fetch all active expenses for this group
        exp_stmt = (
            select(Expense)
            .where(Expense.group_id == group_id, Expense.is_deleted == False)
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        expenses = exp_res.scalars().all()

        payers_list: List[Tuple[str, Decimal]] = []
        splits_list: List[Tuple[str, Decimal]] = []

        for exp in expenses:
            for p in exp.payers:
                payers_list.append((p.user_id, p.amount_paid))
            for s in exp.splits:
                splits_list.append((s.user_id, s.owed_amount))

        # Fetch all active settlements for this group
        settle_stmt = select(Settlement).where(
            Settlement.group_id == group_id,
            Settlement.is_deleted == False
        )
        settle_res = await db.execute(settle_stmt)
        settlements = settle_res.scalars().all()

        settle_list: List[Tuple[str, str, Decimal]] = [
            (s.payer_id, s.recipient_id, s.amount) for s in settlements
        ]

        net_balances = DebtSimplifier.calculate_group_net_balances(
            payers=payers_list,
            splits=splits_list,
            settlements=settle_list,
            currency=currency
        )

        simplified_debts: List[SimplifiedDebt] = []
        if group.simplify_debts:
            simplified_debts = DebtSimplifier.simplify_net_balances(
                net_balances=net_balances,
                currency=currency
            )

        return net_balances, simplified_debts, currency
