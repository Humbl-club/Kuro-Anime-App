-- Security hardening: enable RLS on 5 unprotected tables + fix 5 SECURITY DEFINER views.
-- Deployed to production 2026-02-06 via MCP.

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) Enable Row-Level Security on tables that were missing it
-- ═══════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.editorial_boosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.editorial_penalty_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.editorial_tag_boosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mirror_runs ENABLE ROW LEVEL SECURITY;

-- Read-only policies for service_role (these tables are backend-managed, not user-facing)
CREATE POLICY "service_role_read" ON public.editorial_boosts
  FOR SELECT TO service_role USING (true);

CREATE POLICY "service_role_read" ON public.editorial_penalty_tags
  FOR SELECT TO service_role USING (true);

CREATE POLICY "service_role_read" ON public.editorial_tag_boosts
  FOR SELECT TO service_role USING (true);

CREATE POLICY "service_role_all" ON public.import_state
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "service_role_all" ON public.mirror_runs
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) Switch 5 views from SECURITY DEFINER to SECURITY INVOKER
-- ═══════════════════════════════════════════════════════════════════════════════
ALTER VIEW public.rate_limit_recent_top SET (security_invoker = on);
ALTER VIEW public.llm_usage_daily_totals SET (security_invoker = on);
ALTER VIEW public.user_airing_next SET (security_invoker = on);
ALTER VIEW public.concierge_metrics_hourly SET (security_invoker = on);
ALTER VIEW public.user_lists SET (security_invoker = on);
