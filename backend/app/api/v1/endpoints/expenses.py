"""
EvenBill Expense REST Endpoints
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.expense import Expense, ExpensePayer, ExpenseSplit
from app.models.group import GroupMember
from app.schemas.expense import (
    ExpenseCreate, ExpenseResponse, PayerResponse, SplitResponse
)
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService

router = APIRouter(prefix="/expenses", tags=["Expenses"])


@router.post("/", response_model=APIResponse[ExpenseResponse], status_code=status.HTTP_201_CREATED)
async def create_expense(
    data: ExpenseCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    expense = await LedgerService.create_expense(db, current_user, data)

    # Re-fetch with relationships loaded
    stmt = (
        select(Expense)
        .where(Expense.id == expense.id)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user)
        )
    )
    res = await db.execute(stmt)
    loaded_expense = res.scalar_one()

    payers_resp = [
        PayerResponse(
            user_id=p.user_id,
            full_name=p.user.full_name if p.user else "User",
            amount_paid=p.amount_paid
        )
        for p in loaded_expense.payers
    ]
    splits_resp = [
        SplitResponse(
            user_id=s.user_id,
            full_name=s.user.full_name if s.user else "User",
            owed_amount=s.owed_amount,
            share_quantity=s.share_quantity
        )
        for s in loaded_expense.splits
    ]

    resp = ExpenseResponse(
        id=loaded_expense.id,
        group_id=loaded_expense.group_id,
        created_by=loaded_expense.created_by,
        creator_name=current_user.full_name,
        description=loaded_expense.description,
        total_amount=loaded_expense.total_amount,
        currency=loaded_expense.currency,
        base_currency_amount=loaded_expense.base_currency_amount,
        exchange_rate=loaded_expense.exchange_rate,
        split_type=loaded_expense.split_type,
        category=loaded_expense.category,
        expense_date=loaded_expense.expense_date,
        notes=loaded_expense.notes,
        version=loaded_expense.version,
        created_at=loaded_expense.created_at,
        payers=payers_resp,
        splits=splits_resp
    )
    return APIResponse(data=resp)


@router.get("/group/{group_id}", response_model=APIResponse[List[ExpenseResponse]])
async def list_group_expenses(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Verify group membership
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    stmt = (
        select(Expense)
        .where(Expense.group_id == group_id, Expense.is_deleted == False)
        .options(
            selectinload(Expense.payers).selectinload(ExpensePayer.user),
            selectinload(Expense.splits).selectinload(ExpenseSplit.user)
        )
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    )
    res = await db.execute(stmt)
    expenses = res.scalars().all()

    resp_list = []
    for exp in expenses:
        resp_list.append(
            ExpenseResponse(
                id=exp.id,
                group_id=exp.group_id,
                created_by=exp.created_by,
                description=exp.description,
                total_amount=exp.total_amount,
                currency=exp.currency,
                base_currency_amount=exp.base_currency_amount,
                exchange_rate=exp.exchange_rate,
                split_type=exp.split_type,
                category=exp.category,
                expense_date=exp.expense_date,
                notes=exp.notes,
                version=exp.version,
                created_at=exp.created_at,
                payers=[
                    PayerResponse(
                        user_id=p.user_id,
                        full_name=p.user.full_name if p.user else "User",
                        amount_paid=p.amount_paid
                    )
                    for p in exp.payers
                ],
                splits=[
                    SplitResponse(
                        user_id=s.user_id,
                        full_name=s.user.full_name if s.user else "User",
                        owed_amount=s.owed_amount,
                        share_quantity=s.share_quantity
                    )
                    for s in exp.splits
                ]
            )
        )
    return APIResponse(data=resp_list)
