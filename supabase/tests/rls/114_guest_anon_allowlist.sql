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

-- ---- the allowlist (23 signatures: 19 guest reads + 3 signed-out infrastructure + 1 pure helper) --
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
  ('public.get_concierge_config()'),
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
  for r in select sig from w5_allow where to_regprocedure(sig) is null loop
    perform tests.blocked('W5: allowlisted function absent from fixture: ' || r.sig, 'the live audit (live-anon-grants.sql) enforces it');
  end loop;
end $$;
select tests.ok('W5: anon can execute every allowlisted function present',
  not exists (select sig from w5_allow_present except select sig from w5_anon));
select tests.ok('W5: anon can execute nothing outside the allowlist: '
    || coalesce((select string_agg(x, ', ' order by x) from (select sig from w5_anon except select sig from w5_allow_norm) e(x)), 'none'),
  not exists (select sig from w5_anon except select sig from w5_allow_norm));
select tests.ok('W5: the three signed-out infrastructure functions are still anon-callable (contact form, anonymous parse)',
  (select count(*) from w5_anon where sig in (
     'check_concierge_rate_limit(text,text,integer,integer,integer)', 'get_concierge_config()', 'search_titles(text,text,integer)')) = 3);

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
      ('media_release_schedule_v1', $q$select * from public.media_release_schedule_v1('ANIME', 1, 6)$q$, null),
      ('media_themes_v1', $q$select * from public.media_themes_v1(1)$q$, null),
      ('anime_cast_v1', $q$select * from public.anime_cast_v1(1, 'JAPANESE', 50)$q$, null),
      ('character_voice_actors_v1', $q$select * from public.character_voice_actors_v1(1, 'JAPANESE')$q$, null),
      ('staff_voice_roles_v1', $q$select * from public.staff_voice_roles_v1(1, 50)$q$, null),
      ('check_concierge_rate_limit', $q$select * from public.check_concierge_rate_limit('contact', 'w5-probe-key', 5, 3600, 1)$q$, null),
      ('get_concierge_config', $q$select * from public.get_concierge_config()$q$, null),
      ('search_titles', $q$select * from public.search_titles('a', 'ANIME', 5)$q$, null)
    ) as t(name, stmt, needs)
  loop
    if c.needs is not null and to_regprocedure(c.needs) is null then
      perform tests.blocked('W5 anon call skipped (function absent): ' || c.name, 'the live audit enforces it');
      continue;
    end if;
    v_denied := false;
    begin
      execute c.stmt;
    exception
      when insufficient_privilege then v_denied := true;
      when others then
        raise notice 'W5 anon call % raised % (not a privilege denial; fixture relation or data): %', c.name, sqlstate, sqlerrm;
    end;
    perform tests.ok('W5 anon call not denied: ' || c.name, not v_denied);
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
    'create_club_poll', 'create_club_rail', 'release_import_lock', 'catalogue_search_blob_v1'] loop
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
select tests.ok('W5: a new function that forgets revoke-from-public is still caught by section A/B (anon only via PUBLIC)',
  has_function_privilege('anon', 'public.w5_probe_forgot()', 'EXECUTE')
  and not exists (select 1 from pg_default_acl d, lateral aclexplode(d.defaclacl) a where d.defaclobjtype = 'f' and a.grantee = 'anon'::regrole));

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

-- ---- H. flag row -------------------------------------------------------------------------------------------
select tests.ok('W5: guest_browsing_v1 exists and is off',
  exists (select 1 from public.feature_flags where flag_name = 'guest_browsing_v1' and enabled = false and rollout_percentage = 0));

rollback;
