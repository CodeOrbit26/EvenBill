"""
EvenBill Spending Charts, Graphs, and Category Insights (Pro Feature)
Computes aggregated spending analytics, category breakdowns, monthly trend charts,
and personal spending insights.
"""

from typing import List, Dict, Any, Optional, Tuple
from decimal import Decimal
from datetime import datetime, timezone, date
from pydantic import BaseModel
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy import select, and_, or_, func
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.expense import Expense, ExpensePayer, ExpenseSplit
from app.models.group import Group, GroupMember
from app.schemas.common import APIResponse
from app.services.entitlement_service import EntitlementService, PlanTier, FeatureKey, FeatureLockedException

router = APIRouter(prefix="/analytics", tags=["Spending Analytics & Insights (Pro)"])


class CategorySpendingItem(BaseModel):
    category: str
    total_amount: float
    percentage: float
    expense_count: int


class MonthlySpendingItem(BaseModel):
    month: str  # YYYY-MM
    total_amount: float
    expense_count: int


class GroupSpendingItem(BaseModel):
    group_id: Optional[str]
    group_name: str
    total_amount: float
    percentage: float


class SpendingInsightsResponse(BaseModel):
    total_spent_personal_share: float
    total_paid_by_user: float
    total_expenses_count: int
    currency: str
    categories: List[CategorySpendingItem]
    monthly_trend: List[MonthlySpendingItem]
    group_breakdown: List[GroupSpendingItem]
    is_pro: bool


@router.get("/spending", response_model=APIResponse[SpendingInsightsResponse])
async def get_spending_insights(
    group_id: Optional[str] = Query(None, description="Optional filter by group ID"),
    start_date: Optional[date] = Query(None, description="Filter from start date"),
    end_date: Optional[date] = Query(None, description="Filter to end date"),
    currency: str = Query("USD", min_length=3, max_length=3, description="Currency filter"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Computes comprehensive spending charts, category breakdown, and monthly trend insights.
    Available to Pro users (or returns basic summary for free users with upgrade flag).
    """
    plan = await EntitlementService.get_user_plan(db, current_user)
    is_pro = (plan == PlanTier.PRO)

    # Base query for expenses the user participated in (either as payer or split participant)
    target_currency = currency.upper().strip()

    stmt = (
        select(Expense)
        .options(
            selectinload(Expense.payers),
            selectinload(Expense.splits),
            selectinload(Expense.group)
        )
        .where(
            Expense.is_deleted == False,
            Expense.currency == target_currency
        )
    )

    if group_id:
        # Check group membership
        gm_stmt = select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id
        )
        gm_res = await db.execute(gm_stmt)
        if not gm_res.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group.")
        stmt = stmt.where(Expense.group_id == group_id)
    else:
        # Strictly isolate to current user's expenses
        stmt = stmt.where(
            or_(
                Expense.created_by == current_user.id,
                Expense.payers.any(ExpensePayer.user_id == current_user.id),
                Expense.splits.any(ExpenseSplit.user_id == current_user.id)
            )
        )

    if start_date:
        stmt = stmt.where(Expense.expense_date >= start_date)
    if end_date:
        stmt = stmt.where(Expense.expense_date <= end_date)

    res = await db.execute(stmt)
    all_expenses = res.scalars().all()

    # Filter to expenses where current_user is involved
    user_expenses = []
    personal_shares_total = Decimal("0")
    total_paid = Decimal("0")

    category_totals: Dict[str, Decimal] = {}
    category_counts: Dict[str, int] = {}
    monthly_totals: Dict[str, Decimal] = {}
    monthly_counts: Dict[str, int] = {}
    group_totals: Dict[Optional[str], Tuple[str, Decimal]] = {}

    for exp in all_expenses:
        # Check if user is payer or participant
        user_payer = next((p for p in exp.payers if p.user_id == current_user.id), None)
        user_split = next((s for s in exp.splits if s.user_id == current_user.id), None)

        if not user_payer and not user_split:
            continue

        user_expenses.append(exp)

        if user_payer:
            total_paid += user_payer.amount_paid

        share_amount = user_split.owed_amount if user_split else Decimal("0")
        personal_shares_total += share_amount

        # Category aggregation (based on personal share)
        cat = exp.category or "General"
        category_totals[cat] = category_totals.get(cat, Decimal("0")) + share_amount
        category_counts[cat] = category_counts.get(cat, 0) + 1

        # Monthly aggregation
        m_key = exp.expense_date.strftime("%Y-%m")
        monthly_totals[m_key] = monthly_totals.get(m_key, Decimal("0")) + share_amount
        monthly_counts[m_key] = monthly_counts.get(m_key, 0) + 1

        # Group aggregation
        gid = exp.group_id
        gname = exp.group.name if exp.group else "Individual / Non-group"
        prev_name, prev_tot = group_totals.get(gid, (gname, Decimal("0")))
        group_totals[gid] = (prev_name, prev_tot + share_amount)

    # Build Category Spending Items
    categories_list: List[CategorySpendingItem] = []
    for cat, total in sorted(category_totals.items(), key=lambda x: x[1], reverse=True):
        pct = float((total / personal_shares_total * 100).quantize(Decimal("0.1"))) if personal_shares_total > 0 else 0.0
        categories_list.append(CategorySpendingItem(
            category=cat,
            total_amount=float(total),
            percentage=pct,
            expense_count=category_counts[cat]
        ))

    # Build Monthly Trend (sorted chronologically)
    monthly_trend: List[MonthlySpendingItem] = []
    for m in sorted(monthly_totals.keys()):
        monthly_trend.append(MonthlySpendingItem(
            month=m,
            total_amount=float(monthly_totals[m]),
            expense_count=monthly_counts[m]
        ))

    # Build Group Breakdown
    group_breakdown: List[GroupSpendingItem] = []
    for gid, (gname, tot) in sorted(group_totals.items(), key=lambda x: x[1][1], reverse=True):
        pct = float((tot / personal_shares_total * 100).quantize(Decimal("0.1"))) if personal_shares_total > 0 else 0.0
        group_breakdown.append(GroupSpendingItem(
            group_id=gid,
            group_name=gname,
            total_amount=float(tot),
            percentage=pct
        ))

    return APIResponse(data=SpendingInsightsResponse(
        total_spent_personal_share=float(personal_shares_total),
        total_paid_by_user=float(total_paid),
        total_expenses_count=len(user_expenses),
        currency=target_currency,
        categories=categories_list,
        monthly_trend=monthly_trend,
        group_breakdown=group_breakdown,
        is_pro=is_pro
    ))
