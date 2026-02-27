-- Add global LLM daily budget + tune default "natural usage" limits.
-- Goal: prevent LLM spend abuse even with many users.

begin;
-- 1) Global daily usage table.
create table if not exists public.llm_global_daily_usage (
  day date primary key,
  reserved_tokens integer not null default 0,
  actual_tokens integer not null default 0,
  calls integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.llm_global_daily_usage enable row level security;
-- No policies: clients cannot read/write global usage directly.

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'llm_global_daily_usage_set_updated_at') then
    create trigger llm_global_daily_usage_set_updated_at
      before update on public.llm_global_daily_usage
      for each row execute function public.set_updated_at();
  end if;
end $$;
create or replace function public.llm_global_budget_reserve(
  p_reserved_tokens integer,
  p_max_daily_tokens integer,
  p_max_daily_calls integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare used_tokens integer;
declare used_calls integer;
declare next_tokens integer;
declare next_calls integer;
declare allow boolean;
declare lock_key bigint;
begin
  d := (timezone('utc', now()))::date;
  if p_reserved_tokens is null or p_reserved_tokens < 0 or p_reserved_tokens > 500000 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_reserved_tokens');
  end if;
  if p_max_daily_tokens is null or p_max_daily_tokens < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_tokens');
  end if;
  if p_max_daily_calls is null or p_max_daily_calls < 0 then
    return jsonb_build_object('allowed', false, 'reason', 'invalid_max_daily_calls');
  end if;

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  select coalesce(actual_tokens, 0) + coalesce(reserved_tokens, 0), coalesce(calls, 0)
  into used_tokens, used_calls
  from public.llm_global_daily_usage
  where day = d;

  next_tokens := coalesce(used_tokens, 0) + p_reserved_tokens;
  next_calls := coalesce(used_calls, 0) + 1;

  allow := next_tokens <= p_max_daily_tokens and next_calls <= p_max_daily_calls;

  if allow then
    insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
    values (d, p_reserved_tokens, 0, 1)
    on conflict (day) do update set
      reserved_tokens = public.llm_global_daily_usage.reserved_tokens + excluded.reserved_tokens,
      calls = public.llm_global_daily_usage.calls + 1,
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
create or replace function public.llm_global_budget_finalize(
  p_reserved_tokens integer,
  p_actual_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d date;
declare lock_key bigint;
declare r integer;
declare a integer;
declare reserved_total integer;
declare actual_total integer;
declare calls_total integer;
begin
  d := (timezone('utc', now()))::date;
  r := greatest(0, least(coalesce(p_reserved_tokens, 0), 500000));
  a := greatest(0, least(coalesce(p_actual_tokens, 0), 500000));

  lock_key := hashtext(d::text || ':global_llm')::bigint;
  perform pg_advisory_xact_lock(lock_key);

  insert into public.llm_global_daily_usage(day, reserved_tokens, actual_tokens, calls)
  values (d, 0, 0, 0)
  on conflict (day) do nothing;

  update public.llm_global_daily_usage
  set
    reserved_tokens = greatest(0, reserved_tokens - r),
    actual_tokens = actual_tokens + a,
    updated_at = now()
  where day = d;

  select reserved_tokens, actual_tokens, calls
  into reserved_total, actual_total, calls_total
  from public.llm_global_daily_usage
  where day = d;

  return jsonb_build_object(
    'success', true,
    'day', d::text,
    'reserved_tokens', coalesce(reserved_total, 0),
    'actual_tokens', coalesce(actual_total, 0),
    'calls', coalesce(calls_total, 0)
  );
end $$;
grant execute on function public.llm_global_budget_reserve(integer, integer, integer) to authenticated;
grant execute on function public.llm_global_budget_finalize(integer, integer) to authenticated;
-- 2) Patch default config with "natural usage" limits + global budget.
update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        config,
        '{llm_budget}',
        jsonb_build_object('daily_tokens', 12000, 'daily_calls', 40),
        true
      ),
      '{global_llm_budget}',
      jsonb_build_object('daily_tokens', 250000, 'daily_calls', 600),
      true
    ),
    '{rate_limits}',
    jsonb_build_object(
      'parse', jsonb_build_object('window_seconds', 60, 'max_user', 120, 'max_ip', 300),
      'apply', jsonb_build_object('window_seconds', 60, 'max_user', 12, 'max_ip', 50),
      'undo', jsonb_build_object('window_seconds', 60, 'max_user', 6, 'max_ip', 20),
      'resolve', jsonb_build_object('window_seconds', 60, 'max_user', 10, 'max_ip', 40),
      'recommend', jsonb_build_object('window_seconds', 60, 'max_user', 20, 'max_ip', 80)
    ),
    true
  )
where id = true;
commit;
