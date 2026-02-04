begin;

-- Improve Search performance:
-- - Trigram index for partial title matches (fast incremental typing)
-- - Keyset-paged RPCs returning lightweight cards with a stable rank cursor

create extension if not exists pg_trgm;

-- Trigram indexes for partial matching on titles (english/romaji/native combined).
create index if not exists idx_anime_title_trgm on public.anime
  using gin (lower(coalesce(title_english,'') || ' ' || coalesce(title_romaji,'') || ' ' || coalesce(title_native,'')) gin_trgm_ops);
create index if not exists idx_manga_title_trgm on public.manga
  using gin (lower(coalesce(title_english,'') || ' ' || coalesce(title_romaji,'') || ' ' || coalesce(title_native,'')) gin_trgm_ops);

-- Search RPCs
drop function if exists public.search_anime_page(
  text, integer, double precision, integer, integer, boolean, boolean, boolean, boolean, boolean, text, integer
);
create function public.search_anime_page(
  p_query text,
  p_limit integer default 30,
  p_cursor_rank double precision default null,
  p_cursor_popularity integer default null,
  p_cursor_id integer default null,
  p_trending boolean default false,
  p_new_season boolean default false,
  p_classics boolean default false,
  p_hidden_gems boolean default false,
  p_airing_only boolean default false,
  p_season text default null,
  p_season_year integer default null
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
  genres text[],
  created_at timestamptz,
  rank double precision
)
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select
      nullif(trim(coalesce(p_query, '')), '') as raw,
      nullif(lower(trim(coalesce(p_query, ''))), '') as norm,
      extract(year from now())::int as this_year
  ),
  params as (
    select greatest(1, least(coalesce(p_limit, 30), 50))::int as lim
  ),
  ts as (
    select
      case
        when (select raw from q) is not null and length((select raw from q)) >= 3
          then websearch_to_tsquery('simple', (select raw from q))
        else null
      end as tsq
  ),
  base as (
    select
      a.id,
      a.title_english,
      a.title_romaji,
      a.title_native,
      a.cover_image_large,
      a.cover_image_medium,
      a.banner_image,
      a.format,
      a.status,
      a.episodes as episode_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      a.created_at,
      greatest(
        case
          when (select tsq from ts) is not null then
            ts_rank_cd(
              to_tsvector(
                'simple',
                coalesce(a.title_english,'') || ' ' ||
                coalesce(a.title_romaji,'') || ' ' ||
                coalesce(a.description_normalized,'')
              ),
              (select tsq from ts)
            )
          else 0
        end,
        case
          when (select norm from q) is not null then
            similarity(
              lower(coalesce(a.title_english,'') || ' ' || coalesce(a.title_romaji,'') || ' ' || coalesce(a.title_native,'')),
              (select norm from q)
            )
          else 0
        end
      ) as rank
    from public.anime a
    where
      -- Safety defaults: hide adult/hentai/ecchi by default (can be relaxed later via profile policy).
      a.is_adult is not true
      and not (a.genres @> array['Hentai']::text[])
      and not (a.genres @> array['Ecchi']::text[])
      and (
        -- Filters-only mode (no query): return top items by popularity.
        (select norm from q) is null
        or (
          ((select tsq from ts) is not null and
            to_tsvector(
              'simple',
              coalesce(a.title_english,'') || ' ' ||
              coalesce(a.title_romaji,'') || ' ' ||
              coalesce(a.description_normalized,'')
            ) @@ (select tsq from ts))
          or similarity(
              lower(coalesce(a.title_english,'') || ' ' || coalesce(a.title_romaji,'') || ' ' || coalesce(a.title_native,'')),
              (select norm from q)
            ) > 0.12
          or lower(coalesce(a.title_english,'') || ' ' || coalesce(a.title_romaji,'') || ' ' || coalesce(a.title_native,'')) like ('%' || (select norm from q) || '%')
        )
      )
      and (not coalesce(p_trending, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce(p_new_season, false) or coalesce(a.season_year, a.start_date_year, 0) >= ((select this_year from q) - 1))
      and (not coalesce(p_classics, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce(p_hidden_gems, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce(p_airing_only, false) or a.status = 'RELEASING')
      and (p_season is null or a.season = p_season)
      and (p_season_year is null or a.season_year = p_season_year)
  ),
  paged as (
    select
      *,
      coalesce(popularity, 0) as popularity_sort
    from base
    where
      p_cursor_rank is null
      or (rank, coalesce(popularity, 0), id) < (p_cursor_rank, coalesce(p_cursor_popularity, 0), p_cursor_id)
  )
  select
    id,
    title_english,
    title_romaji,
    title_native,
    cover_image_large,
    cover_image_medium,
    banner_image,
    format,
    status,
    episode_count,
    season_year,
    start_date_year,
    average_score,
    popularity,
    trending,
    favourites,
    genres,
    created_at,
    rank
  from paged
  order by rank desc, popularity_sort desc, id desc
  limit (select lim from params);
$$;

drop function if exists public.search_manga_page(text, integer, double precision, integer, integer, boolean, boolean, boolean, boolean);
create function public.search_manga_page(
  p_query text,
  p_limit integer default 30,
  p_cursor_rank double precision default null,
  p_cursor_popularity integer default null,
  p_cursor_id integer default null,
  p_trending boolean default false,
  p_new_season boolean default false,
  p_classics boolean default false,
  p_hidden_gems boolean default false
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
  genres text[],
  created_at timestamptz,
  rank double precision
)
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select
      nullif(trim(coalesce(p_query, '')), '') as raw,
      nullif(lower(trim(coalesce(p_query, ''))), '') as norm,
      extract(year from now())::int as this_year
  ),
  params as (
    select greatest(1, least(coalesce(p_limit, 30), 50))::int as lim
  ),
  ts as (
    select
      case
        when (select raw from q) is not null and length((select raw from q)) >= 3
          then websearch_to_tsquery('simple', (select raw from q))
        else null
      end as tsq
  ),
  base as (
    select
      m.id,
      m.title_english,
      m.title_romaji,
      m.title_native,
      m.cover_image_large,
      m.cover_image_medium,
      m.format,
      m.status,
      m.chapters as chapter_count,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      m.created_at,
      greatest(
        case
          when (select tsq from ts) is not null then
            ts_rank_cd(
              to_tsvector(
                'simple',
                coalesce(m.title_english,'') || ' ' ||
                coalesce(m.title_romaji,'') || ' ' ||
                coalesce(m.description_normalized,'')
              ),
              (select tsq from ts)
            )
          else 0
        end,
        case
          when (select norm from q) is not null then
            similarity(
              lower(coalesce(m.title_english,'') || ' ' || coalesce(m.title_romaji,'') || ' ' || coalesce(m.title_native,'')),
              (select norm from q)
            )
          else 0
        end
      ) as rank
    from public.manga m
    where
      m.is_adult is not true
      and not (m.genres @> array['Hentai']::text[])
      and not (m.genres @> array['Ecchi']::text[])
      and (
        (select norm from q) is null
        or (
          ((select tsq from ts) is not null and
            to_tsvector(
              'simple',
              coalesce(m.title_english,'') || ' ' ||
              coalesce(m.title_romaji,'') || ' ' ||
              coalesce(m.description_normalized,'')
            ) @@ (select tsq from ts))
          or similarity(
              lower(coalesce(m.title_english,'') || ' ' || coalesce(m.title_romaji,'') || ' ' || coalesce(m.title_native,'')),
              (select norm from q)
            ) > 0.12
          or lower(coalesce(m.title_english,'') || ' ' || coalesce(m.title_romaji,'') || ' ' || coalesce(m.title_native,'')) like ('%' || (select norm from q) || '%')
        )
      )
      and (not coalesce(p_trending, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce(p_new_season, false) or coalesce(m.start_date_year, 0) >= ((select this_year from q) - 1))
      and (not coalesce(p_classics, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce(p_hidden_gems, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ),
  paged as (
    select
      *,
      coalesce(popularity, 0) as popularity_sort
    from base
    where
      p_cursor_rank is null
      or (rank, coalesce(popularity, 0), id) < (p_cursor_rank, coalesce(p_cursor_popularity, 0), p_cursor_id)
  )
  select
    id,
    title_english,
    title_romaji,
    title_native,
    cover_image_large,
    cover_image_medium,
    format,
    status,
    chapter_count,
    start_date_year,
    average_score,
    popularity,
    trending,
    favourites,
    genres,
    created_at,
    rank
  from paged
  order by rank desc, popularity_sort desc, id desc
  limit (select lim from params);
$$;

grant execute on function public.search_anime_page(
  text, integer, double precision, integer, integer, boolean, boolean, boolean, boolean, boolean, text, integer
) to anon, authenticated;
grant execute on function public.search_manga_page(
  text, integer, double precision, integer, integer, boolean, boolean, boolean, boolean
) to anon, authenticated;

commit;

