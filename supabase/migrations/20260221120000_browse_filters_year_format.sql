-- Wire existing Browse "Year" and "Format" filters into backend RPCs.
-- Keeps current Browse semantics and keyset pagination behavior intact.

begin;

drop function if exists public.browse_anime_page(text, text, integer, integer, text, integer, timestamptz, integer, integer);
drop function if exists public.browse_anime_page(text, text, integer, integer, text, integer, timestamptz, integer, integer, integer, integer, text);
drop function if exists public.browse_manga_page(text, text, integer, integer, text, integer, timestamptz, integer, integer);
drop function if exists public.browse_manga_page(text, text, integer, integer, text, integer, timestamptz, integer, integer, integer, integer, text);

create or replace function public.browse_anime_page(
  p_genre text default null,
  p_status text default null,
  p_min_episodes integer default null,
  p_max_episodes integer default null,
  p_sort text default 'popular', -- popular|trending|topRated|newlyAdded
  p_cursor_int integer default null,
  p_cursor_ts timestamptz default null,
  p_cursor_id integer default null,
  p_limit integer default 60,
  p_min_year integer default null,
  p_max_year integer default null,
  p_format text default null
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
  created_at timestamptz
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
      and (
        p_min_year is null
        or coalesce(a.season_year, a.start_date_year) >= p_min_year
      )
      and (
        p_max_year is null
        or coalesce(a.season_year, a.start_date_year) <= p_max_year
      )
      and (
        p_format is null
        or p_format = ''
        or upper(coalesce(a.format, '')) = upper(p_format)
      )
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
    b.genres,
    b.created_at
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

create or replace function public.browse_manga_page(
  p_genre text default null,
  p_status text default null,
  p_min_chapters integer default null,
  p_max_chapters integer default null,
  p_sort text default 'popular', -- popular|trending|topRated|newlyAdded
  p_cursor_int integer default null,
  p_cursor_ts timestamptz default null,
  p_cursor_id integer default null,
  p_limit integer default 60,
  p_min_year integer default null,
  p_max_year integer default null,
  p_format text default null
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
  created_at timestamptz
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
      and (p_min_year is null or m.start_date_year >= p_min_year)
      and (p_max_year is null or m.start_date_year <= p_max_year)
      and (
        p_format is null
        or p_format = ''
        or upper(coalesce(m.format, '')) = upper(p_format)
      )
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
    b.genres,
    b.created_at
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

grant execute on function public.browse_anime_page(text, text, integer, integer, text, integer, timestamptz, integer, integer, integer, integer, text) to anon, authenticated;
grant execute on function public.browse_manga_page(text, text, integer, integer, text, integer, timestamptz, integer, integer, integer, integer, text) to anon, authenticated;

commit;
