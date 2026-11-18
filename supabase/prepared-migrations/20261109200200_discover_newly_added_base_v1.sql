-- Prepared 2026-11-09 (docs/plans/2026-11-09-backend-latency-plan.md step 1c).
-- PARKED 2026-11-18, not applied. No benefit while catalogue imports are off (no new titles since
-- 2026-11-10); the matview drop is folded into catalogue Task 15d. Regenerate from the live
-- discover_bundle before any apply (15d changes it).
--
-- "Newly added" Discover rails read the base tables instead of the daily snapshot matviews
-- mv_anime_newly_added / mv_manga_newly_added (full, unfiltered copies of anime / manga).
-- Owner-approved visible change: the rail shows newly ingested titles immediately instead of
-- after the 01:30 refresh. Filters, limit and row shape are unchanged.
--
-- Order: created_at is NOT NULL on anime and manga (verified live read-only 2026-11-09 and
-- asserted by the test), so `created_at desc nulls last, id desc` returns exactly the rows of
-- the former `created_at desc, id desc` and is served by the existing live indexes
-- idx_anime_load_created_v1 / idx_manga_load_created_v1 (20261109001251). No new index.
--
-- discover_bundle is replaced from the LIVE body (read-only pg_get_functiondef 2026-11-09; it is
-- identical to 20260326234000's body; live adds search_path extensions + jit off, kept here).
-- Only the two newly-added CTEs change. CREATE OR REPLACE keeps the existing ACL.
-- refresh_discover_matviews_v1() is redefined for the four remaining matviews (the old body
-- already skipped missing ones; this keeps its report honest). The two matviews are dropped
-- WITHOUT cascade behind a guard that refuses when any other function body or cron command still
-- names them (views that depend on them make DROP fail, no CASCADE). App builds before the
-- 2026-10-31 capability architecture read them through PostgREST (retired SupabaseService
-- fetchNewlyAdded*; anon / authenticated hold SELECT, pg_class.relacl 2026-11-10). Every
-- TestFlight build from 20 onward reads discover_bundle only; an older, still-installed TestFlight
-- build loses its newly-added list after this drop.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

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
      and coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
      and coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
    where coalesce(a.is_adult, false) = false
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
      and coalesce(a.is_adult, false) = false
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
      and coalesce(a.is_adult, false) = false
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
      and coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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
      and coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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
    where coalesce(m.is_adult, false) = false
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

create or replace function public.refresh_discover_matviews_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v text;
  v_done text[] := '{}';
begin
  foreach v in array array['mv_anime_trending', 'mv_anime_top_rated',
                           'mv_manga_trending', 'mv_manga_top_rated'] loop
    if to_regclass('public.' || v) is null then
      continue;
    end if;
    if (select m.ispopulated from pg_matviews m where m.schemaname = 'public' and m.matviewname = v) then
      execute format('refresh materialized view concurrently public.%I', v);
    else
      execute format('refresh materialized view public.%I', v);  -- first fill cannot be concurrent
    end if;
    v_done := v_done || v;
  end loop;
  return jsonb_build_object('refreshed', to_jsonb(v_done));
end;
$$;
revoke all on function public.refresh_discover_matviews_v1() from public, anon, authenticated;
grant execute on function public.refresh_discover_matviews_v1() to service_role;

do $guard$
declare
  v_users text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_users
  from pg_proc p
  where p.prosrc ~ 'mv_(anime|manga)_newly_added'
    and p.oid not in ('public.discover_bundle(integer,integer)'::regprocedure,
                      'public.refresh_discover_matviews_v1()'::regprocedure);
  if v_users is not null then
    raise exception 'newly-added matviews are still named by: %', v_users;
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select string_agg(jobid::text || ' ' || jobname, ', ') from cron.job
               where command ~ 'mv_(anime|manga)_newly_added'$q$ into v_users;
    if v_users is not null then
      raise exception 'newly-added matviews are still named by cron jobs: %', v_users;
    end if;
  end if;
end;
$guard$;

drop materialized view if exists public.mv_anime_newly_added;
drop materialized view if exists public.mv_manga_newly_added;

notify pgrst, 'reload schema';
commit;
