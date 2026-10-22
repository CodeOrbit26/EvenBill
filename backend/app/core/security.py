"""
EvenBill Security & Cryptography Module
Handles password hashing, JWT token lifecycle, refresh tokens, and invite tokens.
"""

import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
import bcrypt
import jwt

class SecurityUtils:
    @staticmethod
    def hash_password(plain_password: str) -> str:
        """Hashes a password with a random bcrypt salt."""
        password_bytes = plain_password.encode("utf-8")
        salt = bcrypt.gensalt(rounds=12)
        hashed = bcrypt.hashpw(password_bytes, salt)
        return hashed.decode("utf-8")

    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        """Verifies a plain password against the stored bcrypt hash."""
        try:
            return bcrypt.checkpw(
                plain_password.encode("utf-8"),
                hashed_password.encode("utf-8")
            )
        except Exception:
            return False

    @staticmethod
    def create_access_token(
        subject: str,
        secret_key: str,
        algorithm: str = "HS256",
        expires_delta: Optional[timedelta] = None,
        extra_claims: Optional[Dict[str, Any]] = None
    ) -> str:
        """Creates a signed JSON Web Token for user session authentication."""
        now = datetime.now(timezone.utc)
        if expires_delta:
            expire = now + expires_delta
        else:
            expire = now + timedelta(minutes=15)

        payload = {
            "sub": str(subject),
            "iat": now,
            "exp": expire,
            "type": "access",
            "jti": secrets.token_hex(16)
        }
        if extra_claims:
            payload.update(extra_claims)

        return jwt.encode(payload, secret_key, algorithm=algorithm)

    @staticmethod
    def create_refresh_token(
        subject: str,
        secret_key: str,
        algorithm: str = "HS256",
        expires_delta: Optional[timedelta] = None
    ) -> str:
        """Creates a signed refresh token with extended TTL."""
        now = datetime.now(timezone.utc)
        if expires_delta:
            expire = now + expires_delta
        else:
            expire = now + timedelta(days=30)

        payload = {
            "sub": str(subject),
            "iat": now,
            "exp": expire,
            "type": "refresh",
            "jti": secrets.token_hex(16)
        }
        return jwt.encode(payload, secret_key, algorithm=algorithm)

    @staticmethod
    def decode_token(
        token: str,
        secret_key: str,
        algorithms: list = ["HS256"]
    ) -> Dict[str, Any]:
        """Decodes and cryptographically verifies a JWT token."""
        return jwt.decode(token, secret_key, algorithms=algorithms)

    @staticmethod
    def generate_invite_code(length: int = 8) -> str:
        """Generates a secure, human-friendly alphanumeric invite code."""
        # Exclude easily confused characters: 0/O, 1/I/l
        alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
        return "".join(secrets.choice(alphabet) for _ in range(length))
