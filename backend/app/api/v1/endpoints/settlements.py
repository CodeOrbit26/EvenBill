"""
EvenBill Settlement REST Endpoints
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.settlement import Settlement
from app.models.group import GroupMember
from app.schemas.settlement import SettlementCreate, SettlementResponse
from app.schemas.common import APIResponse
from app.services.ledger_service import LedgerService

router = APIRouter(prefix="/settlements", tags=["Settlements"])


@router.post("/", response_model=APIResponse[SettlementResponse], status_code=status.HTTP_201_CREATED)
async def create_settlement(
    data: SettlementCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    settlement = await LedgerService.record_settlement(db, current_user, data)

    # Re-fetch with loaded payer and recipient
    stmt = (
        select(Settlement)
        .where(Settlement.id == settlement.id)
        .options(
            selectinload(Settlement.payer),
            selectinload(Settlement.recipient)
        )
    )
    res = await db.execute(stmt)
    loaded = res.scalar_one()

    resp = SettlementResponse(
        id=loaded.id,
        group_id=loaded.group_id,
        payer_id=loaded.payer_id,
        payer_name=loaded.payer.full_name if loaded.payer else None,
        recipient_id=loaded.recipient_id,
        recipient_name=loaded.recipient.full_name if loaded.recipient else None,
        amount=loaded.amount,
        currency=loaded.currency,
        payment_method=loaded.payment_method,
        transaction_reference=loaded.transaction_reference,
        notes=loaded.notes,
        settled_at=loaded.settled_at
    )
    return APIResponse(data=resp)


@router.get("/group/{group_id}", response_model=APIResponse[List[SettlementResponse]])
async def list_group_settlements(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    mem_stmt = select(GroupMember).where(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user.id
    )
    mem_res = await db.execute(mem_stmt)
    if not mem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    stmt = (
        select(Settlement)
        .where(Settlement.group_id == group_id, Settlement.is_deleted == False)
        .options(
            selectinload(Settlement.payer),
            selectinload(Settlement.recipient)
        )
        .order_by(Settlement.settled_at.desc())
    )
    res = await db.execute(stmt)
    settlements = res.scalars().all()

    resp_list = [
        SettlementResponse(
            id=s.id,
            group_id=s.group_id,
            payer_id=s.payer_id,
            payer_name=s.payer.full_name if s.payer else None,
            recipient_id=s.recipient_id,
            recipient_name=s.recipient.full_name if s.recipient else None,
            amount=s.amount,
            currency=s.currency,
            payment_method=s.payment_method,
            transaction_reference=s.transaction_reference,
            notes=s.notes,
            settled_at=s.settled_at
        )
        for s in settlements
    ]
    return APIResponse(data=resp_list)
