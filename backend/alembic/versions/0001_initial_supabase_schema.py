"""Initial EvenBill PostgreSQL Schema & Row Level Security (RLS) Policies

Revision ID: 0001_initial_supabase_schema
Revises: 
Create Date: 2026-11-21 16:00:00.000000

Includes:
- 21 tables covering all EvenBill modules
- Profiles (mapped 1:1 to Supabase auth.users with CASCADE)
- Friendships, Groups, Group Members, Split Templates, Pending Participants, Invitations
- Expenses, Expense Payers, Expense Splits, Expense Participants
- Settlements, Exchange Rate Snapshots, Receipts, Comments, Activity Events
- Notification Preferences, Subscriptions, Webhook Events, Revoked Tokens, Financial Audit Logs
- Comprehensive PostgreSQL Row Level Security (RLS) policies for all 21 tables
- Helper functions with SECURITY DEFINER to prevent recursion
- Immutability trigger for financial_audit_logs
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '0001_initial_supabase_schema'
down_revision = None
branch_labels = None
depends_on = None

# Cross-platform UUID type: native UUID on PostgreSQL, VARCHAR(36) on SQLite
UID_TYPE = sa.String(length=36).with_variant(postgresql.UUID(as_uuid=False), 'postgresql')


def upgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"

    # 1. Profiles (matches Supabase auth.users UUID)
    op.create_table(
        'profiles',
        sa.Column('id', UID_TYPE, primary_key=True),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('friend_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('name', sa.String(length=150), nullable=False),
        sa.Column('group_type', sa.String(length=32), server_default='OTHER', nullable=False),
        sa.Column('base_currency', sa.String(length=3), server_default='USD', nullable=False),
        sa.Column('simplify_debts', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('invite_code', sa.String(length=16), nullable=False),
        sa.Column('avatar_url', sa.String(length=512), nullable=True),
        sa.Column('created_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('is_archived', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_groups_invite_code', 'groups', ['invite_code'], unique=True)
    op.create_index('ix_groups_created_by', 'groups', ['created_by'])

    # 4. Group Members
    op.create_table(
        'group_members',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('created_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('display_name', sa.String(length=150), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('phone_number', sa.String(length=32), nullable=True),
        sa.Column('status', sa.String(length=32), server_default='ACTIVE', nullable=False),
        sa.Column('claimed_by_user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('claimed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_pending_participants_group_id', 'pending_participants', ['group_id'])
    op.create_index('ix_pending_participants_email', 'pending_participants', ['email'])
    op.create_index('ix_pending_participants_claimed_by', 'pending_participants', ['claimed_by_user_id'])

    # 6. Group Invitations
    op.create_table(
        'invitations',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('invited_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('idempotency_key', sa.String(length=64), nullable=True),
        sa.Column('transaction_type', sa.String(length=32), server_default='EXPENSE', nullable=False),
        sa.Column('original_expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='SET NULL'), nullable=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('created_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('amount_paid', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.UniqueConstraint('expense_id', 'user_id', name='uq_expense_payer')
    )
    op.create_index('ix_expense_payers_expense_id', 'expense_payers', ['expense_id'])
    op.create_index('ix_expense_payers_user_id', 'expense_payers', ['user_id'])

    # 9. Expense Allocations / Splits
    op.create_table(
        'expense_splits',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('owed_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('share_quantity', sa.Numeric(precision=12, scale=4), nullable=True),
        sa.UniqueConstraint('expense_id', 'user_id', name='uq_expense_split')
    )
    op.create_index('ix_expense_splits_expense_id', 'expense_splits', ['expense_id'])
    op.create_index('ix_expense_splits_user_id', 'expense_splits', ['user_id'])

    # 10. Expense Participants
    op.create_table(
        'expense_participants',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=True),
        sa.Column('pending_participant_id', UID_TYPE, sa.ForeignKey('pending_participants.id', ondelete='CASCADE'), nullable=True),
        sa.Column('share_amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('share_percentage', sa.Numeric(precision=7, scale=4), nullable=True),
    )
    op.create_index('ix_expense_participants_expense_id', 'expense_participants', ['expense_id'])
    op.create_index('ix_expense_participants_user_id', 'expense_participants', ['user_id'])
    op.create_index('ix_expense_participants_pending_id', 'expense_participants', ['pending_participant_id'])

    # 11. Settlements
    op.create_table(
        'settlements',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('idempotency_key', sa.String(length=64), nullable=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('payer_id', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('recipient_id', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('amount', sa.Numeric(precision=18, scale=4), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('payment_method', sa.String(length=32), server_default='CASH', nullable=False),
        sa.Column('transaction_reference', sa.String(length=128), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=True),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('expense_id', UID_TYPE, sa.ForeignKey('expenses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('group_id', UID_TYPE, sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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

    # 17. Subscriptions
    op.create_table(
        'subscriptions',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
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

    # 18. Financial Audit Logs (Append-Only)
    op.create_table(
        'financial_audit_logs',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('entity_type', sa.String(length=32), nullable=False),
        sa.Column('entity_id', UID_TYPE, nullable=False),
        sa.Column('action', sa.String(length=32), nullable=False),
        sa.Column('performed_by', UID_TYPE, sa.ForeignKey('profiles.id'), nullable=False),
        sa.Column('previous_state', sa.Text(), nullable=True),
        sa.Column('new_state', sa.Text(), nullable=True),
        sa.Column('occurred_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_financial_audit_logs_entity_id', 'financial_audit_logs', ['entity_id'])

    # 19. Subscription Webhook Events
    op.create_table(
        'subscription_webhook_events',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('event_id', sa.String(length=128), unique=True, nullable=False),
        sa.Column('store', sa.String(length=32), nullable=False),
        sa.Column('event_type', sa.String(length=64), nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='SET NULL'), nullable=True),
        sa.Column('payload', sa.Text(), nullable=True),
        sa.Column('payload_json', sa.Text(), nullable=True),
        sa.Column('processed', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('received_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_subscription_webhook_events_event_id', 'subscription_webhook_events', ['event_id'])

    # 20. Revoked Tokens
    op.create_table(
        'revoked_tokens',
        sa.Column('id', UID_TYPE, primary_key=True),
        sa.Column('jti', sa.String(length=64), unique=True, nullable=False),
        sa.Column('user_id', UID_TYPE, sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('ix_revoked_tokens_jti', 'revoked_tokens', ['jti'])
    op.create_index('ix_revoked_tokens_user_id', 'revoked_tokens', ['user_id'])

    # PostgreSQL Supabase Integration & Row Level Security (RLS)
    if is_pg:
        # A. Foreign Key from public.profiles(id) -> auth.users(id) ON DELETE CASCADE
        # Binds profiles lifecycle 1:1 to Supabase authenticated identity
        op.create_foreign_key(
            'fk_profiles_auth_users',
            'profiles',
            'users',
            ['id'],
            ['id'],
            source_schema='public',
            referent_schema='auth',
            ondelete='CASCADE'
        )

        # B. Helper Functions for Clean, Recursion-Free RLS
        op.execute("""
            CREATE OR REPLACE FUNCTION public.is_group_member(check_group_id uuid, check_user_id uuid)
            RETURNS boolean
            LANGUAGE sql
            SECURITY DEFINER
            STABLE
            AS $$
              SELECT EXISTS (
                SELECT 1 FROM public.group_members
                WHERE group_id = check_group_id
                  AND user_id = check_user_id
                  AND is_active = true
              );
            $$;
        """)

        op.execute("""
            CREATE OR REPLACE FUNCTION public.is_group_admin(check_group_id uuid, check_user_id uuid)
            RETURNS boolean
            LANGUAGE sql
            SECURITY DEFINER
            STABLE
            AS $$
              SELECT EXISTS (
                SELECT 1 FROM public.group_members
                WHERE group_id = check_group_id
                  AND user_id = check_user_id
                  AND role IN ('OWNER', 'ADMIN')
                  AND is_active = true
              );
            $$;
        """)

        # C. Enable Row Level Security (RLS) on ALL 21 Tables
        all_tables = [
            'profiles', 'friendships', 'groups', 'group_members',
            'group_split_templates', 'pending_participants', 'invitations',
            'expenses', 'expense_payers', 'expense_splits', 'expense_participants',
            'settlements', 'exchange_rate_snapshots', 'receipts', 'comments',
            'activity_events', 'notification_preferences', 'subscriptions',
            'financial_audit_logs', 'subscription_webhook_events', 'revoked_tokens'
        ]
        for tbl in all_tables:
            op.execute(f"ALTER TABLE {tbl} ENABLE ROW LEVEL SECURITY;")

        # D. Profiles Policies
        op.execute("""
            CREATE POLICY "profiles_select" ON profiles
            FOR SELECT USING (
                auth.uid() = id OR
                EXISTS (
                    SELECT 1 FROM group_members gm1
                    JOIN group_members gm2 ON gm1.group_id = gm2.group_id
                    WHERE gm1.user_id = auth.uid() AND gm2.user_id = profiles.id
                ) OR
                EXISTS (
                    SELECT 1 FROM friendships f
                    WHERE (f.user_id = auth.uid() AND f.friend_id = profiles.id)
                       OR (f.friend_id = auth.uid() AND f.user_id = profiles.id)
                )
            );
        """)
        op.execute("""
            CREATE POLICY "profiles_insert" ON profiles
            FOR INSERT WITH CHECK (auth.uid() = id);
        """)
        op.execute("""
            CREATE POLICY "profiles_update" ON profiles
            FOR UPDATE USING (auth.uid() = id);
        """)
        op.execute("""
            CREATE POLICY "profiles_delete" ON profiles
            FOR DELETE USING (auth.uid() = id);
        """)

        # E. Friendships Policies
        op.execute("""
            CREATE POLICY "friendships_select" ON friendships
            FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);
        """)
        op.execute("""
            CREATE POLICY "friendships_insert" ON friendships
            FOR INSERT WITH CHECK (auth.uid() = user_id);
        """)
        op.execute("""
            CREATE POLICY "friendships_update" ON friendships
            FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = friend_id);
        """)
        op.execute("""
            CREATE POLICY "friendships_delete" ON friendships
            FOR DELETE USING (auth.uid() = user_id OR auth.uid() = friend_id);
        """)

        # F. Groups Policies
        op.execute("""
            CREATE POLICY "groups_select" ON groups
            FOR SELECT USING (
                auth.uid() = created_by OR
                public.is_group_member(id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "groups_insert" ON groups
            FOR INSERT WITH CHECK (auth.uid() = created_by);
        """)
        op.execute("""
            CREATE POLICY "groups_update" ON groups
            FOR UPDATE USING (
                auth.uid() = created_by OR
                public.is_group_admin(id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "groups_delete" ON groups
            FOR DELETE USING (auth.uid() = created_by);
        """)

        # G. Group Members Policies
        op.execute("""
            CREATE POLICY "group_members_select" ON group_members
            FOR SELECT USING (
                user_id = auth.uid() OR
                public.is_group_member(group_id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "group_members_insert" ON group_members
            FOR INSERT WITH CHECK (
                public.is_group_admin(group_id, auth.uid()) OR
                user_id = auth.uid()
            );
        """)
        op.execute("""
            CREATE POLICY "group_members_update" ON group_members
            FOR UPDATE USING (public.is_group_admin(group_id, auth.uid()));
        """)
        op.execute("""
            CREATE POLICY "group_members_delete" ON group_members
            FOR DELETE USING (
                public.is_group_admin(group_id, auth.uid()) OR
                user_id = auth.uid()
            );
        """)

        # H. Group Split Templates Policies
        op.execute("""
            CREATE POLICY "group_split_templates_select" ON group_split_templates
            FOR SELECT USING (public.is_group_member(group_id, auth.uid()));
        """)
        op.execute("""
            CREATE POLICY "group_split_templates_insert" ON group_split_templates
            FOR INSERT WITH CHECK (
                created_by = auth.uid() AND
                public.is_group_member(group_id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "group_split_templates_update" ON group_split_templates
            FOR UPDATE USING (
                created_by = auth.uid() OR
                public.is_group_admin(group_id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "group_split_templates_delete" ON group_split_templates
            FOR DELETE USING (
                created_by = auth.uid() OR
                public.is_group_admin(group_id, auth.uid())
            );
        """)

        # I. Pending Participants Policies
        op.execute("""
            CREATE POLICY "pending_participants_select" ON pending_participants
            FOR SELECT USING (public.is_group_member(group_id, auth.uid()));
        """)
        op.execute("""
            CREATE POLICY "pending_participants_insert" ON pending_participants
            FOR INSERT WITH CHECK (public.is_group_member(group_id, auth.uid()));
        """)
        op.execute("""
            CREATE POLICY "pending_participants_update" ON pending_participants
            FOR UPDATE USING (
                public.is_group_member(group_id, auth.uid()) OR
                claimed_by_user_id = auth.uid()
            );
        """)
        op.execute("""
            CREATE POLICY "pending_participants_delete" ON pending_participants
            FOR DELETE USING (public.is_group_admin(group_id, auth.uid()));
        """)

        # J. Invitations Policies
        op.execute("""
            CREATE POLICY "invitations_select" ON invitations
            FOR SELECT USING (
                invited_by = auth.uid() OR
                public.is_group_admin(group_id, auth.uid()) OR
                email = (SELECT email FROM profiles WHERE id = auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "invitations_insert" ON invitations
            FOR INSERT WITH CHECK (
                invited_by = auth.uid() AND
                public.is_group_admin(group_id, auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "invitations_update" ON invitations
            FOR UPDATE USING (
                public.is_group_admin(group_id, auth.uid()) OR
                email = (SELECT email FROM profiles WHERE id = auth.uid())
            );
        """)
        op.execute("""
            CREATE POLICY "invitations_delete" ON invitations
            FOR DELETE USING (
                invited_by = auth.uid() OR
                public.is_group_admin(group_id, auth.uid())
            );
        """)

        # K. Expenses Policies
        op.execute("""
            CREATE POLICY "expenses_select" ON expenses
            FOR SELECT USING (
                created_by = auth.uid() OR
                (group_id IS NOT NULL AND public.is_group_member(group_id, auth.uid()))
            );
        """)
        op.execute("""
            CREATE POLICY "expenses_insert" ON expenses
            FOR INSERT WITH CHECK (
                created_by = auth.uid() AND
                (group_id IS NULL OR public.is_group_member(group_id, auth.uid()))
            );
        """)
        op.execute("""
            CREATE POLICY "expenses_update" ON expenses
            FOR UPDATE USING (
                created_by = auth.uid() OR
                (group_id IS NOT NULL AND public.is_group_admin(group_id, auth.uid()))
            );
        """)
        op.execute("""
            CREATE POLICY "expenses_delete" ON expenses
            FOR DELETE USING (
                created_by = auth.uid() OR
                (group_id IS NOT NULL AND public.is_group_admin(group_id, auth.uid()))
            );
        """)

        # L. Expense Payers Policies
        op.execute("""
            CREATE POLICY "expense_payers_select" ON expense_payers
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_payers.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                )
            );
        """)
        op.execute("""
            CREATE POLICY "expense_payers_modify" ON expense_payers
            FOR ALL USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_payers.expense_id
                    AND e.created_by = auth.uid()
                )
            );
        """)

        # M. Expense Splits Policies
        op.execute("""
            CREATE POLICY "expense_splits_select" ON expense_splits
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_splits.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                )
            );
        """)
        op.execute("""
            CREATE POLICY "expense_splits_modify" ON expense_splits
            FOR ALL USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_splits.expense_id
                    AND e.created_by = auth.uid()
                )
            );
        """)

        # N. Expense Participants Policies
        op.execute("""
            CREATE POLICY "expense_participants_select" ON expense_participants
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_participants.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                )
            );
        """)
        op.execute("""
            CREATE POLICY "expense_participants_modify" ON expense_participants
            FOR ALL USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = expense_participants.expense_id
                    AND e.created_by = auth.uid()
                )
            );
        """)

        # O. Settlements Policies
        op.execute("""
            CREATE POLICY "settlements_select" ON settlements
            FOR SELECT USING (
                payer_id = auth.uid() OR
                recipient_id = auth.uid() OR
                created_by = auth.uid() OR
                (group_id IS NOT NULL AND public.is_group_member(group_id, auth.uid()))
            );
        """)
        op.execute("""
            CREATE POLICY "settlements_insert" ON settlements
            FOR INSERT WITH CHECK (
                created_by = auth.uid() AND
                (payer_id = auth.uid() OR recipient_id = auth.uid()) AND
                (group_id IS NULL OR public.is_group_member(group_id, auth.uid()))
            );
        """)
        op.execute("""
            CREATE POLICY "settlements_update" ON settlements
            FOR UPDATE USING (created_by = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "settlements_delete" ON settlements
            FOR DELETE USING (created_by = auth.uid());
        """)

        # P. Exchange Rate Snapshots Policies (Public read, append-only via system)
        op.execute("""
            CREATE POLICY "exchange_rates_select" ON exchange_rate_snapshots
            FOR SELECT USING (true);
        """)

        # Q. Receipts Policies
        op.execute("""
            CREATE POLICY "receipts_select" ON receipts
            FOR SELECT USING (
                user_id = auth.uid() OR
                (expense_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = receipts.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                ))
            );
        """)
        op.execute("""
            CREATE POLICY "receipts_insert" ON receipts
            FOR INSERT WITH CHECK (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "receipts_update" ON receipts
            FOR UPDATE USING (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "receipts_delete" ON receipts
            FOR DELETE USING (user_id = auth.uid());
        """)

        # R. Comments Policies
        op.execute("""
            CREATE POLICY "comments_select" ON comments
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = comments.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                )
            );
        """)
        op.execute("""
            CREATE POLICY "comments_insert" ON comments
            FOR INSERT WITH CHECK (
                user_id = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM expenses e
                    WHERE e.id = comments.expense_id
                    AND (e.created_by = auth.uid() OR (e.group_id IS NOT NULL AND public.is_group_member(e.group_id, auth.uid())))
                )
            );
        """)
        op.execute("""
            CREATE POLICY "comments_update" ON comments
            FOR UPDATE USING (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "comments_delete" ON comments
            FOR DELETE USING (user_id = auth.uid());
        """)

        # S. Activity Events Policies (Select only, system writes)
        op.execute("""
            CREATE POLICY "activity_events_select" ON activity_events
            FOR SELECT USING (
                user_id = auth.uid() OR
                (group_id IS NOT NULL AND public.is_group_member(group_id, auth.uid()))
            );
        """)

        # T. Notification Preferences Policies
        op.execute("""
            CREATE POLICY "notification_preferences_select" ON notification_preferences
            FOR SELECT USING (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "notification_preferences_insert" ON notification_preferences
            FOR INSERT WITH CHECK (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "notification_preferences_update" ON notification_preferences
            FOR UPDATE USING (user_id = auth.uid());
        """)
        op.execute("""
            CREATE POLICY "notification_preferences_delete" ON notification_preferences
            FOR DELETE USING (user_id = auth.uid());
        """)

        # U. Subscriptions Policies (User read-only, webhook/service-role writes)
        op.execute("""
            CREATE POLICY "subscriptions_select" ON subscriptions
            FOR SELECT USING (user_id = auth.uid());
        """)

        # V. Financial Audit Logs Policies (User read-only, append-only immutability)
        op.execute("""
            CREATE POLICY "financial_audit_logs_select" ON financial_audit_logs
            FOR SELECT USING (
                performed_by = auth.uid() OR
                EXISTS (
                    SELECT 1 FROM groups g
                    WHERE g.id = financial_audit_logs.entity_id
                    AND (g.created_by = auth.uid() OR public.is_group_admin(g.id, auth.uid()))
                )
            );
        """)

        # Immutability Trigger: Absolutely forbids UPDATE or DELETE on financial audit logs
        op.execute("""
            CREATE OR REPLACE FUNCTION public.prevent_audit_log_tampering()
            RETURNS trigger
            LANGUAGE plpgsql
            AS $$
            BEGIN
                RAISE EXCEPTION 'financial_audit_logs is strictly immutable: updates and deletions are forbidden';
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS trg_no_update_delete_audit_logs ON financial_audit_logs;")

        op.execute("""
            CREATE TRIGGER trg_no_update_delete_audit_logs
            BEFORE UPDATE OR DELETE ON financial_audit_logs
            FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_tampering();
        """)

        # Auto-provision profile trigger on Supabase auth.users signup
        op.execute("""
            CREATE OR REPLACE FUNCTION public.handle_new_user()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = public
            AS $$
            BEGIN
              INSERT INTO public.profiles (id, email, full_name, is_active, created_at, updated_at)
              VALUES (
                new.id,
                new.email,
                COALESCE(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
                true,
                now(),
                now()
              )
              ON CONFLICT (id) DO NOTHING;
              RETURN new;
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;")

        op.execute("""
            CREATE TRIGGER on_auth_user_created
              AFTER INSERT ON auth.users
              FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
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

    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"
    if is_pg:
        # 1. Drop external trigger on auth.users and internal audit trigger
        op.execute("DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;")
        op.execute("DROP TRIGGER IF EXISTS trg_no_update_delete_audit_logs ON financial_audit_logs;")

        # 2. Drop foreign key constraint to auth.users
        op.execute("ALTER TABLE IF EXISTS profiles DROP CONSTRAINT IF EXISTS fk_profiles_auth_users;")

        # 3. Explicitly drop all migration-owned RLS policies to eliminate dependency deadlocks
        policies = [
            ('profiles', 'profiles_select'),
            ('profiles', 'profiles_insert'),
            ('profiles', 'profiles_update'),
            ('profiles', 'profiles_delete'),
            ('friendships', 'friendships_select'),
            ('friendships', 'friendships_insert'),
            ('friendships', 'friendships_update'),
            ('friendships', 'friendships_delete'),
            ('groups', 'groups_select'),
            ('groups', 'groups_insert'),
            ('groups', 'groups_update'),
            ('groups', 'groups_delete'),
            ('group_members', 'group_members_select'),
            ('group_members', 'group_members_insert'),
            ('group_members', 'group_members_update'),
            ('group_members', 'group_members_delete'),
            ('group_split_templates', 'group_split_templates_select'),
            ('group_split_templates', 'group_split_templates_insert'),
            ('group_split_templates', 'group_split_templates_update'),
            ('group_split_templates', 'group_split_templates_delete'),
            ('pending_participants', 'pending_participants_select'),
            ('pending_participants', 'pending_participants_insert'),
            ('pending_participants', 'pending_participants_update'),
            ('pending_participants', 'pending_participants_delete'),
            ('invitations', 'invitations_select'),
            ('invitations', 'invitations_insert'),
            ('invitations', 'invitations_update'),
            ('invitations', 'invitations_delete'),
            ('expenses', 'expenses_select'),
            ('expenses', 'expenses_insert'),
            ('expenses', 'expenses_update'),
            ('expenses', 'expenses_delete'),
            ('expense_payers', 'expense_payers_select'),
            ('expense_payers', 'expense_payers_modify'),
            ('expense_splits', 'expense_splits_select'),
            ('expense_splits', 'expense_splits_modify'),
            ('expense_participants', 'expense_participants_select'),
            ('expense_participants', 'expense_participants_modify'),
            ('settlements', 'settlements_select'),
            ('settlements', 'settlements_insert'),
            ('settlements', 'settlements_update'),
            ('settlements', 'settlements_delete'),
            ('exchange_rate_snapshots', 'exchange_rates_select'),
            ('receipts', 'receipts_select'),
            ('receipts', 'receipts_insert'),
            ('receipts', 'receipts_update'),
            ('receipts', 'receipts_delete'),
            ('comments', 'comments_select'),
            ('comments', 'comments_insert'),
            ('comments', 'comments_update'),
            ('comments', 'comments_delete'),
            ('activity_events', 'activity_events_select'),
            ('notification_preferences', 'notification_preferences_select'),
            ('notification_preferences', 'notification_preferences_insert'),
            ('notification_preferences', 'notification_preferences_update'),
            ('notification_preferences', 'notification_preferences_delete'),
            ('subscriptions', 'subscriptions_select'),
            ('financial_audit_logs', 'financial_audit_logs_select'),
        ]
        for tbl, pol in policies:
            op.execute(f'DROP POLICY IF EXISTS "{pol}" ON {tbl};')

        # 4. Drop migration-owned functions explicitly without CASCADE
        op.execute("DROP FUNCTION IF EXISTS public.handle_new_user();")
        op.execute("DROP FUNCTION IF EXISTS public.prevent_audit_log_tampering();")
        op.execute("DROP FUNCTION IF EXISTS public.is_group_admin(uuid, uuid);")
        op.execute("DROP FUNCTION IF EXISTS public.is_group_member(uuid, uuid);")

        # 5. Drop migration-owned tables in reverse dependency order without CASCADE
        for tbl in tables:
            op.execute(f"DROP TABLE IF EXISTS {tbl};")
    else:
        for tbl in tables:
            op.drop_table(tbl)
