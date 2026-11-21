"""
EvenBill Structured Logging & Observability Middleware
Implements correlation IDs (X-Correlation-ID), structured JSON logging,
and strict financial & PII redaction (passwords, card numbers, tokens).
"""

import sys
import re
import json
import uuid
import logging
import time
from typing import Any, Dict
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

# Patterns for sensitive financial and PII redaction
REDACTION_PATTERNS = [
    # Passwords and secrets
    (re.compile(r'(["\']?(?:password|secret|token|api_key|access_token|refresh_token)["\']?\s*[:=]\s*["\'])([^"\']+)(["\'])', re.IGNORECASE), r'\1[REDACTED]\3'),
    # Credit Card numbers (13-19 digits, possibly hyphen/space separated)
    (re.compile(r'\b(?:\d[ -]*?){13,19}\b'), '[CARD_REDACTED]'),
    # Authorization header Bearer tokens
    (re.compile(r'Bearer\s+[A-Za-z0-9\-_.~+/]+=*', re.IGNORECASE), 'Bearer [REDACTED_JWT]'),
    # Email addresses in non-user logs
    (re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,7}\b'), '[EMAIL_REDACTED]'),
]


def redact_sensitive_data(text: str) -> str:
    """Masks sensitive authentication credentials, card numbers, and PII."""
    for pattern, replacement in REDACTION_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


class StructuredJsonFormatter(logging.Formatter):
    """Formats log records as JSON with timestamp, level, correlation_id, and message."""
    def format(self, record: logging.LogRecord) -> str:
        log_obj = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "correlation_id": getattr(record, "correlation_id", "none"),
            "message": redact_sensitive_data(record.getMessage())
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)


# Initialize logger
logger = logging.getLogger("evenbill")
logger.setLevel(logging.INFO)
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredJsonFormatter())
    logger.addHandler(handler)


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """
    Assigns or preserves X-Correlation-ID for distributed tracing across services.
    Logs request arrival and completion with duration and status code.
    """
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("x-correlation-id") or str(uuid.uuid4())
        
        # Attach correlation ID to request state
        request.state.correlation_id = correlation_id

        start_time = time.time()
        
        # Process request
        try:
            response: Response = await call_next(request)
        except Exception as exc:
            duration_ms = round((time.time() - start_time) * 1000, 2)
            logger.error(
                f"Unhandled Exception on {request.method} {request.url.path}: {str(exc)} (Duration: {duration_ms}ms)",
                extra={"correlation_id": correlation_id}
            )
            raise exc

        duration_ms = round((time.time() - start_time) * 1000, 2)
        response.headers["X-Correlation-ID"] = correlation_id

        # Redact path query parameters if they contain sensitive tokens
        sanitized_path = redact_sensitive_data(request.url.path)
        logger.info(
            f"{request.method} {sanitized_path} completed status={response.status_code} in {duration_ms}ms",
            extra={"correlation_id": correlation_id}
        )

        return response
