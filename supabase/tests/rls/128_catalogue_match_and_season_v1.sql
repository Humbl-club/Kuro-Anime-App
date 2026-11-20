-- 128_catalogue_match_and_season_v1.sql
-- Prepared 20261119120000_catalogue_intake_match_and_season_v1.sql (NOT deployed):
-- Covers: service-role-only posture + fixed search_path for catalogue_find_title_candidates_v1,
-- case-insensitive/synonym candidate lookup bounded by year window, and season/season_year whitelist on create.
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

select tests.ok('catalogue_find_title_candidates_v1 is plpgsql, invoker, fixed search_path',
  (select count(*) = 1 and bool_and(proconfig @> array['search_path=public, extensions']) and bool_and(not prosecdef)
   from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalogue_find_title_candidates_v1'));
select tests.ok('EXECUTE only for service_role',
  not has_function_privilege('anon', 'public.catalogue_find_title_candidates_v1(text,text[],integer,integer,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalogue_find_title_candidates_v1(text,text[],integer,integer,integer)', 'execute')
  and not has_function_privilege('public', 'public.catalogue_find_title_candidates_v1(text,text[],integer,integer,integer)', 'execute')
  and has_function_privilege('service_role', 'public.catalogue_find_title_candidates_v1(text,text[],integer,integer,integer)', 'execute'));

delete from catalogue_shadow_values;
delete from catalogue_id_links;
delete from public.anime;
delete from public.manga;
insert into public.manga (id, anilist_id, title_english, title_synonyms, start_date_year, format, country_of_origin)
values (1280001, 105778, 'Chainsaw Man', array['Chainsawman'], 2018, 'MANGA', 'JP'),
       (1280002, 200001, 'Old Classic', array[]::text[], 1995, 'MANGA', 'JP');

select tests.eq('matches case-insensitively on synonym within year window',
  jsonb_array_length(public.catalogue_find_title_candidates_v1('manga', array['chainsawman'], 2016, 2020, 50)), 1);
select tests.eq('excludes rows outside year window',
  jsonb_array_length(public.catalogue_find_title_candidates_v1('manga', array['old classic'], 2020, 2026, 50)), 0);

create temp table _r (j jsonb);
insert into _r select public.catalogue_create_title_v1('anime',
  '{"title_romaji":"Winter Premiere","format":"TV","status":"NOT_YET_RELEASED","season":"WINTER","season_year":2027,"start_date_year":2027,"start_date_month":1,"start_date_day":8,"data_sources":["ann"]}'::jsonb,
  'ann', '128001', 1, '{}'::jsonb);
select tests.ok('create persists derived season and season_year',
  exists (select 1 from public.anime a, _r where a.id = (_r.j ->> 'id')::int and a.season = 'WINTER' and a.season_year = 2027 and a.status = 'NOT_YET_RELEASED'));

select tests.as_anon();
select tests.denied('anon cannot call candidate matcher', $q$select public.catalogue_find_title_candidates_v1('manga', array['chainsaw man'], null, null, 10)$q$);
select tests.reset();
rollback;
