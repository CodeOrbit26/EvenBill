"""
EvenBill Supabase JWT Cryptographic Verification Module
Supports asymmetric JWKS key rotation (ES256, RS256) and symmetric fallback (HS256).
Enforces signature, audience, issuer, expiration, and subject claims.
"""

import logging
from typing import Dict, Any, Optional
import jwt
from jwt import PyJWKClient, PyJWKClientError
from fastapi import HTTPException, status
from app.core.config import settings

logger = logging.getLogger(__name__)


class SupabaseJWTVerifier:
    _jwks_client: Optional[PyJWKClient] = None

    @classmethod
    def get_jwks_client(cls) -> PyJWKClient:
        """Returns or initializes the thread-safe cached PyJWKClient."""
        if cls._jwks_client is None:
            cls._jwks_client = PyJWKClient(
                settings.supabase_jwks_url,
                cache_keys=True,
                max_cached_keys=16,
                cache_jwk_set=True,
                lifespan=3600  # 1 hour cache
            )
        return cls._jwks_client

    @classmethod
    def verify_token(cls, token: str) -> Dict[str, Any]:
        """
        Cryptographically verifies an incoming Bearer token:
        1. Inspects unverified header for algorithm and key ID (kid)
        2. Resolves public key from Supabase JWKS (handling rotation automatically)
        3. Enforces signature, expiration, issuer, and audience
        4. Supports fallback to symmetric verification for test tokens
        """
        try:
            unverified_header = jwt.get_unverified_header(token)
            alg = unverified_header.get("alg")
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Malformed token header: {str(e)}",
                headers={"WWW-Authenticate": "Bearer"}
            )

        # Asymmetric verification via Supabase JWKS
        if alg in ["ES256", "RS256", "EdDSA"]:
            key = None
            try:
                jwks = cls.get_jwks_client()
                signing_key = jwks.get_signing_key_from_jwt(token)
                key = signing_key.key
            except PyJWKClientError:
                # Key rotation / cache miss: refresh JWKS and retry once
                try:
                    cls._jwks_client = PyJWKClient(
                        settings.supabase_jwks_url,
                        cache_keys=True,
                        lifespan=3600
                    )
                    signing_key = cls._jwks_client.get_signing_key_from_jwt(token)
                    key = signing_key.key
                except Exception as retry_err:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail=f"Unable to resolve Supabase signing key: {str(retry_err)}",
                        headers={"WWW-Authenticate": "Bearer"}
                    )
            except Exception as e:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Error retrieving token signing key: {str(e)}",
                    headers={"WWW-Authenticate": "Bearer"}
                )

            try:
                payload = jwt.decode(
                    token,
                    key,
                    algorithms=[alg],
                    audience=settings.SUPABASE_AUDIENCE,
                    issuer=settings.supabase_issuer,
                    options={"require": ["exp", "sub", "aud", "iss"]}
                )
                return payload
            except jwt.ExpiredSignatureError:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Token has expired",
                    headers={"WWW-Authenticate": "Bearer"}
                )
            except jwt.InvalidAudienceError:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Invalid token audience (expected '{settings.SUPABASE_AUDIENCE}')",
                    headers={"WWW-Authenticate": "Bearer"}
                )
            except jwt.InvalidIssuerError:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Invalid token issuer (expected '{settings.supabase_issuer}')",
                    headers={"WWW-Authenticate": "Bearer"}
                )
            except jwt.PyJWTError as e:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Cryptographic signature verification failed: {str(e)}",
                    headers={"WWW-Authenticate": "Bearer"}
                )

        # Symmetric fallback (HS256) for local development, tests, or legacy tokens
        secret = settings.SUPABASE_JWT_SECRET or settings.SECRET_KEY
        try:
            payload = jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"verify_aud": False}
            )
            return payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
                headers={"WWW-Authenticate": "Bearer"}
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Could not validate credentials: {str(e)}",
                headers={"WWW-Authenticate": "Bearer"}
            )
