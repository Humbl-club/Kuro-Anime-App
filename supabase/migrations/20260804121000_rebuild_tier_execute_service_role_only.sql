-- Follow-up to 20260804120000: lock rebuild_media_realm_tier() EXECUTE down to
-- service_role. Supabase default privileges grant EXECUTE on new functions to
-- anon/authenticated/service_role; 20260804120000 only revoked from the PUBLIC
-- pseudo-role, leaving anon/authenticated with EXECUTE (observed in proacl
-- post-push). Same class of fix as 20260802017000_realm_llm_upsert_service_role_only.
-- The nightly cron is unaffected: it runs as the function owner (postgres),
-- whose implicit EXECUTE does not depend on these grants.

begin;

revoke all on function public.rebuild_media_realm_tier() from public, anon, authenticated;
grant execute on function public.rebuild_media_realm_tier() to service_role;

commit;
