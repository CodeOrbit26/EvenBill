"""
EvenBill User and Subscription Pydantic Schemas
"""

from typing import Optional
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, description="Minimum 8 characters")
    full_name: str = Field(..., min_length=1, max_length=120)
    phone_number: Optional[str] = Field(None, max_length=32, description="Optional phone number")
    default_currency: str = Field(default="USD", min_length=3, max_length=3)

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters long")
        if not any(char.isdigit() for char in v):
            raise ValueError("Password must contain at least one numeral")
        if not any(char.isalpha() for char in v):
            raise ValueError("Password must contain at least one alphabetical letter")
        return v


class UserLogin(BaseModel):
    email: str = Field(..., description="Email address or phone number")
    password: str


class OAuthLoginRequest(BaseModel):
    provider: str = Field(..., description="OAuth provider: google, apple")
    id_token: Optional[str] = Field(None, description="ID token or authorization credential")
    email: Optional[EmailStr] = Field(None, description="User email address")
    full_name: Optional[str] = Field(None, description="User full name")
    avatar_url: Optional[str] = Field(None, description="Profile avatar URL")
    phone_number: Optional[str] = Field(None, description="User phone number")
    password: Optional[str] = Field(None, min_length=8, description="Optional password to enable direct writing-in login")


class SetPasswordRequest(BaseModel):
    password: str = Field(..., min_length=8, description="Password (min 8 characters)")
    phone_number: Optional[str] = Field(None, max_length=32)
    full_name: Optional[str] = Field(None, max_length=120)


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=120)
    phone_number: Optional[str] = Field(None, max_length=32)
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
    has_password: bool = False
    is_pro: bool = False
    created_at: datetime


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshTokenRequest(BaseModel):
    refresh_token: str
