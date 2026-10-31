-- ============================================================================
-- Legacy view public.user_lists: invoker semantics (F40)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate, explicit
--   human approval; the lead registers it in supabase/tests/pending_migrations.txt.
--
-- The view (legacy_sql/08_create_user_lists_view.sql) unions anime_user_lists and
-- manga_user_lists. Created by the table owner WITHOUT security_invoker it bypasses the
-- owner-only table RLS: any authenticated user reads every user's list rows (shown on
-- the fixture reconstruction in supabase/tests/rls/10_user_lists.sql). 20260206150000 /
-- 20260206164200 set security_invoker = on, but they do not replay and the view is not
-- in the baseline capture, so WHETHER THE DEPLOYED VIEW LEAKS IS UNVERIFIED.
--
-- Kept, not retired: it has live callers, all of which read only the caller's own rows
-- and keep working under invoker semantics:
--   * supabase/functions/concierge-recommend/index.ts (.from("user_lists") with the
--     caller's JWT, filtered by the JWT user id)
--   * recommend / curation SQL functions filtering `ul.user_id = auth.uid()::text`
--     (20260203223000, 20260802140000, 20260806020000, ...)
--
-- Behavior: if the view exists it gets security_invoker = on (base-table RLS applies to
-- the caller). Grants are deliberately NOT changed: an anon read already returns 0 rows
-- through the base-table policy (TO authenticated), and revoking anon would turn the
-- anon-executable SECURITY INVOKER readers (fetch_tonight_shelf, fetch_realm_hidden_gem,
-- recommend_ids_by_tag_categories; they filter by the caller's uid) from "0 rows" into a
-- permission error. If the view does not exist there is nothing that can leak and nothing
-- is created (NOTICE). If the name is something other than a view, this file fails
-- loudly for a human to inspect.
--
-- Read-only check before/after deploying (also in
-- supabase/tests/prerequisites/delete_account_prereqs.sql):
--   select c.relkind, c.reloptions, c.relacl from pg_class c
--    where c.oid = to_regclass('public.user_lists');
-- Rollback (re-opens the leak; do not use except to restore prior state):
--   alter view public.user_lists reset (security_invoker);
-- ============================================================================

do $$
declare
  v_kind "char";
begin
  select c.relkind into v_kind from pg_class c where c.oid = to_regclass('public.user_lists');
  if v_kind is null then
    raise notice 'public.user_lists does not exist: nothing to harden';
    return;
  end if;
  if v_kind <> 'v' then
    raise exception 'public.user_lists exists but is not a view (relkind %): inspect manually', v_kind;
  end if;
  execute 'alter view public.user_lists set (security_invoker = on)';
end $$;
