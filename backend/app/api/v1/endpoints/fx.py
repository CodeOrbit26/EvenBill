"""
EvenBill Foreign Exchange (FX) & Multi-Currency Endpoints
Provides audited exchange-rate snapshots, conversion calculations, and rate status transparency.
Preserves original financial amounts unchanged.
"""

from typing import Dict, Any, Optional
from decimal import Decimal
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.fx_service import FXService, FXRateResult, FXConversionResult

router = APIRouter(prefix="/fx", tags=["Currency Conversion & FX"])


class ConvertCurrencyRequest(BaseModel):
    amount: Decimal = Field(..., gt=0, description="Original monetary amount")
    from_currency: str = Field(..., min_length=3, max_length=3, description="ISO 4217 original currency code")
    to_currency: str = Field(..., min_length=3, max_length=3, description="ISO 4217 target currency code")


@router.get("/rate", response_model=APIResponse[FXRateResult])
async def get_exchange_rate(
    from_currency: str = Query(..., min_length=3, max_length=3, description="Source currency, e.g. USD"),
    to_currency: str = Query(..., min_length=3, max_length=3, description="Target currency, e.g. EUR"),
    current_user: User = Depends(get_current_user),
):
    """
    Query current exchange rate between two currencies.
    Includes rate source (ECB reference benchmark), timestamp, and rate status (LIVE, STALE_FALLBACK, UNAVAILABLE).
    """
    result = FXService.get_exchange_rate(from_currency=from_currency, to_currency=to_currency)
    return APIResponse(data=result)


@router.post("/convert", response_model=APIResponse[FXConversionResult])
async def convert_currency(
    data: ConvertCurrencyRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Calculates currency conversion for display while keeping the original amount strictly unchanged.
    Returns conversion metadata including rate, source, timestamp, and rate status.
    """
    result = FXService.convert(
        amount=data.amount,
        from_currency=data.from_currency,
        to_currency=data.to_currency
    )
    return APIResponse(data=result)
