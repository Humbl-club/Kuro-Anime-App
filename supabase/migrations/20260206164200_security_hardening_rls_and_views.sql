
-- Enable RLS on 5 exposed tables (currently fully open to anon key)
ALTER TABLE public.editorial_boosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.editorial_penalty_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.editorial_tag_boosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mirror_runs ENABLE ROW LEVEL SECURITY;

-- Fix SECURITY DEFINER views → SECURITY INVOKER (respect caller's RLS)
ALTER VIEW public.rate_limit_recent_top SET (security_invoker = on);
ALTER VIEW public.llm_usage_daily_totals SET (security_invoker = on);
ALTER VIEW public.user_airing_next SET (security_invoker = on);
ALTER VIEW public.concierge_metrics_hourly SET (security_invoker = on);
ALTER VIEW public.user_lists SET (security_invoker = on);
;
