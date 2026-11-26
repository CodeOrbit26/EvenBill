"""
EvenBill Activity Feed & Dashboard Summary REST Endpoints
"""

from typing import List, Optional
from datetime import datetime, date, timezone
from decimal import Decimal
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select, or_, and_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.group import Group, GroupMember
from app.models.expense import Expense, ExpensePayer, ExpenseSplit
from app.models.settlement import Settlement
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService
from app.core.money import quantize_currency

router = APIRouter(prefix="/activity", tags=["Activity"])


class ActivityItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    item_type: str  # EXPENSE, SETTLEMENT, REFUND
    title: str
    description: str
    category: str
    total_amount: Decimal
    currency: str
    user_net_share: Decimal  # Positive = user lent / received, Negative = user borrowed / owes
    user_paid_amount: Decimal = Decimal("0")
    user_owed_amount: Decimal = Decimal("0")
    is_user_involved: bool = False
    group_id: Optional[str] = None
    group_name: Optional[str] = None
    created_by_name: str
    timestamp: datetime


class ActivitySummaryResponse(BaseModel):
    total_net_balance: Decimal
    you_are_owed_total: Decimal
    you_owe_total: Decimal
    monthly_spending: Decimal
    currency: str
    active_groups_count: int
    active_friends_count: int


@router.get("/", response_model=APIResponse[List[ActivityItem]])
async def list_activity(
    group_id: Optional[str] = Query(None, description="Filter by group"),
    category: Optional[str] = Query(None, description="Filter by category"),
    search: Optional[str] = Query(None, description="Search term in description or notes"),
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    currency = current_user.default_currency or "USD"

    # Query expenses involving user (or all in group if group_id specified)
    exp_stmt = (
        select(Expense)
        .where(Expense.is_deleted == False)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user),
            selectinload(Expense.creator),
            selectinload(Expense.group)
        )
    )

    user_group_ids = []
    if group_id:
        # Strictly enforce active membership authorization
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied to group activity"
            )
        exp_stmt = exp_stmt.where(Expense.group_id == group_id)
    else:
        # Strictly isolate expenses: user's active groups OR personal expenses involving user
        user_group_ids_stmt = select(GroupMember.group_id).where(
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        user_group_ids_res = await db.execute(user_group_ids_stmt)
        user_group_ids = [r[0] for r in user_group_ids_res.fetchall()]

        involvement_conditions = [
            Expense.created_by == current_user.id,
            Expense.id.in_(select(ExpensePayer.expense_id).where(ExpensePayer.user_id == current_user.id)),
            Expense.id.in_(select(ExpenseSplit.expense_id).where(ExpenseSplit.user_id == current_user.id))
        ]
        if user_group_ids:
            exp_stmt = exp_stmt.where(or_(Expense.group_id.in_(user_group_ids), *involvement_conditions))
        else:
            exp_stmt = exp_stmt.where(or_(*involvement_conditions))

    if category:
        exp_stmt = exp_stmt.where(Expense.category == category.upper().strip())
    if search:
        exp_stmt = exp_stmt.where(
            or_(
                Expense.description.ilike(f"%{search}%"),
                Expense.notes.ilike(f"%{search}%")
            )
        )

    exp_res = await db.execute(exp_stmt)
    all_expenses = exp_res.scalars().all()

    # Filter to expenses where current_user is creator, payer, or split participant (if not already group-filtered)
    user_expenses = []
    for exp in all_expenses:
        if group_id or (exp.group_id and exp.group_id in user_group_ids):
            user_expenses.append(exp)
        else:
            is_involved = (
                exp.created_by == current_user.id
                or any(p.user_id == current_user.id for p in exp.payers)
                or any(s.user_id == current_user.id for s in exp.splits)
            )
            if is_involved:
                user_expenses.append(exp)

    # Query settlements involving user
    settle_stmt = (
        select(Settlement)
        .where(Settlement.is_deleted == False)
        .options(
            selectinload(Settlement.payer),
            selectinload(Settlement.recipient),
            selectinload(Settlement.group)
        )
    )
    if group_id:
        settle_stmt = settle_stmt.where(Settlement.group_id == group_id)
    else:
        if user_group_ids:
            settle_stmt = settle_stmt.where(
                or_(
                    Settlement.payer_id == current_user.id,
                    Settlement.recipient_id == current_user.id,
                    Settlement.group_id.in_(user_group_ids)
                )
            )
        else:
            settle_stmt = settle_stmt.where(
                or_(Settlement.payer_id == current_user.id, Settlement.recipient_id == current_user.id)
            )


    settle_res = await db.execute(settle_stmt)
    all_settlements = settle_res.scalars().all()

    items: List[ActivityItem] = []

    # Map Expenses to ActivityItem
    for exp in user_expenses:
        paid_by_me = sum((p.amount_paid for p in exp.payers if p.user_id == current_user.id), Decimal("0"))
        owed_by_me = sum((s.owed_amount for s in exp.splits if s.user_id == current_user.id), Decimal("0"))
        user_net = paid_by_me - owed_by_me
        is_involved = (
            paid_by_me > Decimal("0")
            or owed_by_me > Decimal("0")
            or any(p.user_id == current_user.id for p in exp.payers)
            or any(s.user_id == current_user.id for s in exp.splits)
        )

        creator_name = exp.creator.full_name if exp.creator else "User"
        group_name = exp.group.name if exp.group else None
        payer_names = [p.user.full_name for p in exp.payers if p.user]
        if len(payer_names) > 1:
            other_word = "other" if len(payer_names) == 2 else "others"
            payer_desc = f"Paid by {payer_names[0]} (+{len(payer_names) - 1} {other_word})"
        elif len(payer_names) == 1:
            payer_desc = f"Paid by {payer_names[0]}"
        else:
            payer_desc = f"Paid by {creator_name}"

        items.append(ActivityItem(
            id=exp.id,
            item_type=exp.transaction_type,
            title=exp.description,
            description=payer_desc,
            category=exp.category,
            total_amount=exp.total_amount,
            currency=exp.currency,
            user_net_share=user_net,
            user_paid_amount=paid_by_me,
            user_owed_amount=owed_by_me,
            is_user_involved=is_involved,
            group_id=exp.group_id,
            group_name=group_name,
            created_by_name=creator_name,
            timestamp=exp.created_at
        ))

    # Map Settlements to ActivityItem
    for s in all_settlements:
        payer_name = s.payer.full_name if s.payer else "Someone"
        recipient_name = s.recipient.full_name if s.recipient else "Someone"

        if s.payer_id == current_user.id:
            user_net = s.amount
            user_paid = s.amount
            user_owed = Decimal("0")
            is_involved = True
            desc = f"You paid {recipient_name}"
        elif s.recipient_id == current_user.id:
            user_net = -s.amount
            user_paid = Decimal("0")
            user_owed = s.amount
            is_involved = True
            desc = f"{payer_name} paid you"
        else:
            user_net = Decimal("0")
            user_paid = Decimal("0")
            user_owed = Decimal("0")
            is_involved = False
            desc = f"{payer_name} paid {recipient_name}"

        items.append(ActivityItem(
            id=s.id,
            item_type="SETTLEMENT",
            title=f"Settlement: {desc}",
            description=f"via {s.payment_method}",
            category="PAYMENT",
            total_amount=s.amount,
            currency=s.currency,
            user_net_share=user_net,
            user_paid_amount=user_paid,
            user_owed_amount=user_owed,
            is_user_involved=is_involved,
            group_id=s.group_id,
            group_name=s.group.name if s.group else None,
            created_by_name=payer_name,
            timestamp=s.settled_at
        ))

    # Sort descending by timestamp
    items.sort(key=lambda x: x.timestamp, reverse=True)
    return APIResponse(data=items[:limit])


@router.get("/summary", response_model=APIResponse[ActivitySummaryResponse])
async def get_activity_summary(
    currency: Optional[str] = Query(None, description="Preferred currency code"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    selected_currency = currency.upper().strip() if currency else (current_user.default_currency or "USD")

    # Active groups count & group balances
    group_memberships_stmt = (
        select(GroupMember)
        .where(
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        .options(selectinload(GroupMember.group).selectinload(Group.members))
    )
    gm_res = await db.execute(group_memberships_stmt)
    memberships = gm_res.scalars().all()
    active_groups = [m.group for m in memberships if m.group and not m.group.is_archived]

    total_owed_to_user = Decimal("0")
    total_owed_by_user = Decimal("0")

    batch_group_balances = await LedgerService.get_groups_net_balances_batch(db, active_groups)
    for g in active_groups:
        net_bals, group_currency = batch_group_balances.get(g.id, ({}, g.base_currency))
        bal = net_bals.get(current_user.id, Decimal("0"))
        converted_bal = LedgerService._convert_amount(bal, group_currency, selected_currency)
        if converted_bal > Decimal("0"):
            total_owed_to_user += converted_bal
        elif converted_bal < Decimal("0"):
            total_owed_by_user += abs(converted_bal)

    # Direct (non-group) expenses & settlements, converted and netted per counterparty
    _, direct_owed_to, direct_owed_by, direct_friends = (
        await LedgerService.get_direct_bilateral_overview(db, current_user.id, selected_currency)
    )
    total_owed_to_user += direct_owed_to
    total_owed_by_user += direct_owed_by

    # Monthly spending calculation (all splits owed by user this month, converted to selected_currency)
    today = date.today()
    start_of_month = date(today.year, today.month, 1)

    spending_stmt = (
        select(ExpenseSplit.owed_amount, Expense.currency)
        .join(Expense, Expense.id == ExpenseSplit.expense_id)
        .where(
            ExpenseSplit.user_id == current_user.id,
            Expense.is_deleted == False,
            Expense.expense_date >= start_of_month
        )
    )
    spend_res = await db.execute(spending_stmt)
    monthly_spending = sum(
        (
            LedgerService._convert_amount(amt, exp_curr, selected_currency)
            for amt, exp_curr in spend_res.fetchall()
        ),
        Decimal("0"),
    )

    # Friends count (distinct active group co-members and direct expense/settlement counterparties)
    friend_ids = set(direct_friends)
    for g in active_groups:
        for m in g.members:
            if m.is_active and m.user_id != current_user.id:
                friend_ids.add(m.user_id)

    net_total = total_owed_to_user - total_owed_by_user

    summary = ActivitySummaryResponse(
        total_net_balance=quantize_currency(net_total, selected_currency),
        you_are_owed_total=quantize_currency(total_owed_to_user, selected_currency),
        you_owe_total=quantize_currency(total_owed_by_user, selected_currency),
        monthly_spending=quantize_currency(Decimal(str(monthly_spending)), selected_currency),
        currency=selected_currency,
        active_groups_count=len(active_groups),
        active_friends_count=len(friend_ids)
    )
    return APIResponse(data=summary)
