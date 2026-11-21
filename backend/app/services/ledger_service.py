"""
EvenBill Financial Ledger Service
Executes atomic expense mutations, validation invariants, remainder distribution,
bilateral balances, and debt simplification with strict financial correctness.
"""

import json
from decimal import Decimal
from typing import List, Dict, Tuple, Optional, Any
from datetime import datetime, timezone
from sqlalchemy import select, and_, or_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.core.money import MoneyEngine, quantize_currency, ItemizedEntry
from app.core.simplification import DebtSimplifier, SimplifiedDebt, BilateralDebt
from app.models.user import User
from app.models.group import Group, GroupMember
from app.models.expense import Expense, ExpensePayer, ExpenseSplit
from app.models.settlement import Settlement
from app.models.audit import FinancialAuditLog
from app.schemas.expense import ExpenseCreate, ExpenseUpdate
from app.schemas.settlement import SettlementCreate


class LedgerService:
    @staticmethod
    async def create_expense(
        db: AsyncSession,
        creator: User,
        data: ExpenseCreate
    ) -> Expense:
        # 1. Idempotency Protection: Prevent duplicate transactions on retry
        if data.idempotency_key:
            existing_stmt = (
                select(Expense)
                .where(Expense.idempotency_key == data.idempotency_key)
                .options(
                    selectinload(Expense.payers).selectinload(ExpensePayer.user),
                    selectinload(Expense.splits).selectinload(ExpenseSplit.user)
                )
            )
            res = await db.execute(existing_stmt)
            existing = res.scalar_one_or_none()
            if existing:
                return existing

        # 2. Subscription Entitlement Enforcement: Check daily expense allowance for Free tier
        from app.services.entitlement_service import EntitlementService
        await EntitlementService.check_expense_creation_allowance(db, creator, data.idempotency_key)

        currency = data.currency.upper().strip()
        quantized_total = quantize_currency(data.total_amount, currency)
        if quantized_total <= Decimal("0"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Expense total amount must be strictly positive"
            )

        # 2. Group Membership and Multi-Currency Resolution
        base_currency = currency
        exchange_rate = data.exchange_rate or Decimal("1.0")
        rate_source = data.exchange_rate_source or "DEFAULT"

        if data.group_id:
            group_stmt = select(Group).where(Group.id == data.group_id, Group.is_archived == False)
            group_res = await db.execute(group_stmt)
            group = group_res.scalar_one_or_none()
            if not group:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found or archived")

            # Verify creator is a member of the group
            member_stmt = select(GroupMember).where(
                GroupMember.group_id == data.group_id,
                GroupMember.user_id == creator.id
            )
            member_res = await db.execute(member_stmt)
            if not member_res.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not a member of this group")

            base_currency = group.base_currency
            if currency != base_currency and exchange_rate == Decimal("1.0") and not data.exchange_rate:
                # Default rate if not supplied (in production, fetched from FXService cache)
                rate_source = "SNAPSHOT_FALLBACK"

        base_currency_amount = quantize_currency(quantized_total * exchange_rate, base_currency)

        # 3. Payer Processing & Validation
        payers_to_insert: List[Tuple[str, Decimal]] = []
        if not data.payers or len(data.payers) == 0:
            payers_to_insert.append((creator.id, quantized_total))
        else:
            total_paid = Decimal("0")
            for p in data.payers:
                p_amt = quantize_currency(p.amount_paid, currency)
                if p_amt <= Decimal("0"):
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"Amount paid by user {p.user_id} must be strictly positive"
                    )
                total_paid += p_amt
                payers_to_insert.append((p.user_id, p_amt))

            if total_paid != quantized_total:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Sum of payer amounts ({total_paid}) does not match total expense amount ({quantized_total})"
                )

        # 4. Split Processing via MoneyEngine
        split_type = data.split_type.upper().strip()
        splits_to_insert: List[Tuple[str, Decimal, Optional[Decimal]]] = []

        try:
            if split_type == "EQUAL":
                participants = data.participant_ids or []
                if not participants:
                    if data.group_id:
                        gm_stmt = select(GroupMember.user_id).where(GroupMember.group_id == data.group_id)
                        gm_res = await db.execute(gm_stmt)
                        participants = [row[0] for row in gm_res.fetchall()]
                    else:
                        participants = [creator.id]

                split_results = MoneyEngine.split_equally(
                    total_amount=quantized_total,
                    currency=currency,
                    participant_ids=participants
                )
                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

            elif split_type == "EXACT":
                if not data.splits:
                    raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Exact splits list is required")
                exact_map = {s.user_id: s.owed_amount for s in data.splits}
                split_results = MoneyEngine.validate_exact_splits(
                    total_amount=quantized_total,
                    currency=currency,
                    exact_amounts=exact_map
                )
                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, None))

            elif split_type == "PERCENTAGE":
                if not data.percentages:
                    raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Percentages map is required")
                split_results = MoneyEngine.split_by_percentages(
                    total_amount=quantized_total,
                    currency=currency,
                    percentages=data.percentages
                )
                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

            elif split_type == "SHARES":
                if not data.shares:
                    raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Shares map is required")
                split_results = MoneyEngine.split_by_shares(
                    total_amount=quantized_total,
                    currency=currency,
                    shares=data.shares
                )
                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

            elif split_type == "ADJUSTMENT":
                participants = data.participant_ids or []
                if not participants:
                    if data.group_id:
                        gm_stmt = select(GroupMember.user_id).where(GroupMember.group_id == data.group_id)
                        gm_res = await db.execute(gm_stmt)
                        participants = [row[0] for row in gm_res.fetchall()]
                    else:
                        participants = [creator.id]

                adjustments = data.adjustments or {}
                split_results = MoneyEngine.split_with_adjustments(
                    total_amount=quantized_total,
                    currency=currency,
                    participant_ids=participants,
                    adjustments=adjustments
                )
                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))

            elif split_type == "ITEMIZED":
                if not data.items:
                    raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Items list is required for itemized split")

                item_entries = [
                    ItemizedEntry(
                        description=it.description,
                        amount=it.amount,
                        participant_ids=it.participant_ids
                    )
                    for it in data.items
                ]

                calculated_total, split_results = MoneyEngine.split_itemized(
                    currency=currency,
                    items=item_entries,
                    tax=data.tax or Decimal("0"),
                    tip=data.tip or Decimal("0"),
                    fee=data.fee or Decimal("0"),
                    discount=data.discount or Decimal("0")
                )

                if calculated_total != quantized_total:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"Calculated itemized total ({calculated_total}) does not match expense total ({quantized_total})"
                    )

                for sr in split_results:
                    splits_to_insert.append((sr.user_id, sr.amount, sr.share_value))
            else:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unsupported split type: {data.split_type}")

        except ValueError as e:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

        # 5. Invariant Verification
        total_owed = sum(s[1] for s in splits_to_insert)
        if total_owed != quantized_total:
            raise AssertionError(f"Split sum ({total_owed}) differs from total expense amount ({quantized_total})")

        # 6. Persist Expense Entity
        expense_date = data.expense_date or datetime.now(timezone.utc).date()
        expense = Expense(
            idempotency_key=data.idempotency_key,
            transaction_type=data.transaction_type.upper().strip(),
            original_expense_id=data.original_expense_id,
            group_id=data.group_id,
            created_by=creator.id,
            description=data.description.strip(),
            total_amount=quantized_total,
            currency=currency,
            base_currency_amount=base_currency_amount,
            exchange_rate=exchange_rate,
            exchange_rate_source=rate_source,
            exchange_rate_timestamp=datetime.now(timezone.utc),
            split_type=split_type,
            category=data.category.upper().strip(),
            expense_date=expense_date,
            notes=data.notes,
            version=1
        )
        db.add(expense)
        await db.flush()

        for uid, amt in payers_to_insert:
            db.add(ExpensePayer(expense_id=expense.id, user_id=uid, amount_paid=amt))

        for uid, amt, share in splits_to_insert:
            db.add(ExpenseSplit(expense_id=expense.id, user_id=uid, owed_amount=amt, share_quantity=share))

        # 7. Audit Log
        audit_payload = {
            "description": expense.description,
            "total_amount": str(expense.total_amount),
            "currency": expense.currency,
            "split_type": expense.split_type,
            "payers": [{"user_id": uid, "amount": str(amt)} for uid, amt in payers_to_insert],
            "splits": [{"user_id": uid, "amount": str(amt)} for uid, amt, _ in splits_to_insert]
        }
        db.add(FinancialAuditLog(
            entity_type="EXPENSE",
            entity_id=expense.id,
            action="CREATE",
            performed_by=creator.id,
            new_state=json.dumps(audit_payload)
        ))

        await db.commit()
        await db.refresh(expense)
        return expense

    @staticmethod
    async def update_expense(
        db: AsyncSession,
        user: User,
        expense_id: str,
        data: ExpenseUpdate
    ) -> Expense:
        """
        Updates an existing expense atomically.
        Replaces payers and splits, increments version, and captures audit diff.
        """
        stmt = (
            select(Expense)
            .where(Expense.id == expense_id, Expense.is_deleted == False)
            .options(
                selectinload(Expense.payers),
                selectinload(Expense.splits)
            )
        )
        res = await db.execute(stmt)
        expense = res.scalar_one_or_none()
        if not expense:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense not found or already deleted")

        # Object-level authorization check
        if expense.group_id:
            mem_stmt = select(GroupMember).where(
                GroupMember.group_id == expense.group_id,
                GroupMember.user_id == user.id
            )
            mem_res = await db.execute(mem_stmt)
            if not mem_res.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not a member of this expense's group")
        else:
            is_involved = (
                expense.created_by == user.id
                or any(p.user_id == user.id for p in expense.payers)
                or any(s.user_id == user.id for s in expense.splits)
            )
            if not is_involved:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not a participant in this personal expense")

        # Optimistic concurrency control (explicit conflict detection)
        if data.version is not None and expense.version != data.version:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Resource conflict: Server version is {expense.version}, but client version is {data.version}. Refresh and reconcile your edits."
            )

        # Capture old state for audit
        old_state = {
            "description": expense.description,
            "total_amount": str(expense.total_amount),
            "currency": expense.currency,
            "split_type": expense.split_type,
            "version": expense.version,
            "payers": [{"user_id": p.user_id, "amount": str(p.amount_paid)} for p in expense.payers],
            "splits": [{"user_id": s.user_id, "amount": str(s.owed_amount)} for s in expense.splits]
        }

        # Apply field changes
        if data.description is not None:
            expense.description = data.description.strip()
        if data.category is not None:
            expense.category = data.category.upper().strip()
        if data.notes is not None:
            expense.notes = data.notes
        if data.expense_date is not None:
            expense.expense_date = data.expense_date

        total_amount = data.total_amount if data.total_amount is not None else expense.total_amount
        currency = data.currency.upper().strip() if data.currency is not None else expense.currency
        split_type = data.split_type.upper().strip() if data.split_type is not None else expense.split_type

        quantized_total = quantize_currency(total_amount, currency)
        expense.total_amount = quantized_total
        expense.currency = currency
        expense.split_type = split_type

        # Update base currency amount using existing frozen exchange rate
        base_currency = currency
        if expense.group_id:
            grp_stmt = select(Group).where(Group.id == expense.group_id)
            grp_res = await db.execute(grp_stmt)
            grp = grp_res.scalar_one_or_none()
            if grp:
                base_currency = grp.base_currency
        expense.base_currency_amount = quantize_currency(quantized_total * expense.exchange_rate, base_currency)

        # Re-process Payers if provided, or scale single payer if total_amount changed
        if data.payers is not None:
            total_paid = Decimal("0")
            new_payers = []
            for p in data.payers:
                p_amt = quantize_currency(p.amount_paid, currency)
                total_paid += p_amt
                new_payers.append((p.user_id, p_amt))

            if total_paid != quantized_total:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Sum of payer amounts ({total_paid}) does not match total expense amount ({quantized_total})"
                )

            # Clear existing payers
            for old_p in list(expense.payers):
                await db.delete(old_p)
            await db.flush()

            for uid, amt in new_payers:
                db.add(ExpensePayer(expense_id=expense.id, user_id=uid, amount_paid=amt))

        elif data.total_amount is not None:
            existing_payers = list(expense.payers)
            if len(existing_payers) == 1:
                existing_payers[0].amount_paid = quantized_total
            else:
                current_total_paid = sum(p.amount_paid for p in existing_payers)
                if current_total_paid != quantized_total:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"Total amount changed to {quantized_total}, but payers sum is {current_total_paid}. Please provide updated payers list."
                    )

        # Re-process Splits if provided or if total_amount changed
        if (
            data.splits is not None or
            data.participant_ids is not None or
            data.percentages is not None or
            data.shares is not None or
            data.adjustments is not None or
            data.items is not None or
            data.total_amount is not None
        ):
            new_splits: List[Tuple[str, Decimal, Optional[Decimal]]] = []
            try:
                if split_type == "EQUAL":
                    participants = data.participant_ids or [s.user_id for s in expense.splits] or [user.id]
                    split_results = MoneyEngine.split_equally(quantized_total, currency, participants)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "EXACT":
                    if not data.splits:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Splits required for EXACT")
                    exact_map = {s.user_id: s.owed_amount for s in data.splits}
                    split_results = MoneyEngine.validate_exact_splits(quantized_total, currency, exact_map)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, None))
                elif split_type == "PERCENTAGE":
                    if not data.percentages:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Percentages required")
                    split_results = MoneyEngine.split_by_percentages(quantized_total, currency, data.percentages)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "SHARES":
                    if not data.shares:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Shares required")
                    split_results = MoneyEngine.split_by_shares(quantized_total, currency, data.shares)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "ADJUSTMENT":
                    participants = data.participant_ids or [s.user_id for s in expense.splits]
                    adjustments = data.adjustments or {}
                    split_results = MoneyEngine.split_with_adjustments(quantized_total, currency, participants, adjustments)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "ITEMIZED":
                    if not data.items:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Items required for itemized split")
                    item_entries = [
                        ItemizedEntry(description=it.description, amount=it.amount, participant_ids=it.participant_ids)
                        for it in data.items
                    ]
                    _, split_results = MoneyEngine.split_itemized(
                        currency=currency,
                        items=item_entries,
                        tax=data.tax or Decimal("0"),
                        tip=data.tip or Decimal("0"),
                        fee=data.fee or Decimal("0"),
                        discount=data.discount or Decimal("0")
                    )
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

            # Clear old splits
            for old_s in list(expense.splits):
                await db.delete(old_s)
            await db.flush()

            for uid, amt, share in new_splits:
                db.add(ExpenseSplit(expense_id=expense.id, user_id=uid, owed_amount=amt, share_quantity=share))

        expense.version += 1
        expense.updated_at = datetime.now(timezone.utc)

        # Audit Record
        new_state = {
            "description": expense.description,
            "total_amount": str(expense.total_amount),
            "currency": expense.currency,
            "split_type": expense.split_type,
            "version": expense.version,
        }
        db.add(FinancialAuditLog(
            entity_type="EXPENSE",
            entity_id=expense.id,
            action="UPDATE",
            performed_by=user.id,
            previous_state=json.dumps(old_state),
            new_state=json.dumps(new_state)
        ))

        await db.commit()
        await db.refresh(expense)
        return expense

    @staticmethod
    async def delete_expense(
        db: AsyncSession,
        user: User,
        expense_id: str
    ) -> bool:
        """
        Soft-deletes an expense so ledger history is preserved and balances recalculate cleanly.
        Enforces object-level authorization.
        """
        stmt = (
            select(Expense)
            .options(
                selectinload(Expense.payers),
                selectinload(Expense.splits)
            )
            .where(Expense.id == expense_id, Expense.is_deleted == False)
        )
        res = await db.execute(stmt)
        expense = res.scalar_one_or_none()
        if not expense:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense not found or already deleted")

        # Object-level authorization check
        if expense.group_id:
            membership = await db.execute(
                select(GroupMember).where(
                    GroupMember.group_id == expense.group_id,
                    GroupMember.user_id == user.id,
                    GroupMember.is_active == True
                )
            )
            if not membership.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You must be an active member of the group to delete this expense"
                )
        else:
            is_creator = expense.created_by == user.id
            is_payer = any(p.user_id == user.id for p in expense.payers)
            is_participant = any(s.user_id == user.id for s in expense.splits)
            if not (is_creator or is_payer or is_participant):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Not authorized to delete this personal expense"
                )

        expense.is_deleted = True
        expense.version += 1
        expense.updated_at = datetime.now(timezone.utc)

        db.add(FinancialAuditLog(
            entity_type="EXPENSE",
            entity_id=expense.id,
            action="DELETE",
            performed_by=user.id,
            previous_state=json.dumps({"is_deleted": False, "version": expense.version - 1}),
            new_state=json.dumps({"is_deleted": True, "version": expense.version})
        ))

        await db.commit()
        return True

    @staticmethod
    async def record_settlement(
        db: AsyncSession,
        creator: User,
        data: SettlementCreate
    ) -> Settlement:
        # Idempotency Protection
        if data.idempotency_key:
            existing_stmt = select(Settlement).where(Settlement.idempotency_key == data.idempotency_key)
            existing_res = await db.execute(existing_stmt)
            existing = existing_res.scalar_one_or_none()
            if existing:
                return existing

        payer_id = data.payer_id or creator.id
        if creator.id not in (payer_id, data.recipient_id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Authenticated user must be either the payer or recipient"
            )

        if payer_id == data.recipient_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Payer and recipient cannot be the same user"
            )

        currency = data.currency.upper().strip()
        quantized_amount = quantize_currency(data.amount, currency)
        if quantized_amount <= Decimal("0"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Settlement amount must be strictly positive"
            )

        # Verify both users exist
        for uid in (payer_id, data.recipient_id):
            u_res = await db.execute(select(User.id).where(User.id == uid))
            if not u_res.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"User {uid} not found"
                )

        # Verify group membership if group_id is specified
        if data.group_id:
            for uid in (payer_id, data.recipient_id):
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
            idempotency_key=data.idempotency_key,
            group_id=data.group_id,
            payer_id=payer_id,
            recipient_id=data.recipient_id,
            amount=quantized_amount,
            currency=currency,
            payment_method=data.payment_method.upper().strip(),
            transaction_reference=data.transaction_reference,
            notes=data.notes,
            created_by=creator.id
        )
        db.add(settlement)
        await db.flush()

        audit_payload = {
            "payer_id": payer_id,
            "recipient_id": data.recipient_id,
            "amount": str(quantized_amount),
            "currency": currency,
            "payment_method": settlement.payment_method,
            "group_id": data.group_id
        }
        db.add(FinancialAuditLog(
            entity_type="SETTLEMENT",
            entity_id=settlement.id,
            action="CREATE",
            performed_by=creator.id,
            new_state=json.dumps(audit_payload)
        ))

        await db.commit()
        await db.refresh(settlement)
        return settlement

    @staticmethod
    async def get_group_balances(
        db: AsyncSession,
        group_id: str
    ) -> Tuple[Dict[str, Decimal], List[SimplifiedDebt], List[BilateralDebt], str]:
        group_stmt = select(Group).where(Group.id == group_id).options(selectinload(Group.members))
        group_res = await db.execute(group_stmt)
        group = group_res.scalar_one_or_none()
        if not group:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

        currency = group.base_currency

        # Active non-deleted expenses
        exp_stmt = (
            select(Expense)
            .where(Expense.group_id == group_id, Expense.is_deleted == False)
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        expenses = exp_res.scalars().all()

        payers_list: List[Tuple[str, Decimal]] = []
        splits_list: List[Tuple[str, Decimal]] = []
        expense_records: List[Dict] = []

        for exp in expenses:
            # Handle currency conversion to base currency
            rate = exp.exchange_rate if exp.currency != currency else Decimal("1.0")

            exp_payers = [(p.user_id, quantize_currency(p.amount_paid * rate, currency)) for p in exp.payers]
            exp_splits = [(s.user_id, quantize_currency(s.owed_amount * rate, currency)) for s in exp.splits]

            payers_list.extend(exp_payers)
            splits_list.extend(exp_splits)
            expense_records.append({
                "payers": exp_payers,
                "splits": exp_splits,
                "total_amount": quantize_currency(exp.total_amount * rate, currency)
            })

        # Active non-deleted settlements
        settle_stmt = select(Settlement).where(
            Settlement.group_id == group_id,
            Settlement.is_deleted == False
        )
        settle_res = await db.execute(settle_stmt)
        settlements = settle_res.scalars().all()

        settle_list: List[Tuple[str, str, Decimal]] = [
            (s.payer_id, s.recipient_id, s.amount) for s in settlements
        ]
        settlement_records = [
            {"payer_id": s.payer_id, "recipient_id": s.recipient_id, "amount": s.amount}
            for s in settlements
        ]

        # Net balance calculation
        net_balances = DebtSimplifier.calculate_group_net_balances(
            payers=payers_list,
            splits=splits_list,
            settlements=settle_list,
            currency=currency
        )

        # Ensure all group members have an explicit balance entry (0.0000 if settled)
        if group and group.members:
            for m in group.members:
                if m.user_id not in net_balances:
                    net_balances[m.user_id] = quantize_currency(Decimal("0"), currency)

        # Bilateral direct debts (without simplification)
        bilateral_debts = DebtSimplifier.calculate_pairwise_bilateral_debts(
            expense_records=expense_records,
            settlement_records=settlement_records,
            currency=currency
        )

        # Simplified debts
        simplified_debts: List[SimplifiedDebt] = []
        if group.simplify_debts:
            simplified_debts = DebtSimplifier.simplify_net_balances(
                net_balances=net_balances,
                currency=currency
            )

        return net_balances, simplified_debts, bilateral_debts, currency

    @staticmethod
    async def get_1on1_friend_balances(
        db: AsyncSession,
        user_id_1: str,
        user_id_2: str,
        currency: str = "USD"
    ) -> Decimal:
        """
        Calculates the exact net 1-on-1 bilateral balance between two users.
        Positive = user_id_1 is owed money by user_id_2.
        Negative = user_id_1 owes money to user_id_2.
        Never double-counts the payer's own share.
        """
        # Find all direct expenses (group_id is None) involving both users
        exp_stmt = (
            select(Expense)
            .where(
                Expense.group_id.is_(None),
                Expense.is_deleted == False,
                Expense.currency == currency.upper()
            )
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        expenses = exp_res.scalars().all()

        shared_expenses = []
        for exp in expenses:
            participant_uids = {p.user_id for p in exp.payers} | {s.user_id for s in exp.splits}
            if user_id_1 in participant_uids and user_id_2 in participant_uids:
                shared_expenses.append({
                    "payers": [(p.user_id, p.amount_paid) for p in exp.payers],
                    "splits": [(s.user_id, s.owed_amount) for s in exp.splits],
                    "total_amount": exp.total_amount
                })

        # Settlements between user_1 and user_2
        settle_stmt = select(Settlement).where(
            Settlement.group_id.is_(None),
            Settlement.is_deleted == False,
            Settlement.currency == currency.upper(),
            or_(
                and_(Settlement.payer_id == user_id_1, Settlement.recipient_id == user_id_2),
                and_(Settlement.payer_id == user_id_2, Settlement.recipient_id == user_id_1),
            )
        )
        settle_res = await db.execute(settle_stmt)
        settlements = settle_res.scalars().all()

        settlement_records = [
            {"payer_id": s.payer_id, "recipient_id": s.recipient_id, "amount": s.amount}
            for s in settlements
        ]

        bilateral_list = DebtSimplifier.calculate_pairwise_bilateral_debts(
            expense_records=shared_expenses,
            settlement_records=settlement_records,
            currency=currency.upper()
        )

        for b in bilateral_list:
            if b.debtor_id == user_id_2 and b.creditor_id == user_id_1:
                return b.amount
            elif b.debtor_id == user_id_1 and b.creditor_id == user_id_2:
                return -b.amount

        return Decimal("0")
