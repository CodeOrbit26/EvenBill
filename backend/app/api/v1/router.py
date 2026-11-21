"""
EvenBill API v1 Router Aggregator
"""

from fastapi import APIRouter
from app.api.v1.endpoints import (
    health, auth, users, groups, expenses, settlements, friends,
    activity, subscriptions, receipts, split_templates, analytics, fx, bank
)

api_router = APIRouter()

api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(groups.router)
api_router.include_router(expenses.router)
api_router.include_router(settlements.router)
api_router.include_router(friends.router)
api_router.include_router(activity.router)
api_router.include_router(subscriptions.router)
api_router.include_router(receipts.router)
api_router.include_router(split_templates.router)
api_router.include_router(analytics.router)
api_router.include_router(fx.router)
api_router.include_router(bank.router)


