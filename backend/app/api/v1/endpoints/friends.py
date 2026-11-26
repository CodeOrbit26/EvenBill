"""
EvenBill Friends & Bilateral Relationships REST Endpoints
"""

from typing import List, Optional
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
from app.core.money import quantize_currency
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService

router = APIRouter(prefix="/friends", tags=["Friends"])


class FriendItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    email: str
    avatar_url: Optional[str] = None
    net_balance: Decimal
    currency: str
    status: str  # YOU_ARE_OWED, YOU_OWE, SETTLED


class AddFriendRequest(BaseModel):
    email: str


@router.get("/", response_model=APIResponse[List[FriendItem]])
async def list_friends(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    currency = current_user.default_currency or "USD"

    # 1. Discover all distinct active co-members across shared non-archived groups
    shared_group_ids_stmt = (
        select(GroupMember.group_id)
        .join(Group, Group.id == GroupMember.group_id)
        .where(
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
            Group.is_archived == False,
        )
    )
    shared_res = await db.execute(shared_group_ids_stmt)
    group_ids = [row[0] for row in shared_res.fetchall()]

    friend_user_ids = set()

    if group_ids:
        co_members_stmt = select(GroupMember.user_id).where(
            GroupMember.group_id.in_(group_ids),
            GroupMember.user_id != current_user.id,
            GroupMember.is_active == True,
        )
        co_res = await db.execute(co_members_stmt)
        for row in co_res.fetchall():
            friend_user_ids.add(row[0])

    # 2. Discover users from direct (non-group) expenses involving current user
    direct_exp_stmt = (
        select(Expense)
        .where(
            Expense.group_id.is_(None),
            Expense.is_deleted == False,
            or_(
                Expense.created_by == current_user.id,
                Expense.payers.any(ExpensePayer.user_id == current_user.id),
                Expense.splits.any(ExpenseSplit.user_id == current_user.id),
            ),
        )
        .options(selectinload(Expense.payers), selectinload(Expense.splits))
    )
    direct_res = await db.execute(direct_exp_stmt)
    for exp in direct_res.scalars().all():
        uids = {p.user_id for p in exp.payers} | {s.user_id for s in exp.splits}
        if current_user.id in uids:
            for u in uids:
                if u != current_user.id:
                    friend_user_ids.add(u)

    # 3. Discover users from direct settlements
    direct_set_stmt = select(Settlement).where(
        Settlement.group_id.is_(None),
        Settlement.is_deleted == False,
        or_(Settlement.payer_id == current_user.id, Settlement.recipient_id == current_user.id)
    )
    set_res = await db.execute(direct_set_stmt)
    for s in set_res.scalars().all():
        if s.payer_id != current_user.id:
            friend_user_ids.add(s.payer_id)
        if s.recipient_id != current_user.id:
            friend_user_ids.add(s.recipient_id)

    if not friend_user_ids:
        return APIResponse(data=[])

    users_stmt = select(User).where(User.id.in_(list(friend_user_ids)))
    users_res = await db.execute(users_stmt)
    friends = users_res.scalars().all()

    per_counterparty, _, _, _ = await LedgerService.get_direct_bilateral_overview(
        db=db,
        user_id=current_user.id,
        target_currency=currency,
    )

    items: List[FriendItem] = []
    for f in friends:
        net_bal = quantize_currency(per_counterparty.get(f.id, Decimal("0")), currency)
        if net_bal > Decimal("0"):
            bal_status = "YOU_ARE_OWED"
        elif net_bal < Decimal("0"):
            bal_status = "YOU_OWE"
        else:
            bal_status = "SETTLED"

        items.append(
            FriendItem(
                id=f.id,
                name=f.full_name,
                email=f.email,
                avatar_url=f.avatar_url,
                net_balance=net_bal,
                currency=currency,
                status=bal_status
            )
        )

    # Sort friends by name alphabetically
    items.sort(key=lambda x: x.name.lower())
    return APIResponse(data=items)


@router.post("/", response_model=APIResponse[FriendItem], status_code=status.HTTP_201_CREATED)
async def add_friend(
    data: AddFriendRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    target_email = data.email.lower().strip()
    if target_email == current_user.email.lower():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You cannot add yourself as a friend")

    stmt = select(User).where(User.email == target_email)
    res = await db.execute(stmt)
    friend = res.scalar_one_or_none()

    if not friend:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No EvenBill user found with email '{target_email}'. Send them an invitation to join!"
        )

    currency = current_user.default_currency or "USD"
    net_bal = await LedgerService.get_1on1_friend_balances(
        db=db,
        user_id_1=current_user.id,
        user_id_2=friend.id,
        currency=currency
    )

    if net_bal > Decimal("0"):
        bal_status = "YOU_ARE_OWED"
    elif net_bal < Decimal("0"):
        bal_status = "YOU_OWE"
    else:
        bal_status = "SETTLED"

    return APIResponse(data=FriendItem(
        id=friend.id,
        name=friend.full_name,
        email=friend.email,
        avatar_url=friend.avatar_url,
        net_balance=net_bal,
        currency=currency,
        status=bal_status
    ))
