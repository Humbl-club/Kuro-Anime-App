-- 128_concierge_rate_limit_bounds.sql
-- Prepared 20261118140000_concierge_rate_limit_bounds_v1.sql (NOT deployed). check_concierge_rate_limit is
-- anon-callable, so its inputs are bounded: p_kind is a fixed set (every kind the Edge Functions send),
-- p_ip is a keyed value only, and a rejected call writes no rate_limit_buckets row. The function stays
-- callable (anon + authenticated) with unchanged arguments, result shape and counting.
-- Disposable local fixture only, never hosted.
-- @requires table public.rate_limit_buckets
-- @requires function public.check_concierge_rate_limit(text,text,integer,integer,integer)
-- @requires function public.rate_limit_hit(text,integer)
-- @requires function public.get_concierge_config()
\set ON_ERROR_STOP on
begin;

select tests.make_user(1281);

-- ---- A. every kind the repository sends is accepted (anon, explicit key) ------------------------------
select tests.as_anon();
do $$
declare k text; r jsonb;
begin
  foreach k in array array['parse','apply','undo','resolve','recommend','anilist_import','rag','rag_feedback',
                           'contact','contact_app_ip','contact_user','contact_global','contact_notify'] loop
    r := public.check_concierge_rate_limit(k, 'c1:00000000000000000000000000000128', 60, 5, 5);
    perform tests.ok('kind accepted: ' || k, (r->>'allowed')::boolean and (r->>'ip_hits')::int = 1);
  end loop;
end $$;
select tests.reset();

-- ---- B. unknown / empty / null kinds are rejected and write nothing -------------------------------------
create temp table t128_before as select count(*) as n from public.rate_limit_buckets;
grant select on t128_before to anon, authenticated;
select tests.as_anon();
select tests.raises('anon: a free-text kind is rejected',
  $q$select public.check_concierge_rate_limit('attacker-' || gen_random_uuid()::text, 'c1:00000000000000000000000000000128', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: an empty kind is rejected (no fallback to any)',
  $q$select public.check_concierge_rate_limit('', 'c1:00000000000000000000000000000128', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: a null kind is rejected',
  $q$select public.check_concierge_rate_limit(null, 'c1:00000000000000000000000000000128', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: near-miss kind (case/suffix) is rejected',
  $q$select public.check_concierge_rate_limit('Parse', 'c1:00000000000000000000000000000128', 60, 5, 5)$q$, '%unknown kind%');
select tests.reset();
select tests.eq('rejected calls created no bucket rows',
  (select count(*) from public.rate_limit_buckets), (select n from t128_before));

-- ---- C. p_ip must be a keyed value: c1:/contact: + 32 hex; NULL/empty keep the old behaviour --------------
select tests.as_anon();
select tests.ok('anon: a c1: keyed bucket is accepted',
  (public.check_concierge_rate_limit('parse', 'c1:' || repeat('a', 32), 60, 5, 5)->>'allowed')::boolean);
select tests.ok('anon: a contact: keyed bucket is accepted',
  (public.check_concierge_rate_limit('contact', 'contact:' || repeat('b', 32), 3600, 5, 5)->>'allowed')::boolean);
select tests.raises('anon: a raw IPv4 address is rejected',
  $q$select public.check_concierge_rate_limit('parse', '203.0.113.7', 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: a raw IPv6 address is rejected',
  $q$select public.check_concierge_rate_limit('parse', '2001:db8::1', 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: free text is rejected',
  $q$select public.check_concierge_rate_limit('parse', 'victim-bucket', 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: an unknown prefix is rejected',
  $q$select public.check_concierge_rate_limit('parse', 'c2:' || repeat('a', 32), 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: uppercase hex is rejected',
  $q$select public.check_concierge_rate_limit('parse', 'c1:' || repeat('A', 32), 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: wrong hex length is rejected',
  $q$select public.check_concierge_rate_limit('parse', 'c1:' || repeat('a', 31), 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: a suffix after the 32 hex is rejected',
  $q$select public.check_concierge_rate_limit('parse', 'c1:' || repeat('a', 32) || 'x', 60, 5, 5)$q$, '%keyed bucket%');
select tests.raises('anon: a very long p_ip is rejected',
  $q$select public.check_concierge_rate_limit('parse', repeat('b', 100000), 60, 5, 5)$q$, '%keyed bucket%');
select tests.eq('anon with no ip: unchanged "no uid/ip" allow',
  public.check_concierge_rate_limit('parse', null, 60, 5, 5)->>'note', 'no uid/ip');
select tests.eq('anon with empty ip: unchanged "no uid/ip" allow',
  public.check_concierge_rate_limit('parse', '', 60, 5, 5)->>'note', 'no uid/ip');
select tests.reset();
select tests.eq('rejected p_ip values wrote no row',
  (select count(*) from public.rate_limit_buckets where bucket_key like 'ip:203.%' or bucket_key like 'ip:victim%' or bucket_key like 'ip:2001%'), 0::bigint);

-- ---- C2. anon cannot choose window or maxima; authenticated overrides are clamped -----------------------
select tests.as_anon();
create temp table t128_anon on commit drop as
  select n, public.check_concierge_rate_limit('contact', 'contact:00000000000000000000000000000131', 86400, 1000000, 1000000) as r
  from generate_series(1, 7) n;
select tests.eq('anon: window/max overrides ignored (contact = 5 per 3600 s, not 1000000 per day)',
  (select string_agg(r->>'allowed', ',' order by n) from t128_anon), 'true,true,true,true,true,false,false');
select tests.eq('anon: the window used is the kind default', (select (r->>'window_seconds')::int from t128_anon where n = 1), 3600);
select tests.eq('anon: an absurd or negative window is ignored, not an error',
  (public.check_concierge_rate_limit('parse', 'c1:' || repeat('1', 32), -5, 1, 1)->>'window_seconds')::int, 60);
select tests.eq('anon: a zero window is ignored too',
  (public.check_concierge_rate_limit('parse', 'c1:' || repeat('2', 32), 0, 1, 1)->>'window_seconds')::int, 60);
select tests.ok('anon: max_ip override of 1 does not block the second call (config value applies)',
  (public.check_concierge_rate_limit('parse', 'c1:' || repeat('3', 32), 60, 1, 1)->>'allowed')::boolean
  and (public.check_concierge_rate_limit('parse', 'c1:' || repeat('3', 32), 60, 1, 1)->>'allowed')::boolean);
select tests.eq('anon: contact_user/app_ip/global/notify keep contact-submit''s maxima',
  (select string_agg(public.check_concierge_rate_limit(k, 'contact:' || repeat('4', 32), null, null, null)->>'max_ip', ',' order by k)
   from unnest(array['contact','contact_app_ip','contact_global','contact_notify','contact_user']) k),
  '5,30,200,50,5');
select tests.reset();

select tests.as_user(tests.uid(1281));
select tests.raises('authenticated: a zero window is rejected',
  $q$select public.check_concierge_rate_limit('apply', 'c1:00000000000000000000000000000129', 0, 5, 5)$q$, '%window not allowed%');
select tests.raises('authenticated: a negative window is rejected',
  $q$select public.check_concierge_rate_limit('apply', 'c1:00000000000000000000000000000129', -60, 5, 5)$q$, '%window not allowed%');
select tests.raises('authenticated: an arbitrary window (7 s) is rejected',
  $q$select public.check_concierge_rate_limit('apply', 'c1:00000000000000000000000000000129', 7, 5, 5)$q$, '%window not allowed%');
select tests.eq('authenticated: an allow-listed window is honoured',
  (public.check_concierge_rate_limit('apply', 'c1:00000000000000000000000000000129', 300, 5, 5)->>'window_seconds')::int, 300);
select tests.eq('authenticated: maxima are clamped to 1..10000',
  (select (r->>'max_user') || ',' || (r->>'max_ip') from (select public.check_concierge_rate_limit('apply', 'c1:00000000000000000000000000000129', 60, 99999999, 0) r) q), '10000,1');
select tests.reset();

-- ---- D. counting and result shape are unchanged ------------------------------------------------------
select tests.as_anon();
create temp table t128_rl on commit drop as
  select n, public.check_concierge_rate_limit('contact', 'contact:00000000000000000000000000000130', 3600, 5, 3) as r
  from generate_series(1, 6) n;
select tests.eq('anon: the kind default (5) applies, not the 3 passed in: five allowed, the sixth denied',
  (select string_agg(r->>'allowed', ',' order by n) from t128_rl), 'true,true,true,true,true,false');
select tests.ok('result keeps its keys',
  (select r ?& array['allowed','user_hits','ip_hits','retry_after_s','window_seconds','max_user','max_ip'] from t128_rl where n = 1));
select tests.reset();

select tests.as_user(tests.uid(1281));
select tests.ok('authenticated: callable, user bucket counted',
  (public.check_concierge_rate_limit('undo', 'c1:00000000000000000000000000000129', 60, 5, 5)->>'user_hits')::int = 1);
select tests.raises('authenticated: a free-text kind is rejected as well',
  $q$select public.check_concierge_rate_limit('made-up', 'c1:00000000000000000000000000000129', 60, 5, 5)$q$, '%unknown kind%');
select tests.reset();

-- ---- E. grants and definition ---------------------------------------------------------------------------
select tests.ok('anon and authenticated may execute; PUBLIC may not',
  has_function_privilege('anon', 'public.check_concierge_rate_limit(text,text,integer,integer,integer)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.check_concierge_rate_limit(text,text,integer,integer,integer)', 'EXECUTE')
  and not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
    where p.oid = 'public.check_concierge_rate_limit(text,text,integer,integer,integer)'::regprocedure and a.grantee = 0));
select tests.ok('SECURITY DEFINER with search_path = public, extensions',
  (select p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public, extensions')
   from pg_proc p where p.oid = 'public.check_concierge_rate_limit(text,text,integer,integer,integer)'::regprocedure));

rollback;
