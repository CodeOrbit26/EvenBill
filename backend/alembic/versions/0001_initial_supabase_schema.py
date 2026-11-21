"""Initial EvenBill PostgreSQL Schema & Row Level Security (RLS) Policies

Revision ID: 0001_initial_supabase_schema
Revises: 
Create Date: 2026-11-21 16:00:00.000000

Includes:
- profiles (references auth.users)
- friendships
- groups
- group_members
- pending_participants
- invitations
- expenses
- expense_payers
- expense_participants
- expense_allocations
- settlements
- exchange_rate_snapshots
- receipt_metadata
- comments
- activity_events
- notification_preferences
- Comprehensive PostgreSQL Row Level Security (RLS) policies
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '0001_initial_supabase_schema'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"

    # 1. Profiles (matches Supabase auth.users UUID)
    op.create_table(
        'profiles',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('hashed_password', sa.String(length=255), nullable=True),
        sa.Column('full_name', sa.String(length=120), nullable=False),
        sa.Column('phone_number', sa.String(length=32), nullable=True),
        sa.Column('avatar_url', sa.String(length=512), nullable=True),
        sa.Column('default_currency', sa.String(length=3), server_default='USD', nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('is_verified', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('is_pro', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('mfa_secret', sa.String(length=64), nullable=True),
        sa.Column('mfa_enabled', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_profiles_email', 'profiles', ['email'], unique=True)

    # 2. Friendships
    op.create_table(
        'friendships',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('friend_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('status', sa.String(length=32), server_default='ACCEPTED', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', 'friend_id', name='uq_friendship_pair')
    )
    op.create_index('ix_friendships_user_id', 'friendships', ['user_id'])
    op.create_index('ix_friendships_friend_id', 'friendships', ['friend_id'])

    # 3. Groups
    op.create_table(
        'groups',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('name', sa.String(length=150), nullable=False),
        sa.Column('group_type', sa.String(length=32), server_default='OTHER', nullable=False),
        sa.Column('base_currency', sa.String(length=3), server_default='USD', nullable=False),
        sa.Column('simplify_debts', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('invite_code', sa.String(length=16), nullable=False),
        sa.Column('avatar_url', sa.String(length=512), nullable=True),
        sa.Column('created_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('is_archived', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_groups_invite_code', 'groups', ['invite_code'], unique=True)
    op.create_index('ix_groups_created_by', 'groups', ['created_by'])

    # 4. Group Members
    op.create_table(
        'group_members',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role', sa.String(length=32), server_default='MEMBER', nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('group_id', 'user_id', name='uq_group_user')
    )
    op.create_index('ix_group_members_group_id', 'group_members', ['group_id'])
    op.create_index('ix_group_members_user_id', 'group_members', ['user_id'])

    # Group Split Templates
    op.create_table(
        'group_split_templates',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('created_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('split_type', sa.String(length=32), server_default='EQUAL', nullable=False),
        sa.Column('is_default', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('allocations_json', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_group_split_templates_group_id', 'group_split_templates', ['group_id'])

    # 5. Pending Participants
    op.create_table(
        'pending_participants',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('display_name', sa.String(length=150), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('phone_number', sa.String(length=32), nullable=True),
        sa.Column('status', sa.String(length=32), server_default='ACTIVE', nullable=False),
        sa.Column('claimed_by_user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('claimed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_pending_participants_group_id', 'pending_participants', ['group_id'])
    op.create_index('ix_pending_participants_email', 'pending_participants', ['email'])
    op.create_index('ix_pending_participants_claimed_by', 'pending_participants', ['claimed_by_user_id'])

    # 6. Group Invitations
    op.create_table(
        'invitations',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('invited_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('token', sa.String(length=64), nullable=False),
        sa.Column('status', sa.String(length=32), server_default='PENDING', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('ix_invitations_token', 'invitations', ['token'], unique=True)
    op.create_index('ix_invitations_group_id', 'invitations', ['group_id'])

    # 7. Expenses
    op.create_table(
        'expenses',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('idempotency_key', sa.String(length=64), nullable=True),
        sa.Column('transaction_type', sa.String(length=32), server_default='EXPENSE', nullable=False),
        sa.Column('original_expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='SET NULL'), nullable=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('created_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('description', sa.String(length=255), nullable=False),
        sa.Column('total_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('base_currency_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('exchange_rate', sa.Numeric(precision=18, scale=8), server_default='1.0', nullable=False),
        sa.Column('exchange_rate_source', sa.String(length=64), server_default='DEFAULT', nullable=False),
        sa.Column('exchange_rate_timestamp', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('split_type', sa.String(length=32), server_default='EQUAL', nullable=False),
        sa.Column('category', sa.String(length=64), server_default='GENERAL', nullable=False),
        sa.Column('expense_date', sa.Date(), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('is_deleted', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('version', sa.Integer(), server_default='1', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_expenses_idempotency_key', 'expenses', ['idempotency_key'], unique=True)
    op.create_index('ix_expenses_group_id', 'expenses', ['group_id'])
    op.create_index('ix_expenses_created_by', 'expenses', ['created_by'])
    op.create_index('ix_expenses_is_deleted', 'expenses', ['is_deleted'])

    # 8. Expense Payers
    op.create_table(
        'expense_payers',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('amount_paid', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.UniqueConstraint('expense_id', 'user_id', name='uq_expense_payer')
    )
    op.create_index('ix_expense_payers_expense_id', 'expense_payers', ['expense_id'])
    op.create_index('ix_expense_payers_user_id', 'expense_payers', ['user_id'])

    # 9. Expense Allocations / Splits
    op.create_table(
        'expense_splits',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('owed_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('share_quantity', sa.Numeric(precision=12, scale=4), nullable=True),
        sa.UniqueConstraint('expense_id', 'user_id', name='uq_expense_split')
    )
    op.create_index('ix_expense_splits_expense_id', 'expense_splits', ['expense_id'])
    op.create_index('ix_expense_splits_user_id', 'expense_splits', ['user_id'])

    # 10. Expense Participants
    op.create_table(
        'expense_participants',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=True),
        sa.Column('pending_participant_id', sa.String(length=36), sa.ForeignKey('pending_participants.id', ondelete='CASCADE'), nullable=True),
        sa.Column('share_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('share_percentage', sa.Numeric(precision=7, scale=4), nullable=True),
    )
    op.create_index('ix_expense_participants_expense_id', 'expense_participants', ['expense_id'])
    op.create_index('ix_expense_participants_user_id', 'expense_participants', ['user_id'])
    op.create_index('ix_expense_participants_pending_id', 'expense_participants', ['pending_participant_id'])

    # 11. Settlements
    op.create_table(
        'settlements',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('idempotency_key', sa.String(length=64), nullable=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('payer_id', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('recipient_id', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('payment_method', sa.String(length=32), server_default='CASH', nullable=False),
        sa.Column('transaction_reference', sa.String(length=128), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('is_deleted', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('settled_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_settlements_idempotency_key', 'settlements', ['idempotency_key'], unique=True)
    op.create_index('ix_settlements_group_id', 'settlements', ['group_id'])
    op.create_index('ix_settlements_payer_id', 'settlements', ['payer_id'])
    op.create_index('ix_settlements_recipient_id', 'settlements', ['recipient_id'])

    # 12. Exchange Rate Snapshots
    op.create_table(
        'exchange_rate_snapshots',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('base_currency', sa.String(length=3), nullable=False),
        sa.Column('target_currency', sa.String(length=3), nullable=False),
        sa.Column('rate', sa.Numeric(precision=18, scale=8), nullable=False),
        sa.Column('provider', sa.String(length=64), server_default='ECB', nullable=False),
        sa.Column('timestamp', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_exchange_rate_snapshots_base', 'exchange_rate_snapshots', ['base_currency'])
    op.create_index('ix_exchange_rate_snapshots_target', 'exchange_rate_snapshots', ['target_currency'])

    # 13. Receipt Metadata
    op.create_table(
        'receipts',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('s3_key', sa.String(length=512), nullable=False),
        sa.Column('file_name', sa.String(length=255), nullable=False),
        sa.Column('file_size_bytes', sa.Integer(), nullable=False),
        sa.Column('mime_type', sa.String(length=64), nullable=False),
        sa.Column('content_hash', sa.String(length=64), nullable=True),
        sa.Column('ocr_status', sa.String(length=32), server_default='NONE', nullable=False),
        sa.Column('raw_ocr_payload', sa.Text(), nullable=True),
        sa.Column('extracted_merchant', sa.String(length=255), nullable=True),
        sa.Column('extracted_total', sa.Numeric(precision=18, scale=4), nullable=True),
        sa.Column('extracted_currency', sa.String(length=3), nullable=True),
        sa.Column('extracted_date', sa.Date(), nullable=True),
        sa.Column('is_deleted', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('uploaded_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_receipts_expense_id', 'receipts', ['expense_id'])
    op.create_index('ix_receipts_user_id', 'receipts', ['user_id'])
    op.create_index('ix_receipts_content_hash', 'receipts', ['content_hash'])

    # 14. Comments
    op.create_table(
        'comments',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('expense_id', sa.String(length=36), sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('is_deleted', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_comments_expense_id', 'comments', ['expense_id'])
    op.create_index('ix_comments_user_id', 'comments', ['user_id'])

    # 15. Activity Events
    op.create_table(
        'activity_events',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('group_id', sa.String(length=36), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('event_type', sa.String(length=64), nullable=False),
        sa.Column('summary', sa.String(length=255), nullable=False),
        sa.Column('metadata_json', sa.Text(), nullable=True),
        sa.Column('occurred_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_activity_events_group_id', 'activity_events', ['group_id'])
    op.create_index('ix_activity_events_user_id', 'activity_events', ['user_id'])
    op.create_index('ix_activity_events_event_type', 'activity_events', ['event_type'])

    # 16. Notification Preferences
    op.create_table(
        'notification_preferences',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('email_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('push_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('expense_added', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('settlement_recorded', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('group_invitations', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('weekly_digest', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', name='uq_user_notification_prefs')
    )
    op.create_index('ix_notification_preferences_user_id', 'notification_preferences', ['user_id'])

    # Ancillary tables (Subscriptions & Financial Audit Logs)
    op.create_table(
        'subscriptions',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('tier', sa.String(length=32), server_default='FREE', nullable=False),
        sa.Column('status', sa.String(length=32), server_default='ACTIVE', nullable=False),
        sa.Column('original_transaction_id', sa.String(length=128), nullable=True),
        sa.Column('store', sa.String(length=32), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('grace_period_until', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancel_at_period_end', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('refunded_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('is_sandbox', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_subscriptions_user_id', 'subscriptions', ['user_id'])

    op.create_table(
        'financial_audit_logs',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('entity_type', sa.String(length=32), nullable=False),
        sa.Column('entity_id', sa.String(length=36), nullable=False),
        sa.Column('action', sa.String(length=32), nullable=False),
        sa.Column('performed_by', sa.String(length=36), sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('previous_state', sa.Text(), nullable=True),
        sa.Column('new_state', sa.Text(), nullable=True),
        sa.Column('occurred_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_financial_audit_logs_entity_id', 'financial_audit_logs', ['entity_id'])

    op.create_table(
        'subscription_webhook_events',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('event_id', sa.String(length=128), unique=True, nullable=False),
        sa.Column('store', sa.String(length=32), nullable=False),
        sa.Column('event_type', sa.String(length=64), nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='SET NULL'), nullable=True),
        sa.Column('payload', sa.Text(), nullable=True),
        sa.Column('payload_json', sa.Text(), nullable=True),
        sa.Column('processed', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('received_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_subscription_webhook_events_event_id', 'subscription_webhook_events', ['event_id'])

    op.create_table(
        'revoked_tokens',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('jti', sa.String(length=64), unique=True, nullable=False),
        sa.Column('user_id', sa.String(length=36), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('ix_revoked_tokens_jti', 'revoked_tokens', ['jti'])
    op.create_index('ix_revoked_tokens_user_id', 'revoked_tokens', ['user_id'])

    # PostgreSQL Row Level Security (RLS) Policies
    if is_pg:
        # Enable RLS on protected tables
        tables = [
            'profiles', 'friendships', 'groups', 'group_members',
            'pending_participants', 'invitations', 'expenses', 'expense_payers',
            'expense_splits', 'expense_participants', 'settlements', 'receipts',
            'comments', 'activity_events', 'notification_preferences'
        ]
        for tbl in tables:
            op.execute(f"ALTER TABLE {tbl} ENABLE ROW LEVEL SECURITY;")

        # Profiles RLS
        op.execute("""
            CREATE POLICY "profiles_select_policy" ON profiles
            FOR SELECT USING (auth.uid()::text = id);
        """)
        op.execute("""
            CREATE POLICY "profiles_update_policy" ON profiles
            FOR UPDATE USING (auth.uid()::text = id);
        """)

        # Groups RLS (Only members or creator)
        op.execute("""
            CREATE POLICY "groups_select_policy" ON groups
            FOR SELECT USING (
                auth.uid()::text = created_by OR
                EXISTS (
                    SELECT 1 FROM group_members gm
                    WHERE gm.group_id = groups.id
                    AND gm.user_id = auth.uid()::text
                    AND gm.is_active = true
                )
            );
        """)

        # Expenses RLS (Group members or creator only)
        op.execute("""
            CREATE POLICY "expenses_select_policy" ON expenses
            FOR SELECT USING (
                auth.uid()::text = created_by OR
                (group_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM group_members gm
                    WHERE gm.group_id = expenses.group_id
                    AND gm.user_id = auth.uid()::text
                    AND gm.is_active = true
                ))
            );
        """)

        # Settlements RLS (Payer, recipient, creator, or group members)
        op.execute("""
            CREATE POLICY "settlements_select_policy" ON settlements
            FOR SELECT USING (
                auth.uid()::text = payer_id OR
                auth.uid()::text = recipient_id OR
                auth.uid()::text = created_by OR
                (group_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM group_members gm
                    WHERE gm.group_id = settlements.group_id
                    AND gm.user_id = auth.uid()::text
                    AND gm.is_active = true
                ))
            );
        """)

        # Invitations RLS (Protect invite tokens: group admins/owners or invited email)
        op.execute("""
            CREATE POLICY "invitations_select_policy" ON invitations
            FOR SELECT USING (
                auth.uid()::text = invited_by OR
                EXISTS (
                    SELECT 1 FROM group_members gm
                    WHERE gm.group_id = invitations.group_id
                    AND gm.user_id = auth.uid()::text
                    AND gm.role IN ('OWNER', 'ADMIN')
                    AND gm.is_active = true
                )
            );
        """)


def downgrade() -> None:
    tables = [
        'revoked_tokens', 'subscription_webhook_events', 'financial_audit_logs',
        'subscriptions', 'notification_preferences', 'activity_events',
        'comments', 'receipts', 'exchange_rate_snapshots', 'settlements',
        'expense_participants', 'expense_splits', 'expense_payers', 'expenses',
        'invitations', 'pending_participants', 'group_split_templates',
        'group_members', 'groups', 'friendships', 'profiles'
    ]
    for tbl in tables:
        op.drop_table(tbl)
