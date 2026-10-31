-- ============================================================================
-- club_rails: direct INSERT aligned with create_club_rail (owner/admin only)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate,
--         explicit human approval. Listed in supabase/tests/pending_migrations.txt.
--         This file lives in supabase/prepared-migrations/ so no push can deploy it by
--         accident; after approval, `git mv` it into supabase/migrations/.
--
-- Finding (E2 backend harness, finding 7, observed in the local fixture):
--   club_rails_insert_member allows ANY member to insert a rail through the
--   table API (WITH CHECK is_club_member(club_id) AND created_by = auth.uid()),
--   while the create_club_rail RPC raises NOT_ADMIN for non owner/admin members.
--   UPDATE and DELETE on club_rails are already owner/admin only, so a plain
--   member could create rails that no plain member can then edit or remove.
--
-- Fix: replace the INSERT policy with the RPC's rule: caller is owner/admin of
-- the club AND created_by is the caller. The iOS client creates rails only via
-- create_club_rail (SECURITY DEFINER, owned by postgres, so table policies do not
-- gate it); nothing in Kuro/ inserts into club_rails directly.
-- (The RPC also sanitizes the title and computes sort_order; a direct INSERT by an
--  owner/admin still bypasses that, as before. Removing direct INSERT entirely is
--  the stricter alternative if the owner prefers RPC-only writes.)
--
-- Production parity: this repo chain is production's captured policy state;
-- production can differ through changes made outside the chain. Verify read-only
-- before deploying:
--   select policyname, cmd, roles, qual, with_check from pg_policies
--    where schemaname = 'public' and tablename = 'club_rails';
-- Post-deploy verification: the INSERT row must be club_rails_insert_admin with
--   (is_club_admin_or_owner(club_id) AND (created_by = (SELECT auth.uid() ...)))
--
-- Idempotent: both policy names are dropped if present, then the new one is created.
-- Rollback (re-opens the mismatch):
--   drop policy if exists club_rails_insert_admin on public.club_rails;
--   create policy club_rails_insert_member on public.club_rails for insert to authenticated
--     with check (public.is_club_member(club_id) and created_by = auth.uid());
-- ============================================================================

drop policy if exists club_rails_insert_member on public.club_rails;
drop policy if exists club_rails_insert_admin on public.club_rails;

create policy club_rails_insert_admin on public.club_rails
  for insert to authenticated
  with check (
    public.is_club_admin_or_owner(club_id)
    and created_by = (select auth.uid())
  );

-- RLS stays enabled (no-op if already on).
alter table public.club_rails enable row level security;
