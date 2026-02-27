-- Club analytics / telemetry table + RPC + housekeeping integration.
-- Events: club_created, club_joined, club_left, rail_opened, vote_cast, import_applied, import_undone.
-- NO content logging (no titles, no user data beyond uid + club_id).

begin;
-- 1. Analytics table
create table if not exists public.club_analytics (
  id         uuid primary key default gen_random_uuid(),
  event_type text not null,
  club_id    uuid,
  user_id    uuid,
  metadata   jsonb default '{}',
  created_at timestamptz not null default now()
);
alter table public.club_analytics enable row level security;
-- Authenticated users can insert rows for their own user_id only.
create policy "club_analytics_insert_own"
  on public.club_analytics
  for insert
  to authenticated
  with check (user_id = auth.uid());
-- Only service_role can read analytics (no user-facing reads).
create policy "club_analytics_select_service"
  on public.club_analytics
  for select
  to service_role
  using (true);
-- Index for housekeeping (age-based deletion) and per-club queries.
create index if not exists idx_club_analytics_created_at
  on public.club_analytics (created_at);
create index if not exists idx_club_analytics_club_id
  on public.club_analytics (club_id)
  where club_id is not null;
-- 2. RPC: log_club_event (SECURITY DEFINER so user_id is always auth.uid())
create or replace function public.log_club_event(
  p_event_type text,
  p_club_id    uuid default null,
  p_metadata   jsonb default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.club_analytics (event_type, club_id, user_id, metadata)
  values (p_event_type, p_club_id, auth.uid(), p_metadata);
end;
$$;
-- 3. Extend concierge_housekeeping to prune club_analytics > 90 days.
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
declare days_club_analytics integer;
begin
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);
  days_mode_cache := coalesce((r->>'mode_cache')::int, 30);
  days_club_analytics := coalesce((r->>'club_analytics')::int, 90);

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

  -- Club analytics: 90-day default retention.
  delete from public.club_analytics
  where created_at < now() - make_interval(days => greatest(30, days_club_analytics));
end $$;
-- 4. Add retention config default for club_analytics.
update public.concierge_config
set config = jsonb_set(
  config,
  '{retention_days,club_analytics}',
  to_jsonb(90),
  true
)
where id = true
  and (config->'retention_days'->>'club_analytics') is null;
commit;
