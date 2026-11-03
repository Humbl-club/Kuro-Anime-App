-- 85_media_similar_v1.sql
-- Prepared 20261103100100_media_similar_v1.sql (NOT deployed): the "More like this" card
-- reader is a thin SECURITY INVOKER wrapper over recommend_ids_similar_to_seeds.
-- media_similar_titles itself does not replay into this fixture (20260804130000 fails on a
-- missing media_tag_vectors), so the wrapped RPC is replaced INSIDE this rolled-back
-- transaction by a recording stub with a fixed answer. That proves the WRAPPER: single seed,
-- gimmicks off, over-fetch then limit, wrapped order kept, adult/coverless/seed rows dropped,
-- card columns per kind, typed errors, grants, and that the table stays unreadable to clients.
-- It does not run the real scorer (covered by the realm tests and live evidence).
-- @requires table public.anime
-- @requires table public.manga
-- @requires function public.recommend_ids_similar_to_seeds(text,integer[],integer,boolean)
\set ON_ERROR_STOP on
\o /dev/null
begin;

-- ---- 0. posture ---------------------------------------------------------------
select tests.ok('media_similar_v1 is SECURITY INVOKER with search_path = public, extensions',
  (select not prosecdef and proconfig @> array['search_path=public, extensions']
     from pg_proc where oid = 'public.media_similar_v1(text,integer,integer)'::regprocedure));
select tests.ok('anon and authenticated may execute it',
  has_function_privilege('anon', 'public.media_similar_v1(text,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.media_similar_v1(text,integer,integer)', 'execute'));
select tests.ok('the precomputed store stays without client grants (read only through the RPC)',
  to_regclass('public.media_similar_titles') is null
  or (not has_table_privilege('anon', 'public.media_similar_titles', 'select')
      and not has_table_privilege('authenticated', 'public.media_similar_titles', 'select')));

-- ---- seed + recording stub (superuser; both rolled back) -------------------------
insert into public.anime (id, title_romaji, title_english, cover_image_large, is_adult, format, episodes, season_year, genres) values
  (850001, 'Seed Show', null, 'https://img.invalid/a1.jpg', false, 'TV', 12, 2020, array['Drama']),
  (850002, 'Adult Pick', null, 'https://img.invalid/a2.jpg', true, 'TV', 12, 2020, null),
  (850003, 'Best Pick', 'Best Pick EN', 'https://img.invalid/a3.jpg', false, 'TV', 24, 2019, array['Drama', 'Romance']),
  (850004, 'Coverless Pick', null, '  ', false, 'TV', 12, 2018, null),
  (850005, 'Second Pick', null, 'https://img.invalid/a5.jpg', false, 'MOVIE', 1, 2021, null);
insert into public.manga (id, title_romaji, cover_image_large, is_adult, format, chapters, volumes) values
  (850101, 'Seed Manga', 'https://img.invalid/m1.jpg', false, 'MANGA', 100, 10),
  (850102, 'Manga Pick', 'https://img.invalid/m2.jpg', false, 'MANGA', 50, 5);

create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  perform set_config('tests.similar_args', p_media_type || '|' || array_to_string(p_seed_ids, ',') || '|' || p_limit || '|' || p_allow_gimmicks, true);
  if p_media_type = 'ANIME' then
    return query select * from (values (850003, 5, 95::real), (850002, 5, 90::real), (850001, 9, 89::real),
      (850004, 4, 80::real), (999999, 1, 75::real), (850005, 3, 70::real)) v(a, b, c) limit p_limit;
  else
    return query select * from (values (850102, 2, 60::real)) v(a, b, c) limit p_limit;
  end if;
end $$;

-- ---- 1. anime ------------------------------------------------------------------
select tests.as_anon();
select tests.eq('anime: adult, seed, coverless and unknown ids dropped; wrapped order kept; ranks renumbered',
  (select string_agg(rank || ':' || id || ':' || title_romaji, ',') from public.media_similar_v1('anime', 850001)),
  '1:850003:Best Pick,2:850005:Second Pick');
select tests.eq('the wrapped RPC is called with ONE seed, gimmicks off, and an over-fetch of limit + 8',
  current_setting('tests.similar_args', true), 'ANIME|850001|20|false');
select tests.eq('anime: card columns come back (english title, format, episodes, year, genres, score)',
  (select media_type || '/' || title_english || '/' || format || '/' || episodes || '/' || season_year || '/'
          || array_to_string(genres, '+') || '/' || similarity_score || '/' || coalesce(chapters::text, 'null')
     from public.media_similar_v1('ANIME', 850001) where id = 850003),
  'ANIME/Best Pick EN/TV/24/2019/Drama+Romance/95/null');
select tests.eq('anime: limit applies after the filters',
  (select string_agg(id::text, ',') from public.media_similar_v1('ANIME', 850001, 1)), '850003');
select tests.eq('an oversized limit still answers', (select count(*) from public.media_similar_v1('ANIME', 850001, 500)), 2::bigint);
select tests.eq('limit is clamped to 30 (fetch 38)', current_setting('tests.similar_args', true), 'ANIME|850001|38|false');

-- ---- 2. manga ------------------------------------------------------------------
select tests.as_user(tests.uid(851));
select tests.eq('manga: chapters/volumes columns, no anime-only fields',
  (select media_type || '/' || id || '/' || chapters || '/' || volumes || '/' || coalesce(episodes::text, 'null') || '/' || coalesce(banner_image, 'null')
     from public.media_similar_v1('MANGA', 850101)),
  'MANGA/850102/50/5/null/null');

-- ---- 3. typed errors -------------------------------------------------------------
select tests.raises('unknown medium raises INVALID_MEDIUM', $q$select * from public.media_similar_v1('NOVEL', 1)$q$, 'INVALID_MEDIUM:%');
select tests.raises('non-positive id raises INVALID_MEDIA_ID', $q$select * from public.media_similar_v1('ANIME', 0)$q$, 'INVALID_MEDIA_ID:%');
select tests.raises('null id raises INVALID_MEDIA_ID', $q$select * from public.media_similar_v1('ANIME', null)$q$, 'INVALID_MEDIA_ID:%');

select tests.reset();
rollback;
