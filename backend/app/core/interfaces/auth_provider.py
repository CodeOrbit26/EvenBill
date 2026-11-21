"""
Authentication Provider Interface
Defines the contract for user registration, authentication, session tokens, and password management.
"""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from pydantic import BaseModel


class AuthTokenBundle(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str
    expires_in: int
    user_id: str


class IAuthProvider(ABC):
    @abstractmethod
    async def authenticate(self, email: str, password: str) -> AuthTokenBundle:
        """Authenticate user credentials and return an access and refresh token bundle."""
        pass

    @abstractmethod
    async def register(self, email: str, password: str, full_name: str) -> Dict[str, Any]:
        """Register a new user identity."""
        pass

    @abstractmethod
    async def refresh_token(self, refresh_token_str: str) -> AuthTokenBundle:
        """Rotate a refresh token and return a refreshed token bundle."""
        pass

    @abstractmethod
    async def verify_email(self, verification_token: str) -> bool:
        """Verify an email confirmation token."""
        pass

