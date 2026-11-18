-- 20261118140000_concierge_rate_limit_bounds_v1.sql
-- PREPARED, NOT APPLIED. Owner approval required to deploy. Independent review finding: hardening of
-- public.check_concierge_rate_limit(text,text,integer,integer,integer).
--
-- The function is callable with the anon key (contact-submit and the anonymous parse need that; the
-- 20261118110000 allowlist keeps it) and wrote one rate_limit_buckets row per distinct (kind, ip, window)
-- the caller made up. Two exposures:
--   1. p_kind and p_ip were free text: anyone could mint unlimited bucket rows.
--   2. Edge callers sent the raw client address, so a third party could fill a known address's bucket
--      (about 100 calls a minute) and block Concierge for everybody behind it.
-- (2) is fixed in the Edge Functions (supabase/functions/_shared/limiter_ip.ts keys the address with an
-- HMAC before it reaches this function). This migration is the database side of (1):
--   * p_kind must be one of the kinds the repository actually sends (list below); anything else raises
--     22023, which the Edge gate (rate_limit_gate.ts) reads as "limiter unavailable" (fail closed, 503).
--     A NULL or empty kind is also rejected (it used to fall back to 'any', which no caller uses).
--   * p_ip is at most 128 characters (the keyed value is 35; contact-submit's is 40).
-- Everything else is the 20260204233010 body unchanged (same arguments, defaults, result shape, bucket
-- keys, config lookup), now with search_path = public, extensions. Callable exactly as before.
--
-- Allowed kinds (every p_kind in supabase/functions, grep 2026-11-18):
--   concierge-parse parse | concierge-apply apply | concierge-undo undo | concierge-resolve resolve
--   concierge-recommend recommend | concierge-import-anilist anilist_import
--   concierge-retrieve-assist rag | concierge-retrieve-feedback rag_feedback
--   contact-submit contact, contact_app_ip, contact_user, contact_global, contact_notify
-- A new kind needs a new migration that extends this list; that is deliberate.
--
-- Replace keeps the existing ACL; the grants are restated anyway (anon + authenticated, nothing for PUBLIC).
-- Idempotent: CREATE OR REPLACE.

begin;

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
set search_path = public, extensions
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
  if p_kind is null or p_kind not in (
       'parse', 'apply', 'undo', 'resolve', 'recommend', 'anilist_import', 'rag', 'rag_feedback',
       'contact', 'contact_app_ip', 'contact_user', 'contact_global', 'contact_notify') then
    raise exception 'check_concierge_rate_limit: unknown kind' using errcode = '22023';
  end if;
  if p_ip is not null and length(p_ip) > 128 then
    raise exception 'check_concierge_rate_limit: p_ip too long' using errcode = '22023';
  end if;

  uid := auth.uid();
  kind := p_kind;

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

revoke all on function public.check_concierge_rate_limit(text, text, integer, integer, integer) from public;
grant execute on function public.check_concierge_rate_limit(text, text, integer, integer, integer) to anon, authenticated;

commit;
