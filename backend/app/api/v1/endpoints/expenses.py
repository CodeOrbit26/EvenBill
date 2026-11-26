"""
EvenBill Expense REST Endpoints
Comprehensive support for creation, updates, soft-deletions, group and personal listing,
1-on-1 bilateral friend balances, and multi-currency snapshots.
"""

from typing import List, Optional
from decimal import Decimal
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select, or_, and_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.expense import Expense, ExpensePayer, ExpenseSplit, Receipt
from app.models.group import GroupMember
from app.schemas.expense import (
    ExpenseCreate, ExpenseUpdate, ExpenseResponse, PayerResponse, SplitResponse
)
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService
from app.services.entitlement_service import EntitlementService, PlanTier, FeatureKey, FeatureLockedException

router = APIRouter(prefix="/expenses", tags=["Expenses"])


class FriendBalanceResponse(BaseModel):
    user_id: str
    friend_id: str
    currency: str
    net_balance: Decimal
    status: str  # "YOU_ARE_OWED", "YOU_OWE", "SETTLED"
    amount: Decimal


def serialize_expense(exp: Expense) -> ExpenseResponse:
    """Serializes an ORM Expense into a strictly typed ExpenseResponse."""
    payers_resp = [
        PayerResponse(
            user_id=p.user_id,
            full_name=p.user.full_name if p.user else "User",
            amount_paid=p.amount_paid
        )
        for p in (exp.payers or [])
    ]
    splits_resp = [
        SplitResponse(
            user_id=s.user_id,
            full_name=s.user.full_name if s.user else "User",
            owed_amount=s.owed_amount,
            share_quantity=s.share_quantity
        )
        for s in (exp.splits or [])
    ]
    creator_name = exp.creator.full_name if exp.creator else "User"

    has_receipt = False
    receipts_list = exp.__dict__.get("receipts")
    if receipts_list:
        has_receipt = any(not r.is_deleted for r in receipts_list)

    return ExpenseResponse(
        id=exp.id,
        idempotency_key=exp.idempotency_key,
        transaction_type=exp.transaction_type,
        original_expense_id=exp.original_expense_id,
        group_id=exp.group_id,
        created_by=exp.created_by,
        creator_name=creator_name,
        description=exp.description,
        total_amount=exp.total_amount,
        currency=exp.currency,
        base_currency_amount=exp.base_currency_amount,
        exchange_rate=exp.exchange_rate,
        exchange_rate_source=exp.exchange_rate_source,
        exchange_rate_timestamp=exp.exchange_rate_timestamp,
        split_type=exp.split_type,
        category=exp.category,
        expense_date=exp.expense_date,
        notes=exp.notes,
        is_deleted=exp.is_deleted,
        version=exp.version,
        created_at=exp.created_at,
        updated_at=exp.updated_at,
        payers=payers_resp,
        splits=splits_resp,
        has_receipt=has_receipt
    )


async def get_expense_with_relations(db: AsyncSession, expense_id: str) -> Optional[Expense]:
    stmt = (
        select(Expense)
        .where(Expense.id == expense_id)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user),
            selectinload(Expense.creator),
            selectinload(Expense.receipts)
        )
    )
    res = await db.execute(stmt)
    return res.scalar_one_or_none()


@router.post("/", response_model=APIResponse[ExpenseResponse], status_code=status.HTTP_201_CREATED)
async def create_expense(
    data: ExpenseCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    created = await LedgerService.create_expense(db, current_user, data)
    loaded_expense = await get_expense_with_relations(db, created.id)
    if not loaded_expense:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to load expense")

    return APIResponse(data=serialize_expense(loaded_expense))


@router.get("/group/{group_id}", response_model=APIResponse[List[ExpenseResponse]])
async def list_group_expenses(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Verify active group membership
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to group expenses")

    stmt = (
        select(Expense)
        .where(Expense.group_id == group_id, Expense.is_deleted == False)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user),
            selectinload(Expense.creator),
            selectinload(Expense.receipts)
        )
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    )
    res = await db.execute(stmt)
    expenses = res.scalars().all()
    return APIResponse(data=[serialize_expense(exp) for exp in expenses])


@router.get("/personal", response_model=APIResponse[List[ExpenseResponse]])
async def list_personal_expenses(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    List non-group expenses involving the current user (as creator, payer, or split participant).
    """
    stmt = (
        select(Expense)
        .where(Expense.group_id.is_(None), Expense.is_deleted == False)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user),
            selectinload(Expense.creator),
            selectinload(Expense.receipts)
        )
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    )
    res = await db.execute(stmt)
    all_personal = res.scalars().all()

    user_expenses = [
        exp for exp in all_personal
        if exp.created_by == current_user.id
        or any(p.user_id == current_user.id for p in exp.payers)
        or any(s.user_id == current_user.id for s in exp.splits)
    ]
    return APIResponse(data=[serialize_expense(exp) for exp in user_expenses])


@router.get("/balances/1on1", response_model=APIResponse[FriendBalanceResponse])
async def get_1on1_balance(
    friend_id: str = Query(..., description="The user ID of the friend"),
    currency: str = Query("USD", min_length=3, max_length=3, description="Currency code"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Returns the exact net bilateral balance between the current user and friend.
    Positive net_balance = friend owes current user.
    Negative net_balance = current user owes friend.
    """
    net_bal = await LedgerService.get_1on1_friend_balances(
        db=db,
        user_id_1=current_user.id,
        user_id_2=friend_id,
        currency=currency.upper()
    )

    if net_bal > Decimal("0"):
        bal_status = "YOU_ARE_OWED"
    elif net_bal < Decimal("0"):
        bal_status = "YOU_OWE"
    else:
        bal_status = "SETTLED"

    resp = FriendBalanceResponse(
        user_id=current_user.id,
        friend_id=friend_id,
        currency=currency.upper(),
        net_balance=net_bal,
        status=bal_status,
        amount=abs(net_bal)
    )
    return APIResponse(data=resp)


from app.core.rate_limit import rate_limit


@router.get(
    "/search",
    response_model=APIResponse[List[ExpenseResponse]],
    dependencies=[Depends(rate_limit(max_requests=60, window_seconds=60, scope="expense_search"))]
)
async def search_expenses(
    q: Optional[str] = Query(None, description="Search term in description or notes"),
    category: Optional[str] = Query(None, description="Category filter"),
    start_date: Optional[date] = Query(None, description="Start date filter"),
    end_date: Optional[date] = Query(None, description="End date filter"),
    min_amount: Optional[Decimal] = Query(None, ge=0, description="Minimum amount"),
    max_amount: Optional[Decimal] = Query(None, ge=0, description="Maximum amount"),
    group_id: Optional[str] = Query(None, description="Group ID filter"),
    has_receipt: Optional[bool] = Query(None, description="Filter by presence of receipts"),
    participant_id: Optional[str] = Query(None, description="Filter by participant user ID"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Search and filter across past expenses.
    EvenBill Pro provides unlimited multi-parameter search & filtering.
    """
    stmt = (
        select(Expense)
        .where(Expense.is_deleted == False)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user),
            selectinload(Expense.creator),
            selectinload(Expense.receipts)
        )
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    )

    if group_id:
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to group expenses")
        stmt = stmt.where(Expense.group_id == group_id)
    else:
        stmt = stmt.where(
            or_(
                Expense.created_by == current_user.id,
                Expense.payers.any(ExpensePayer.user_id == current_user.id),
                Expense.splits.any(ExpenseSplit.user_id == current_user.id)
            )
        )

    if q:
        query_pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Expense.description.ilike(query_pattern),
                Expense.notes.ilike(query_pattern)
            )
        )

    if category:
        stmt = stmt.where(Expense.category.ilike(category.strip()))

    if start_date:
        stmt = stmt.where(Expense.expense_date >= start_date)

    if end_date:
        stmt = stmt.where(Expense.expense_date <= end_date)

    if min_amount is not None:
        stmt = stmt.where(Expense.total_amount >= min_amount)

    if max_amount is not None:
        stmt = stmt.where(Expense.total_amount <= max_amount)

    if participant_id:
        stmt = stmt.where(
            or_(
                Expense.payers.any(ExpensePayer.user_id == participant_id),
                Expense.splits.any(ExpenseSplit.user_id == participant_id)
            )
        )

    if has_receipt is not None:
        if has_receipt:
            stmt = stmt.where(Expense.receipts.any(Receipt.is_deleted == False))
        else:
            stmt = stmt.where(~Expense.receipts.any(Receipt.is_deleted == False))

    res = await db.execute(stmt)
    expenses = res.scalars().all()

    return APIResponse(data=[serialize_expense(e) for e in expenses])


@router.get("/{expense_id}", response_model=APIResponse[ExpenseResponse])
async def get_expense(
    expense_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    expense = await get_expense_with_relations(db, expense_id)
    if not expense or expense.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense not found")

    # Authorization check
    if expense.group_id:
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == expense.group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
    else:
        is_involved = (
            expense.created_by == current_user.id
            or any(p.user_id == current_user.id for p in expense.payers)
            or any(s.user_id == current_user.id for s in expense.splits)
        )
        if not is_involved:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    return APIResponse(data=serialize_expense(expense))


@router.put("/{expense_id}", response_model=APIResponse[ExpenseResponse])
async def update_expense(
    expense_id: str,
    data: ExpenseUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Atomically updates an expense, recalculates splits, increments version, and writes audit record.
    """
    updated = await LedgerService.update_expense(
        db=db,
        user=current_user,
        expense_id=expense_id,
        data=data
    )
    loaded_expense = await get_expense_with_relations(db, updated.id)
    if not loaded_expense:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to load updated expense")

    return APIResponse(data=serialize_expense(loaded_expense))


@router.delete("/{expense_id}", response_model=APIResponse[dict])
async def delete_expense(
    expense_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Soft-deletes an expense so ledger history is preserved and balances recalculate cleanly.
    """
    success = await LedgerService.delete_expense(
        db=db,
        user=current_user,
        expense_id=expense_id
    )
    return APIResponse(data={"deleted": success, "expense_id": expense_id})

