-- Phase 1: Critical Security — Drop dangerous functions + revoke access
-- P0 security fixes from backend quality audit

-- 1. Drop 4 dead functions (2 contain hardcoded service_role JWT)
DROP FUNCTION IF EXISTS public.check_and_trigger_sync();
DROP FUNCTION IF EXISTS public.start_bulk_import();
DROP FUNCTION IF EXISTS public.heartbeat();
DROP FUNCTION IF EXISTS public.on_heartbeat();

-- 2. Revoke anon/authenticated access from admin-only functions
REVOKE EXECUTE ON FUNCTION public.admin_schema_snapshot() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rebuild_title_search() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.concierge_housekeeping() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_mirror_health(integer, integer) FROM anon, authenticated;

-- 3. Fix concierge_mode_analytics INSERT policy
-- Was WITH CHECK (false) — blocked ALL authenticated inserts.
-- Table has no user_id column (anonymous analytics: mode_id, confidence, prompt_hash).
-- Service_role (edge functions) bypasses RLS anyway.
-- Change to WITH CHECK (true) so authenticated clients can also log analytics.
DROP POLICY IF EXISTS mode_analytics_insert ON public.concierge_mode_analytics;
CREATE POLICY mode_analytics_insert ON public.concierge_mode_analytics
  FOR INSERT TO authenticated
  WITH CHECK (true);;
