-- 114_guest_anon_allowlist.sql
-- W5 guest browsing: prepared 20261118110000_guest_anon_allowlist_v1.sql (NOT deployed).
-- The anonymous API role may EXECUTE exactly an allowlist of read RPCs (the guest pages' reads, the
-- signed-out infrastructure the live app and Edge Functions need), nothing else. No anonymous write
-- path is added. Disposable local fixture only, never hosted.
-- The allowlisted functions and the migration are the SUBJECT: their absence FAILS (or is reported
-- BLOCKED per signature below), it never blocks the file.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.feature_flags
\set ON_ERROR_STOP on
begin;

-- ---- the allowlist (22 signatures: 19 guest reads + 2 signed-out infrastructure + 1 pure helper) --
create temp table w5_allow(sig text primary key);
insert into w5_allow(sig) values
  ('public.discover_bundle(integer,integer)'),
  ('public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)'),
  ('public.discover_mood_v1(text,text,integer,integer)'),
  ('public.media_franchise_ids_v1(integer[],integer[])'),
  ('public.recommend_ids_similar_to_seeds(text,integer[],integer,boolean)'),
  ('public.media_similar_v1(text,integer,integer)'),
  ('public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)'),
  ('public.browse_manga_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)'),
  ('public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'),
  ('public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'),
  ('public.get_media_ladder(text,integer)'),
  ('public.get_manga_chapter_status(integer)'),
  ('public.media_release_schedule_v1(text,integer,integer)'),
  ('public.media_themes_v1(integer)'),
  ('public.anime_cast_v1(integer,text,integer)'),
  ('public.character_voice_actors_v1(integer,text)'),
  ('public.staff_voice_roles_v1(integer,integer)'),
  ('public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'),
  ('public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'),
  -- signed-out infrastructure (not guest pages): contact form limiter (anon client), anonymous public parse
  ('public.check_concierge_rate_limit(text,text,integer,integer,integer)'),
  ('public.search_titles(text,text,integer)'),
  ('public.normalize_title(text)');   -- pure helper that SECURITY INVOKER search_titles calls

create temp table w5_allow_present as
  select to_regprocedure(sig)::text as sig from w5_allow where to_regprocedure(sig) is not null;
create temp table w5_anon as
  select p.oid::regprocedure::text as sig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
create temp table w5_allow_norm as select to_regprocedure(sig)::text as sig from w5_allow where to_regprocedure(sig) is not null;
grant select on w5_allow, w5_allow_present, w5_anon, w5_allow_norm to anon, authenticated;

-- ---- A. exact set ------------------------------------------------------------------------------------
do $$
declare r record;
begin
  -- I3: every allowlisted signature must resolve, except W4's two search_*_v2 (prepared 20261118100000, may be absent).
  for r in select sig from w5_allow where to_regprocedure(sig) is null loop
    if r.sig like 'public.search\_%\_page\_v2(%' then
      perform tests.blocked('W5: W4 function absent from fixture (allowed): ' || r.sig, 'W4 20261118100000 is applied separately; the live audit enforces it');
    else
      perform tests.ok('W5: allowlisted function resolves in the fixture: ' || r.sig, false);
    end if;
  end loop;
end $$;
select tests.ok('W5: anon can execute every allowlisted function present',
  not exists (select sig from w5_allow_present except select sig from w5_anon));
select tests.ok('W5: anon can execute nothing outside the allowlist: '
    || coalesce((select string_agg(x, ', ' order by x) from (select sig from w5_anon except select sig from w5_allow_norm) e(x)), 'none'),
  not exists (select sig from w5_anon except select sig from w5_allow_norm));
select tests.ok('W5: the two signed-out infrastructure functions are still anon-callable (contact form, anonymous parse)',
  (select count(*) from w5_anon where sig in (
     'check_concierge_rate_limit(text,text,integer,integer,integer)', 'search_titles(text,text,integer)')) = 2);
select tests.ok('W5 M1: get_concierge_config is NOT anon-callable (signed-in callers or SECURITY DEFINER callers only)',
  not has_function_privilege('anon', 'public.get_concierge_config()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_concierge_config()', 'EXECUTE'));

-- A2. callee closure: a SECURITY INVOKER allowlisted function runs its callees as anon, so it must not
-- name a public function the allowlist does not cover (the failure that search_titles -> normalize_title showed).
select tests.ok('W5: no SECURITY INVOKER allowlisted function calls a public function outside the allowlist: '
    || coalesce((select string_agg(distinct a.proname || ' -> ' || c.proname, ', ')
        from pg_proc a join pg_namespace an on an.oid = a.pronamespace
        join pg_proc c on c.pronamespace = a.pronamespace and c.oid <> a.oid
        where an.nspname = 'public' and not a.prosecdef and a.oid::regprocedure::text in (select sig from w5_allow_norm)
          and a.prokind = 'f' and a.prosrc ~* ('\m' || c.proname || '\s*\(')
          and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
          and c.oid::regprocedure::text not in (select sig from w5_allow_norm)), 'none'),
  not exists (select 1
        from pg_proc a join pg_namespace an on an.oid = a.pronamespace
        join pg_proc c on c.pronamespace = a.pronamespace and c.oid <> a.oid
        where an.nspname = 'public' and not a.prosecdef and a.oid::regprocedure::text in (select sig from w5_allow_norm)
          and a.prokind = 'f' and a.prosrc ~* ('\m' || c.proname || '\s*\(')
          and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
          and c.oid::regprocedure::text not in (select sig from w5_allow_norm)));

-- ---- A3. re-run the migration body inside rolled-back sub-transactions ------------------------------------------
-- The migration file is the SUBJECT: strip its begin/commit, run it from a plpgsql EXECUTE under a savepoint,
-- return what we find (or the error text), and let the exception block roll everything back.
\set w5mig `sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/prepared-migrations/20261118110000_guest_anon_allowlist_v1.sql`
select set_config('w5.mig', :'w5mig', false);
create function pg_temp.w5_rerun(p_setup text, p_check text) returns text language plpgsql as $f$
declare v text;
begin
  execute p_setup;
  execute current_setting('w5.mig');
  execute p_check into v;
  raise exception 'W5RES:%', v;
exception when others then
  return sqlerrm;
end $f$;

-- I3: a missing allowlisted signature must RAISE (and not be skipped with a notice)
select tests.ok('W5 I3: migration RAISES when a non-W4 allowlisted signature is missing: ' || r,
  r like 'W5: allowlisted function absent:%media_themes_v1%')
from (select pg_temp.w5_rerun('drop function public.media_themes_v1(integer)', 'select 1') as r) q;
select tests.ok('W5 I3: migration RAISES for a missing search_titles too: ' || r, r like 'W5: allowlisted function absent:%search_titles%')
from (select pg_temp.w5_rerun('drop function public.search_titles(text,text,integer)', 'select 1') as r) q;
select tests.ok('W5 I3: migration tolerates a missing W4 search_anime_page_v2 / search_manga_page_v2: ' || r, r = 'W5RES:1')
from (select pg_temp.w5_rerun(
  'drop function if exists public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer); '
  || 'drop function if exists public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)',
  'select 1') as r) q;

-- I2: step 4 must not turn PUBLIC-only access into explicit grants for other roles; M3: supabase_admin default
create role w5_dashboard_user nologin;
select tests.ok('W5 I2/M3: step 4 re-grants only authenticated and service_role (never authenticator, dashboard_user, supabase_*); no anon default survives: ' || r, r = 'W5RES:ok')
from (select pg_temp.w5_rerun(
  $s$ create function public.w5_s4_probe() returns integer language plpgsql set search_path = public, extensions as $b$ begin return 1; end $b$;
      alter default privileges for role supabase_admin in schema public grant execute on functions to anon $s$,
  $c$ select case
        when exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                     where p.pronamespace = 'public'::regnamespace and p.proname = 'w5_s4_probe'
                       and a.grantee not in (p.proowner, 'authenticated'::regrole, 'service_role'::regrole))
          then 'extra grantee on probe'
        when not (has_function_privilege('authenticated', 'public.w5_s4_probe()', 'EXECUTE')
                  and has_function_privilege('service_role', 'public.w5_s4_probe()', 'EXECUTE'))
          then 'authenticated/service_role lost the probe'
        when exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                     where p.pronamespace = 'public'::regnamespace
                       and a.grantee not in (p.proowner, 'authenticated'::regrole, 'service_role'::regrole, 'anon'::regrole)
                       and a.grantee <> 0)
          then 'some public function has an explicit grant to another role: ' || (select string_agg(distinct a.grantee::regrole::text, ',')
                from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where p.pronamespace = 'public'::regnamespace
                  and a.grantee not in (p.proowner, 'authenticated'::regrole, 'service_role'::regrole, 'anon'::regrole) and a.grantee <> 0)
        when exists (select 1 from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace, lateral aclexplode(d.defaclacl) a
                     where n.nspname = 'public' and d.defaclobjtype = 'f' and a.grantee = 'anon'::regrole)
          then 'a per-schema default still grants anon (incl. supabase_admin)'
        else 'ok' end $c$) as r) q;
drop role w5_dashboard_user;

-- ---- B. no PUBLIC grant ----------------------------------------------------------------------------------
select tests.ok('W5: no non-extension public function grants EXECUTE to PUBLIC: '
    || coalesce((select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
          and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')), 'none'),
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
          and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')));
do $$
declare v_name text; v_oid oid;
begin
  foreach v_name in array array['fetch_daily_feature', 'fetch_because_you_rail', 'purge_outbound_link_events',
                                'enqueue_media_relation_refresh', 'catalogue_search_blob_v1'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = v_name) then
      perform tests.blocked('W5: spot check ' || v_name || ' absent from fixture', 'the live audit enforces it');
      continue;
    end if;
    perform tests.ok('W5: anon cannot execute any overload of ' || v_name,
      not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = v_name and has_function_privilege('anon', p.oid, 'EXECUTE')));
  end loop;
end $$;

-- ---- C. no allowlisted call is denied as anon -----------------------------------------------------------
set local session_replication_role = replica;
insert into public.anime (id, title_romaji, title_english, format, status, genres, is_adult, episodes, season_year, start_date_year)
values (1, 'W5 Probe', 'W5 Probe', 'TV', 'FINISHED', array['Drama'], false, 12, 2020, 2020);
insert into public.manga (id, title_romaji, title_english, format, status, genres, is_adult, chapters, start_date_year)
values (1, 'W5 Probe', 'W5 Probe', 'MANGA', 'FINISHED', array['Drama'], false, 40, 2020);
set local session_replication_role = origin;
create temp table w5_impressions_before as select count(*) as n from public.discover_rail_impressions;
grant select on w5_impressions_before to anon;

select tests.as_anon();
do $$
declare
  c record;
  v_denied boolean;
  v_other text;
begin
  for c in
    select * from (values
      ('discover_bundle', $q$select * from public.discover_bundle(30, 24)$q$, null::text),
      ('discover_section_page_v1', $q$select * from public.discover_section_page_v1('trending', 'ANIME', null, null, null, null, 24, 0)$q$, null),
      ('discover_mood_v1', $q$select * from public.discover_mood_v1('cozy', 'ANIME', 24, 0)$q$, null),
      ('discover_mood_v1 like_last_loved', $q$select * from public.discover_mood_v1('like_last_loved', 'ANIME', 24, 0)$q$, null),
      ('media_franchise_ids_v1', $q$select * from public.media_franchise_ids_v1(array[1], array[]::integer[])$q$, null),
      ('recommend_ids_similar_to_seeds', $q$select * from public.recommend_ids_similar_to_seeds('ANIME', array[1], 12, false)$q$, null),
      ('media_similar_v1', $q$select * from public.media_similar_v1('ANIME', 1, 12)$q$, null),
      ('browse_anime_page', $q$select * from public.browse_anime_page()$q$, null),
      ('browse_manga_page', $q$select * from public.browse_manga_page()$q$, null),
      ('search_anime_page', $q$select * from public.search_anime_page('a')$q$, null),
      ('search_manga_page', $q$select * from public.search_manga_page('a')$q$, null),
      ('search_anime_page_v2', $q$select * from public.search_anime_page_v2('a')$q$, 'public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'),
      ('search_manga_page_v2', $q$select * from public.search_manga_page_v2('a')$q$, 'public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'),
      ('get_media_ladder', $q$select * from public.get_media_ladder('ANIME', 1)$q$, null),
      ('get_manga_chapter_status', $q$select * from public.get_manga_chapter_status(1)$q$, null),
      ('media_release_schedule_v1', $q$select * from public.media_release_schedule_v1('anime', 1, 6)$q$, null),
      ('media_themes_v1', $q$select * from public.media_themes_v1(1)$q$, null),
      ('anime_cast_v1', $q$select * from public.anime_cast_v1(1, 'JAPANESE', 50)$q$, null),
      ('character_voice_actors_v1', $q$select * from public.character_voice_actors_v1(1, 'JAPANESE')$q$, null),
      ('staff_voice_roles_v1', $q$select * from public.staff_voice_roles_v1(1, 50)$q$, null),
      ('check_concierge_rate_limit', $q$select * from public.check_concierge_rate_limit('contact', 'w5-probe-key', 5, 3600, 1)$q$, null),
      ('search_titles', $q$select * from public.search_titles('a', 'ANIME', 5)$q$, null)
    ) as t(name, stmt, needs)
  loop
    if c.needs is not null and to_regprocedure(c.needs) is null then
      perform tests.blocked('W5 anon call skipped (function absent): ' || c.name, 'the live audit enforces it');
      continue;
    end if;
    v_denied := false; v_other := null;
    begin
      execute c.stmt;
    exception
      when insufficient_privilege then v_denied := true;
      when undefined_function or undefined_table or undefined_column then
        -- the audited fixture lacks a relation/helper the real function reads (not a privilege problem; a
        -- privilege problem is 42501 above). Visible in the log, not silent; the live audit covers it.
        raise notice 'W5 anon call % hit a fixture gap (% %)', c.name, sqlstate, sqlerrm;
      when others then
        v_other := sqlstate || ' ' || sqlerrm;
    end;
    perform tests.ok('W5 anon call not denied: ' || c.name, not v_denied);
    perform tests.ok('W5 anon call raised no other error: ' || c.name || coalesce(' (' || v_other || ')', ''), v_other is null);
  end loop;
end $$;
select tests.reset();
select tests.ok('W5: the anon discover_bundle call wrote no impression rows',
  (select count(*) from public.discover_rail_impressions) = (select n from w5_impressions_before));

-- ---- D. denied as anon (writes, private reads, internal helpers) -------------------------------------------
do $$
declare v_name text;
begin
  foreach v_name in array array[
    'fetch_daily_feature', 'enqueue_media_relation_refresh', 'record_outbound_link', 'series_detail_bundle_v1',
    'count_friends_tracking', 'purge_outbound_link_events', 'home_bundle_v1', 'apply_progress_mutations_v1',
    'fetch_my_taste_profile', 'record_taste_deck_signal', 'join_club', 'create_club', 'rate_limit_hit',
    'check_email_exists', 'log_concierge_run', 'llm_budget_reserve', 'is_flag_enabled', 'curated_rail_cards',
    'collection_feed_page', 'collection_anime_page', 'collection_manga_page', 'acquire_import_lock',
    'create_club_poll', 'create_club_rail', 'release_import_lock', 'catalogue_search_blob_v1', 'get_concierge_config',
    'get_provider_availability_refresh_candidates'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = v_name) then
      perform tests.blocked('W5: denied-check ' || v_name || ' absent from fixture', 'the live audit enforces it');
      continue;
    end if;
    perform tests.ok('W5: anon cannot execute any overload of ' || v_name,
      not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = v_name and has_function_privilege('anon', p.oid, 'EXECUTE')));
  end loop;
end $$;
select tests.as_anon();
select tests.denied('W5: anon call to fetch_daily_feature is refused with 42501', $$select public.fetch_daily_feature()$$);
select tests.denied('W5: anon call to enqueue_media_relation_refresh is refused with 42501', $$select public.enqueue_media_relation_refresh('ANIME', 1, 'probe')$$);
select tests.denied('W5: anon call to count_friends_tracking is refused with 42501', $$select public.count_friends_tracking('[]')$$);
select tests.denied('W5: anon call to purge_outbound_link_events is refused with 42501', $$select public.purge_outbound_link_events()$$);
select tests.denied('W5: anon call to apply_progress_mutations_v1 is refused with 42501', $$select public.apply_progress_mutations_v1('[]'::jsonb)$$);
select tests.reset();

-- ---- E. other roles unchanged ------------------------------------------------------------------------------
select tests.ok('W5: authenticated keeps EXECUTE on the signed-in readers and writers',
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('fetch_daily_feature', 'series_detail_bundle_v1', 'home_bundle_v1', 'apply_progress_mutations_v1',
         'record_outbound_link', 'join_club', 'fetch_my_taste_profile', 'record_taste_deck_signal', 'count_friends_tracking')));
select tests.ok('W5: authenticated keeps EXECUTE on every allowlisted function present',
  not exists (select 1 from w5_allow_norm a where not has_function_privilege('authenticated', a.sig, 'EXECUTE')));
select tests.ok('W5: service_role keeps EXECUTE on the service-only functions',
  has_function_privilege('service_role', 'public.purge_outbound_link_events()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.check_email_exists(text)', 'EXECUTE'));
select tests.ok('W5: check_email_exists stays closed to authenticated (review_security_v1)',
  not has_function_privilege('authenticated', 'public.check_email_exists(text)', 'EXECUTE'));

-- Q11: an unguarded service-only function must not stay open to signed-in users (the two auth.role()-guarded ones are untouched)
do $$
begin
  if to_regprocedure('public.get_provider_availability_refresh_candidates(integer,text,integer,integer)') is null then
    perform tests.blocked('W5 Q11: get_provider_availability_refresh_candidates absent from fixture', 'the live audit enforces it');
  else
    perform tests.ok('W5 Q11: get_provider_availability_refresh_candidates is service-only (not anon, authenticated or public)',
      not has_function_privilege('anon', 'public.get_provider_availability_refresh_candidates(integer,text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.get_provider_availability_refresh_candidates(integer,text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('public', 'public.get_provider_availability_refresh_candidates(integer,text,integer,integer)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.get_provider_availability_refresh_candidates(integer,text,integer,integer)', 'EXECUTE'));
  end if;
  if exists (select 1 from pg_proc where proname in ('publish_mapping_revision', 'recompute_media_realm_llm_deltas') and pronamespace = 'public'::regnamespace) then
    perform tests.ok('W5 Q11: the auth.role()-guarded publish_mapping_revision / recompute_media_realm_llm_deltas keep authenticated EXECUTE',
      (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')) from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname in ('publish_mapping_revision', 'recompute_media_realm_llm_deltas')));
  else
    perform tests.blocked('W5 Q11: publish_mapping_revision / recompute_media_realm_llm_deltas absent from fixture', 'the live audit enforces it');
  end if;
end $$;

-- ---- F. per-schema anon default gone, a new function is closed to anon -------------------------------------
select tests.ok('W5: no per-schema default grants anon EXECUTE in public',
  not exists (select 1 from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace,
              lateral aclexplode(d.defaclacl) a
              where n.nspname = 'public' and d.defaclobjtype = 'f' and a.grantee = 'anon'::regrole and a.privilege_type = 'EXECUTE'));
create function public.w5_probe() returns integer language plpgsql set search_path = public, extensions as $$ begin return 1; end $$;
revoke all on function public.w5_probe() from public;
select tests.ok('W5: a new public function with the section 3 revoke is closed to anon and open to authenticated',
  not has_function_privilege('anon', 'public.w5_probe()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.w5_probe()', 'EXECUTE')
  and has_function_privilege('service_role', 'public.w5_probe()', 'EXECUTE'));
create function public.w5_probe_forgot() returns integer language plpgsql set search_path = public, extensions as $$ begin return 1; end $$;
-- Known limit (D-W5-DP): the global PUBLIC default is NOT revoked, so a NEW function that forgets
-- `revoke all ... from public` IS anon-executable through PUBLIC. Only a later migration that revokes, plus a
-- re-run of live audit query 1 after every later migration, closes it. This proves the exact-set query sees it.
select tests.ok('W5 limit: a new function that forgets revoke-from-public IS anon-executable via PUBLIC (no per-schema default involved)',
  has_function_privilege('anon', 'public.w5_probe_forgot()', 'EXECUTE')
  and not exists (select 1 from pg_default_acl d, lateral aclexplode(d.defaclacl) a where d.defaclobjtype = 'f' and a.grantee = 'anon'::regrole));
select tests.ok('W5 limit: the section A exact-set query catches that forgotten function',
  exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'w5_probe_forgot'
          and has_function_privilege('anon', p.oid, 'EXECUTE') and p.oid::regprocedure::text not in (select sig from w5_allow_norm)));

-- ---- G. catalogue tables stay readable; user lists stay private --------------------------------------------
select tests.as_anon();
do $$
declare v_table text; n bigint;
begin
  foreach v_table in array array['anime', 'manga', 'episodes', 'chapters', 'anime_characters', 'anime_staff', 'anime_studios',
      'manga_characters', 'manga_authors', 'manga_staff', 'external_links', 'characters', 'staff', 'studios', 'authors',
      'anime_tags', 'manga_tags', 'tags', 'character_voice_actors', 'theme_links', 'feature_flags'] loop
    if to_regclass('public.' || v_table) is null then
      perform tests.blocked('W5: guest table ' || v_table || ' absent from fixture', 'the live audit enforces it');
      continue;
    end if;
    begin
      execute format('select count(*) from public.%I', v_table) into n;
      perform tests.ok('W5: anon can still read table ' || v_table, true);
    exception when insufficient_privilege then
      perform tests.ok('W5: anon can still read table ' || v_table, false);
    end;
  end loop;
end $$;
select tests.ok('W5: anon sees no anime_user_lists rows', (select count(*) from public.anime_user_lists) = 0);
select tests.reset();

-- ---- I. nothing anon can reach calls a function anon may not execute (mirror of live Q2-Q4) -------------------------
-- Q2: RLS policies that apply to anon/PUBLIC on a table anon can touch; policy expressions run AS the caller.
-- Q3: views anon can select that run as the caller (security_invoker); definer-owned views run as their owner.
-- Q4: column defaults on tables anon can INSERT into, unless RLS leaves anon no INSERT policy at all.
create temp table w5_reach as
  select 'policy ' || pol.polname || ' on ' || c.relname as what, p.oid::regprocedure::text as fn
  from pg_policy pol
  join pg_class c on c.oid = pol.polrelid join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public'
  join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = pol.oid and d.refclassid = 'pg_proc'::regclass
  join pg_proc p on p.oid = d.refobjid and p.pronamespace = 'public'::regnamespace
  where (0 = any(pol.polroles) or 'anon'::regrole::oid = any(pol.polroles))
    and not exists (select 1 from pg_depend e where e.objid = p.oid and e.deptype = 'e')
  union all
  select 'view ' || c.relname, p.oid::regprocedure::text
  from pg_class c join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public' and c.relkind = 'v'
  join pg_rewrite rw on rw.ev_class = c.oid
  join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid and d.refclassid = 'pg_proc'::regclass
  join pg_proc p on p.oid = d.refobjid and p.pronamespace = 'public'::regnamespace
  where has_table_privilege('anon', c.oid, 'SELECT')
    and coalesce(c.reloptions @> array['security_invoker=true'], false)
    and not exists (select 1 from pg_depend e where e.objid = p.oid and e.deptype = 'e')
  union all
  select 'column default ' || c.relname || '.' || a.attname, p.oid::regprocedure::text
  from pg_attrdef ad
  join pg_class c on c.oid = ad.adrelid join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public'
  join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
  join pg_depend d on d.classid = 'pg_attrdef'::regclass and d.objid = ad.oid and d.refclassid = 'pg_proc'::regclass
  join pg_proc p on p.oid = d.refobjid and p.pronamespace = 'public'::regnamespace
  where has_table_privilege('anon', c.oid, 'INSERT')
    and (not c.relrowsecurity
         or exists (select 1 from pg_policy pol where pol.polrelid = c.oid and pol.polcmd in ('a', '*')
                    and (0 = any(pol.polroles) or 'anon'::regrole::oid = any(pol.polroles))))
    and not exists (select 1 from pg_depend e where e.objid = p.oid and e.deptype = 'e');
select tests.ok('W5: no policy, caller-run view or column default reachable by anon calls a non-allowlisted function: '
    || coalesce((select string_agg(distinct what || ' -> ' || fn, '; ') from w5_reach
                 where not has_function_privilege('anon', fn::regprocedure, 'EXECUTE')), 'none'),
  not exists (select 1 from w5_reach where not has_function_privilege('anon', fn::regprocedure, 'EXECUTE')));
-- the check is live: a policy on an anon-readable table that names a non-allowlisted function is reported
create table public.w5_reach_probe(id int);
alter table public.w5_reach_probe enable row level security;
grant select on public.w5_reach_probe to anon;
create policy w5_reach_probe_p on public.w5_reach_probe for select to anon using (public.w5_probe_forgot() = 1);
revoke all on function public.w5_probe_forgot() from public, anon;
select tests.ok('W5: the reachability query sees a policy that calls a function anon cannot execute',
  exists (select 1 from pg_policy pol join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = pol.oid
          join pg_proc p on p.oid = d.refobjid and d.refclassid = 'pg_proc'::regclass
          where pol.polname = 'w5_reach_probe_p' and not has_function_privilege('anon', p.oid, 'EXECUTE')));

-- ---- H. flag row -------------------------------------------------------------------------------------------
select tests.ok('W5: guest_browsing_v1 exists and is off',
  exists (select 1 from public.feature_flags where flag_name = 'guest_browsing_v1' and enabled = false and rollout_percentage = 0));

rollback;
