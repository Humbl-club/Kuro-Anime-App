-- 128_concierge_rate_limit_bounds.sql
-- Prepared 20261118140000_concierge_rate_limit_bounds_v1.sql (NOT deployed). check_concierge_rate_limit is
-- anon-callable, so its inputs are bounded: p_kind is a fixed set (every kind the Edge Functions send),
-- p_ip is at most 128 characters, and a rejected call writes no rate_limit_buckets row. The function stays
-- callable (anon + authenticated) with unchanged arguments, result shape and counting.
-- Disposable local fixture only, never hosted.
-- @requires table public.rate_limit_buckets
-- @requires function public.check_concierge_rate_limit(text,text,integer,integer,integer)
-- @requires function public.rate_limit_hit(text,integer)
-- @requires function public.get_concierge_config()
\set ON_ERROR_STOP on
begin;

-- ---- A. every kind the repository sends is accepted (anon, explicit key) ------------------------------
select tests.as_anon();
do $$
declare k text; r jsonb;
begin
  foreach k in array array['parse','apply','undo','resolve','recommend','anilist_import','rag','rag_feedback',
                           'contact','contact_app_ip','contact_user','contact_global','contact_notify'] loop
    r := public.check_concierge_rate_limit(k, 't128-key', 60, 5, 5);
    perform tests.ok('kind accepted: ' || k, (r->>'allowed')::boolean and (r->>'ip_hits')::int = 1);
  end loop;
end $$;
select tests.reset();

-- ---- B. unknown / empty / null kinds are rejected and write nothing -------------------------------------
create temp table t128_before as select count(*) as n from public.rate_limit_buckets;
grant select on t128_before to anon, authenticated;
select tests.as_anon();
select tests.raises('anon: a free-text kind is rejected',
  $q$select public.check_concierge_rate_limit('attacker-' || gen_random_uuid()::text, 't128-key', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: an empty kind is rejected (no fallback to any)',
  $q$select public.check_concierge_rate_limit('', 't128-key', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: a null kind is rejected',
  $q$select public.check_concierge_rate_limit(null, 't128-key', 60, 5, 5)$q$, '%unknown kind%');
select tests.raises('anon: near-miss kind (case/suffix) is rejected',
  $q$select public.check_concierge_rate_limit('Parse', 't128-key', 60, 5, 5)$q$, '%unknown kind%');
select tests.reset();
select tests.eq('rejected calls created no bucket rows',
  (select count(*) from public.rate_limit_buckets), (select n from t128_before));

-- ---- C. p_ip length bound: 128 accepted, 129 rejected, null/empty still the old behaviour --------------
select tests.as_anon();
select tests.ok('anon: a 128-character p_ip is accepted',
  (public.check_concierge_rate_limit('parse', repeat('a', 128), 60, 5, 5)->>'allowed')::boolean);
select tests.raises('anon: a 129-character p_ip is rejected',
  $q$select public.check_concierge_rate_limit('parse', repeat('a', 129), 60, 5, 5)$q$, '%p_ip too long%');
select tests.raises('anon: a very long p_ip is rejected',
  $q$select public.check_concierge_rate_limit('parse', repeat('b', 100000), 60, 5, 5)$q$, '%p_ip too long%');
select tests.eq('anon with no ip: unchanged "no uid/ip" allow',
  public.check_concierge_rate_limit('parse', null, 60, 5, 5)->>'note', 'no uid/ip');
select tests.eq('anon with empty ip: unchanged "no uid/ip" allow',
  public.check_concierge_rate_limit('parse', '', 60, 5, 5)->>'note', 'no uid/ip');
select tests.reset();
select tests.eq('the 129-character call wrote no row',
  (select count(*) from public.rate_limit_buckets where bucket_key like 'ip:' || repeat('a', 129) || '%'), 0::bigint);

-- ---- D. counting and result shape are unchanged ------------------------------------------------------
select tests.as_anon();
create temp table t128_rl on commit drop as
  select n, public.check_concierge_rate_limit('contact', 'contact:t128-count', 3600, 5, 3) as r
  from generate_series(1, 4) n;
select tests.eq('anon: three allowed per window by max_ip, the fourth denied',
  (select string_agg(r->>'allowed', ',' order by n) from t128_rl), 'true,true,true,false');
select tests.ok('result keeps its keys',
  (select r ?& array['allowed','user_hits','ip_hits','retry_after_s','window_seconds','max_user','max_ip'] from t128_rl where n = 1));
select tests.reset();

select tests.make_user(1281);
select tests.as_user(tests.uid(1281));
select tests.ok('authenticated: callable, user bucket counted',
  (public.check_concierge_rate_limit('apply', 't128-auth', 60, 5, 5)->>'user_hits')::int = 1);
select tests.raises('authenticated: a free-text kind is rejected as well',
  $q$select public.check_concierge_rate_limit('made-up', 't128-auth', 60, 5, 5)$q$, '%unknown kind%');
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
