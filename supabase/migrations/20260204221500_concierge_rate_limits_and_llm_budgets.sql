-- Server-side guardrails for Concierge:
-- - Rate limits (per-user and per-IP) for Edge Functions
-- - LLM daily budget + global kill-switch flag

begin;

-- 1) Kill switch / flags (readable via SECURITY DEFINER function).
create table if not exists public.system_flags (
  key text primary key,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.system_flags enable row level security;

-- No policies: clients cannot read flags directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'system_flags_set_updated_at') then
    create trigger system_flags_set_updated_at
      before update on public.system_flags
      for each row execute function public.set_updated_at();
  end if;
end $$;

insert into public.system_flags(key, enabled)
values ('llm_enabled', true)
on conflict (key) do nothing;

create or replace function public.is_flag_enabled(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v boolean;
begin
  select enabled into v from public.system_flags where key = p_key;
  return coalesce(v, true);
end $$;

grant execute on function public.is_flag_enabled(text) to anon, authenticated;

-- 2) Rate limit buckets (atomic upsert increments).
create table if not exists public.rate_limit_buckets (
  bucket_key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_key, window_start)
);

create index if not exists idx_rate_limit_buckets_window_start on public.rate_limit_buckets (window_start desc);

alter table public.rate_limit_buckets enable row level security;
-- No policies: users cannot read/write buckets directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'rate_limit_buckets_set_updated_at') then
    create trigger rate_limit_buckets_set_updated_at
      before update on public.rate_limit_buckets
      for each row execute function public.set_updated_at();
  end if;
end $$;

create or replace function public.rate_limit_hit(
  p_bucket_key text,
  p_window_seconds integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare wstart timestamptz;
declare v integer;
begin
  if p_bucket_key is null or length(p_bucket_key) = 0 then
    raise exception 'rate_limit_hit: missing bucket_key';
  end if;
  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'rate_limit_hit: invalid window_seconds';
  end if;

  -- Fixed window bucket aligned to epoch.
  wstart := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_buckets(bucket_key, window_start, hits)
  values (p_bucket_key, wstart, 1)
  on conflict (bucket_key, window_start)
  do update set hits = public.rate_limit_buckets.hits + 1, updated_at = now()
  returning hits into v;

  return v;
end $$;

grant execute on function public.rate_limit_hit(text, integer) to anon, authenticated;

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
begin
  uid := auth.uid();
  kind := coalesce(nullif(p_kind, ''), 'any');

  if uid is null and (p_ip is null or length(p_ip) = 0) then
    return jsonb_build_object('allowed', true, 'note', 'no uid/ip');
  end if;

  if uid is not null then
    u_hits := public.rate_limit_hit('user:' || uid::text || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if u_hits > coalesce(p_max_user, 0) then allow := false; end if;
  end if;

  if p_ip is not null and length(p_ip) > 0 then
    ip_hits := public.rate_limit_hit('ip:' || p_ip || ':' || kind || ':' || p_window_seconds::text, p_window_seconds);
    if ip_hits > coalesce(p_max_ip, 0) then allow := false; end if;
  end if;

  retry_after := p_window_seconds - (extract(epoch from now())::integer % p_window_seconds);
  return jsonb_build_object(
    'allowed', allow,
    'user_hits', u_hits,
    'ip_hits', ip_hits,
    'retry_after_s', retry_after
  );
end $$;

grant execute on function public.check_concierge_rate_limit(text, text, integer, integer, integer) to anon, authenticated;

-- 3) LLM daily budget (reserve + finalize to keep budgets accurate and concurrency-safe).
create table if not exists public.llm_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  last_model text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.llm_daily_usage enable row level security;
-- No policies: users cannot read/write usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_daily_usage_set_updated_at') then
    create trigger llm_daily_usage_set_updated_at
      before update on public.llm_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;

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
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;

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
    next_tokens <= coalesce(p_max_daily_tokens, 0)
    and next_calls <= coalesce(p_max_daily_calls, 0);

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
    'max_daily_tokens', p_max_daily_tokens,
    'max_daily_calls', p_max_daily_calls
  );
end $$;

create or replace function public.llm_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer,
  p_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare tokens_total integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  uid := auth.uid();
  if uid is null then
    return jsonb_build_object('success', false, 'reason', 'unauthenticated');
  end if;

  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(uid::text || ':' || d::text || ':llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  -- Ensure row exists even if finalize is called after a failed reserve (best-effort).
  insert into public.llm_daily_usage(user_id, day, reserved_tokens, actual_tokens, calls, last_model)
  values (uid, d, 0, 0, 0, p_model)
  on conflict (user_id, day) do nothing;

  update public.llm_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    last_model = coalesce(p_model, last_model),
    updated_at = now()
  where user_id = uid and day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_daily_usage
  where user_id = uid and day = d;

  tokens_total := coalesce(reserved_total, 0) + coalesce(actual_total, 0);
  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'tokens_total', coalesce(tokens_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;

grant execute on function public.llm_budget_reserve(integer, integer, integer, text) to authenticated;
grant execute on function public.llm_budget_finalize(integer, integer, text) to authenticated;

commit;
