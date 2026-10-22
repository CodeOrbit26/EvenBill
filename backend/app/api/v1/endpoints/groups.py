"""
EvenBill Group Management REST Endpoints
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.core.security import SecurityUtils
from app.models.user import User
from app.models.group import Group, GroupMember
from app.schemas.group import (
    GroupCreate, GroupResponse, GroupDetailResponse,
    GroupMemberResponse, NetBalanceItem, SimplifiedDebtItem
)
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService

router = APIRouter(prefix="/groups", tags=["Groups"])


@router.post("/", response_model=APIResponse[GroupResponse], status_code=status.HTTP_201_CREATED)
async def create_group(
    data: GroupCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    invite_code = SecurityUtils.generate_invite_code(8)
    group = Group(
        name=data.name.strip(),
        group_type=data.group_type.upper(),
        base_currency=data.base_currency.upper(),
        simplify_debts=data.simplify_debts,
        invite_code=invite_code,
        created_by=current_user.id
    )
    db.add(group)
    await db.flush()

    # Add creator as OWNER member
    member = GroupMember(
        group_id=group.id,
        user_id=current_user.id,
        role="OWNER"
    )
    db.add(member)
    await db.commit()
    await db.refresh(group)

    resp = GroupResponse(
        id=group.id,
        name=group.name,
        group_type=group.group_type,
        base_currency=group.base_currency,
        simplify_debts=group.simplify_debts,
        invite_code=group.invite_code,
        avatar_url=group.avatar_url,
        created_by=group.created_by,
        is_archived=group.is_archived,
        created_at=group.created_at,
        member_count=1
    )
    return APIResponse(data=resp)


@router.get("/", response_model=APIResponse[List[GroupResponse]])
async def list_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Fetch all groups where user is a member
    stmt = (
        select(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(GroupMember.user_id == current_user.id, Group.is_archived == False)
        .options(selectinload(Group.members))
    )
    result = await db.execute(stmt)
    groups = result.scalars().all()

    resp_list = [
        GroupResponse(
            id=g.id,
            name=g.name,
            group_type=g.group_type,
            base_currency=g.base_currency,
            simplify_debts=g.simplify_debts,
            invite_code=g.invite_code,
            avatar_url=g.avatar_url,
            created_by=g.created_by,
            is_archived=g.is_archived,
            created_at=g.created_at,
            member_count=len(g.members)
        )
        for g in groups
    ]
    return APIResponse(data=resp_list)


@router.get("/{group_id}", response_model=APIResponse[GroupDetailResponse])
async def get_group_details(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Verify membership
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not a member of this group")

    # Fetch group with members
    stmt = select(Group).where(Group.id == group_id).options(
        selectinload(Group.members).selectinload(GroupMember.user)
    )
    result = await db.execute(stmt)
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    # Calculate balances and debt simplification
    net_balances, simplified_debts, currency = await LedgerService.get_group_balances(db, group_id)

    # Build member dictionary for name lookup
    members_dict = {m.user.id: m.user.full_name for m in group.members}

    # Format member responses
    member_responses = [
        GroupMemberResponse(
            id=m.id,
            user_id=m.user.id,
            full_name=m.user.full_name,
            email=m.user.email,
            avatar_url=m.user.avatar_url,
            role=m.role,
            joined_at=m.joined_at
        )
        for m in group.members
    ]

    # Format net balance responses
    net_balance_items = [
        NetBalanceItem(
            user_id=uid,
            full_name=members_dict.get(uid, "Unknown User"),
            net_balance=amt,
            currency=currency
        )
        for uid, amt in net_balances.items()
    ]

    # Format simplified debt items
    simplified_items = [
        SimplifiedDebtItem(
            debtor_id=d.debtor_id,
            debtor_name=members_dict.get(d.debtor_id, "Unknown User"),
            creditor_id=d.creditor_id,
            creditor_name=members_dict.get(d.creditor_id, "Unknown User"),
            amount=d.amount,
            currency=d.currency
        )
        for d in simplified_debts
    ]

    group_resp = GroupResponse(
        id=group.id,
        name=group.name,
        group_type=group.group_type,
        base_currency=group.base_currency,
        simplify_debts=group.simplify_debts,
        invite_code=group.invite_code,
        avatar_url=group.avatar_url,
        created_by=group.created_by,
        is_archived=group.is_archived,
        created_at=group.created_at,
        member_count=len(group.members)
    )

    detail_resp = GroupDetailResponse(
        group=group_resp,
        members=member_responses,
        net_balances=net_balance_items,
        simplified_debts=simplified_items
    )
    return APIResponse(data=detail_resp)


@router.post("/join/{invite_code}", response_model=APIResponse[GroupResponse])
async def join_group_by_code(
    invite_code: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Group).where(Group.invite_code == invite_code.upper().strip(), Group.is_archived == False)
    result = await db.execute(stmt)
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid invite code")

    # Check if already a member
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group.id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    existing_member = mem_res.scalar_one_or_none()
    if existing_member:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You are already a member of this group")

    # Add as member
    new_member = GroupMember(
        group_id=group.id,
        user_id=current_user.id,
        role="MEMBER"
    )
    db.add(new_member)
    await db.commit()

    return APIResponse(data=GroupResponse(
        id=group.id,
        name=group.name,
        group_type=group.group_type,
        base_currency=group.base_currency,
        simplify_debts=group.simplify_debts,
        invite_code=group.invite_code,
        avatar_url=group.avatar_url,
        created_by=group.created_by,
        is_archived=group.is_archived,
        created_at=group.created_at,
        member_count=0
    ))
