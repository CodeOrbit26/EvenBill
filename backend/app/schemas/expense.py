"""
EvenBill Expense Pydantic Schemas
"""

from typing import List, Optional, Dict
from datetime import date, datetime
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict


class PayerItem(BaseModel):
    user_id: str
    amount_paid: Decimal = Field(..., gt=Decimal("0"))


class SplitItem(BaseModel):
    user_id: str
    owed_amount: Decimal = Field(..., ge=Decimal("0"))
    share_quantity: Optional[Decimal] = None


class ExpenseCreate(BaseModel):
    group_id: Optional[str] = None
    description: str = Field(..., min_length=1, max_length=255)
    total_amount: Decimal = Field(..., gt=Decimal("0"))
    currency: str = Field(default="USD", min_length=3, max_length=3)
    split_type: str = Field(default="EQUAL", description="EQUAL, EXACT, PERCENTAGE, SHARES, ITEMIZED")
    category: str = Field(default="GENERAL")
    expense_date: Optional[date] = None
    notes: Optional[str] = None

    payers: Optional[List[PayerItem]] = None
    participant_ids: Optional[List[str]] = None
    splits: Optional[List[SplitItem]] = None
    percentages: Optional[Dict[str, Decimal]] = None
    shares: Optional[Dict[str, Decimal]] = None


class PayerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: str
    full_name: str
    amount_paid: Decimal


class SplitResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: str
    full_name: str
    owed_amount: Decimal
    share_quantity: Optional[Decimal] = None


class ExpenseResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: Optional[str] = None
    created_by: str
    creator_name: Optional[str] = None
    description: str
    total_amount: Decimal
    currency: str
    base_currency_amount: Decimal
    exchange_rate: Decimal
    split_type: str
    category: str
    expense_date: date
    notes: Optional[str] = None
    version: int
    created_at: datetime
    payers: List[PayerResponse] = []
    splits: List[SplitResponse] = []
