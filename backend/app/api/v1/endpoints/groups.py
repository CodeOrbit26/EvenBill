"""
EvenBill Group Management REST Endpoints
"""

import uuid
from decimal import Decimal
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, DBAPIError
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.core.security import SecurityUtils
from app.models.user import User
from app.models.group import Group, GroupMember, GroupInvitation
from app.models.pending_participant import GroupPendingParticipant
from app.schemas.group import (
    GroupCreate, GroupUpdate, GroupResponse, GroupDetailResponse,
    GroupMemberAdd, GroupMemberResponse, NetBalanceItem, SimplifiedDebtItem, BilateralDebtItem,
    GroupInvitationCreate, GroupInvitationResponse
)
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService
from app.services.auth_service import AuthService

router = APIRouter(prefix="/groups", tags=["Groups"])


def _build_group_response(
    group: Group,
    *,
    member_count: int,
    net_balance: Decimal = Decimal("0"),
) -> GroupResponse:
    return GroupResponse(
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
        member_count=member_count,
        net_balance=net_balance,
    )


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

    return APIResponse(data=_build_group_response(group, member_count=1))


@router.get("/", response_model=APIResponse[List[GroupResponse]])
async def list_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Fetch all non-archived groups where user is an active member
    stmt = (
        select(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(
            GroupMember.user_id == current_user.id,
            GroupMember.is_active == True,
            Group.is_archived == False,
        )
        .options(selectinload(Group.members))
    )
    result = await db.execute(stmt)
    groups = result.scalars().all()

    batch_balances = await LedgerService.get_groups_net_balances_batch(db, list(groups))

    resp_list: List[GroupResponse] = []
    for g in groups:
        net_bals, _ = batch_balances.get(g.id, ({}, g.base_currency))
        my_net = net_bals.get(current_user.id, Decimal("0"))
        active_member_count = sum(1 for m in g.members if m.is_active)
        resp_list.append(
            _build_group_response(
                g,
                member_count=active_member_count,
                net_balance=my_net,
            )
        )
    return APIResponse(data=resp_list)


@router.get("/{group_id}", response_model=APIResponse[GroupDetailResponse])
async def get_group_details(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # Verify active membership
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not an active member of this group")

    # Fetch group with members
    stmt = select(Group).where(Group.id == group_id).options(
        selectinload(Group.members).selectinload(GroupMember.user)
    )
    result = await db.execute(stmt)
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    # Calculate balances and debt simplification
    net_balances, simplified_debts, bilateral_debts, currency = await LedgerService.get_group_balances(db, group_id)

    # Build member dictionary for name lookup (includes former members so historical balances preserve names)
    members_dict = {m.user.id: m.user.full_name for m in group.members}

    active_members = [m for m in group.members if m.is_active]

    # Format active member responses
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
        for m in active_members
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

    # Format bilateral debt items
    bilateral_items = [
        BilateralDebtItem(
            debtor_id=b.debtor_id,
            debtor_name=members_dict.get(b.debtor_id, "Unknown User"),
            creditor_id=b.creditor_id,
            creditor_name=members_dict.get(b.creditor_id, "Unknown User"),
            amount=b.amount,
            currency=b.currency
        )
        for b in bilateral_debts
    ]

    group_resp = _build_group_response(
        group,
        member_count=len(active_members),
        net_balance=net_balances.get(current_user.id, Decimal("0")),
    )

    detail_resp = GroupDetailResponse(
        group=group_resp,
        members=member_responses,
        net_balances=net_balance_items,
        simplified_debts=simplified_items,
        bilateral_debts=bilateral_items
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

    # Check if already a member (reactivate if previously deactivated)
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group.id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    existing_member = mem_res.scalar_one_or_none()
    if existing_member:
        if existing_member.is_active:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="You are already a member of this group")
        existing_member.is_active = True
    else:
        db.add(
            GroupMember(
                group_id=group.id,
                user_id=current_user.id,
                role="MEMBER",
            )
        )
    try:
        await db.commit()
    except (IntegrityError, DBAPIError):
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Conflict joining group: membership or claim already exists."
        )

    net_bals, _, _, _ = await LedgerService.get_group_balances(db, group.id)
    members_res = await db.execute(
        select(GroupMember).where(
            GroupMember.group_id == group.id,
            GroupMember.is_active == True,
        )
    )
    return APIResponse(
        data=_build_group_response(
            group,
            member_count=len(members_res.scalars().all()),
            net_balance=net_bals.get(current_user.id, Decimal("0")),
        )
    )


@router.post("/{group_id}/members", response_model=APIResponse[GroupMemberResponse], status_code=status.HTTP_201_CREATED)
async def add_group_member(
    group_id: str,
    data: GroupMemberAdd,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Directly add an existing user or a named offline member to a group."""
    grp_res = await db.execute(select(Group).where(Group.id == group_id, Group.is_archived == False))
    group = grp_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    caller_res = await db.execute(select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    ))
    if not caller_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: Not an active member of this group")

    clean_name = data.full_name.strip()
    if not clean_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Member name cannot be empty")
    clean_email = data.email.strip().lower() if data.email and data.email.strip() else None
    clean_phone = data.phone_number.strip() if data.phone_number and data.phone_number.strip() else None

    target_user = None
    if clean_email:
        u_res = await db.execute(select(User).where(User.email == clean_email))
        target_user = u_res.scalar_one_or_none()
    if not target_user and clean_phone:
        u_res = await db.execute(select(User).where(User.phone_number == clean_phone))
        target_user = u_res.scalar_one_or_none()

    if target_user:
        existing_mem = (await db.execute(select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == target_user.id
        ))).scalar_one_or_none()
        if existing_mem:
            if existing_mem.is_active:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="User is already a member of this group")
            existing_mem.is_active = True
            await db.commit()
            await db.refresh(existing_mem)
            return APIResponse(data=GroupMemberResponse(
                id=existing_mem.id,
                user_id=target_user.id,
                full_name=target_user.full_name,
                email=target_user.email,
                avatar_url=target_user.avatar_url,
                role=existing_mem.role,
                joined_at=existing_mem.joined_at,
            ))
    else:
        if not clean_email and not clean_phone:
            dup_stmt = (
                select(GroupMember)
                .join(User, User.id == GroupMember.user_id)
                .where(
                    GroupMember.group_id == group_id,
                    GroupMember.is_active == True,
                    User.full_name.ilike(clean_name),
                )
            )
            dup_res = await db.execute(dup_stmt)
            if dup_res.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="A member with this name is already in the group (add email or phone to distinguish)"
                )

        # Synthetic domain keeps future real signups with clean_email free of 409 collisions.
        synthetic_email = f"member.{uuid.uuid4().hex[:12]}@member.evenbill.local"
        user_id = str(uuid.uuid4())

        has_auth = await AuthService._check_auth_users_exists(db)
        if has_auth:
            await AuthService._insert_auth_user(
                db=db,
                user_id=user_id,
                email=synthetic_email,
                hashed_pw=None,
                full_name=clean_name,
                default_currency=group.base_currency,
            )

        p_stmt = select(User).where(User.id == user_id)
        p_res = await db.execute(p_stmt)
        target_user = p_res.scalar_one_or_none()

        if not target_user:
            target_user = User(
                id=user_id,
                email=synthetic_email,
                hashed_password=None,
                full_name=clean_name,
                phone_number=clean_phone,
                default_currency=group.base_currency,
                is_active=True,
                is_verified=False,
            )
            db.add(target_user)
            await db.flush()
        else:
            target_user.full_name = clean_name
            target_user.phone_number = clean_phone
            target_user.default_currency = group.base_currency
            await db.flush()

        if clean_email or clean_phone:
            db.add(GroupPendingParticipant(
                group_id=group.id,
                display_name=clean_name,
                email=clean_email,
                phone_number=clean_phone,
                status="ACTIVE",
            ))

    new_member = GroupMember(
        group_id=group.id,
        user_id=target_user.id,
        role="MEMBER",
    )
    db.add(new_member)
    try:
        await db.commit()
        await db.refresh(new_member)
    except (IntegrityError, DBAPIError):
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Conflict adding member: user may already be a member or concurrently added."
        )

    return APIResponse(data=GroupMemberResponse(
        id=new_member.id,
        user_id=target_user.id,
        full_name=target_user.full_name,
        email=target_user.email,
        avatar_url=target_user.avatar_url,
        role=new_member.role,
        joined_at=new_member.joined_at,
    ))


@router.put("/{group_id}", response_model=APIResponse[GroupResponse])
async def update_group(
    group_id: str,
    data: GroupUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    group_stmt = select(Group).where(Group.id == group_id, Group.is_archived == False).options(selectinload(Group.members))
    group_res = await db.execute(group_stmt)
    group = group_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    if data.name is not None:
        group.name = data.name.strip()
    if data.group_type is not None:
        group.group_type = data.group_type.upper().strip()
    if data.simplify_debts is not None:
        group.simplify_debts = data.simplify_debts
    if data.avatar_url is not None:
        group.avatar_url = data.avatar_url.strip()

    await db.commit()
    await db.refresh(group)

    net_bals, _, _, _ = await LedgerService.get_group_balances(db, group.id)
    return APIResponse(
        data=_build_group_response(
            group,
            member_count=sum(1 for m in group.members if m.is_active),
            net_balance=net_bals.get(current_user.id, Decimal("0")),
        )
    )


@router.delete("/{group_id}", response_model=APIResponse[dict])
async def delete_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.role.in_(["OWNER", "ADMIN"]),
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only owners or admins can delete this group")

    group_stmt = select(Group).where(Group.id == group_id)
    group_res = await db.execute(group_stmt)
    group = group_res.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    group.is_archived = True
    await db.commit()
    return APIResponse(data={"deleted": True, "group_id": group_id})


from app.core.rate_limit import rate_limit


@router.post(
    "/{group_id}/invitations",
    response_model=APIResponse[GroupInvitationResponse],
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit(max_requests=25, window_seconds=3600, scope="create_invitation"))]
)
async def create_invitation(
    group_id: str,
    data: GroupInvitationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    invitation = GroupInvitation(
        group_id=group_id,
        email=data.email.lower().strip(),
        invited_by=current_user.id,
        status="PENDING"
    )
    db.add(invitation)
    await db.commit()
    await db.refresh(invitation)

    return APIResponse(data=GroupInvitationResponse(
        id=invitation.id,
        group_id=invitation.group_id,
        email=invitation.email,
        invited_by=invitation.invited_by,
        inviter_name=current_user.full_name,
        status=invitation.status,
        created_at=invitation.created_at,
        expires_at=invitation.expires_at
    ))


@router.get("/{group_id}/invitations", response_model=APIResponse[List[GroupInvitationResponse]])
async def list_invitations(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id,
        GroupMember.is_active == True,
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)

    inv_stmt = select(GroupInvitation).where(GroupInvitation.group_id == group_id).options(selectinload(GroupInvitation.inviter))
    inv_res = await db.execute(inv_stmt)
    invitations = inv_res.scalars().all()

    resp_list = []
    for inv in invitations:
        # Check if expired
        st = inv.status
        exp_at = inv.expires_at
        if exp_at and exp_at.tzinfo is None:
            exp_at = exp_at.replace(tzinfo=timezone.utc)
        if st == "PENDING" and exp_at and exp_at < now:
            st = "EXPIRED"

        resp_list.append(GroupInvitationResponse(
            id=inv.id,
            group_id=inv.group_id,
            email=inv.email,
            invited_by=inv.invited_by,
            inviter_name=inv.inviter.full_name if inv.inviter else None,
            status=st,
            created_at=inv.created_at,
            expires_at=inv.expires_at
        ))
    return APIResponse(data=resp_list)


@router.post("/invitations/{invitation_id}/revoke", response_model=APIResponse[dict])
async def revoke_invitation(
    invitation_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(GroupInvitation).where(GroupInvitation.id == invitation_id)
    res = await db.execute(stmt)
    inv = res.scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invitation not found")

    # IDOR protection: only the original inviter or a group OWNER/ADMIN can revoke
    is_inviter = inv.invited_by == current_user.id
    if not is_inviter:
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == inv.group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role.in_(["OWNER", "ADMIN"]),
            GroupMember.is_active == True,
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to revoke this invitation")

    inv.status = "REVOKED"
    await db.commit()
    return APIResponse(data={"revoked": True, "invitation_id": invitation_id})


@router.post("/invitations/{invitation_id}/accept", response_model=APIResponse[dict])
async def accept_invitation(
    invitation_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    from datetime import datetime, timezone
    stmt = select(GroupInvitation).where(GroupInvitation.id == invitation_id)
    res = await db.execute(stmt)
    inv = res.scalar_one_or_none()
    if not inv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invitation not found")

    if inv.status == "ACCEPTED":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This invitation has already been accepted")

    if inv.status == "REVOKED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This invitation has been revoked")

    exp_at = inv.expires_at
    if exp_at and exp_at.tzinfo is None:
        exp_at = exp_at.replace(tzinfo=timezone.utc)

    if exp_at and exp_at < datetime.now(timezone.utc):
        inv.status = "EXPIRED"
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This invitation has expired")

    # IDOR / Interception protection: current user email must match invitation target email
    if current_user.email.lower().strip() != inv.email.lower().strip():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This invitation was issued to a different email address"
        )

    # Add as member (or reactivate deactivated membership)
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == inv.group_id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    existing_mem = mem_res.scalar_one_or_none()
    if not existing_mem:
        db.add(GroupMember(group_id=inv.group_id, user_id=current_user.id, role="MEMBER"))
    elif not existing_mem.is_active:
        existing_mem.is_active = True

    inv.status = "ACCEPTED"
    try:
        await db.commit()
    except (IntegrityError, DBAPIError):
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Conflict accepting invitation: already accepted or member already in group."
        )
    return APIResponse(data={"accepted": True, "group_id": inv.group_id})

