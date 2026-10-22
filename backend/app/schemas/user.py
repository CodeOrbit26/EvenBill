"""
EvenBill User and Subscription Pydantic Schemas
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field, ConfigDict


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, description="Minimum 8 characters")
    full_name: str = Field(..., min_length=1, max_length=120)
    default_currency: str = Field(default="USD", min_length=3, max_length=3)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=120)
    default_currency: Optional[str] = Field(None, min_length=3, max_length=3)
    avatar_url: Optional[str] = None


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    full_name: str
    phone_number: Optional[str] = None
    avatar_url: Optional[str] = None
    default_currency: str
    is_active: bool
    is_verified: bool
    is_pro: bool = False
    created_at: datetime


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshTokenRequest(BaseModel):
    refresh_token: str
