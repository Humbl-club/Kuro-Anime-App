-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 15b, part 2). NOT applied.
--
-- The Discover readers of the visibility filter. Split from 20261112100400 because their latest definitions
-- are in prepared files whose hosted state is not established by this task:
--   discover_bundle           20261109200200_discover_newly_added_base_v1.sql (backend latency step 1c, PARKED:
--                             switches the newly-added rails to the base tables). This file is built on that body,
--                             so it carries 1c's change. Apply 1c first, or regenerate this function from the live
--                             body; do NOT apply this file over an older live discover_bundle unintentionally.
--   discover_section_page_v1, discover_mood_v1, _discover_page_v1
--                             20261104100000 / 20261104100100 (Discover usability). If those are not applied,
--                             CREATE OR REPLACE here would create them.
-- Requires 20261112100400 (the visibility columns).
-- The trending and top-rated rails read matviews, which are copies of the catalogue taken at refresh time:
-- their rows are checked against the base table (catalogue_anime_visible / catalogue_manga_visible).
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local check_function_bodies = off;

create or replace function public.catalogue_anime_visible(p_id integer)
returns boolean
language sql
stable
set search_path = public, extensions
as $$ select exists (select 1 from public.anime a where a.id = p_id and a.catalogue_visibility = 'visible') $$;

create or replace function public.catalogue_manga_visible(p_id integer)
returns boolean
language sql
stable
set search_path = public, extensions
as $$ select exists (select 1 from public.manga m where m.id = p_id and m.catalogue_visibility = 'visible') $$;

revoke all on function public.catalogue_anime_visible(integer) from public;
revoke all on function public.catalogue_manga_visible(integer) from public;
grant execute on function public.catalogue_anime_visible(integer) to anon, authenticated, service_role;
grant execute on function public.catalogue_manga_visible(integer) to anon, authenticated, service_role;

-- discover_bundle: latest definition 20261109200200_discover_newly_added_base_v1.sql; 18 anime/manga/matview references, 18 visibility predicates added
create or replace function public.discover_bundle(
  p_limit integer default 30,
  p_hours integer default 24
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
set jit = off
as $function$
declare
  v_payload jsonb;
  v_user_id text := auth.uid()::text;
  v_anime_new_to_you_ids integer[] := '{}'::integer[];
  v_manga_new_to_you_ids integer[] := '{}'::integer[];
begin
  with me as (
    select v_user_id as user_id
  ),
  params as (
    select
      greatest(1, least(coalesce(p_limit, 30), 60))::int as lim,
      greatest(1, least(coalesce(p_hours, 24), 168))::int as hrs,
      public.current_season_name(now()) as season,
      extract(year from now())::int as year,
      (date_trunc('day', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin') as berlin_day_start,
      ((date_trunc('day', now() at time zone 'Europe/Berlin') + interval '1 day') at time zone 'Europe/Berlin') as berlin_day_end
  ),
  curated_gateway_anime as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      i.rank as r
    from public.curated_rail_items i
    join public.anime a on a.anilist_id = i.anilist_id
    where i.rail_id = 'gateway_anime'
      and i.media_type = 'ANIME'
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by i.rank asc
    limit (select lim from params)
  ),
  anime_essentials_fallback as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      999999 as r
    from public.anime a, params p
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and coalesce(a.average_score, 0) >= 85
    order by coalesce(a.favourites, 0) desc, coalesce(a.average_score, 0) desc, coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_essentials as (
    select
      x.id,
      x.title_english, x.title_romaji, x.title_native,
      x.cover_image_large, x.cover_image_medium, x.banner_image,
      x.format, x.status,
      x.episode_count,
      x.season_year,
      x.start_date_year,
      x.average_score,
      x.popularity,
      x.trending,
      x.favourites,
      x.genres
    from (
      select * from curated_gateway_anime
      union all
      select * from anime_essentials_fallback
      where not exists (select 1 from curated_gateway_anime)
    ) x
    order by x.r asc, x.id desc
    limit (select lim from params)
  ),
  curated_classics_anime as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      i.rank as r
    from public.curated_rail_items i
    join public.anime a on a.anilist_id = i.anilist_id
    where i.rail_id = 'classics_anime'
      and i.media_type = 'ANIME'
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by i.rank asc
    limit (select lim from params)
  ),
  anime_classics_fallback as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      999999 as r
    from public.anime a, params p
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and coalesce(a.season_year, a.start_date_year, 9999) < 2015
      and coalesce(a.average_score, 0) >= 80
    order by coalesce(a.average_score, 0) desc, coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_classics as (
    select
      x.id,
      x.title_english, x.title_romaji, x.title_native,
      x.cover_image_large, x.cover_image_medium, x.banner_image,
      x.format, x.status,
      x.episode_count,
      x.season_year,
      x.start_date_year,
      x.average_score,
      x.popularity,
      x.trending,
      x.favourites,
      x.genres
    from (
      select * from curated_classics_anime
      union all
      select * from anime_classics_fallback
      where not exists (select 1 from curated_classics_anime)
    ) x
    order by x.r asc, x.id desc
    limit (select lim from params)
  ),
  anime_new_to_you_candidates as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.anime a, params p
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (select user_id from me) is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )
      and coalesce(a.average_score, 0) >= 80
    order by coalesce(a.popularity, 0) desc, coalesce(a.average_score, 0) desc, coalesce(a.favourites, 0) desc, a.id desc
    limit greatest((select lim from params) * 6, 60)
  ),
  anime_new_to_you as (
    select
      c.id,
      c.title_english, c.title_romaji, c.title_native,
      c.cover_image_large, c.cover_image_medium, c.banner_image,
      c.format, c.status,
      c.episode_count,
      c.season_year,
      c.start_date_year,
      c.average_score,
      c.popularity,
      c.trending,
      c.favourites,
      c.genres
    from anime_new_to_you_candidates c
    left join public.discover_rail_impressions i
      on i.user_id = (select user_id from me)
     and i.rail_key = 'discover_new_to_you'
     and i.media_type = 'anime'
     and i.media_id = c.id
    order by
      case when i.last_shown_at is null then 0 else 1 end asc,
      i.last_shown_at asc nulls first,
      coalesce(c.popularity, 0) desc,
      coalesce(c.average_score, 0) desc,
      coalesce(c.favourites, 0) desc,
      c.id desc
    limit (select lim from params)
  ),
  anime_trending as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.mv_anime_trending a, params p
    where (coalesce(a.is_adult, false) = false and public.catalogue_anime_visible(a.id))
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by coalesce(a.trending, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_top_rated as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.mv_anime_top_rated a, params p
    where (coalesce(a.is_adult, false) = false and public.catalogue_anime_visible(a.id))
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and coalesce(a.average_score, 0) >= 80
    order by coalesce(a.average_score, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_newly_added as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.anime a, params p
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by a.created_at desc nulls last, a.id desc
    limit (select lim from params)
  ),
  anime_airing_today as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.anime a, params p
    where a.status = 'RELEASING'
      and a.next_airing_at is not null
      and a.next_airing_at >= p.berlin_day_start
      and a.next_airing_at < p.berlin_day_end
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by
      coalesce(a.popularity, 0) desc,
      coalesce(a.average_score, 0) desc,
      coalesce(a.favourites, 0) desc,
      a.next_airing_at asc,
      a.id desc
    limit (select lim from params)
  ),
  anime_current_season as (
    select
      a.id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_large, a.cover_image_medium, a.banner_image,
      a.format, a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres
    from public.anime a, params p
    where a.season = (select season from params)
      and a.season_year = (select year from params)
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    order by coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),
  curated_gateway_manga as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      i.rank as r
    from public.curated_rail_items i
    join public.manga m on m.anilist_id = i.anilist_id
    where i.rail_id = 'gateway_manga'
      and i.media_type = 'MANGA'
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by i.rank asc
    limit (select lim from params)
  ),
  manga_essentials_fallback as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      999999 as r
    from public.manga m, params p
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and coalesce(m.average_score, 0) >= 85
    order by coalesce(m.favourites, 0) desc, coalesce(m.average_score, 0) desc, coalesce(m.popularity, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_essentials as (
    select
      x.id,
      x.title_english, x.title_romaji, x.title_native,
      x.cover_image_large, x.cover_image_medium,
      x.format, x.status,
      x.chapter_count,
      x.start_date_year,
      x.average_score,
      x.popularity,
      x.trending,
      x.favourites,
      x.genres
    from (
      select * from curated_gateway_manga
      union all
      select * from manga_essentials_fallback
      where not exists (select 1 from curated_gateway_manga)
    ) x
    order by x.r asc, x.id desc
    limit (select lim from params)
  ),
  curated_classics_manga as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      i.rank as r
    from public.curated_rail_items i
    join public.manga m on m.anilist_id = i.anilist_id
    where i.rail_id = 'classics_manga'
      and i.media_type = 'MANGA'
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by i.rank asc
    limit (select lim from params)
  ),
  manga_classics_fallback as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      999999 as r
    from public.manga m, params p
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and coalesce(m.start_date_year, 9999) < 2015
      and coalesce(m.average_score, 0) >= 80
    order by coalesce(m.average_score, 0) desc, coalesce(m.popularity, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_classics as (
    select
      x.id,
      x.title_english, x.title_romaji, x.title_native,
      x.cover_image_large, x.cover_image_medium,
      x.format, x.status,
      x.chapter_count,
      x.start_date_year,
      x.average_score,
      x.popularity,
      x.trending,
      x.favourites,
      x.genres
    from (
      select * from curated_classics_manga
      union all
      select * from manga_classics_fallback
      where not exists (select 1 from curated_classics_manga)
    ) x
    order by x.r asc, x.id desc
    limit (select lim from params)
  ),
  manga_new_to_you_candidates as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres
    from public.manga m, params p
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (select user_id from me) is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
      and coalesce(m.average_score, 0) >= 80
    order by coalesce(m.popularity, 0) desc, coalesce(m.average_score, 0) desc, coalesce(m.favourites, 0) desc, m.id desc
    limit greatest((select lim from params) * 6, 60)
  ),
  manga_new_to_you as (
    select
      c.id,
      c.title_english, c.title_romaji, c.title_native,
      c.cover_image_large, c.cover_image_medium,
      c.format, c.status,
      c.chapter_count,
      c.start_date_year,
      c.average_score,
      c.popularity,
      c.trending,
      c.favourites,
      c.genres
    from manga_new_to_you_candidates c
    left join public.discover_rail_impressions i
      on i.user_id = (select user_id from me)
     and i.rail_key = 'discover_new_to_you'
     and i.media_type = 'manga'
     and i.media_id = c.id
    order by
      case when i.last_shown_at is null then 0 else 1 end asc,
      i.last_shown_at asc nulls first,
      coalesce(c.popularity, 0) desc,
      coalesce(c.average_score, 0) desc,
      coalesce(c.favourites, 0) desc,
      c.id desc
    limit (select lim from params)
  ),
  manga_trending as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres
    from public.mv_manga_trending m, params p
    where (coalesce(m.is_adult, false) = false and public.catalogue_manga_visible(m.id))
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by coalesce(m.trending, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_top_rated as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres
    from public.mv_manga_top_rated m, params p
    where (coalesce(m.is_adult, false) = false and public.catalogue_manga_visible(m.id))
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and coalesce(m.average_score, 0) >= 80
    order by coalesce(m.average_score, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_newly_added as (
    select
      m.id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_large, m.cover_image_medium,
      m.format, m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres
    from public.manga m, params p
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by m.created_at desc nulls last, m.id desc
    limit (select lim from params)
  )
  select
    jsonb_build_object(
      'anime', jsonb_build_object(
        'essentials', coalesce((select jsonb_agg(to_jsonb(anime_essentials)) from anime_essentials), '[]'::jsonb),
        'classics', coalesce((select jsonb_agg(to_jsonb(anime_classics)) from anime_classics), '[]'::jsonb),
        'new_to_you', coalesce((select jsonb_agg(to_jsonb(anime_new_to_you)) from anime_new_to_you), '[]'::jsonb),
        'trending', coalesce((select jsonb_agg(to_jsonb(anime_trending)) from anime_trending), '[]'::jsonb),
        'top_rated', coalesce((select jsonb_agg(to_jsonb(anime_top_rated)) from anime_top_rated), '[]'::jsonb),
        'newly_added', coalesce((select jsonb_agg(to_jsonb(anime_newly_added)) from anime_newly_added), '[]'::jsonb),
        'airing_today', coalesce((select jsonb_agg(to_jsonb(anime_airing_today)) from anime_airing_today), '[]'::jsonb),
        'current_season', coalesce((select jsonb_agg(to_jsonb(anime_current_season)) from anime_current_season), '[]'::jsonb)
      ),
      'manga', jsonb_build_object(
        'essentials', coalesce((select jsonb_agg(to_jsonb(manga_essentials)) from manga_essentials), '[]'::jsonb),
        'classics', coalesce((select jsonb_agg(to_jsonb(manga_classics)) from manga_classics), '[]'::jsonb),
        'new_to_you', coalesce((select jsonb_agg(to_jsonb(manga_new_to_you)) from manga_new_to_you), '[]'::jsonb),
        'trending', coalesce((select jsonb_agg(to_jsonb(manga_trending)) from manga_trending), '[]'::jsonb),
        'top_rated', coalesce((select jsonb_agg(to_jsonb(manga_top_rated)) from manga_top_rated), '[]'::jsonb),
        'newly_added', coalesce((select jsonb_agg(to_jsonb(manga_newly_added)) from manga_newly_added), '[]'::jsonb)
      )
    ),
    coalesce(array(select id from anime_new_to_you), '{}'::integer[]),
    coalesce(array(select id from manga_new_to_you), '{}'::integer[])
  into v_payload, v_anime_new_to_you_ids, v_manga_new_to_you_ids;

  if v_user_id is not null then
    insert into public.discover_rail_impressions (user_id, rail_key, media_type, media_id, last_shown_at)
    select v_user_id, 'discover_new_to_you', 'anime', id, now()
    from unnest(v_anime_new_to_you_ids) as id
    on conflict (user_id, rail_key, media_type, media_id)
    do update set last_shown_at = excluded.last_shown_at;

    insert into public.discover_rail_impressions (user_id, rail_key, media_type, media_id, last_shown_at)
    select v_user_id, 'discover_new_to_you', 'manga', id, now()
    from unnest(v_manga_new_to_you_ids) as id
    on conflict (user_id, rail_key, media_type, media_id)
    do update set last_shown_at = excluded.last_shown_at;
  end if;

  return v_payload;
end;
$function$;

-- discover_section_page_v1: latest definition 20261104100000_discover_usability_v1.sql; 4 anime/manga/matview references, 4 visibility predicates added
create or replace function public.discover_section_page_v1(
  p_section text,
  p_media_type text default 'ANIME',
  p_sort text default null,
  p_format text default null,
  p_length text default null,
  p_status text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_uid_text text := auth.uid()::text;
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_section text := lower(btrim(coalesce(p_section, '')));
  v_sort text := lower(btrim(coalesce(nullif(btrim(p_sort), ''), 'default')));
  v_format text := upper(nullif(btrim(coalesce(p_format, '')), ''));
  v_length text := lower(nullif(btrim(coalesce(p_length, '')), ''));
  v_status_in text := lower(nullif(btrim(coalesce(p_status, '')), ''));
  v_status text;
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(440, greatest(0, coalesce(p_offset, 0)));
  v_hide_owned boolean;
  -- Pool depth: the page plus one more row, doubled while franchise dedupe leaves too few.
  v_pool integer;
  v_pool_cap constant integer := 4000;
  v_got integer;
  v_distinct integer;
  v_season text := case
    when extract(month from now())::int in (12, 1, 2) then 'WINTER'
    when extract(month from now())::int in (3, 4, 5) then 'SPRING'
    when extract(month from now())::int in (6, 7, 8) then 'SUMMER'
    else 'FALL' end;
  v_year integer := extract(year from now())::int;
  v_day_start timestamptz := (date_trunc('day', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin');
  v_day_end timestamptz := ((date_trunc('day', now() at time zone 'Europe/Berlin') + interval '1 day') at time zone 'Europe/Berlin');
  v_curated_rail text;
  v_has_curated boolean := false;
  v_ids integer[];
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if v_section not in ('essentials', 'classics', 'new_to_you', 'trending', 'top_rated', 'newly_added',
                       'current_season', 'airing_today')
     or (v_type = 'MANGA' and v_section in ('current_season', 'airing_today')) then
    raise exception 'INVALID_SECTION: % is not a % Discover section', p_section, v_type;
  end if;
  if v_sort not in ('default', 'popular', 'newest', 'top_rated') then
    raise exception 'INVALID_SORT: p_sort must be default, popular, newest or top_rated';
  end if;
  if v_length is not null and v_length not in ('short', 'standard', 'long') then
    raise exception 'INVALID_LENGTH: p_length must be short, standard or long';
  end if;
  v_status := case v_status_in
    when 'finished' then 'FINISHED'
    when 'releasing' then 'RELEASING'
    when 'upcoming' then 'NOT_YET_RELEASED'
    else null end;
  if v_status_in is not null and v_status is null then
    raise exception 'INVALID_STATUS: p_status must be finished, releasing or upcoming';
  end if;

  v_hide_owned := v_section = 'new_to_you' and v_uid is not null;
  v_pool := least(v_pool_cap, (v_offset + v_limit) * 2 + 40);

  if v_section in ('essentials', 'classics') then
    v_curated_rail := case v_section when 'essentials' then 'gateway_' else 'classics_' end
                      || lower(v_type);
    if to_regclass('public.curated_rail_items') is not null then
      execute 'select exists (select 1 from public.curated_rail_items where rail_id = $1 and media_type = $2)'
        into v_has_curated using v_curated_rail, v_type;
    end if;
  end if;

  loop
    if v_type = 'ANIME' then
      if v_has_curated then
        execute $q$
          select array_agg(s.aid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last, s.aid desc)
          from (
            select a.id as aid,
                   case when $3 = 'default' then -min(i.rank)::bigint
                        when $3 = 'popular' then max(a.popularity)::bigint
                        when $3 = 'top_rated' then max(a.average_score)::bigint
                        else max(coalesce(a.start_date_year, a.season_year))::bigint end as k1,
                   case when $3 = 'newest' then max(a.start_date_month)::bigint else null end as k2,
                   case when $3 = 'newest' then max(a.start_date_day)::bigint else null end as k3
            from public.curated_rail_items i
            join public.anime a on a.anilist_id = i.anilist_id
            where i.rail_id = $1 and i.media_type = 'ANIME'
              and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
              and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
              and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
              and (($2::text is null and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
                   or upper(coalesce(a.format, '')) = $2)
              and ($4::text is null
                   or ($4 = 'short' and a.episodes between 1 and 13)
                   or ($4 = 'standard' and a.episodes between 14 and 50)
                   or ($4 = 'long' and a.episodes >= 51))
              and ($5::text is null or a.status = $5)
              and ($7::uuid is null or not exists (
                    select 1 from public.taste_signal_events e
                    where e.user_id = $7 and e.media_type = 'ANIME' and e.media_id = a.id
                      and e.event_type in ('deck_skip', 'deck_known')
                      and e.created_at > now() - interval '365 days'))
              and (not $8 or not exists (
                    select 1 from public.anime_user_lists ul
                    where ul.user_id = $7::text and ul.anime_id = a.id))
            group by a.id
            order by 2 desc nulls last, 3 desc nulls last, 4 desc nulls last, 1 desc
            limit $6
          ) s
        $q$ into v_ids using v_curated_rail, v_format, v_sort, v_length, v_status, v_pool, v_uid, v_hide_owned;
      else
        select array_agg(s.aid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last,
                                        s.k4 desc nulls last, s.k5 desc nulls last, s.k6 desc nulls last,
                                        s.k7 desc nulls last, s.k8 desc nulls last, s.pop desc, s.aid desc)
          into v_ids
        from (
          select a.id as aid,
                 -- the section's own order (default)
                 case when v_sort = 'default' and v_section = 'essentials' then coalesce(a.favourites, 0) end as k1,
                 case when v_sort = 'default' and v_section in ('essentials', 'classics', 'top_rated') then coalesce(a.average_score, 0) end as k2,
                 case when v_sort = 'default' and v_section = 'trending' then coalesce(a.trending, 0) end as k3,
                 case when v_sort = 'default' and v_section = 'newly_added' then a.created_at end as k4,
                 -- chosen sorts
                 case when v_sort = 'top_rated' then a.average_score end as k5,
                 case when v_sort = 'newest' then coalesce(a.start_date_year, a.season_year) end as k6,
                 case when v_sort = 'newest' then a.start_date_month end as k7,
                 case when v_sort = 'newest' then a.start_date_day end as k8,
                 -- popularity: the 'popular' sort and every section's tiebreak
                 coalesce(a.popularity, 0) as pop
          from public.anime a
          where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
            and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
            and ((v_format is null and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
                 or upper(coalesce(a.format, '')) = v_format)
            and (v_length is null
                 or (v_length = 'short' and a.episodes between 1 and 13)
                 or (v_length = 'standard' and a.episodes between 14 and 50)
                 or (v_length = 'long' and a.episodes >= 51))
            and (v_status is null or a.status = v_status)
            and case v_section
                  when 'essentials' then coalesce(a.average_score, 0) >= 85
                  when 'classics' then coalesce(a.season_year, a.start_date_year, 9999) < 2015
                                       and coalesce(a.average_score, 0) >= 80
                  when 'new_to_you' then coalesce(a.average_score, 0) >= 80
                  when 'trending' then coalesce(a.trending, 0) > 0
                  when 'top_rated' then coalesce(a.average_score, 0) >= 80
                  when 'newly_added' then true
                  when 'current_season' then a.season = v_season and a.season_year = v_year
                  when 'airing_today' then a.status = 'RELEASING' and a.next_airing_at >= v_day_start
                                           and a.next_airing_at < v_day_end
                  else false
                end
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'ANIME' and e.media_id = a.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (not v_hide_owned or not exists (
                  select 1 from public.anime_user_lists ul
                  where ul.user_id = v_uid_text and ul.anime_id = a.id))
          order by k1 desc nulls last, k2 desc nulls last, k3 desc nulls last, k4 desc nulls last,
                   k5 desc nulls last, k6 desc nulls last, k7 desc nulls last, k8 desc nulls last,
                   pop desc, aid desc
          limit v_pool
        ) s;
      end if;
    else
      if v_has_curated then
        execute $q$
          select array_agg(s.mid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last, s.mid desc)
          from (
            select m.id as mid,
                   case when $3 = 'default' then -min(i.rank)::bigint
                        when $3 = 'popular' then max(m.popularity)::bigint
                        when $3 = 'top_rated' then max(m.average_score)::bigint
                        else max(m.start_date_year)::bigint end as k1,
                   case when $3 = 'newest' then max(m.start_date_month)::bigint else null end as k2,
                   case when $3 = 'newest' then max(m.start_date_day)::bigint else null end as k3
            from public.curated_rail_items i
            join public.manga m on m.anilist_id = i.anilist_id
            where i.rail_id = $1 and i.media_type = 'MANGA'
              and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
              and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
              and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
              and ($2::text is null or upper(coalesce(m.format, '')) = $2)
              and ($4::text is null
                   or ($4 = 'short' and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5)))
                   or ($4 = 'standard' and m.chapters between 51 and 150)
                   or ($4 = 'long' and m.chapters >= 151))
              and ($5::text is null or m.status = $5)
              and ($7::uuid is null or not exists (
                    select 1 from public.taste_signal_events e
                    where e.user_id = $7 and e.media_type = 'MANGA' and e.media_id = m.id
                      and e.event_type in ('deck_skip', 'deck_known')
                      and e.created_at > now() - interval '365 days'))
              and (not $8 or not exists (
                    select 1 from public.manga_user_lists ul
                    where ul.user_id = $7::text and ul.manga_id = m.id))
            group by m.id
            order by 2 desc nulls last, 3 desc nulls last, 4 desc nulls last, 1 desc
            limit $6
          ) s
        $q$ into v_ids using v_curated_rail, v_format, v_sort, v_length, v_status, v_pool, v_uid, v_hide_owned;
      else
        select array_agg(s.mid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last,
                                        s.k4 desc nulls last, s.k5 desc nulls last, s.k6 desc nulls last,
                                        s.k7 desc nulls last, s.k8 desc nulls last, s.pop desc, s.mid desc)
          into v_ids
        from (
          select m.id as mid,
                 case when v_sort = 'default' and v_section = 'essentials' then coalesce(m.favourites, 0) end as k1,
                 case when v_sort = 'default' and v_section in ('essentials', 'classics', 'top_rated') then coalesce(m.average_score, 0) end as k2,
                 case when v_sort = 'default' and v_section = 'trending' then coalesce(m.trending, 0) end as k3,
                 case when v_sort = 'default' and v_section = 'newly_added' then m.created_at end as k4,
                 case when v_sort = 'top_rated' then m.average_score end as k5,
                 case when v_sort = 'newest' then m.start_date_year end as k6,
                 case when v_sort = 'newest' then m.start_date_month end as k7,
                 case when v_sort = 'newest' then m.start_date_day end as k8,
                 coalesce(m.popularity, 0) as pop
          from public.manga m
          where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
            and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
            and (v_format is null or upper(coalesce(m.format, '')) = v_format)
            and (v_length is null
                 or (v_length = 'short' and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5)))
                 or (v_length = 'standard' and m.chapters between 51 and 150)
                 or (v_length = 'long' and m.chapters >= 151))
            and (v_status is null or m.status = v_status)
            and case v_section
                  when 'essentials' then coalesce(m.average_score, 0) >= 85
                  when 'classics' then coalesce(m.start_date_year, 9999) < 2015 and coalesce(m.average_score, 0) >= 80
                  when 'new_to_you' then coalesce(m.average_score, 0) >= 80
                  when 'trending' then coalesce(m.trending, 0) > 0
                  when 'top_rated' then coalesce(m.average_score, 0) >= 80
                  when 'newly_added' then true
                  else false
                end
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'MANGA' and e.media_id = m.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (not v_hide_owned or not exists (
                  select 1 from public.manga_user_lists ul
                  where ul.user_id = v_uid_text and ul.manga_id = m.id))
          order by k1 desc nulls last, k2 desc nulls last, k3 desc nulls last, k4 desc nulls last,
                   k5 desc nulls last, k6 desc nulls last, k7 desc nulls last, k8 desc nulls last,
                   pop desc, mid desc
          limit v_pool
        ) s;
      end if;
    end if;

    -- Enough distinct franchises for this page (+1, so a full page is never mistaken for the end),
    -- or the source is exhausted, or the cap is reached: stop growing.
    v_got := coalesce(cardinality(v_ids), 0);
    exit when v_got < v_pool or v_pool >= v_pool_cap;
    select count(distinct coalesce(fc.component_label, x.mid)) into v_distinct
    from unnest(v_ids) as x(mid)
    left join public.media_franchise_components fc on fc.media_type = v_type and fc.media_id = x.mid;
    exit when v_distinct > v_offset + v_limit;
    v_pool := least(v_pool_cap, v_pool * 2);
  end loop;

  return query
  select * from public._discover_page_v1(
    v_uid, v_type, coalesce(v_ids, '{}'::integer[]), v_section = 'new_to_you', v_limit, v_offset
  );
end;
$$;

-- discover_mood_v1: latest definition 20261104100100_discover_mood_perf_v1.sql; 8 anime/manga/matview references, 4 visibility predicates added
create or replace function public.discover_mood_v1(
  p_mood text,
  p_media_type text default 'ANIME',
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_uid_text text := auth.uid()::text;
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_mood text := lower(btrim(coalesce(p_mood, '')));
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(440, greatest(0, coalesce(p_offset, 0)));
  v_pool integer;
  v_pool_cap constant integer := 4000;
  v_got integer;
  v_distinct integer;
  v_threshold real := 0.25;
  v_cozy text[] := array['slice-of-life-iyashikei', 'food-craft', 'family-generations'];
  v_not_cozy text[] := array['horror-dread', 'tragedy-tearjerker', 'psychological-thriller'];
  v_intense text[] := array['psychological-thriller', 'horror-dread', 'dark-fantasy', 'war-military',
                            'crime-underworld', 'mind-game-strategy'];
  v_realms boolean := to_regclass('public.media_realm_membership') is not null;
  v_seed integer;
  v_seed_title text;
  v_ids integer[];
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if v_mood not in ('short', 'cozy', 'intense', 'like_last_loved') then
    raise exception 'INVALID_MOOD: p_mood must be short, cozy, intense or like_last_loved';
  end if;
  v_pool := least(v_pool_cap, (v_offset + v_limit) * 2 + 40);

  if v_mood = 'like_last_loved' then
    -- like_last_loved: the caller's seed; signed out or no seed answers no rows.
    if v_uid is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select ul.anime_id into v_seed
      from public.anime_user_lists ul
      where ul.user_id = v_uid_text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.anime_id desc
      limit 1;
    else
      select ul.manga_id into v_seed
      from public.manga_user_lists ul
      where ul.user_id = v_uid_text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.manga_id desc
      limit 1;
    end if;
    if v_seed is null then
      select e.media_id into v_seed
      from public.taste_signal_events e
      where e.user_id = v_uid and e.media_type = v_type and e.event_type = 'deck_love'
      order by e.created_at desc, e.id desc
      limit 1;
    end if;
    if v_seed is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select coalesce(a.title_english, a.title_romaji, a.title_native) into v_seed_title
      from public.anime a where a.id = v_seed;
    else
      select coalesce(m.title_english, m.title_romaji, m.title_native) into v_seed_title
      from public.manga m where m.id = v_seed;
    end if;
    select array_agg(r.media_id order by r.ord) into v_ids
    from public.recommend_ids_similar_to_seeds(v_type, array[v_seed], 60, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    where r.media_id <> v_seed;

    return query
    select * from public._discover_page_v1(
      v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset, v_seed, v_seed_title
    );
    return;
  end if;

  loop
    if v_mood = 'short' then
      if v_type = 'ANIME' then
        select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
        from (
          select a.id as aid, coalesce(a.popularity, 0) as pop
          from public.anime a
          where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
            and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
            and coalesce(a.average_score, 0) >= 70
            and ((upper(coalesce(a.format, '')) in ('TV', 'ONA', 'OVA') and a.status = 'FINISHED'
                  and a.episodes between 1 and 13)
                 or (upper(coalesce(a.format, '')) = 'MOVIE' and a.duration between 1 and 25))
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'ANIME' and e.media_id = a.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (v_uid is null or not exists (
                  select 1 from public.anime_user_lists ul
                  where ul.user_id = v_uid_text and ul.anime_id = a.id))
          order by pop desc, aid desc
          limit v_pool
        ) s;
      else
        select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
        from (
          select m.id as mid, coalesce(m.popularity, 0) as pop
          from public.manga m
          where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
            and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
            and coalesce(m.average_score, 0) >= 70
            and m.status = 'FINISHED'
            and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5))
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'MANGA' and e.media_id = m.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (v_uid is null or not exists (
                  select 1 from public.manga_user_lists ul
                  where ul.user_id = v_uid_text and ul.manga_id = m.id))
          order by pop desc, mid desc
          limit v_pool
        ) s;
      end if;
    elsif v_realms then
      execute $q$
        with cand as (
          select r.media_id as mid, sum(r.weight)::real as w
          from public.media_realm_membership r
          where r.media_type = $1 and r.realm = any($2) and r.weight >= $4
          group by r.media_id
        ), excl as (
          select distinct x.media_id as mid
          from public.media_realm_membership x
          where x.media_type = $1 and x.realm = any($3) and x.weight >= $4
        )
        select array_agg(s.mid order by s.w desc, s.pop desc, s.mid desc)
        from (
          select c.mid, c.w, coalesce(t.pop, 0) as pop
          from cand c
          join (
            select a.id, a.popularity as pop, a.average_score as sc, a.genres as g, a.is_adult as adult, a.format as f,
                   coalesce(a.cover_image_large, a.cover_image_medium, '') as cover
            from public.anime a where $1 = 'ANIME'
            union all
            select m.id, m.popularity, m.average_score, m.genres, m.is_adult, m.format,
                   coalesce(m.cover_image_large, m.cover_image_medium, '')
            from public.manga m where $1 = 'MANGA'
          ) t on t.id = c.mid
          where coalesce(t.adult, false) = false
            and not (coalesce(t.g, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(t.cover), '') is not null
            and coalesce(t.sc, 0) >= 65
            and ($1 = 'MANGA' or upper(coalesce(t.f, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
            and ($5 = false or not ('Horror' = any(coalesce(t.g, '{}'::text[]))))
            and not exists (select 1 from excl e where e.mid = c.mid)
            and ($7::uuid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = $7 and e.media_type = $1 and e.media_id = c.mid
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and ($7::uuid is null or not exists (
                  select 1 from public.anime_user_lists ul
                  where $1 = 'ANIME' and ul.user_id = $7::text and ul.anime_id = c.mid))
            and ($7::uuid is null or not exists (
                  select 1 from public.manga_user_lists ul
                  where $1 = 'MANGA' and ul.user_id = $7::text and ul.manga_id = c.mid))
          order by 2 desc, 3 desc, 1 desc
          limit $6
        ) s
      $q$ into v_ids
      using v_type,
            case when v_mood = 'cozy' then v_cozy else v_intense end,
            case when v_mood = 'cozy' then v_not_cozy else array[]::text[] end,
            v_threshold, v_mood = 'cozy', v_pool, v_uid;
    elsif v_type = 'ANIME' then
      select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
      from (
        select a.id as aid, coalesce(a.popularity, 0) as pop
        from public.anime a
        where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
          and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
          and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
          and coalesce(a.average_score, 0) >= 65
          and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(a.genres, '{}'::text[]))
                        and not (coalesce(a.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(a.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
          and (v_uid is null or not exists (
                select 1 from public.taste_signal_events e
                where e.user_id = v_uid and e.media_type = 'ANIME' and e.media_id = a.id
                  and e.event_type in ('deck_skip', 'deck_known')
                  and e.created_at > now() - interval '365 days'))
          and (v_uid is null or not exists (
                select 1 from public.anime_user_lists ul
                where ul.user_id = v_uid_text and ul.anime_id = a.id))
        order by pop desc, aid desc
        limit v_pool
      ) s;
    else
      select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
      from (
        select m.id as mid, coalesce(m.popularity, 0) as pop
        from public.manga m
        where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
          and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
          and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
          and coalesce(m.average_score, 0) >= 65
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(m.genres, '{}'::text[]))
                        and not (coalesce(m.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(m.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
          and (v_uid is null or not exists (
                select 1 from public.taste_signal_events e
                where e.user_id = v_uid and e.media_type = 'MANGA' and e.media_id = m.id
                  and e.event_type in ('deck_skip', 'deck_known')
                  and e.created_at > now() - interval '365 days'))
          and (v_uid is null or not exists (
                select 1 from public.manga_user_lists ul
                where ul.user_id = v_uid_text and ul.manga_id = m.id))
        order by pop desc, mid desc
        limit v_pool
      ) s;
    end if;

    v_got := coalesce(cardinality(v_ids), 0);
    exit when v_got < v_pool or v_pool >= v_pool_cap;
    select count(distinct coalesce(fc.component_label, x.mid)) into v_distinct
    from unnest(v_ids) as x(mid)
    left join public.media_franchise_components fc on fc.media_type = v_type and fc.media_id = x.mid;
    exit when v_distinct > v_offset + v_limit;
    v_pool := least(v_pool_cap, v_pool * 2);
  end loop;

  return query
  select * from public._discover_page_v1(
    v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset
  );
end;
$$;

-- _discover_page_v1: latest definition 20261104100000_discover_usability_v1.sql; 4 anime/manga/matview references, 2 visibility predicates added
create or replace function public._discover_page_v1(
  p_uid uuid,
  p_media_type text,
  p_ids integer[],
  p_hide_owned boolean,
  p_limit integer,
  p_offset integer,
  p_reason_media_id integer default null,
  p_reason_title text default null
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid_text text := p_uid::text;
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(500, greatest(0, coalesce(p_offset, 0)));
begin
  if p_media_type = 'ANIME' then
    return query
    with ordered as (
      select x.mid, min(x.ord) as ord
      from unnest(coalesce(p_ids, '{}'::integer[])) with ordinality as x(mid, ord)
      where x.mid is not null
      group by x.mid
    ),
    eligible as (
      select o.ord, a.id as aid, coalesce(fc.component_label, a.id) as fid, ul.list_type as lt
      from ordered o
      join public.anime a on a.id = o.mid
      left join public.media_franchise_components fc
        on fc.media_type = 'ANIME' and fc.media_id = a.id
      left join public.anime_user_lists ul
        on p_uid is not null and ul.user_id = v_uid_text and ul.anime_id = a.id
      where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
        and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
        and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
        and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
        and (not coalesce(p_hide_owned, false) or ul.anime_id is null)
        and not exists (
          select 1 from public.taste_signal_events e
          where p_uid is not null
            and e.user_id = p_uid
            and e.media_type = 'ANIME'
            and e.media_id = a.id
            and e.event_type in ('deck_skip', 'deck_known')
            and e.created_at > now() - interval '365 days'
        )
    ),
    deduped as (
      select distinct on (e.fid) e.ord, e.aid, e.fid, e.lt
      from eligible e
      order by e.fid, e.ord
    ),
    ranked as (
      select d.*, (row_number() over (order by d.ord))::integer as rn
      from deduped d
    )
    select 'ANIME'::text, r.rn, a.id,
           a.title_english, a.title_romaji, a.title_native,
           a.cover_image_large, a.cover_image_medium, a.banner_image,
           a.format, a.status, a.episodes, null::integer, null::integer,
           a.season_year, a.start_date_year,
           a.average_score, a.popularity, a.trending, a.favourites,
           a.genres, a.created_at,
           r.fid, r.lt,
           p_reason_media_id, p_reason_title
    from ranked r
    join public.anime a on a.id = r.aid
    where r.rn > v_offset
    order by r.rn
    limit v_limit;
  elsif p_media_type = 'MANGA' then
    return query
    with ordered as (
      select x.mid, min(x.ord) as ord
      from unnest(coalesce(p_ids, '{}'::integer[])) with ordinality as x(mid, ord)
      where x.mid is not null
      group by x.mid
    ),
    eligible as (
      select o.ord, m.id as mid2, coalesce(fc.component_label, m.id) as fid, ul.list_type as lt
      from ordered o
      join public.manga m on m.id = o.mid
      left join public.media_franchise_components fc
        on fc.media_type = 'MANGA' and fc.media_id = m.id
      left join public.manga_user_lists ul
        on p_uid is not null and ul.user_id = v_uid_text and ul.manga_id = m.id
      where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
        and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
        and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
        and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
        and (not coalesce(p_hide_owned, false) or ul.manga_id is null)
        and not exists (
          select 1 from public.taste_signal_events e
          where p_uid is not null
            and e.user_id = p_uid
            and e.media_type = 'MANGA'
            and e.media_id = m.id
            and e.event_type in ('deck_skip', 'deck_known')
            and e.created_at > now() - interval '365 days'
        )
    ),
    deduped as (
      select distinct on (e.fid) e.ord, e.mid2, e.fid, e.lt
      from eligible e
      order by e.fid, e.ord
    ),
    ranked as (
      select d.*, (row_number() over (order by d.ord))::integer as rn
      from deduped d
    )
    select 'MANGA'::text, r.rn, m.id,
           m.title_english, m.title_romaji, m.title_native,
           m.cover_image_large, m.cover_image_medium, m.banner_image,
           m.format, m.status, null::integer, m.chapters, m.volumes,
           null::integer, m.start_date_year,
           m.average_score, m.popularity, m.trending, m.favourites,
           m.genres, m.created_at,
           r.fid, r.lt,
           p_reason_media_id, p_reason_title
    from ranked r
    join public.manga m on m.id = r.mid2
    where r.rn > v_offset
    order by r.rn
    limit v_limit;
  else
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
