"""
EvenBill Expense Pydantic Schemas
Comprehensive support for Equal, Exact, Percentage, Shares, Adjustments, Itemized splits with Tax/Tip,
and Idempotency protection.
"""

from typing import List, Optional, Dict
from datetime import date, datetime
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict
from app.schemas.common import UUIDStr


class PayerItem(BaseModel):
    user_id: UUIDStr = Field(..., json_schema_extra={"format": "uuid", "example": "4b684cb3-0ea1-4566-b333-e99d79a78bc5"})
    amount_paid: Decimal = Field(..., gt=Decimal("0"))


class SplitItem(BaseModel):
    user_id: UUIDStr = Field(..., json_schema_extra={"format": "uuid", "example": "4b684cb3-0ea1-4566-b333-e99d79a78bc5"})
    owed_amount: Decimal = Field(..., ge=Decimal("0"))
    share_quantity: Optional[Decimal] = None


class ItemizedItemInput(BaseModel):
    description: str = Field(..., min_length=1, max_length=150)
    amount: Decimal = Field(..., gt=Decimal("0"))
    participant_ids: List[UUIDStr] = Field(..., min_length=1, json_schema_extra={"example": ["4b684cb3-0ea1-4566-b333-e99d79a78bc5"]})


class ExpenseCreate(BaseModel):
    idempotency_key: Optional[str] = Field(None, max_length=64)
    transaction_type: str = Field(default="EXPENSE", description="EXPENSE, REIMBURSEMENT, REFUND")
    original_expense_id: Optional[UUIDStr] = Field(None, json_schema_extra={"format": "uuid", "example": "4b684cb3-0ea1-4566-b333-e99d79a78bc5"})

    group_id: Optional[UUIDStr] = Field(None, json_schema_extra={"format": "uuid", "example": "4b684cb3-0ea1-4566-b333-e99d79a78bc5"})
    description: str = Field(..., min_length=1, max_length=255)
    total_amount: Decimal = Field(..., gt=Decimal("0"))
    currency: str = Field(default="USD", min_length=3, max_length=3)
    split_type: str = Field(default="EQUAL", description="EQUAL, EXACT, PERCENTAGE, SHARES, ADJUSTMENT, ITEMIZED")
    category: str = Field(default="GENERAL")
    expense_date: Optional[date] = None
    notes: Optional[str] = None

    # Multi-Currency parameters (optional, defaults to 1.0 or ECB snapshot)
    exchange_rate: Optional[Decimal] = None
    exchange_rate_source: Optional[str] = None

    # Payers: if not provided or empty, defaults to current authenticated user paying 100%
    payers: Optional[List[PayerItem]] = None

    # Splitting parameters depending on split_type:
    # 1. EQUAL: list of participant user IDs
    participant_ids: Optional[List[UUIDStr]] = Field(None, json_schema_extra={"example": ["4b684cb3-0ea1-4566-b333-e99d79a78bc5"]})
    # 2. EXACT: list of SplitItem
    splits: Optional[List[SplitItem]] = None
    # 3. PERCENTAGE: dict of user_id -> percentage (summing to 100)
    percentages: Optional[Dict[str, Decimal]] = None
    # 4. SHARES: dict of user_id -> share weights
    shares: Optional[Dict[str, Decimal]] = None
    # 5. ADJUSTMENT: dict of user_id -> offset amount (+/-)
    adjustments: Optional[Dict[str, Decimal]] = None
    # 6. ITEMIZED: items list + taxes, tips, fees, discounts
    items: Optional[List[ItemizedItemInput]] = None
    tax: Optional[Decimal] = Decimal("0")
    tip: Optional[Decimal] = Decimal("0")
    fee: Optional[Decimal] = Decimal("0")
    discount: Optional[Decimal] = Decimal("0")


class ExpenseUpdate(BaseModel):
    description: Optional[str] = Field(None, min_length=1, max_length=255)
    total_amount: Optional[Decimal] = Field(None, gt=Decimal("0"))
    currency: Optional[str] = Field(None, min_length=3, max_length=3)
    category: Optional[str] = None
    expense_date: Optional[date] = None
    notes: Optional[str] = None
    split_type: Optional[str] = None

    payers: Optional[List[PayerItem]] = None
    participant_ids: Optional[List[UUIDStr]] = Field(None, json_schema_extra={"example": ["4b684cb3-0ea1-4566-b333-e99d79a78bc5"]})
    splits: Optional[List[SplitItem]] = None
    percentages: Optional[Dict[str, Decimal]] = None
    shares: Optional[Dict[str, Decimal]] = None
    adjustments: Optional[Dict[str, Decimal]] = None
    items: Optional[List[ItemizedItemInput]] = None
    tax: Optional[Decimal] = None
    tip: Optional[Decimal] = None
    fee: Optional[Decimal] = None
    discount: Optional[Decimal] = None
    version: Optional[int] = Field(None, ge=1, description="Client resource version for optimistic concurrency control")



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
    idempotency_key: Optional[str] = None
    transaction_type: str = "EXPENSE"
    original_expense_id: Optional[str] = None
    group_id: Optional[str] = None
    created_by: str
    creator_name: Optional[str] = None
    description: str
    total_amount: Decimal
    currency: str
    base_currency_amount: Decimal
    exchange_rate: Decimal
    exchange_rate_source: str = "DEFAULT"
    exchange_rate_timestamp: Optional[datetime] = None
    split_type: str
    category: str
    expense_date: date
    notes: Optional[str] = None
    is_deleted: bool = False
    version: int = 1
    created_at: datetime
    updated_at: Optional[datetime] = None
    payers: List[PayerResponse] = []
    splits: List[SplitResponse] = []
    has_receipt: bool = False
