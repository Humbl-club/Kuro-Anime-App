-- Concierge router hardening:
-- - Add independent kill-switch for LLM mode routing fallback
-- - Retention for concierge_mode_cache

begin;

-- Router kill switch (separate from llm_enabled narration/resolve).
insert into public.system_flags(key, enabled)
values ('llm_router_enabled', false)
on conflict (key) do nothing;

-- Extend housekeeping to prune mode cache.
create or replace function public.concierge_housekeeping()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare cfg jsonb;
declare r jsonb;
declare days_rate integer;
declare days_llm integer;
declare days_import integer;
declare days_runs integer;
declare days_feedback integer;
declare days_mode_cache integer;
begin
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);
  days_mode_cache := coalesce((r->>'mode_cache')::int, 30);

  delete from public.rate_limit_buckets
  where window_start < now() - make_interval(days => greatest(1, days_rate));

  delete from public.llm_daily_usage
  where day < (timezone('utc', now())::date - greatest(7, days_llm));

  -- Import sessions/items (only completed/cancelled/failed; keep drafts).
  delete from public.import_session_items i
  using public.import_sessions s
  where i.session_id = s.id
    and s.status in ('applied','cancelled','failed')
    and s.updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.import_sessions
  where status in ('applied','cancelled','failed')
    and updated_at < now() - make_interval(days => greatest(7, days_import));

  delete from public.concierge_runs
  where created_at < now() - make_interval(days => greatest(14, days_runs));

  delete from public.concierge_parse_feedback
  where created_at < now() - make_interval(days => greatest(7, days_feedback));

  delete from public.concierge_mode_cache
  where updated_at < now() - make_interval(days => greatest(7, days_mode_cache));
end $$;

-- Patch config retention defaults to include mode_cache (best-effort).
update public.concierge_config
set config = jsonb_set(
  config,
  '{retention_days,mode_cache}',
  to_jsonb(30),
  true
)
where id = true
  and (config->'retention_days'->>'mode_cache') is null;

commit;

