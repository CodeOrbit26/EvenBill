"""
EvenBill Rate Limiting Infrastructure
Implements sliding-window rate limiting for authentication, invitations,
expensive search queries, and receipt uploads.
Returns HTTP 429 Too Many Requests with Retry-After header upon violation.
"""

import time
from typing import Dict, List, Optional
from collections import defaultdict
from fastapi import Request, HTTPException, status
from app.core.config import settings


class SlidingWindowRateLimiter:
    def __init__(self):
        # Maps key -> list of float timestamps
        self._history: Dict[str, List[float]] = defaultdict(list)

    def is_allowed(self, key: str, max_requests: int, window_seconds: int) -> tuple[bool, int]:
        """
        Evaluates whether a request with `key` is allowed within the sliding window.
        Returns (is_allowed, retry_after_seconds).
        """
        now = time.time()
        window_start = now - window_seconds

        # Prune outdated timestamps
        timestamps = [ts for ts in self._history[key] if ts > window_start]
        self._history[key] = timestamps

        if len(timestamps) >= max_requests:
            # Calculate oldest timestamp in current window
            oldest = timestamps[0]
            retry_after = int(max(1, window_seconds - (now - oldest)))
            return False, retry_after

        # Record this request
        self._history[key].append(now)
        return True, 0

    def reset(self):
        """Resets all tracking (useful for unit testing)."""
        self._history.clear()


# Global limiter instance
limiter = SlidingWindowRateLimiter()


def rate_limit(max_requests: int, window_seconds: int, scope: str = "global"):
    """
    FastAPI dependency for endpoint-level rate limiting.
    Uses Client IP for unauthenticated callers, or User-ID if authenticated.
    """
    async def dependency(request: Request):
        if not getattr(settings, "RATE_LIMIT_ENABLED", True):
            return

        # Derive client identifier
        auth_header = request.headers.get("authorization", "")
        client_ip = request.client.host if request.client else "unknown"
        
        # Build rate limit bucket key
        key = f"{scope}:{client_ip}"
        if auth_header.startswith("Bearer "):
            # Key by token substring to rate limit per user session
            key = f"{scope}:{auth_header[-16:]}"

        allowed, retry_after = limiter.is_allowed(key, max_requests, window_seconds)
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Rate limit exceeded. Maximum {max_requests} requests per {window_seconds} seconds permitted for {scope}.",
                headers={"Retry-After": str(retry_after)}
            )

    return dependency
