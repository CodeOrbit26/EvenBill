"""
EvenBill Financial Ledger Service
Executes atomic expense mutations, validation invariants, remainder distribution,
bilateral balances, and debt simplification with strict financial correctness.
"""

import json
from decimal import Decimal
from typing import List, Dict, Tuple, Optional, Any, Set
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
from app.services.fx_service import FXService, UnsupportedCurrencyPairError


class LedgerService:
    @staticmethod
    def _get_verified_rate(from_currency: str, to_currency: str) -> Decimal:
        """Resolves a verified conversion rate or raises HTTP 422 on unsupported pairs."""
        src = from_currency.upper().strip()
        dst = to_currency.upper().strip()
        if src == dst:
            return Decimal("1.0")
        try:
            rate_info = FXService.get_verified_rate(src, dst)
        except UnsupportedCurrencyPairError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=str(exc),
            )
        assert rate_info.rate is not None
        return rate_info.rate

    @staticmethod
    def _convert_amount(amount: Decimal, from_currency: str, to_currency: str) -> Decimal:
        """Converts [amount] into [to_currency] using verified FX rates and target quantization."""
        src = from_currency.upper().strip()
        dst = to_currency.upper().strip()
        if src == dst:
            return quantize_currency(amount, dst)
        try:
            return FXService.convert(amount, src, dst).converted_amount
        except UnsupportedCurrencyPairError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=str(exc),
            )

    @staticmethod
    def _convert_allocations_preserving_total(
        entries: List[Tuple[str, Decimal]],
        rate: Decimal,
        target_total: Decimal,
        target_currency: str,
    ) -> List[Tuple[str, Decimal]]:
        """Converts per-user amounts by [rate] while preserving exact sum == [target_total]."""
        converted: List[Tuple[str, Decimal]] = [
            (uid, quantize_currency(amt * rate, target_currency)) for uid, amt in entries
        ]
        if not converted:
            return converted
        diff = target_total - sum(amt for _, amt in converted)
        if diff != Decimal("0"):
            idx = max(range(len(converted)), key=lambda i: abs(converted[i][1]))
            uid, amt = converted[idx]
            converted[idx] = (uid, quantize_currency(amt + diff, target_currency))
        return converted

    @staticmethod
    async def _validate_referenced_users(
        db: AsyncSession,
        user_ids: Set[str],
        group_id: Optional[str] = None,
    ) -> None:
        """Ensures every payer/split UUID maps to an existing profile (and group member when scoped)."""
        if not user_ids:
            return
        uid_list = list(user_ids)
        u_res = await db.execute(select(User.id).where(User.id.in_(uid_list)))
        existing_uids = {row[0] for row in u_res.fetchall()}
        missing = sorted(user_ids - existing_uids)
        if missing:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Referenced user(s) not found: {', '.join(missing)}"
            )

        if group_id:
            gm_res = await db.execute(
                select(GroupMember.user_id).where(
                    GroupMember.group_id == group_id,
                    GroupMember.user_id.in_(uid_list),
                    GroupMember.is_active == True,
                )
            )
            member_uids = {row[0] for row in gm_res.fetchall()}
            non_members = sorted(user_ids - member_uids)
            if non_members:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"User(s) {', '.join(non_members)} are not members of group {group_id}"
                )

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
        if data.exchange_rate is not None and data.exchange_rate <= Decimal("0"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Exchange rate must be strictly positive",
            )

        base_currency = currency
        exchange_rate = data.exchange_rate or Decimal("1.0")
        rate_source = data.exchange_rate_source or "IDENTITY"

        if data.group_id:
            group_stmt = select(Group).where(Group.id == data.group_id, Group.is_archived == False)
            group_res = await db.execute(group_stmt)
            group = group_res.scalar_one_or_none()
            if not group:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found or archived")

            # Verify creator is an active member of the group
            member_stmt = select(GroupMember).where(
                GroupMember.group_id == data.group_id,
                GroupMember.user_id == creator.id,
                GroupMember.is_active == True,
            )
            member_res = await db.execute(member_stmt)
            if not member_res.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not an active member of this group")

            base_currency = group.base_currency.upper().strip()
            if currency == base_currency:
                if data.exchange_rate is not None and data.exchange_rate != Decimal("1"):
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                        detail=f"Exchange rate must be 1.0 when currency matches group base currency ({base_currency}).",
                    )
                exchange_rate = Decimal("1.0")
                rate_source = data.exchange_rate_source or "IDENTITY"
            elif data.exchange_rate is None:
                try:
                    rate_info = FXService.get_verified_rate(currency, base_currency)
                except UnsupportedCurrencyPairError as exc:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                        detail=str(exc),
                    )
                assert rate_info.rate is not None
                exchange_rate = rate_info.rate
                rate_source = data.exchange_rate_source or rate_info.source
            else:
                rate_source = data.exchange_rate_source or "MANUAL"
        elif data.exchange_rate is not None and data.exchange_rate != Decimal("1"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Exchange rate must be 1.0 or omitted for direct (non-group) expenses.",
            )

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
                        gm_stmt = select(GroupMember.user_id).where(
                            GroupMember.group_id == data.group_id,
                            GroupMember.is_active == True,
                        )
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
                        gm_stmt = select(GroupMember.user_id).where(
                            GroupMember.group_id == data.group_id,
                            GroupMember.is_active == True,
                        )
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

        # 5. Invariant Verification & Referenced User Validation
        total_owed = sum(s[1] for s in splits_to_insert)
        if total_owed != quantized_total:
            raise AssertionError(f"Split sum ({total_owed}) differs from total expense amount ({quantized_total})")

        referenced_uids = {uid for uid, _ in payers_to_insert} | {uid for uid, _, _ in splits_to_insert}
        await LedgerService._validate_referenced_users(db, referenced_uids, data.group_id)

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
                GroupMember.user_id == user.id,
                GroupMember.is_active == True,
            )
            mem_res = await db.execute(mem_stmt)
            if not mem_res.scalar_one_or_none():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not an active member of this expense's group")
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
            "exchange_rate": str(expense.exchange_rate),
            "exchange_rate_source": expense.exchange_rate_source,
            "base_currency_amount": str(expense.base_currency_amount),
            "split_type": expense.split_type,
            "version": expense.version,
            "payers": [{"user_id": p.user_id, "amount": str(p.amount_paid)} for p in expense.payers],
            "splits": [{"user_id": s.user_id, "amount": str(s.owed_amount)} for s in expense.splits]
        }

        prev_currency = expense.currency.upper().strip()
        prev_total = expense.total_amount
        prev_split_type = expense.split_type.upper().strip()

        # Apply field changes
        if data.description is not None:
            expense.description = data.description.strip()
        if data.category is not None:
            expense.category = data.category.upper().strip()
        if data.notes is not None:
            expense.notes = data.notes
        if data.expense_date is not None:
            expense.expense_date = data.expense_date

        raw_total = data.total_amount if data.total_amount is not None else prev_total
        currency = data.currency.upper().strip() if data.currency is not None else prev_currency
        split_type = data.split_type.upper().strip() if data.split_type is not None else prev_split_type

        currency_changed = currency != prev_currency
        quantized_total = quantize_currency(raw_total, currency)
        if quantized_total <= Decimal("0"):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Expense total amount must be strictly positive",
            )
        total_changed = data.total_amount is not None or quantized_total != prev_total

        expense.total_amount = quantized_total
        expense.currency = currency
        expense.split_type = split_type

        # Update base currency amount, preserving custom frozen historical rates unless currency actually changed
        base_currency = currency
        if expense.group_id:
            grp_stmt = select(Group).where(Group.id == expense.group_id)
            grp_res = await db.execute(grp_stmt)
            grp = grp_res.scalar_one_or_none()
            if grp:
                base_currency = grp.base_currency.upper().strip()

        if data.exchange_rate is not None:
            if data.exchange_rate <= Decimal("0"):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail="Exchange rate must be strictly positive",
                )
            if currency == base_currency and data.exchange_rate != Decimal("1"):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail=f"Exchange rate must be 1.0 when currency matches base currency ({base_currency}).",
                )
            expense.exchange_rate = data.exchange_rate
            expense.exchange_rate_source = (
                data.exchange_rate_source
                or ("IDENTITY" if currency == base_currency else "MANUAL")
            ).strip()
            expense.exchange_rate_timestamp = datetime.now(timezone.utc)
        elif currency == base_currency:
            expense.exchange_rate = Decimal("1.0")
            expense.exchange_rate_source = "IDENTITY"
            expense.exchange_rate_timestamp = datetime.now(timezone.utc)
        elif currency_changed or (
            expense.exchange_rate == Decimal("1.0")
            and expense.exchange_rate_source in ("DEFAULT", "SNAPSHOT_FALLBACK", "UNAVAILABLE_FALLBACK")
        ):
            try:
                rate_info = FXService.get_verified_rate(currency, base_currency)
            except UnsupportedCurrencyPairError as exc:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail=str(exc),
                )
            assert rate_info.rate is not None
            expense.exchange_rate = rate_info.rate
            expense.exchange_rate_source = rate_info.source
            expense.exchange_rate_timestamp = datetime.now(timezone.utc)

        expense.base_currency_amount = quantize_currency(quantized_total * expense.exchange_rate, base_currency)

        # Reconcile Payers if provided, total changed, or currency precision/identity changed
        resulting_payers: List[Tuple[str, Decimal]] = []
        existing_payers = list(expense.payers)
        if data.payers is not None:
            if len(data.payers) == 0:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail="Payers list cannot be empty when explicitly provided",
                )
            total_paid = Decimal("0")
            for p in data.payers:
                p_amt = quantize_currency(p.amount_paid, currency)
                if p_amt <= Decimal("0"):
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                        detail=f"Amount paid by user {p.user_id} must be strictly positive",
                    )
                total_paid += p_amt
                resulting_payers.append((p.user_id, p_amt))

            if total_paid != quantized_total:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    detail=f"Sum of payer amounts ({total_paid}) does not match total expense amount ({quantized_total})"
                )

            for old_p in existing_payers:
                await db.delete(old_p)
            await db.flush()

            for uid, amt in resulting_payers:
                db.add(ExpensePayer(expense_id=expense.id, user_id=uid, amount_paid=amt))

        elif total_changed or currency_changed:
            if len(existing_payers) == 1:
                existing_payers[0].amount_paid = quantized_total
                resulting_payers = [(existing_payers[0].user_id, quantized_total)]
            elif existing_payers:
                requantized = [(p, quantize_currency(p.amount_paid, currency)) for p in existing_payers]
                req_sum = sum(amt for _, amt in requantized)
                if any(amt <= Decimal("0") for _, amt in requantized) or req_sum != quantized_total:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                        detail=(
                            f"Expense updated to {quantized_total} {currency}, "
                            f"but existing multi-payer amounts resolve to {req_sum}. "
                            "Please provide updated payers list."
                        ),
                    )
                for p_obj, q_amt in requantized:
                    p_obj.amount_paid = q_amt
                    resulting_payers.append((p_obj.user_id, q_amt))
        else:
            resulting_payers = [(p.user_id, p.amount_paid) for p in existing_payers]

        # Reconcile Splits whenever split parameters, total_amount, currency, or split_type changed
        existing_splits = list(expense.splits)
        should_reprocess_splits = (
            data.splits is not None
            or data.participant_ids is not None
            or data.percentages is not None
            or data.shares is not None
            or data.adjustments is not None
            or data.items is not None
            or total_changed
            or currency_changed
            or split_type != prev_split_type
        )
        resulting_splits: List[Tuple[str, Decimal, Optional[Decimal]]] = []
        if should_reprocess_splits:
            new_splits: List[Tuple[str, Decimal, Optional[Decimal]]] = []
            try:
                if split_type == "EQUAL":
                    participants = data.participant_ids or [s.user_id for s in existing_splits] or [user.id]
                    split_results = MoneyEngine.split_equally(quantized_total, currency, participants)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "EXACT":
                    if data.splits is not None:
                        exact_map = {s.user_id: s.owed_amount for s in data.splits}
                    elif existing_splits:
                        exact_map = {s.user_id: s.owed_amount for s in existing_splits}
                    else:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Splits required for EXACT")
                    split_results = MoneyEngine.validate_exact_splits(quantized_total, currency, exact_map)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, None))
                elif split_type == "PERCENTAGE":
                    percentages = data.percentages
                    if not percentages:
                        if existing_splits and all(s.share_quantity is not None for s in existing_splits):
                            percentages = {s.user_id: s.share_quantity for s in existing_splits if s.share_quantity is not None}
                        else:
                            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Percentages required")
                    split_results = MoneyEngine.split_by_percentages(quantized_total, currency, percentages)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "SHARES":
                    shares = data.shares
                    if not shares:
                        if existing_splits and all(s.share_quantity is not None for s in existing_splits):
                            shares = {s.user_id: s.share_quantity for s in existing_splits if s.share_quantity is not None}
                        else:
                            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Shares required")
                    split_results = MoneyEngine.split_by_shares(quantized_total, currency, shares)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "ADJUSTMENT":
                    participants = data.participant_ids or [s.user_id for s in existing_splits]
                    adjustments = (
                        data.adjustments
                        if data.adjustments is not None
                        else {s.user_id: s.share_quantity for s in existing_splits if s.share_quantity is not None}
                    )
                    split_results = MoneyEngine.split_with_adjustments(quantized_total, currency, participants, adjustments)
                    for sr in split_results:
                        new_splits.append((sr.user_id, sr.amount, sr.share_value))
                elif split_type == "ITEMIZED":
                    if data.items:
                        item_entries = [
                            ItemizedEntry(description=it.description, amount=it.amount, participant_ids=it.participant_ids)
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
                                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                                detail=f"Calculated itemized total ({calculated_total}) does not match expense total ({quantized_total})",
                            )
                        for sr in split_results:
                            new_splits.append((sr.user_id, sr.amount, sr.share_value))
                    elif currency_changed and not total_changed and existing_splits:
                        exact_map = {s.user_id: s.owed_amount for s in existing_splits}
                        split_results = MoneyEngine.validate_exact_splits(quantized_total, currency, exact_map)
                        share_map = {s.user_id: s.share_quantity for s in existing_splits}
                        for sr in split_results:
                            q_share = (
                                quantize_currency(share_map[sr.user_id], currency)
                                if share_map.get(sr.user_id) is not None
                                else None
                            )
                            new_splits.append((sr.user_id, sr.amount, q_share))
                    else:
                        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Items required for itemized split")
                else:
                    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unsupported split type: {split_type}")
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(e))

            for old_s in existing_splits:
                await db.delete(old_s)
            await db.flush()

            for uid, amt, share in new_splits:
                db.add(ExpenseSplit(expense_id=expense.id, user_id=uid, owed_amount=amt, share_quantity=share))
            resulting_splits = new_splits
        else:
            resulting_splits = [(s.user_id, s.owed_amount, s.share_quantity) for s in existing_splits]

        # Enforce strict conservation after update
        final_paid_sum = sum((amt for _, amt in resulting_payers), Decimal("0"))
        final_owed_sum = sum((amt for _, amt, _ in resulting_splits), Decimal("0"))
        if final_paid_sum != quantized_total:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"Sum of payer amounts ({final_paid_sum}) does not match total expense amount ({quantized_total})",
            )
        if final_owed_sum != quantized_total:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"Sum of split amounts ({final_owed_sum}) does not match total expense amount ({quantized_total})",
            )

        referenced_uids = (
            {uid for uid, _ in resulting_payers}
            | {uid for uid, _, _ in resulting_splits}
        )
        await LedgerService._validate_referenced_users(db, referenced_uids, expense.group_id)

        expense.version += 1
        expense.updated_at = datetime.now(timezone.utc)

        # Audit Record
        new_state = {
            "description": expense.description,
            "total_amount": str(expense.total_amount),
            "currency": expense.currency,
            "exchange_rate": str(expense.exchange_rate),
            "exchange_rate_source": expense.exchange_rate_source,
            "base_currency_amount": str(expense.base_currency_amount),
            "split_type": expense.split_type,
            "version": expense.version,
            "payers": [{"user_id": uid, "amount": str(amt)} for uid, amt in resulting_payers],
            "splits": [{"user_id": uid, "amount": str(amt)} for uid, amt, _ in resulting_splits],
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

        # Verify active group membership if group_id is specified
        if data.group_id:
            for uid in (payer_id, data.recipient_id):
                gm_stmt = select(GroupMember).where(
                    GroupMember.group_id == data.group_id,
                    GroupMember.user_id == uid,
                    GroupMember.is_active == True,
                )
                res = await db.execute(gm_stmt)
                if not res.scalar_one_or_none():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"User {uid} is not an active member of group {data.group_id}"
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
    def _compute_group_ledger_from_records(
        group: Group,
        expenses: List[Expense],
        settlements: List[Settlement],
        include_debts: bool = True,
    ) -> Tuple[Dict[str, Decimal], List[SimplifiedDebt], List[BilateralDebt], str]:
        """Computes group net balances (and optional debts) from preloaded ORM records."""
        currency = group.base_currency.upper().strip()
        payers_list: List[Tuple[str, Decimal]] = []
        splits_list: List[Tuple[str, Decimal]] = []
        expense_records: List[Dict[str, Any]] = []

        for exp in expenses:
            exp_currency = exp.currency.upper().strip()
            if exp_currency == currency:
                rate = Decimal("1.0")
            elif exp.exchange_rate != Decimal("1.0") or exp.exchange_rate_source not in (
                "DEFAULT",
                "SNAPSHOT_FALLBACK",
                "UNAVAILABLE_FALLBACK",
            ):
                rate = exp.exchange_rate
            else:
                rate = LedgerService._get_verified_rate(exp_currency, currency)

            converted_total = quantize_currency(exp.total_amount * rate, currency)
            exp_payers = LedgerService._convert_allocations_preserving_total(
                [(p.user_id, p.amount_paid) for p in exp.payers],
                rate,
                converted_total,
                currency,
            )
            exp_splits = LedgerService._convert_allocations_preserving_total(
                [(s.user_id, s.owed_amount) for s in exp.splits],
                rate,
                converted_total,
                currency,
            )

            payers_list.extend(exp_payers)
            splits_list.extend(exp_splits)
            if include_debts:
                expense_records.append({
                    "payers": exp_payers,
                    "splits": exp_splits,
                    "total_amount": converted_total,
                })

        settle_list: List[Tuple[str, str, Decimal]] = []
        settlement_records: List[Dict[str, Any]] = []
        for s in settlements:
            s_amt = LedgerService._convert_amount(s.amount, s.currency, currency)
            settle_list.append((s.payer_id, s.recipient_id, s_amt))
            if include_debts:
                settlement_records.append({
                    "payer_id": s.payer_id,
                    "recipient_id": s.recipient_id,
                    "amount": s_amt,
                })

        net_balances = DebtSimplifier.calculate_group_net_balances(
            payers=payers_list,
            splits=splits_list,
            settlements=settle_list,
            currency=currency,
        )

        # Pad active members with 0.0000 when settled (preserve inactive former members who still have ledger entries)
        if group.members:
            for m in group.members:
                if m.is_active and m.user_id not in net_balances:
                    net_balances[m.user_id] = quantize_currency(Decimal("0"), currency)

        if not include_debts:
            return net_balances, [], [], currency

        bilateral_debts = DebtSimplifier.calculate_pairwise_bilateral_debts(
            expense_records=expense_records,
            settlement_records=settlement_records,
            currency=currency,
        )

        simplified_debts: List[SimplifiedDebt] = []
        if group.simplify_debts:
            simplified_debts = DebtSimplifier.simplify_net_balances(
                net_balances=net_balances,
                currency=currency,
            )

        return net_balances, simplified_debts, bilateral_debts, currency

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

        exp_stmt = (
            select(Expense)
            .where(Expense.group_id == group_id, Expense.is_deleted == False)
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        expenses = list(exp_res.scalars().all())

        settle_stmt = select(Settlement).where(
            Settlement.group_id == group_id,
            Settlement.is_deleted == False,
        )
        settle_res = await db.execute(settle_stmt)
        settlements = list(settle_res.scalars().all())

        return LedgerService._compute_group_ledger_from_records(
            group=group,
            expenses=expenses,
            settlements=settlements,
            include_debts=True,
        )

    @staticmethod
    async def get_groups_net_balances_batch(
        db: AsyncSession,
        groups: List[Group],
    ) -> Dict[str, Tuple[Dict[str, Decimal], str]]:
        """
        Batch-computes per-member net balances and base currency for multiple [groups]
        in 2 queries (IN group_ids) instead of N separate get_group_balances calls.
        """
        if not groups:
            return {}

        group_ids = [g.id for g in groups]
        exp_stmt = (
            select(Expense)
            .where(Expense.group_id.in_(group_ids), Expense.is_deleted == False)
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        exps_by_group: Dict[str, List[Expense]] = {gid: [] for gid in group_ids}
        for exp in exp_res.scalars().all():
            if exp.group_id in exps_by_group:
                exps_by_group[exp.group_id].append(exp)

        settle_stmt = select(Settlement).where(
            Settlement.group_id.in_(group_ids),
            Settlement.is_deleted == False,
        )
        settle_res = await db.execute(settle_stmt)
        settlements_by_group: Dict[str, List[Settlement]] = {gid: [] for gid in group_ids}
        for s in settle_res.scalars().all():
            if s.group_id in settlements_by_group:
                settlements_by_group[s.group_id].append(s)

        results: Dict[str, Tuple[Dict[str, Decimal], str]] = {}
        for g in groups:
            net_balances, _, _, currency = LedgerService._compute_group_ledger_from_records(
                group=g,
                expenses=exps_by_group.get(g.id, []),
                settlements=settlements_by_group.get(g.id, []),
                include_debts=False,
            )
            results[g.id] = (net_balances, currency)
        return results

    @staticmethod
    async def get_direct_bilateral_overview(
        db: AsyncSession,
        user_id: str,
        target_currency: str = "USD",
    ) -> Tuple[Dict[str, Decimal], Decimal, Decimal, Set[str]]:
        """
        Computes per-counterparty bilateral net balances for all direct (non-group)
        expenses and settlements involving [user_id], converted to [target_currency].
        Returns: (per_counterparty_net, you_are_owed_total, you_owe_total, counterparty_ids).
        """
        dst_currency = target_currency.upper().strip()
        exp_stmt = (
            select(Expense)
            .where(
                Expense.group_id.is_(None),
                Expense.is_deleted == False,
                or_(
                    Expense.created_by == user_id,
                    Expense.payers.any(ExpensePayer.user_id == user_id),
                    Expense.splits.any(ExpenseSplit.user_id == user_id),
                ),
            )
            .options(selectinload(Expense.payers), selectinload(Expense.splits))
        )
        exp_res = await db.execute(exp_stmt)
        expenses = exp_res.scalars().all()

        counterparties: Set[str] = set()
        shared_expenses: List[Dict[str, Any]] = []
        for exp in expenses:
            participant_uids = {p.user_id for p in exp.payers} | {s.user_id for s in exp.splits}
            if user_id not in participant_uids:
                continue
            for uid in participant_uids:
                if uid != user_id:
                    counterparties.add(uid)

            exp_curr = exp.currency.upper().strip()
            rate = LedgerService._get_verified_rate(exp_curr, dst_currency)
            converted_total = quantize_currency(exp.total_amount * rate, dst_currency)
            conv_payers = LedgerService._convert_allocations_preserving_total(
                [(p.user_id, p.amount_paid) for p in exp.payers],
                rate,
                converted_total,
                dst_currency,
            )
            conv_splits = LedgerService._convert_allocations_preserving_total(
                [(s.user_id, s.owed_amount) for s in exp.splits],
                rate,
                converted_total,
                dst_currency,
            )
            shared_expenses.append({
                "payers": conv_payers,
                "splits": conv_splits,
                "total_amount": converted_total,
            })

        settle_stmt = select(Settlement).where(
            Settlement.group_id.is_(None),
            Settlement.is_deleted == False,
            or_(Settlement.payer_id == user_id, Settlement.recipient_id == user_id),
        )
        settle_res = await db.execute(settle_stmt)
        settlements = settle_res.scalars().all()

        settlement_records = []
        for s in settlements:
            other_uid = s.recipient_id if s.payer_id == user_id else s.payer_id
            if other_uid != user_id:
                counterparties.add(other_uid)
            settlement_records.append({
                "payer_id": s.payer_id,
                "recipient_id": s.recipient_id,
                "amount": LedgerService._convert_amount(s.amount, s.currency, dst_currency),
            })

        bilateral_list = DebtSimplifier.calculate_pairwise_bilateral_debts(
            expense_records=shared_expenses,
            settlement_records=settlement_records,
            currency=dst_currency,
        )

        per_counterparty: Dict[str, Decimal] = {}
        you_are_owed = Decimal("0")
        you_owe = Decimal("0")
        for b in bilateral_list:
            if b.creditor_id == user_id and b.debtor_id != user_id:
                per_counterparty[b.debtor_id] = per_counterparty.get(b.debtor_id, Decimal("0")) + b.amount
                you_are_owed += b.amount
            elif b.debtor_id == user_id and b.creditor_id != user_id:
                per_counterparty[b.creditor_id] = per_counterparty.get(b.creditor_id, Decimal("0")) - b.amount
                you_owe += b.amount

        return (
            per_counterparty,
            quantize_currency(you_are_owed, dst_currency),
            quantize_currency(you_owe, dst_currency),
            counterparties,
        )

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
        per_counterparty, _, _, _ = await LedgerService.get_direct_bilateral_overview(
            db, user_id_1, currency
        )
        return quantize_currency(per_counterparty.get(user_id_2, Decimal("0")), currency)
