"""
EvenBill Group Pydantic Schemas
"""

from typing import List, Optional, Dict
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict


class GroupCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=150)
    group_type: str = Field(default="OTHER", description="HOME, TRIP, COUPLE, OTHER")
    base_currency: str = Field(default="USD", min_length=3, max_length=3)
    simplify_debts: bool = True


class GroupUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=150)
    group_type: Optional[str] = None
    simplify_debts: Optional[bool] = None
    avatar_url: Optional[str] = None


class GroupMemberResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    full_name: str
    email: str
    avatar_url: Optional[str] = None
    role: str
    joined_at: datetime


class GroupResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    group_type: str
    base_currency: str
    simplify_debts: bool
    invite_code: str
    avatar_url: Optional[str] = None
    created_by: str
    is_archived: bool
    created_at: datetime
    member_count: int = 0


class SimplifiedDebtItem(BaseModel):
    debtor_id: str
    debtor_name: str
    creditor_id: str
    creditor_name: str
    amount: Decimal
    currency: str


class NetBalanceItem(BaseModel):
    user_id: str
    full_name: str
    net_balance: Decimal
    currency: str


class GroupDetailResponse(BaseModel):
    group: GroupResponse
    members: List[GroupMemberResponse]
    net_balances: List[NetBalanceItem]
    simplified_debts: List[SimplifiedDebtItem]
