"""
EvenBill API v1 Router Aggregator
"""

from fastapi import APIRouter
from app.api.v1.endpoints import health, auth, groups, expenses, settlements

api_router = APIRouter()

api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(groups.router)
api_router.include_router(expenses.router)
api_router.include_router(settlements.router)
