"""
EvenBill Activity Feed & Dashboard Summary REST Endpoints
"""

from typing import List, Optional
from datetime import datetime, date, timezone
from decimal import Decimal
from fastapi import APIRouter, Depends, Query
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
        # Strictly enforce membership authorization
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied to group activity"
            )
        exp_stmt = exp_stmt.where(Expense.group_id == group_id)
    else:
        # Strictly isolate expenses: user's groups OR personal expenses involving user
        user_group_ids_stmt = select(GroupMember.group_id).where(GroupMember.user_id == current_user.id)
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
        paid_by_me = sum(p.amount_paid for p in exp.payers if p.user_id == current_user.id)
        owed_by_me = sum(s.owed_amount for s in exp.splits if s.user_id == current_user.id)
        user_net = paid_by_me - owed_by_me

        creator_name = exp.creator.full_name if exp.creator else "User"
        group_name = exp.group.name if exp.group else None

        items.append(ActivityItem(
            id=exp.id,
            item_type=exp.transaction_type,
            title=exp.description,
            description=f"Paid by {exp.payers[0].user.full_name if exp.payers and exp.payers[0].user else creator_name}",
            category=exp.category,
            total_amount=exp.total_amount,
            currency=exp.currency,
            user_net_share=user_net,
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
            desc = f"You paid {recipient_name}"
        else:
            user_net = -s.amount
            desc = f"{payer_name} paid you"

        items.append(ActivityItem(
            id=s.id,
            item_type="SETTLEMENT",
            title=f"Settlement: {desc}",
            description=f"via {s.payment_method}",
            category="PAYMENT",
            total_amount=s.amount,
            currency=s.currency,
            user_net_share=user_net,
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

    # Groups count & group balances
    group_memberships_stmt = (
        select(GroupMember)
        .where(GroupMember.user_id == current_user.id)
        .options(selectinload(GroupMember.group))
    )
    gm_res = await db.execute(group_memberships_stmt)
    memberships = gm_res.scalars().all()
    active_groups = [m.group for m in memberships if m.group and not m.group.is_archived]

    total_owed_to_user = Decimal("0")
    total_owed_by_user = Decimal("0")

    for g in active_groups:
        net_bals, _, _, _ = await LedgerService.get_group_balances(db, g.id)
        bal = net_bals.get(current_user.id, Decimal("0"))
        if bal > Decimal("0"):
            total_owed_to_user += bal
        elif bal < Decimal("0"):
            total_owed_by_user += abs(bal)

    # Monthly spending calculation (all splits owed by user this month)
    today = date.today()
    start_of_month = date(today.year, today.month, 1)

    spending_stmt = (
        select(ExpenseSplit.owed_amount)
        .join(Expense, Expense.id == ExpenseSplit.expense_id)
        .where(
            ExpenseSplit.user_id == current_user.id,
            Expense.is_deleted == False,
            Expense.expense_date >= start_of_month
        )
    )
    spend_res = await db.execute(spending_stmt)
    monthly_spending = sum(row[0] for row in spend_res.fetchall()) if spend_res else Decimal("0")

    # Friends count (distinct friends)
    friend_ids = set()
    for g in active_groups:
        gm_stmt = select(GroupMember.user_id).where(
            GroupMember.group_id == g.id,
            GroupMember.user_id != current_user.id
        )
        res = await db.execute(gm_stmt)
        for r in res.fetchall():
            friend_ids.add(r[0])

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
