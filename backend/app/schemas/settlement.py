"""
EvenBill Settlement Pydantic Schemas
"""

from typing import Optional
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict


class SettlementCreate(BaseModel):
    group_id: Optional[str] = None
    recipient_id: str = Field(..., description="User ID of the person receiving the payment")
    amount: Decimal = Field(..., gt=Decimal("0"))
    currency: str = Field(default="USD", min_length=3, max_length=3)
    payment_method: str = Field(default="CASH", description="CASH, UPI, PAYPAL, VENMO, WISE, IN_APP")
    transaction_reference: Optional[str] = None
    notes: Optional[str] = None


class SettlementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: Optional[str] = None
    payer_id: str
    payer_name: Optional[str] = None
    recipient_id: str
    recipient_name: Optional[str] = None
    amount: Decimal
    currency: str
    payment_method: str
    transaction_reference: Optional[str] = None
    notes: Optional[str] = None
    settled_at: datetime
