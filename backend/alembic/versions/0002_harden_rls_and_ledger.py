"""Harden RLS, Ledger Privileges, Search Paths, and Immutability Triggers

Revision ID: 0002_harden_rls_and_ledger_security
Revises: 0001_initial_supabase_schema
Create Date: 2026-11-21 20:00:00.000000

Defensive Security Enhancements:
1. SET search_path = '' and fully qualified object paths on all SECURITY DEFINER functions.
2. check_profile_immutable_fields(): rejects client changes to is_pro, is_verified, id, created_at while allowing authorized backend admin operations with immutable audit logging.
3. check_groups_immutable_fields(): guarantees created_by, id, and created_at cannot be changed by administrators.
4. check_group_members_immutable_fields(): guarantees group_id, user_id, id cannot be modified, and prevents unauthorized OWNER modification.
5. consume_invitation_or_claim_on_join(): atomically consumes invitations and pending claims on member join.
6. group_members_insert: strict multi-condition policy preventing arbitrary self-joining.
7. group_members_update: WITH CHECK preventing unauthorized promotion to OWNER.
8. REVOKE INSERT, UPDATE, DELETE on financial ledger, receipt, and audit tables from anon and authenticated.
9. REVOKE CREATE ON SCHEMA public from PUBLIC, anon, and authenticated.
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0002_harden_rls_and_ledger'
down_revision = '0001_initial_supabase_schema'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"

    if is_pg:
        # 1. Hardened Group Helper Functions with empty search_path
        op.execute("""
            CREATE OR REPLACE FUNCTION public.is_group_member(check_group_id pg_catalog.uuid, check_user_id pg_catalog.uuid)
            RETURNS pg_catalog.bool
            LANGUAGE sql
            SECURITY DEFINER
            STABLE
            SET search_path = ''
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
            CREATE OR REPLACE FUNCTION public.is_group_admin(check_group_id pg_catalog.uuid, check_user_id pg_catalog.uuid)
            RETURNS pg_catalog.bool
            LANGUAGE sql
            SECURITY DEFINER
            STABLE
            SET search_path = ''
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

        op.execute("""
            CREATE OR REPLACE FUNCTION public.prevent_audit_log_tampering()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            BEGIN
              RAISE EXCEPTION 'financial_audit_logs is strictly immutable: updates and deletions are forbidden';
            END;
            $$;
        """)

        op.execute("""
            CREATE OR REPLACE FUNCTION public.handle_new_user()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            BEGIN
              INSERT INTO public.profiles (id, email, full_name, is_active, created_at, updated_at)
              VALUES (
                new.id,
                new.email,
                COALESCE(new.raw_user_meta_data->>'full_name', pg_catalog.split_part(new.email, '@', 1)),
                true,
                pg_catalog.now(),
                pg_catalog.now()
              )
              ON CONFLICT (id) DO NOTHING;
              RETURN new;
            END;
            $$;
        """)

        # 2. Profile Protected Fields Trigger with Backend Admin Authorization & Audit Logging
        op.execute("""
            CREATE OR REPLACE FUNCTION public.check_profile_immutable_fields()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            BEGIN
              IF (NEW.is_pro IS DISTINCT FROM OLD.is_pro) OR
                 (NEW.is_verified IS DISTINCT FROM OLD.is_verified) OR
                 (NEW.id IS DISTINCT FROM OLD.id) OR
                 (NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
                
                -- Reject ordinary client updates (authenticated or anon roles)
                IF (pg_catalog.current_setting('role', true) IN ('authenticated', 'anon')) OR
                   (pg_catalog.current_setting('request.jwt.claim.role', true) IN ('authenticated', 'anon')) OR
                   (session_user IN ('authenticated', 'anon')) THEN
                  RAISE EXCEPTION 'Modification of protected profile fields (is_pro, is_verified, id, created_at) is strictly forbidden for ordinary clients.';
                END IF;

                -- Even for trusted backend, id and created_at are strictly immutable
                IF (NEW.id IS DISTINCT FROM OLD.id) OR (NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
                  RAISE EXCEPTION 'Profile id and created_at are strictly immutable.';
                END IF;

                -- Log authorized administrative privilege update to financial_audit_logs
                INSERT INTO public.financial_audit_logs (
                    id, entity_type, entity_id, action,
                    performed_by, previous_state, new_state, occurred_at
                ) VALUES (
                    pg_catalog.gen_random_uuid(),
                    'PROFILE',
                    NEW.id,
                    'PRIVILEGE_UPDATE',
                    COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid, NEW.id),
                    pg_catalog.jsonb_build_object(
                        'caller_role', pg_catalog.current_setting('role', true),
                        'is_pro', OLD.is_pro,
                        'is_verified', OLD.is_verified
                    )::text,
                    pg_catalog.jsonb_build_object(
                        'caller_role', pg_catalog.current_setting('role', true),
                        'is_pro', NEW.is_pro,
                        'is_verified', NEW.is_verified
                    )::text,
                    pg_catalog.now()
                );
              END IF;
              RETURN NEW;
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS trg_protect_profile_fields ON public.profiles;")

        op.execute("""
            CREATE TRIGGER trg_protect_profile_fields
            BEFORE UPDATE ON public.profiles
            FOR EACH ROW EXECUTE FUNCTION public.check_profile_immutable_fields();
        """)

        # 3. Group Immutability Trigger (Protects created_by, id, created_at)
        op.execute("""
            CREATE OR REPLACE FUNCTION public.check_groups_immutable_fields()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            BEGIN
              IF (NEW.created_by IS DISTINCT FROM OLD.created_by) THEN
                RAISE EXCEPTION 'Changing group creator (created_by) is strictly forbidden.';
              END IF;
              IF (NEW.id IS DISTINCT FROM OLD.id) THEN
                RAISE EXCEPTION 'Group id is strictly immutable.';
              END IF;
              IF (NEW.created_at IS DISTINCT FROM OLD.created_at) THEN
                RAISE EXCEPTION 'Group created_at is strictly immutable.';
              END IF;
              RETURN NEW;
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS trg_protect_group_fields ON public.groups;")

        op.execute("""
            CREATE TRIGGER trg_protect_group_fields
            BEFORE UPDATE ON public.groups
            FOR EACH ROW EXECUTE FUNCTION public.check_groups_immutable_fields();
        """)

        # 4. Group Member Immutability & Concurrency Trigger (Protects group_id, user_id, id, and OWNER invariant)
        op.execute("""
            CREATE OR REPLACE FUNCTION public.check_group_members_immutable_fields()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            DECLARE
              target_group_id pg_catalog.uuid;
              caller_sub pg_catalog.uuid;
              caller_is_client pg_catalog.bool;
              remaining_owners pg_catalog.int4;
            BEGIN
              target_group_id := COALESCE(NEW.group_id, OLD.group_id);
              caller_sub := NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::pg_catalog.uuid;
              caller_is_client := (
                pg_catalog.current_setting('role', true) IN ('authenticated', 'anon') OR
                pg_catalog.current_setting('request.jwt.claim.role', true) IN ('authenticated', 'anon') OR
                session_user IN ('authenticated', 'anon')
              );

              -- 1. Structural Immutability on UPDATE
              IF TG_OP = 'UPDATE' THEN
                IF (NEW.group_id IS DISTINCT FROM OLD.group_id) THEN
                  RAISE EXCEPTION 'Transferring group membership between groups is strictly forbidden.';
                END IF;
                IF (NEW.user_id IS DISTINCT FROM OLD.user_id) THEN
                  RAISE EXCEPTION 'Changing user_id on group membership is strictly forbidden.';
                END IF;
                IF (NEW.id IS DISTINCT FROM OLD.id) THEN
                  RAISE EXCEPTION 'Membership id is strictly immutable.';
                END IF;
                IF (NEW.joined_at IS DISTINCT FROM OLD.joined_at) THEN
                  RAISE EXCEPTION 'Membership joined_at is strictly immutable.';
                END IF;
              END IF;

              -- 2. Concurrency Serialization: If an OWNER role is modified, demoted, or deleted,
              -- lock the parent group row to prevent concurrent ownership-transfer race conditions.
              IF (TG_OP = 'UPDATE' AND (OLD.role = 'OWNER' OR NEW.role = 'OWNER')) OR
                 (TG_OP = 'DELETE' AND OLD.role = 'OWNER') THEN
                PERFORM 1 FROM public.groups WHERE id = target_group_id FOR UPDATE;
              END IF;

              -- 3. Promotion to OWNER: Only existing group OWNER can promote anyone to OWNER
              IF TG_OP = 'UPDATE' AND (OLD.role != 'OWNER' AND NEW.role = 'OWNER') THEN
                IF caller_is_client AND NOT EXISTS (
                  SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = target_group_id
                    AND gm.user_id = caller_sub
                    AND gm.role = 'OWNER'
                    AND gm.is_active = true
                ) THEN
                  RAISE EXCEPTION 'Only an existing group OWNER can promote a member to OWNER.';
                END IF;
              END IF;

              -- 4. Demotion, Deactivation, or Deletion of an OWNER:
              IF (TG_OP = 'UPDATE' AND OLD.role = 'OWNER' AND (NEW.role != 'OWNER' OR NEW.is_active = false)) OR
                 (TG_OP = 'DELETE' AND OLD.role = 'OWNER') THEN
                
                -- Client role authorization: must be an active group OWNER to demote or remove an OWNER
                IF caller_is_client AND NOT EXISTS (
                  SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = target_group_id
                    AND gm.user_id = caller_sub
                    AND gm.role = 'OWNER'
                    AND gm.is_active = true
                ) THEN
                  RAISE EXCEPTION 'Only a group OWNER can demote an existing OWNER.';
                END IF;

                -- Invariant check: Group must ALWAYS retain at least one other active OWNER
                SELECT count(*) INTO remaining_owners
                FROM public.group_members gm
                WHERE gm.group_id = target_group_id
                  AND gm.role = 'OWNER'
                  AND gm.is_active = true
                  AND gm.id != OLD.id;

                IF remaining_owners = 0 THEN
                  RAISE EXCEPTION 'Cannot demote or remove the last active OWNER: group must have at least one active OWNER.';
                END IF;
              END IF;

              IF TG_OP = 'DELETE' THEN
                RETURN OLD;
              ELSE
                RETURN NEW;
              END IF;
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS trg_protect_group_member_fields ON public.group_members;")

        op.execute("""
            CREATE TRIGGER trg_protect_group_member_fields
            BEFORE UPDATE OR DELETE ON public.group_members
            FOR EACH ROW EXECUTE FUNCTION public.check_group_members_immutable_fields();
        """)

        # 5. Concurrency-Safe Atomic Invitation & Pending Participant Consumption Trigger
        op.execute("""
            CREATE OR REPLACE FUNCTION public.consume_invitation_or_claim_on_join()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = ''
            AS $$
            DECLARE
              user_email text;
              user_phone text;
              caller_sub pg_catalog.uuid;
              invites_updated integer := 0;
              claims_updated integer := 0;
              is_admin_or_owner boolean := false;
              is_creator boolean := false;
              target_pp_id pg_catalog.uuid;
              target_inv_id pg_catalog.uuid;
            BEGIN
              -- 1. Extract candidate identity from profile
              SELECT email, phone_number INTO user_email, user_phone
              FROM public.profiles
              WHERE id = NEW.user_id;

              caller_sub := NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::pg_catalog.uuid;

              -- 2. Determine if caller is an admin/owner or creator
              IF caller_sub IS NOT NULL THEN
                SELECT EXISTS (
                  SELECT 1 FROM public.groups g
                  WHERE g.id = NEW.group_id AND g.created_by = caller_sub
                ) INTO is_creator;

                SELECT EXISTS (
                  SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = NEW.group_id
                    AND gm.user_id = caller_sub
                    AND gm.role IN ('OWNER', 'ADMIN')
                    AND gm.is_active = true
                ) INTO is_admin_or_owner;
              END IF;

              -- 3. Atomic Invitation Consumption with Row Lock
              IF user_email IS NOT NULL THEN
                SELECT inv.id INTO target_inv_id
                FROM public.invitations inv
                WHERE inv.group_id = NEW.group_id
                  AND pg_catalog.lower(inv.email) = pg_catalog.lower(user_email)
                  AND inv.status = 'PENDING'
                  AND inv.expires_at > pg_catalog.now()
                FOR UPDATE
                LIMIT 1;

                IF target_inv_id IS NOT NULL THEN
                  UPDATE public.invitations
                  SET status = 'ACCEPTED'
                  WHERE id = target_inv_id
                    AND status = 'PENDING';
                  GET DIAGNOSTICS invites_updated = ROW_COUNT;
                END IF;
              END IF;

              -- 4. Atomic Pending Participant Consumption with Row Lock
              SELECT pp.id INTO target_pp_id
              FROM public.pending_participants pp
              WHERE pp.group_id = NEW.group_id
                AND pp.status = 'ACTIVE'
                AND (
                  (user_email IS NOT NULL AND pp.email IS NOT NULL AND pg_catalog.lower(pp.email) = pg_catalog.lower(user_email)) OR
                  (user_phone IS NOT NULL AND pp.phone_number IS NOT NULL AND pp.phone_number = user_phone)
                )
              FOR UPDATE
              LIMIT 1;

              IF target_pp_id IS NOT NULL THEN
                UPDATE public.pending_participants
                SET status = 'CLAIMED',
                    claimed_by_user_id = NEW.user_id,
                    claimed_at = pg_catalog.now()
                WHERE id = target_pp_id
                  AND status = 'ACTIVE';
                GET DIAGNOSTICS claims_updated = ROW_COUNT;
              END IF;

              -- 5. Strict Concurrency Validation for Self-Joining Users:
              -- If this is an unprivileged client self-joining (user_id = auth.uid(), not creator, not admin/owner),
              -- they MUST successfully consume at least one valid invitation or pending participant.
              -- If another transaction claimed the record first, claims_updated and invites_updated are 0,
              -- triggering an immediate exception that rolls back this transaction.
              IF (caller_sub IS NOT NULL AND NEW.user_id = caller_sub AND NOT is_creator AND NOT is_admin_or_owner) THEN
                IF (invites_updated = 0 AND claims_updated = 0) THEN
                  RAISE EXCEPTION 'Concurrent join failed: Pending participant or invitation has already been claimed or expired.';
                END IF;
              END IF;

              RETURN NEW;
            END;
            $$;
        """)

        op.execute("DROP TRIGGER IF EXISTS trg_consume_invite_on_member_join ON public.group_members;")

        op.execute("""
            CREATE TRIGGER trg_consume_invite_on_member_join
            AFTER INSERT ON public.group_members
            FOR EACH ROW EXECUTE FUNCTION public.consume_invitation_or_claim_on_join();
        """)

        # 6. Helper Function for Circular-Free Invitation & Claim Verification
        op.execute("""
            CREATE OR REPLACE FUNCTION public.can_join_group(check_group_id pg_catalog.uuid, check_user_id pg_catalog.uuid)
            RETURNS pg_catalog.bool
            LANGUAGE sql
            SECURITY DEFINER
            STABLE
            SET search_path = ''
            AS $$
              SELECT EXISTS (
                SELECT 1 FROM public.invitations inv
                JOIN public.profiles p ON p.id = check_user_id
                WHERE inv.group_id = check_group_id
                  AND pg_catalog.lower(inv.email) = pg_catalog.lower(p.email)
                  AND inv.status = 'PENDING'
                  AND inv.expires_at > pg_catalog.now()
              ) OR EXISTS (
                SELECT 1 FROM public.pending_participants pp
                JOIN public.profiles p ON p.id = check_user_id
                WHERE pp.group_id = check_group_id
                  AND pp.status = 'ACTIVE'
                  AND (
                    (pp.email IS NOT NULL AND pg_catalog.lower(pp.email) = pg_catalog.lower(p.email)) OR
                    (pp.phone_number IS NOT NULL AND p.phone_number IS NOT NULL AND pp.phone_number = p.phone_number)
                  )
              );
            $$;
        """)

        # 7. Replace group_members_insert with Hardened Multi-Condition Policy
        op.execute('DROP POLICY IF EXISTS "group_members_insert" ON public.group_members;')
        op.execute("""
            CREATE POLICY "group_members_insert" ON public.group_members
            FOR INSERT WITH CHECK (
                -- 1. Existing Group OWNER adding or transferring OWNER role
                (
                    role = 'OWNER' AND
                    EXISTS (
                        SELECT 1 FROM public.group_members gm
                        WHERE gm.group_id = group_members.group_id
                          AND gm.user_id = auth.uid()
                          AND gm.role = 'OWNER'
                          AND gm.is_active = true
                    )
                ) OR
                
                -- 2. Group Creator bootstrapping initial OWNER membership
                (
                    user_id = auth.uid() AND
                    role = 'OWNER' AND
                    EXISTS (
                        SELECT 1 FROM public.groups g
                        WHERE g.id = group_members.group_id
                          AND g.created_by = auth.uid()
                    )
                ) OR
                
                -- 3. Group Admin (or Owner) adding an ADMIN or MEMBER (strictly forbidden from assigning OWNER)
                (
                    role IN ('MEMBER', 'ADMIN') AND
                    public.is_group_admin(group_id, auth.uid())
                ) OR
                
                -- 4. Joining via valid invitation or pending claim (strictly MEMBER role)
                (
                    user_id = auth.uid() AND
                    role = 'MEMBER' AND
                    public.can_join_group(group_id, auth.uid())
                )
            );
        """)

        # 8. Update pending_participants_select to permit claimable lookups without RLS deadlock
        op.execute('DROP POLICY IF EXISTS "pending_participants_select" ON public.pending_participants;')
        op.execute("""
            CREATE POLICY "pending_participants_select" ON public.pending_participants
            FOR SELECT USING (
                public.is_group_member(group_id, auth.uid()) OR
                claimed_by_user_id = auth.uid() OR
                (email IS NOT NULL AND pg_catalog.lower(email) = (SELECT pg_catalog.lower(p.email) FROM public.profiles p WHERE p.id = auth.uid())) OR
                (phone_number IS NOT NULL AND phone_number = (SELECT p.phone_number FROM public.profiles p WHERE p.id = auth.uid()))
            );
        """)

        # 9. Replace group_members_update with WITH CHECK preventing unauthorized promotion to OWNER
        op.execute('DROP POLICY IF EXISTS "group_members_update" ON public.group_members;')
        op.execute("""
            CREATE POLICY "group_members_update" ON public.group_members
            FOR UPDATE USING (
                public.is_group_admin(group_id, auth.uid())
            )
            WITH CHECK (
                (role != 'OWNER' OR EXISTS (
                    SELECT 1 FROM public.group_members gm
                    WHERE gm.group_id = group_members.group_id
                      AND gm.user_id = auth.uid()
                      AND gm.role = 'OWNER'
                ))
            );
        """)

        # 8. Revoke direct write privileges from client roles to guarantee FastAPI write authority
        op.execute("""
            DO $$
            BEGIN
                IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
                    REVOKE INSERT, UPDATE, DELETE ON 
                        public.expenses,
                        public.expense_payers,
                        public.expense_splits,
                        public.expense_participants,
                        public.settlements,
                        public.receipts,
                        public.activity_events,
                        public.financial_audit_logs,
                        public.exchange_rate_snapshots,
                        public.subscriptions,
                        public.subscription_webhook_events,
                        public.revoked_tokens
                    FROM anon;
                END IF;

                IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
                    REVOKE INSERT, UPDATE, DELETE ON 
                        public.expenses,
                        public.expense_payers,
                        public.expense_splits,
                        public.expense_participants,
                        public.settlements,
                        public.receipts,
                        public.activity_events,
                        public.financial_audit_logs,
                        public.exchange_rate_snapshots,
                        public.subscriptions,
                        public.subscription_webhook_events,
                        public.revoked_tokens
                    FROM authenticated;
                END IF;
            END $$;
        """)

        # 10. Schema Security Hardening: Revoke CREATE on schema public and grant explicit EXECUTE
        op.execute("REVOKE CREATE ON SCHEMA public FROM PUBLIC;")
        op.execute("REVOKE EXECUTE ON FUNCTION public.is_group_member(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;")
        op.execute("REVOKE EXECUTE ON FUNCTION public.is_group_admin(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;")
        op.execute("REVOKE EXECUTE ON FUNCTION public.can_join_group(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;")
        op.execute("""
            DO $$
            BEGIN
                IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
                    REVOKE CREATE ON SCHEMA public FROM anon;
                    REVOKE EXECUTE ON FUNCTION public.is_group_member(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
                    REVOKE EXECUTE ON FUNCTION public.is_group_admin(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
                    REVOKE EXECUTE ON FUNCTION public.can_join_group(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
                END IF;
                IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
                    REVOKE CREATE ON SCHEMA public FROM authenticated;
                    GRANT EXECUTE ON FUNCTION public.is_group_member(pg_catalog.uuid, pg_catalog.uuid) TO authenticated;
                    GRANT EXECUTE ON FUNCTION public.is_group_admin(pg_catalog.uuid, pg_catalog.uuid) TO authenticated;
                    GRANT EXECUTE ON FUNCTION public.can_join_group(pg_catalog.uuid, pg_catalog.uuid) TO authenticated;
                END IF;
            END $$;
        """)


def downgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"

    if is_pg:
        # 1. Drop Triggers added in 0002
        op.execute("DROP TRIGGER IF EXISTS trg_consume_invite_on_member_join ON public.group_members;")
        op.execute("DROP TRIGGER IF EXISTS trg_protect_group_member_fields ON public.group_members;")
        op.execute("DROP TRIGGER IF EXISTS trg_protect_group_fields ON public.groups;")
        op.execute("DROP TRIGGER IF EXISTS trg_protect_profile_fields ON public.profiles;")

        # 2. Restore original 0001 policies FIRST to eliminate policy dependency on can_join_group
        op.execute('DROP POLICY IF EXISTS "pending_participants_select" ON public.pending_participants;')
        op.execute("""
            CREATE POLICY "pending_participants_select" ON public.pending_participants
            FOR SELECT USING (public.is_group_member(group_id, auth.uid()));
        """)

        op.execute('DROP POLICY IF EXISTS "group_members_insert" ON public.group_members;')
        op.execute("""
            CREATE POLICY "group_members_insert" ON public.group_members
            FOR INSERT WITH CHECK (
                public.is_group_admin(group_id, auth.uid()) OR
                user_id = auth.uid()
            );
        """)

        op.execute('DROP POLICY IF EXISTS "group_members_update" ON public.group_members;')
        op.execute("""
            CREATE POLICY "group_members_update" ON public.group_members
            FOR UPDATE USING (public.is_group_admin(group_id, auth.uid()));
        """)

        # 3. Drop Functions added in 0002 explicitly without CASCADE
        op.execute("DROP FUNCTION IF EXISTS public.can_join_group(pg_catalog.uuid, pg_catalog.uuid);")
        op.execute("DROP FUNCTION IF EXISTS public.consume_invitation_or_claim_on_join();")
        op.execute("DROP FUNCTION IF EXISTS public.check_group_members_immutable_fields();")
        op.execute("DROP FUNCTION IF EXISTS public.check_groups_immutable_fields();")
        op.execute("DROP FUNCTION IF EXISTS public.check_profile_immutable_fields();")

        # 4. Restore original 0001 functions without empty search_path
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
