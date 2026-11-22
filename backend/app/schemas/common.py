"""
EvenBill Common Response Schemas
"""

from typing import Generic, TypeVar, Optional, Any, Annotated
import uuid
from datetime import datetime, timezone
from pydantic import BaseModel, Field, AfterValidator


def validate_uuid_str(v: str) -> str:
    """Validates that a string is a well-formed UUID and normalizes to standard lowercase representation."""
    if v is None:
        return v
    try:
        val = uuid.UUID(str(v).strip())
        return str(val)
    except (ValueError, AttributeError, TypeError):
        raise ValueError(f"Invalid UUID format: '{v}'. Expected 36-character hexadecimal UUID format (e.g. '3fa85f64-5717-4562-b3fc-2c963f66afa6').")


UUIDStr = Annotated[str, AfterValidator(validate_uuid_str)]


DataT = TypeVar("DataT")


class ResponseMeta(BaseModel):
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    version: str = "v1"


class APIResponse(BaseModel, Generic[DataT]):
    success: bool = True
    data: Optional[DataT] = None
    meta: ResponseMeta = Field(default_factory=ResponseMeta)
    error: Optional[str] = None
