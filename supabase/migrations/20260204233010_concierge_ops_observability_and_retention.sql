-- Concierge ops hardening:
-- - Config table for tunable guardrails without redeploy
-- - Parse feedback logging (low-confidence/no-match)
-- - Retention + housekeeping (pg_cron)
-- - Admin-only metrics views (no grants)

begin;
-- 1) Config (single-row JSON, simple to edit in the dashboard).
create table if not exists public.concierge_config (
  id boolean primary key default true, -- single row: id=true
  config jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.concierge_config enable row level security;
-- No policies: clients cannot read/write config directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'concierge_config_set_updated_at') then
    create trigger concierge_config_set_updated_at
      before update on public.concierge_config
      for each row execute function public.set_updated_at();
  end if;
end $$;
-- Default config (safe launch defaults).
insert into public.concierge_config(id, config)
values (
  true,
  jsonb_build_object(
    'rate_limits', jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 140, 'max_ip', 240),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 18, 'max_ip', 80),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 30, 'max_ip', 100)
    ),
    'llm_budget', jsonb_build_object(
      'daily_tokens', 20000,
      'daily_calls', 80
    ),
    'parse_feedback', jsonb_build_object(
      'enabled', true,
      'low_confidence_score', 0.55,
      'max_log_chars', 140
    ),
    'retention_days', jsonb_build_object(
      'rate_limit_buckets', 2,
      'llm_daily_usage', 90,
      'import_sessions', 30,
      'concierge_runs', 60,
      'parse_feedback', 14
    )
  )
)
on conflict (id) do nothing;
create or replace function public.get_concierge_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare cfg jsonb;
begin
  select config into cfg from public.concierge_config where id = true;
  return coalesce(cfg, '{}'::jsonb);
end $$;
grant execute on function public.get_concierge_config() to anon, authenticated;
-- 2) Parse feedback table (for iterative improvement).
create table if not exists public.concierge_parse_feedback (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  raw_snippet text,
  normalized text,
  alias_norm text,
  best_score real,
  candidates_count integer,
  top_media_type text,
  top_media_id integer,
  created_at timestamptz not null default now()
);
create index if not exists idx_concierge_parse_feedback_created on public.concierge_parse_feedback (created_at desc);
create index if not exists idx_concierge_parse_feedback_user_created on public.concierge_parse_feedback (user_id, created_at desc);
alter table public.concierge_parse_feedback enable row level security;
-- No policies: do not expose raw user text to other clients.

create or replace function public.log_concierge_parse_feedback(
  p_raw text,
  p_normalized text,
  p_alias_norm text,
  p_best_score real,
  p_candidates_count integer,
  p_top_media_type text,
  p_top_media_id integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare cfg jsonb;
declare enabled boolean;
declare low_score real;
declare max_chars integer;
begin
  uid := auth.uid();
  if uid is null then
    return;
  end if;

  cfg := public.get_concierge_config();
  enabled := coalesce((cfg->'parse_feedback'->>'enabled')::boolean, true);
  if not enabled then
    return;
  end if;

  low_score := coalesce((cfg->'parse_feedback'->>'low_confidence_score')::real, 0.55);
  if p_best_score is not null and p_best_score >= low_score then
    return;
  end if;

  max_chars := greatest(20, least(coalesce((cfg->'parse_feedback'->>'max_log_chars')::int, 140), 400));

  insert into public.concierge_parse_feedback(
    user_id, raw_snippet, normalized, alias_norm, best_score, candidates_count, top_media_type, top_media_id
  )
  values(
    uid,
    left(coalesce(p_raw, ''), max_chars),
    left(coalesce(p_normalized, ''), max_chars),
    left(coalesce(p_alias_norm, ''), max_chars),
    p_best_score,
    p_candidates_count,
    left(coalesce(p_top_media_type, ''), 16),
    p_top_media_id
  );
end $$;
grant execute on function public.log_concierge_parse_feedback(text, text, text, real, integer, text, integer) to authenticated;
-- 3) Make guardrail functions read defaults from config when caller passes null.
create or replace function public.check_concierge_rate_limit(
  p_kind text,
  p_ip text,
  p_window_seconds integer default 60,
  p_max_user integer default 40,
  p_max_ip integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare u_hits integer;
declare ip_hits integer;
declare allow boolean := true;
declare retry_after integer;
declare kind text;
declare cfg jsonb;
declare rl jsonb;
declare win_s integer;
declare max_u integer;
declare max_i integer;
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  cfg := public.get_concierge_config();
  rl := cfg->'rate_limits'->kind;

  win_s := coalesce(p_window_seconds, (rl->>'window_seconds')::int, 60);
  max_u := coalesce(p_max_user, (rl->>'max_user')::int, 40);
  max_i := coalesce(p_max_ip, (rl->>'max_ip')::int, 120);

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || win_s::text, win_s);
    if u_hits > coalesce(max_u, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || win_s::text, win_s);
    if ip_hits > coalesce(max_i, 0) then allow := false; end if;
  end if;

  retry_after := win_s - (extract(epoch from now())::integer % win_s);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after,
    'window_seconds', win_s,
    'max_user', max_u,
    'max_ip', max_i
  );
end $$;
-- LLM budget defaults from config when caller passes null.
create or replace function public.llm_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer default 20000,
  p_max_daily_calls integer default 80,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
declare cfg jsonb;
declare budget jsonb;
declare max_tokens integer;
declare max_calls integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

  cfg := public.get_concierge_config();
  budget := cfg->'llm_budget';
  max_tokens := coalesce(p_max_daily_tokens, (budget->>'daily_tokens')::int, 20000);
  max_calls := coalesce(p_max_daily_calls, (budget->>'daily_calls')::int, 80);

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select
    coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0),
    coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_daily_usage
  where user_id = uid and day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow :=
    next_tokens <= coalesce(max_tokens, 0)
    and next_calls <= coalesce(max_calls, 0);

  if allow then
    insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
    values (uid, d, p_reserved_tokens, 0, 1, p_model)
    on conflict (user_id, day)
    do update set
      reserved_tokens = public.llm_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_daily_usage.calls + 1,
      last_model = coalesce(excluded.last_model, public.llm_daily_usage.last_model),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'allowed', allow,
    'day', d::text,
    'used_tokens', coalesce(used_tokens, 0),
    'used_calls', coalesce(used_calls, 0),
    'next_tokens', next_tokens,
    'next_calls', next_calls,
    'max_daily_tokens', max_tokens,
    'max_daily_calls', max_calls
  );
end $$;
-- 4) Housekeeping + retention.
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
begin
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);

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
end $$;
-- Schedule housekeeping daily (best-effort). If pg_cron isn't available, the function still exists.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    -- ignore if extension not available in this environment
    return;
  end;

  -- Ensure we don't double-schedule.
  if not exists (select 1 from cron.job where jobname = 'concierge_housekeeping_daily') then
    perform cron.schedule('concierge_housekeeping_daily', '0 4 * * *', 'select public.concierge_housekeeping();');
  end if;
end $$;
-- 5) Admin views (no grants; use dashboard/service role).
create or replace view public.concierge_metrics_hourly as
select
  date_trunc('hour', created_at) as hour,
  kind,
  status,
  count(*)::int as runs,
  coalesce(sum(items_count), 0)::int as items_total,
  coalesce(avg(latency_ms), 0)::real as avg_latency_ms,
  coalesce(sum(case when error is null then 0 else 1 end), 0)::int as errors
from public.concierge_runs
group by 1, 2, 3;
create or replace view public.llm_usage_daily_totals as
select
  day,
  count(*)::int as users,
  sum(actual_tokens)::bigint as actual_tokens,
  sum(reserved_tokens)::bigint as reserved_tokens,
  sum(calls)::bigint as calls
from public.llm_daily_usage
group by 1
order by day desc;
create or replace view public.rate_limit_recent_top as
select
  window_start,
  bucket_key,
  hits
from public.rate_limit_buckets
where window_start > now() - interval '6 hours'
order by hits desc, window_start desc
limit 200;
commit;
