"""
EvenBill Group Split Templates Endpoints
Provides saved default split templates for groups (EvenBill Pro capability).
Allows group members to save recurring split proportions (e.g. 60/40, custom shares)
and set a default split template for new expenses.
"""

from typing import List, Dict, Any, Optional
import json
from datetime import datetime, timezone
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, and_, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.group import Group, GroupMember, GroupSplitTemplate
from app.schemas.common import APIResponse, UUIDStr
from app.services.entitlement_service import EntitlementService, PlanTier, FeatureKey, FeatureLockedException

router = APIRouter(prefix="/groups/{group_id}/split-templates", tags=["Group Split Templates (Pro)"])


class SplitAllocationItem(BaseModel):
    user_id: UUIDStr
    value: float = Field(..., ge=0, description="Percent, share, or exact amount depending on split_type")


class CreateSplitTemplateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    split_type: str = Field(..., description="EQUAL, PERCENTAGE, SHARES, EXACT")
    allocations: List[SplitAllocationItem]
    is_default: bool = False


class UpdateSplitTemplateRequest(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    split_type: Optional[str] = None
    allocations: Optional[List[SplitAllocationItem]] = None
    is_default: Optional[bool] = None


class SplitTemplateResponse(BaseModel):
    id: str
    group_id: str
    name: str
    split_type: str
    allocations: List[Dict[str, Any]]
    is_default: bool
    created_by: str
    created_at: datetime


async def _verify_group_membership(db: AsyncSession, group_id: str, user_id: str) -> Group:
    stmt = (
        select(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(
            Group.id == group_id,
            GroupMember.user_id == user_id,
            GroupMember.is_active == True,
        )
    )
    res = await db.execute(stmt)
    group = res.scalars().first()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not an active member of this group."
        )
    return group


@router.post("", response_model=APIResponse[SplitTemplateResponse], status_code=status.HTTP_201_CREATED)
async def create_split_template(
    group_id: str,
    data: CreateSplitTemplateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Create a saved split template for a group.
    Requires EvenBill Pro subscription.
    """
    await _verify_group_membership(db, group_id, current_user.id)

    plan = await EntitlementService.get_user_plan(db, current_user)
    if plan != PlanTier.PRO:
        raise FeatureLockedException(
            feature_key=FeatureKey.SAVED_SPLIT_TEMPLATES,
            detail="Saved default split templates are an EvenBill Pro feature.",
            plan=plan,
            permitted_next_action="Upgrade to EvenBill Pro to create and save custom group split presets."
        )

    # If this is marked default, unset existing defaults for this group
    if data.is_default:
        await db.execute(
            update(GroupSplitTemplate)
            .where(GroupSplitTemplate.group_id == group_id)
            .values(is_default=False)
        )

    allocations_data = [item.model_dump() for item in data.allocations]

    template = GroupSplitTemplate(
        group_id=group_id,
        created_by=current_user.id,
        name=data.name.strip(),
        split_type=data.split_type.upper().strip(),
        allocations_json=json.dumps(allocations_data),
        is_default=data.is_default,
    )
    db.add(template)
    await db.commit()
    await db.refresh(template)

    return APIResponse(data=SplitTemplateResponse(
        id=template.id,
        group_id=template.group_id,
        name=template.name,
        split_type=template.split_type,
        allocations=allocations_data,
        is_default=template.is_default,
        created_by=template.created_by,
        created_at=template.created_at
    ))


@router.get("", response_model=APIResponse[List[SplitTemplateResponse]])
async def list_split_templates(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    List all saved split templates for the specified group.
    """
    await _verify_group_membership(db, group_id, current_user.id)

    stmt = (
        select(GroupSplitTemplate)
        .where(GroupSplitTemplate.group_id == group_id)
        .order_by(GroupSplitTemplate.is_default.desc(), GroupSplitTemplate.created_at.desc())
    )
    res = await db.execute(stmt)
    templates = res.scalars().all()

    items = []
    for t in templates:
        allocations = json.loads(t.allocations_json) if t.allocations_json else []
        items.append(SplitTemplateResponse(
            id=t.id,
            group_id=t.group_id,
            name=t.name,
            split_type=t.split_type,
            allocations=allocations,
            is_default=t.is_default,
            created_by=t.created_by,
            created_at=t.created_at
        ))

    return APIResponse(data=items)


@router.put("/{template_id}", response_model=APIResponse[SplitTemplateResponse])
async def update_split_template(
    group_id: str,
    template_id: str,
    data: UpdateSplitTemplateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update a saved split template.
    """
    await _verify_group_membership(db, group_id, current_user.id)

    stmt = select(GroupSplitTemplate).where(
        GroupSplitTemplate.id == template_id,
        GroupSplitTemplate.group_id == group_id
    )
    res = await db.execute(stmt)
    template = res.scalar_one_or_none()
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Split template not found.")

    if data.is_default is True:
        await db.execute(
            update(GroupSplitTemplate)
            .where(GroupSplitTemplate.group_id == group_id)
            .values(is_default=False)
        )
        template.is_default = True
    elif data.is_default is False:
        template.is_default = False

    if data.name is not None:
        template.name = data.name.strip()
    if data.split_type is not None:
        template.split_type = data.split_type.upper().strip()
    if data.allocations is not None:
        template.allocations_json = json.dumps([item.model_dump() for item in data.allocations])

    await db.commit()
    await db.refresh(template)

    allocations = json.loads(template.allocations_json) if template.allocations_json else []
    return APIResponse(data=SplitTemplateResponse(
        id=template.id,
        group_id=template.group_id,
        name=template.name,
        split_type=template.split_type,
        allocations=allocations,
        is_default=template.is_default,
        created_by=template.created_by,
        created_at=template.created_at
    ))


@router.delete("/{template_id}", response_model=APIResponse[Dict[str, Any]])
async def delete_split_template(
    group_id: str,
    template_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete a saved split template.
    """
    await _verify_group_membership(db, group_id, current_user.id)

    stmt = select(GroupSplitTemplate).where(
        GroupSplitTemplate.id == template_id,
        GroupSplitTemplate.group_id == group_id
    )
    res = await db.execute(stmt)
    template = res.scalar_one_or_none()
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Split template not found.")

    if template.created_by != current_user.id:
        mem_stmt = select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == current_user.id,
            GroupMember.role.in_(["OWNER", "ADMIN"]),
            GroupMember.is_active == True,
        )
        mem_res = await db.execute(mem_stmt)
        if not mem_res.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the template creator or a group admin can delete this template."
            )

    await db.delete(template)
    await db.commit()

    return APIResponse(data={"deleted": True, "template_id": template_id})
