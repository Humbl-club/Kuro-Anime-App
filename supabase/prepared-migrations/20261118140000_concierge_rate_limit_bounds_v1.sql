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
--   * p_ip must be a keyed value: '^(c1|contact):[0-9a-f]{32}$' (Edge helper / contact-submit), or NULL/empty.
--     Raw addresses and any other shape raise 22023.
--   * Anonymous callers' p_window_seconds / p_max_user / p_max_ip are IGNORED: window and maxima come from the
--     concierge config for the kind, else a built-in default (the contact-submit table: 3600 s; contact 5,
--     contact_app_ip 30, contact_user 5, contact_global 200, contact_notify 50), else 60 s / 40 / 120.
--     Authenticated and service callers may override: window must be 60, 300, 900, 3600 or 86400 (else 22023),
--     maxima are clamped to 1..10000.
-- Follow-up (not in this lane): the stronger end state is calling the limiter from the Edge Functions with the
-- service role and revoking anon EXECUTE; contact-submit and the anonymous parse call it as anon today, so the
-- 20261118110000 allowlist grant stays.
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
declare caller_role text;
declare builtin_window integer;
declare builtin_max integer;
begin
  if p_kind is null or p_kind not in (
       'parse', 'apply', 'undo', 'resolve', 'recommend', 'anilist_import', 'rag', 'rag_feedback',
       'contact', 'contact_app_ip', 'contact_user', 'contact_global', 'contact_notify') then
    raise exception 'check_concierge_rate_limit: unknown kind' using errcode = '22023';
  end if;
  -- contact-submit's table (supabase/functions/contact-submit/handler.ts RATE_LIMIT): 3600 s windows. Kept here so
  -- the anonymous contact path keeps its limits now that anon overrides are ignored.
  builtin_window := case when p_kind like 'contact%' then 3600 end;
  builtin_max := case p_kind
    when 'contact' then 5 when 'contact_app_ip' then 30 when 'contact_user' then 5
    when 'contact_global' then 200 when 'contact_notify' then 50 end;

  -- p_ip is only ever a keyed value: 'c1:' + 32 hex (Edge helper _shared/limiter_ip.ts) or 'contact:' + 32 hex
  -- (contact-submit hashIp). A raw address, free text or any other shape is rejected, so a caller cannot choose
  -- or guess another party's bucket and cannot mint arbitrary keys. NULL / empty means "no address".
  if p_ip is not null and length(p_ip) > 0 and p_ip !~ '^(c1|contact):[0-9a-f]{32}$' then
    raise exception 'check_concierge_rate_limit: p_ip must be a keyed bucket value' using errcode = '22023';
  end if;

  uid := auth.uid();
  kind := p_kind;
  caller_role := coalesce(auth.role(), 'anon');

  cfg := public.get_concierge_config();
  rl := cfg->'rate_limits'->kind;

  if caller_role in ('authenticated', 'service_role') then
    -- Overrides are clamped: the window must be one of a few fixed sizes, the maxima within 1..10000.
    if p_window_seconds is not null and p_window_seconds not in (60, 300, 900, 3600, 86400) then
      raise exception 'check_concierge_rate_limit: window not allowed' using errcode = '22023';
    end if;
    win_s := coalesce(p_window_seconds, (rl->>'window_seconds')::int, builtin_window, 60);
    max_u := coalesce(p_max_user, (rl->>'max_user')::int, builtin_max, 40);
    max_i := coalesce(p_max_ip, (rl->>'max_ip')::int, builtin_max, 120);
    max_u := least(greatest(max_u, 1), 10000);
    max_i := least(greatest(max_i, 1), 10000);
  else
    -- Anonymous callers cannot choose the window or the maxima: config for the kind, else the built-in
    -- default below (the contact-submit table), else 60 s / 40 / 120. Their p_window_seconds / p_max_* are ignored.
    win_s := coalesce((rl->>'window_seconds')::int, builtin_window, 60);
    max_u := coalesce((rl->>'max_user')::int, builtin_max, 40);
    max_i := coalesce((rl->>'max_ip')::int, builtin_max, 120);
  end if;

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
