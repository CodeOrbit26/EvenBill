"""
EvenBill Production Health, Readiness & Liveness Probes
Provides Kubernetes/Docker orchestration endpoints for high-availability deployments.
"""

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.core.config import settings

router = APIRouter(tags=["System & Reliability"])


@router.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """General service health status."""
    db_status = "connected"
    try:
        await db.execute(text("SELECT 1"))
    except Exception as e:
        db_status = f"unhealthy: {str(e)}"

    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "database": db_status
    }


@router.get("/health/live")
async def liveness_probe():
    """
    Kubernetes Liveness Probe: returns HTTP 200 if the Python process is alive.
    If this probe fails, the orchestrator restarts the container.
    """
    return {
        "status": "alive",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION
    }


@router.get("/health/ready")
async def readiness_probe(db: AsyncSession = Depends(get_db)):
    """
    Kubernetes Readiness Probe: checks database connection.
    If database connectivity is lost, returns HTTP 503 so traffic is temporarily rerouted.
    """
    try:
        await db.execute(text("SELECT 1"))
        return {
            "status": "ready",
            "service": settings.PROJECT_NAME,
            "database": "connected"
        }
    except Exception as exc:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "not_ready",
                "service": settings.PROJECT_NAME,
                "error": f"Database unavailable: {str(exc)}"
            }
        )
