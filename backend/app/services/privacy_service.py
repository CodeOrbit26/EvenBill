"""
EvenBill Privacy & Compliance Service
Handles GDPR/CCPA data export, right-to-be-forgotten account anonymization,
statutory audit retention, and ledger preservation invariants.
"""

from typing import Dict, Any
from datetime import datetime, timezone
import json
from sqlalchemy import select, update, or_
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User, Subscription, RevokedToken
from app.models.group import Group, GroupMember
from app.models.expense import Expense, ExpensePayer, ExpenseSplit, Receipt
from app.models.settlement import Settlement
from app.models.audit import FinancialAuditLog


class PrivacyService:
    @staticmethod
    async def export_user_data(db: AsyncSession, user: User) -> Dict[str, Any]:
        """
        Compiles all personal and financial data related to the user
        into a portable JSON format adhering to GDPR Article 20 / CCPA portability.
        """
        # 1. Profile information
        profile_data = {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "phone_number": user.phone_number,
            "default_currency": user.default_currency,
            "created_at": user.created_at.isoformat(),
            "updated_at": user.updated_at.isoformat(),
        }

        # 2. Groups
        gm_stmt = select(GroupMember).where(GroupMember.user_id == user.id).options(selectinload(GroupMember.group))
        gm_res = await db.execute(gm_stmt)
        memberships = gm_res.scalars().all()
        groups_data = [
            {
                "group_id": m.group_id,
                "group_name": m.group.name if m.group else "Unknown",
                "role": m.role,
                "joined_at": m.joined_at.isoformat()
            }
            for m in memberships
        ]

        # 3. Expenses created, paid, or split
        # Creator expenses
        exp_stmt = (
            select(Expense)
            .where(
                or_(
                    Expense.created_by == user.id,
                    Expense.id.in_(select(ExpensePayer.expense_id).where(ExpensePayer.user_id == user.id)),
                    Expense.id.in_(select(ExpenseSplit.expense_id).where(ExpenseSplit.user_id == user.id))
                ),
                Expense.is_deleted == False
            )
            .options(
                selectinload(Expense.payers),
                selectinload(Expense.splits)
            )
        )
        exp_res = await db.execute(exp_stmt)
        expenses = exp_res.scalars().all()

        expenses_data = []
        for exp in expenses:
            expenses_data.append({
                "id": exp.id,
                "description": exp.description,
                "total_amount": float(exp.total_amount),
                "currency": exp.currency,
                "date": exp.expense_date.isoformat(),
                "category": exp.category,
                "split_type": exp.split_type,
                "group_id": exp.group_id,
                "created_by": exp.created_by,
                "payers": [{"user_id": p.user_id, "amount": float(p.amount_paid)} for p in exp.payers],
                "splits": [{"user_id": s.user_id, "amount": float(s.owed_amount)} for s in exp.splits]
            })

        # 4. Settlements
        settle_stmt = select(Settlement).where(
            or_(Settlement.payer_id == user.id, Settlement.recipient_id == user.id)
        )
        settle_res = await db.execute(settle_stmt)
        settlements = settle_res.scalars().all()
        settlements_data = [
            {
                "id": s.id,
                "payer_id": s.payer_id,
                "recipient_id": s.recipient_id,
                "amount": float(s.amount),
                "currency": s.currency,
                "payment_method": s.payment_method,
                "transaction_reference": s.transaction_reference,
                "notes": s.notes,
                "created_at": s.created_at.isoformat()
            }
            for s in settlements
        ]

        # 5. Receipts uploaded by user
        rec_stmt = select(Receipt).where(Receipt.user_id == user.id, Receipt.is_deleted == False)
        rec_res = await db.execute(rec_stmt)
        receipts = rec_res.scalars().all()
        receipts_data = [
            {
                "id": r.id,
                "file_name": r.file_name,
                "mime_type": r.mime_type,
                "file_size_bytes": r.file_size_bytes,
                "uploaded_at": r.created_at.isoformat()
            }
            for r in receipts
        ]

        # 6. Subscriptions
        sub_stmt = select(Subscription).where(Subscription.user_id == user.id)
        sub_res = await db.execute(sub_stmt)
        subscriptions = sub_res.scalars().all()
        subs_data = [
            {
                "id": sub.id,
                "tier": sub.tier,
                "status": sub.status,
                "created_at": sub.created_at.isoformat()
            }
            for sub in subscriptions
        ]

        return {
            "export_version": "1.0",
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "profile": profile_data,
            "groups": groups_data,
            "expenses": expenses_data,
            "settlements": settlements_data,
            "receipts": receipts_data,
            "subscriptions": subs_data
        }

    @staticmethod
    async def delete_and_anonymize_user(db: AsyncSession, user: User) -> Dict[str, Any]:
        """
        Implements GDPR Article 17 Right to Erasure while enforcing the
        CRITICAL FINANCIAL INVARIANT:
        Ledger balance conservation requires that historical transaction rows
        remain immutable so other group members' balances are not corrupted.
        
        The user profile is scrubbed of all PII, password hash is destroyed,
        and account is deactivated.
        """
        old_email = user.email
        anonymized_tag = user.id[:8]

        # Scrub PII
        user.email = f"deleted_{anonymized_tag}@anonymized.evenbill.app"
        user.full_name = "Former Member"
        user.phone_number = None
        user.avatar_url = None
        user.hashed_password = None
        user.is_active = False
        user.is_verified = False

        # Soft-delete all receipts owned by this user
        now = datetime.now(timezone.utc)
        await db.execute(
            update(Receipt)
            .where(Receipt.user_id == user.id)
            .values(is_deleted=True, deleted_at=now)
        )

        # Deactivate group memberships
        await db.execute(
            update(GroupMember)
            .where(GroupMember.user_id == user.id)
            .values(is_active=False)
        )

        # Audit log of anonymization
        db.add(FinancialAuditLog(
            entity_type="USER",
            entity_id=user.id,
            action="ANONYMIZE_ACCOUNT_DELETION",
            performed_by=user.id,
            previous_state=json.dumps({"status": "active"}),
            new_state=json.dumps({"status": "anonymized", "is_active": False})
        ))

        await db.commit()

        return {
            "status": "anonymized_and_deleted",
            "user_id": user.id,
            "message": "Account has been scrubbed of PII and permanently deactivated. Historical ledger invariant preserved."
        }
