-- 104_discover_newly_added_base.sql
-- Prepared 20261109200200_discover_newly_added_base_v1.sql (NOT deployed): the Discover
-- "Newly added" rails read anime / manga directly; the two full-copy snapshot matviews are
-- dropped; refresh_discover_matviews_v1() refreshes the four remaining ones.
-- Differential: the frozen pre-change body (fixtures/104_discover_bundle_baseline.sql) runs
-- against snapshot matviews rebuilt from the same rows inside this transaction (the state right
-- after a 01:30 refresh); its whole jsonb must equal the new function's. Then freshness: a row
-- inserted after the snapshot appears first in the new rail.
-- curated_rail_items and user_lists do not replay into the fixture: stand-ins (the live view text
-- for user_lists, read-only pg_get_viewdef 2026-11-09) are created inside the rolled-back
-- transaction only when absent.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.discover_rail_impressions
-- @requires function public.discover_bundle(integer,integer)
\set ON_ERROR_STOP on
\o /dev/null
begin;
set local jit = off;
\ir ../fixtures/104_discover_bundle_baseline.sql
select tests.reset();

-- ---- 1. posture --------------------------------------------------------------------
select tests.ok('the two newly-added snapshot matviews are gone',
  to_regclass('public.mv_anime_newly_added') is null and to_regclass('public.mv_manga_newly_added') is null);
select tests.eq('the four trending / top-rated matviews remain',
  (select count(*) from pg_matviews where schemaname = 'public'
     and matviewname in ('mv_anime_trending','mv_anime_top_rated','mv_manga_trending','mv_manga_top_rated')), 4::bigint);
select tests.eq('refresh_discover_matviews_v1 lists exactly the four remaining matviews',
  (select array_agg(x order by x) from jsonb_array_elements_text(public.refresh_discover_matviews_v1() -> 'refreshed') x),
  array['mv_anime_top_rated','mv_anime_trending','mv_manga_top_rated','mv_manga_trending']);
select tests.ok('refresh_discover_matviews_v1 stays service-only',
  not has_function_privilege('anon', 'public.refresh_discover_matviews_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.refresh_discover_matviews_v1()', 'execute'));
select tests.ok('discover_bundle reads the base tables for newly added and no longer names the snapshots',
  (select prosrc !~ 'mv_(anime|manga)_newly_added'
      and prosrc like '%from public.anime a, params p%order by a.created_at desc nulls last, a.id desc%'
      and prosrc like '%from public.manga m, params p%order by m.created_at desc nulls last, m.id desc%'
   from pg_proc where oid = 'public.discover_bundle(integer,integer)'::regprocedure));
select tests.ok('discover_bundle keeps definer, search_path = public, extensions and jit off',
  (select prosecdef and proconfig @> array['search_path=public, extensions','jit=off']
   from pg_proc where oid = 'public.discover_bundle(integer,integer)'::regprocedure));
select tests.ok('authenticated may still execute discover_bundle',
  has_function_privilege('authenticated', 'public.discover_bundle(integer,integer)', 'execute'));
-- The order rewrite (desc nulls last) is result-identical only while created_at cannot be null.
select tests.ok('precondition: anime.created_at and manga.created_at are NOT NULL',
  (select bool_and(attnotnull) from pg_attribute
    where attrelid in ('public.anime'::regclass, 'public.manga'::regclass) and attname = 'created_at') );

-- ---- 2. stand-ins and rows ---------------------------------------------------------
do $standins$
begin
  if to_regclass('public.curated_rail_items') is null then
    create table public.curated_rail_items (rail_id text not null, media_type text not null, anilist_id integer not null, rank integer not null);
  end if;
  if to_regprocedure('public.current_season_name(timestamptz)') is null then
    -- 20260203223000's body (does not replay into the fixture).
    execute $f$
      create function public.current_season_name(p_at timestamptz default now()) returns text
      language sql immutable as $b$
        select case
          when extract(month from p_at)::int in (12, 1, 2) then 'WINTER'
          when extract(month from p_at)::int in (3, 4, 5) then 'SPRING'
          when extract(month from p_at)::int in (6, 7, 8) then 'SUMMER'
          else 'FALL'
        end $b$ $f$;
  end if;
  if to_regclass('public.user_lists') is null then
    execute $v$
      create view public.user_lists with (security_invoker = on) as
      select aul.id, aul.user_id, aul.anime_id as media_id, 'anime'::text as media_type, aul.list_type as status,
             aul.progress, null::integer as progress_volumes,
             case when aul.rating is null then null::integer else aul.rating * 10 end as score,
             aul.notes, null::timestamptz as started_at, null::timestamptz as completed_at, false as private,
             aul.created_at, aul.updated_at
        from public.anime_user_lists aul
      union all
      select mul.id, mul.user_id, mul.manga_id, 'manga'::text, mul.list_type, mul.progress, null::integer,
             case when mul.rating is null then null::integer else mul.rating * 10 end,
             mul.notes, null::timestamptz, null::timestamptz, false, mul.created_at, mul.updated_at
        from public.manga_user_lists mul $v$;
  end if;
end;
$standins$;

select tests.make_user(1041);
set local session_replication_role = replica;  -- ingestion triggers off, this transaction only
-- 160 anime / 160 manga: ties on created_at (id breaks them), adult / Hentai / Ecchi / ancillary
-- formats that must stay out, scores >= 80 and trending > 0 so every other rail has rows too.
-- Every rail gets real rows: classics (year < 2015, score >= 80), airing today (RELEASING with
-- next_airing_at inside the current Berlin day) and the current season.
insert into public.anime (id, anilist_id, title_romaji, title_english, format, status, popularity, trending, average_score,
                          favourites, genres, is_adult, episodes, season, season_year, start_date_year, next_airing_at,
                          cover_image_large, created_at)
select 1040000 + n, 1040000 + n, 'Fresh anime ' || n, 'Fresh anime EN ' || n,
       case when n % 11 = 0 then 'SPECIAL' when n % 13 = 0 then 'TV_SHORT' when n % 17 = 0 then 'MUSIC' else 'TV' end,
       case when n % 3 = 0 then 'RELEASING' else 'FINISHED' end,
       1000 + n, n % 40, 60 + n % 40, n % 50,
       case when n % 19 = 0 then array['Hentai'] when n % 23 = 0 then array['Ecchi'] else array['Action'] end,
       n % 29 = 0, 12,
       case when n % 4 = 0 then public.current_season_name(now()) end,
       case when n % 4 = 0 then extract(year from now())::int when n % 5 = 0 then 2005 else 2020 + n % 6 end,
       case when n % 4 = 0 then extract(year from now())::int when n % 5 = 0 then 2005 else 2020 + n % 6 end,
       case when n % 3 = 0 and n % 7 = 0
            then (date_trunc('day', now() at time zone 'Europe/Berlin') + interval '12 hours') at time zone 'Europe/Berlin' end,
       'https://img.invalid/a' || n || '.jpg',
       now() - ((n / 3) * interval '1 hour')
from generate_series(1, 160) n;
insert into public.manga (id, anilist_id, title_romaji, title_english, format, status, popularity, trending, average_score,
                          favourites, genres, is_adult, chapters, start_date_year, cover_image_large, created_at)
select 1040000 + n, 1040000 + n, 'Fresh manga ' || n, 'Fresh manga EN ' || n, 'MANGA', 'FINISHED',
       1000 + n, n % 40, 60 + n % 40, n % 50,
       case when n % 19 = 0 then array['Hentai'] when n % 23 = 0 then array['Ecchi'] else array['Drama'] end,
       n % 29 = 0, 50, case when n % 5 = 0 then 2005 else 2020 + n % 6 end, 'https://img.invalid/m' || n || '.jpg',
       now() - ((n / 3) * interval '1 hour')
from generate_series(1, 160) n;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(1041)::text, 1040002, 'WATCHING', 1);
set local session_replication_role = origin;
refresh materialized view public.mv_anime_trending;
refresh materialized view public.mv_anime_top_rated;
refresh materialized view public.mv_manga_trending;
refresh materialized view public.mv_manga_top_rated;
analyze public.anime;
analyze public.manga;

-- ---- 3. differential: old body over fresh snapshots == new body over base tables ----
create materialized view public.mv_anime_newly_added as select * from public.anime;
create materialized view public.mv_manga_newly_added as select * from public.manga;
select set_config('request.jwt.claims',
  json_build_object('sub', tests.uid(1041)::text, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
savepoint before_old;
select pg_temp.old_discover_bundle(30, 24)::text as old_bundle \gset
rollback to savepoint before_old;
drop materialized view public.mv_anime_newly_added;
drop materialized view public.mv_manga_newly_added;
savepoint before_new;
select public.discover_bundle(30, 24)::text as new_bundle \gset
rollback to savepoint before_new;

select tests.ok('the whole bundle is identical to the pre-change body right after a refresh',
  :'old_bundle'::jsonb = :'new_bundle'::jsonb);
select tests.eq('anime newly added is full (30 rows) and excludes adult, Hentai, Ecchi and ancillary formats',
  (select count(*) from jsonb_array_elements(:'new_bundle'::jsonb -> 'anime' -> 'newly_added') e
    where (e ->> 'id')::int - 1040000 not in (select n from generate_series(1,160) n
      where n % 11 = 0 or n % 13 = 0 or n % 17 = 0 or n % 19 = 0 or n % 23 = 0 or n % 29 = 0)), 30::bigint);
select tests.eq('manga newly added is full (30 rows) and excludes adult, Hentai and Ecchi',
  (select count(*) from jsonb_array_elements(:'new_bundle'::jsonb -> 'manga' -> 'newly_added') e
    where (e ->> 'id')::int - 1040000 not in (select n from generate_series(1,160) n
      where n % 19 = 0 or n % 23 = 0 or n % 29 = 0)), 30::bigint);
select tests.eq('ties on created_at are broken by id descending (1040001 and 1040002 share created_at)',
  (select array_agg((e ->> 'id')::int order by o) from jsonb_array_elements(:'new_bundle'::jsonb -> 'anime' -> 'newly_added') with ordinality x(e, o) where o <= 2),
  array[1040002, 1040001]);
select tests.ok('every rail of both media is populated (the differential compares real rows everywhere)',
  (select bool_and(jsonb_array_length(:'new_bundle'::jsonb -> 'anime' -> k) > 0)
     from unnest(array['essentials','classics','new_to_you','trending','top_rated','newly_added','airing_today','current_season']) k)
  and (select bool_and(jsonb_array_length(:'new_bundle'::jsonb -> 'manga' -> k) > 0)
     from unnest(array['essentials','classics','new_to_you','trending','top_rated','newly_added']) k));

-- ---- 4. freshness: a title ingested after the 01:30 snapshot shows at once ------------
set local session_replication_role = replica;
insert into public.anime (id, anilist_id, title_romaji, format, status, popularity, genres, is_adult, cover_image_large, created_at)
values (1040999, 1040999, 'Just ingested', 'TV', 'RELEASING', 1, array['Action'], false, 'https://img.invalid/new.jpg', now() + interval '1 minute');
set local session_replication_role = origin;
select tests.eq('a just-ingested anime leads the newly-added rail without any refresh',
  (public.discover_bundle(30, 24) -> 'anime' -> 'newly_added' -> 0 ->> 'id')::int, 1040999);

-- ---- 5. plan: the existing order index serves the rail (no sort over the table) -------
create temporary table newly_added_plans (medium text, plan jsonb);
do $plans$
declare
  src text; cte text; plan jsonb; med text;
begin
  select prosrc into src from pg_proc where oid = 'public.discover_bundle(integer,integer)'::regprocedure;
  foreach med in array array['anime','manga'] loop
    cte := substring(src from med || '_newly_added as \((.*?)limit \(select lim from params\)');
    if cte is null then raise exception 'could not extract the % newly-added CTE', med; end if;
    execute 'explain (format json) with params as (select 30::int as lim) ' || cte || ' limit 30' into plan;
    insert into newly_added_plans values (med, plan);
  end loop;
end;
$plans$;
select tests.ok('newly added uses idx_anime_load_created_v1 / idx_manga_load_created_v1 without a Sort node',
  (select count(*) = 2 from newly_added_plans
    where plan::text like '%"Index Name": "idx_' || medium || '_load_created_v1"%'
      and plan::text not like '%"Node Type": "Sort"%'));
\o
select medium, plan from newly_added_plans;
\o /dev/null
rollback;
