"""
EvenBill Backend Application Entrypoint
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

from app.core.config import settings
from app.core.security_headers import SecurityHeadersMiddleware
from app.core.logging import CorrelationIdMiddleware
from app.db.session import engine, Base
import app.models  # Ensure all ORM models are registered with Base.metadata
from app.api.v1.router import api_router
from app.api.v1.endpoints import health


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Auto-create tables on startup for development and local testing
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="EvenBill — Secure, International Expense Sharing Platform",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
    lifespan=lifespan
)

# Correlation ID and Structured Logging (outermost)
app.add_middleware(CorrelationIdMiddleware)

# Strict Security Headers & CSRF Middleware
app.add_middleware(SecurityHeadersMiddleware)

# CORS Middleware (narrowly restricted for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["*"],
)

# Validation Error Handler
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors()
    error_msg = "; ".join([f"{'.'.join(str(loc) for loc in err['loc'])}: {err['msg']}" for err in errors])
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "success": False,
            "data": None,
            "error": error_msg,
            "meta": {"version": settings.VERSION}
        }
    )

# Root-level health probes for load balancers / container orchestrators
app.include_router(health.router)

# Mount API Routers
app.include_router(api_router, prefix=settings.API_V1_STR)


@app.get("/")
async def root():
    return {
        "name": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": f"{settings.API_V1_STR}/docs",
        "status": "operational"
    }
