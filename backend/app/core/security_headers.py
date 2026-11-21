"""
EvenBill Security Headers and CSRF Protection Middleware
Injects HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy,
and enforces CSRF validation on cookie-based state-changing requests.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from fastapi import status
from app.core.config import settings


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # 1. CSRF Protection for cookie-authenticated web sessions
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            # Check if cookie-based authentication is present
            has_auth_cookie = bool(request.cookies.get("access_token") or request.cookies.get("session_id"))
            if has_auth_cookie:
                csrf_cookie = request.cookies.get("csrf_token")
                csrf_header = request.headers.get("x-csrf-token")
                requested_with = request.headers.get("x-requested-with")
                
                # Verify token or custom header protection
                if not (requested_with or (csrf_cookie and csrf_header and csrf_cookie == csrf_header)):
                    return JSONResponse(
                        status_code=status.HTTP_403_FORBIDDEN,
                        content={
                            "success": False,
                            "error": "CSRF validation failed: missing or mismatched CSRF token for cookie session."
                        }
                    )

        # 2. Process downstream request
        response: Response = await call_next(request)

        # 3. Inject strict production-grade security headers
        headers = response.headers
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "DENY"
        headers["X-XSS-Protection"] = "1; mode=block"
        headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=()"
        
        # CSP prevents XSS and malicious framing
        headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: https://storage.evenbill.app; "
            "font-src 'self' data:; "
            "frame-ancestors 'none'; "
            "object-src 'none'; "
            "base-uri 'self';"
        )

        # Enforce HSTS in production or staging environments
        if settings.ENVIRONMENT in ("production", "staging"):
            headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"

        return response
