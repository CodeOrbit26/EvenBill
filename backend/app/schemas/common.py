"""
EvenBill Common Response Schemas
"""

from typing import Generic, TypeVar, Optional, Any
from datetime import datetime, timezone
from pydantic import BaseModel, Field

DataT = TypeVar("DataT")


class ResponseMeta(BaseModel):
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    version: str = "v1"


class APIResponse(BaseModel, Generic[DataT]):
    success: bool = True
    data: Optional[DataT] = None
    meta: ResponseMeta = Field(default_factory=ResponseMeta)
    error: Optional[str] = None
