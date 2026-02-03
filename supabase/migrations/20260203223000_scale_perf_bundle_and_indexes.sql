-- Scale/perf improvements:
-- - Single-call Discover bundle RPC (reduces client fan-out)
-- - Key indexes for browse/search filters & ordering
-- - Keyset pagination RPCs for browse (avoid OFFSET cost)

begin;

-- 1) Indexes for common filters/sorts
-- Genres are queried via `contains(genres, ['Action'])`, so a GIN index is critical.
create index if not exists idx_anime_genres_gin on public.anime using gin (genres);
create index if not exists idx_manga_genres_gin on public.manga using gin (genres);

-- Sort columns used heavily by browse/discover.
create index if not exists idx_anime_popularity_id on public.anime (popularity desc nulls last, id desc);
create index if not exists idx_anime_trending_id on public.anime (trending desc nulls last, id desc);
create index if not exists idx_anime_score_id on public.anime (average_score desc nulls last, id desc);
create index if not exists idx_anime_created_id on public.anime (created_at desc, id desc);
create index if not exists idx_anime_status_popularity_id on public.anime (status, popularity desc nulls last, id desc);
create index if not exists idx_anime_season_year_popularity_id on public.anime (season, season_year, popularity desc nulls last, id desc);
create index if not exists idx_anime_next_airing_at on public.anime (next_airing_at);

create index if not exists idx_manga_popularity_id on public.manga (popularity desc nulls last, id desc);
create index if not exists idx_manga_trending_id on public.manga (trending desc nulls last, id desc);
create index if not exists idx_manga_score_id on public.manga (average_score desc nulls last, id desc);
create index if not exists idx_manga_created_id on public.manga (created_at desc, id desc);

-- Text search (used by app search). Expression GIN index avoids table scans.
-- NOTE: uses the "simple" config since title fields are mostly proper nouns.
create index if not exists idx_anime_search_tsv on public.anime using gin (
  to_tsvector(
    'simple',
    coalesce(title_english, '') || ' ' ||
    coalesce(title_romaji, '') || ' ' ||
    coalesce(description_normalized, '')
  )
);
create index if not exists idx_manga_search_tsv on public.manga using gin (
  to_tsvector(
    'simple',
    coalesce(title_english, '') || ' ' ||
    coalesce(title_romaji, '') || ' ' ||
    coalesce(description_normalized, '')
  )
);

-- 2) Helper for season derivation (server-side, so clients don't hardcode logic).
create or replace function public.current_season_name(p_at timestamptz default now())
returns text
language sql
immutable
as $$
  select case
    when extract(month from p_at)::int in (12, 1, 2) then 'WINTER'
    when extract(month from p_at)::int in (3, 4, 5) then 'SPRING'
    when extract(month from p_at)::int in (6, 7, 8) then 'SUMMER'
    else 'FALL'
  end;
$$;

-- 3) Discover bundle (single call).
-- Returns minimal card fields for rails; details are fetched by id when needed.
create or replace function public.discover_bundle(
  p_limit integer default 30,
  p_hours integer default 24
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select auth.uid()::text as user_id
  ),
  params as (
    select
      greatest(1, least(coalesce(p_limit, 30), 60))::int as lim,
      greatest(1, least(coalesce(p_hours, 24), 168))::int as hrs,
      public.current_season_name(now()) as season,
      extract(year from now())::int as year
  ),
  anime_essentials as (
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
      and coalesce(a.average_score, 0) >= 85
    order by coalesce(a.favourites, 0) desc, coalesce(a.average_score, 0) desc, coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_classics as (
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
      and coalesce(a.season_year, a.start_date_year, 9999) < 2015
      and coalesce(a.average_score, 0) >= 80
    order by coalesce(a.average_score, 0) desc, coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),
  anime_new_to_you as (
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
      and (select user_id from me) is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )
      and coalesce(a.average_score, 0) >= 80
    order by coalesce(a.average_score, 0) desc, coalesce(a.popularity, 0) desc, a.id desc
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
    from public.mv_anime_newly_added a, params p
    where coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    order by a.created_at desc, a.id desc
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
    where a.next_airing_at is not null
      and a.next_airing_at > now()
      and a.next_airing_at <= now() + make_interval(hours => (select hrs from params))
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    order by a.next_airing_at asc, a.id desc
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
      and a.status = 'RELEASING'
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    order by coalesce(a.popularity, 0) desc, a.id desc
    limit (select lim from params)
  ),

  manga_essentials as (
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
      and coalesce(m.average_score, 0) >= 85
    order by coalesce(m.favourites, 0) desc, coalesce(m.average_score, 0) desc, coalesce(m.popularity, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_classics as (
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
      and coalesce(m.start_date_year, 9999) < 2015
      and coalesce(m.average_score, 0) >= 80
    order by coalesce(m.average_score, 0) desc, coalesce(m.popularity, 0) desc, m.id desc
    limit (select lim from params)
  ),
  manga_new_to_you as (
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
    order by coalesce(m.average_score, 0) desc, coalesce(m.popularity, 0) desc, m.id desc
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
    from public.mv_manga_newly_added m, params p
    where coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by m.created_at desc, m.id desc
    limit (select lim from params)
  )
  select jsonb_build_object(
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
  );
$$;

grant execute on function public.discover_bundle(integer, integer) to anon, authenticated;

-- 4) Browse keyset pagination RPCs (cards).
-- This keeps the app fast at deeper pages and protects Postgres from OFFSET scans.
create or replace function public.browse_anime_page(
  p_genre text default null,
  p_status text default null,
  p_min_episodes integer default null,
  p_max_episodes integer default null,
  p_sort text default 'popular', -- popular|trending|topRated|newlyAdded
  p_cursor_int integer default null,
  p_cursor_ts timestamptz default null,
  p_cursor_id integer default null,
  p_limit integer default 60
)
returns table (
  id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_large text,
  cover_image_medium text,
  banner_image text,
  format text,
  status text,
  episode_count integer,
  season_year integer,
  start_date_year integer,
  average_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      greatest(1, least(coalesce(p_limit, 60), 120))::int as lim,
      coalesce(nullif(p_sort,''), 'popular') as sort
  ),
  base as (
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
      a.created_at,
      case
        when (select sort from params) = 'trending' then coalesce(a.trending, 0)
        when (select sort from params) = 'topRated' then coalesce(a.average_score, 0)
        else coalesce(a.popularity, 0)
      end as sort_int
    from public.anime a
    where coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (p_genre is null or p_genre = '' or a.genres @> array[p_genre]::text[])
      and (p_status is null or p_status = '' or a.status = p_status)
      and (p_min_episodes is null or coalesce(a.episodes, 0) >= p_min_episodes)
      and (p_max_episodes is null or coalesce(a.episodes, 0) <= p_max_episodes)
  )
  select
    b.id,
    b.title_english, b.title_romaji, b.title_native,
    b.cover_image_large, b.cover_image_medium, b.banner_image,
    b.format, b.status,
    b.episode_count,
    b.season_year,
    b.start_date_year,
    b.average_score,
    b.popularity,
    b.trending,
    b.favourites,
    b.genres
  from base b, params p
  where
    case
      when p.sort = 'newlyAdded' then
        (
          p_cursor_ts is null
          or (b.created_at < p_cursor_ts)
          or (b.created_at = p_cursor_ts and b.id < p_cursor_id)
        )
      else
        (
          p_cursor_int is null
          or (b.sort_int < p_cursor_int)
          or (b.sort_int = p_cursor_int and b.id < p_cursor_id)
        )
    end
  order by
    case when p.sort = 'newlyAdded' then b.created_at else null end desc nulls last,
    case when p.sort = 'newlyAdded' then null else b.sort_int end desc,
    b.id desc
  limit (select lim from params);
$$;

-- NOTE: manga browse cursor uses chapters filter instead of episodes.
create or replace function public.browse_manga_page(
  p_genre text default null,
  p_status text default null,
  p_min_chapters integer default null,
  p_max_chapters integer default null,
  p_sort text default 'popular', -- popular|trending|topRated|newlyAdded
  p_cursor_int integer default null,
  p_cursor_ts timestamptz default null,
  p_cursor_id integer default null,
  p_limit integer default 60
)
returns table (
  id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_large text,
  cover_image_medium text,
  format text,
  status text,
  chapter_count integer,
  start_date_year integer,
  average_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      greatest(1, least(coalesce(p_limit, 60), 120))::int as lim,
      coalesce(nullif(p_sort,''), 'popular') as sort
  ),
  base as (
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
      m.created_at,
      case
        when (select sort from params) = 'trending' then coalesce(m.trending, 0)
        when (select sort from params) = 'topRated' then coalesce(m.average_score, 0)
        else coalesce(m.popularity, 0)
      end as sort_int
    from public.manga m
    where coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (p_genre is null or p_genre = '' or m.genres @> array[p_genre]::text[])
      and (p_status is null or p_status = '' or m.status = p_status)
      and (p_min_chapters is null or coalesce(m.chapters, 0) >= p_min_chapters)
      and (p_max_chapters is null or coalesce(m.chapters, 0) <= p_max_chapters)
  )
  select
    b.id,
    b.title_english, b.title_romaji, b.title_native,
    b.cover_image_large, b.cover_image_medium,
    b.format, b.status,
    b.chapter_count,
    b.start_date_year,
    b.average_score,
    b.popularity,
    b.trending,
    b.favourites,
    b.genres
  from base b, params p
  where
    case
      when p.sort = 'newlyAdded' then
        (
          p_cursor_ts is null
          or (b.created_at < p_cursor_ts)
          or (b.created_at = p_cursor_ts and b.id < p_cursor_id)
        )
      else
        (
          p_cursor_int is null
          or (b.sort_int < p_cursor_int)
          or (b.sort_int = p_cursor_int and b.id < p_cursor_id)
        )
    end
  order by
    case when p.sort = 'newlyAdded' then null else b.sort_int end desc,
    b.id desc
  limit (select lim from params);
$$;

grant execute on function public.browse_anime_page(text, text, integer, integer, text, integer, timestamptz, integer, integer) to anon, authenticated;
grant execute on function public.browse_manga_page(text, text, integer, integer, text, integer, timestamptz, integer, integer) to anon, authenticated;

commit;
