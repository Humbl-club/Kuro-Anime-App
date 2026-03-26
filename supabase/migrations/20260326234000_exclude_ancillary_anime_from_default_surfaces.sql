-- Hide ancillary anime formats from default Search, Browse, and Discover surfaces.
-- Browse still allows an explicit format override for users who deliberately filter into them.

begin;

-- Search should behave like title search first, not broad fuzzy/description search.
-- This keeps short incremental queries deterministic and popularity-ordered within
-- the strongest title-match bucket.
create extension if not exists pg_trgm;

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
      length(nullif(lower(trim(coalesce(p_query, ''))), ''))::int as norm_len,
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
      lower(coalesce(a.title_english, '')) as title_english_norm,
      lower(coalesce(a.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(a.title_native, '')) as title_native_norm,
      lower(trim(
        concat_ws(
          ' ',
          nullif(a.title_english, ''),
          nullif(a.title_romaji, ''),
          nullif(a.title_native, '')
        )
      )) as title_blob
    from public.anime a
    where
      a.is_adult is not true
      and not (a.genres @> array['Hentai']::text[])
      and not (a.genres @> array['Ecchi']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce(p_trending, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce(p_new_season, false) or coalesce(a.season_year, a.start_date_year, 0) >= ((select this_year from q) - 1))
      and (not coalesce(p_classics, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce(p_hidden_gems, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce(p_airing_only, false) or a.status = 'RELEASING')
      and (p_season is null or a.season = p_season)
      and (p_season_year is null or a.season_year = p_season_year)
  ),
  ranked as (
    select
      *,
      (
        case
          when (select norm from q) is null then 0::double precision
          when title_english_norm = (select norm from q)
            or title_romaji_norm = (select norm from q)
            or title_native_norm = (select norm from q)
            then 600::double precision
          when title_english_norm like ((select norm from q) || '%')
            or title_romaji_norm like ((select norm from q) || '%')
            or title_native_norm like ((select norm from q) || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || (select norm from q) || '%')
            then 450::double precision
          when title_blob like ('%' || (select norm from q) || '%')
            then 400::double precision
          when (select tsq from ts) is not null
            and to_tsvector('simple', title_blob) @@ (select tsq from ts)
            then 320::double precision
          when (select norm_len from q) >= 5
            and greatest(
              extensions.similarity(title_english_norm, (select norm from q)),
              extensions.similarity(title_romaji_norm, (select norm from q)),
              extensions.similarity(title_native_norm, (select norm from q)),
              extensions.similarity(title_blob, (select norm from q))
            ) >= 0.35
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      (select norm from q) is null
      or title_english_norm = (select norm from q)
      or title_romaji_norm = (select norm from q)
      or title_native_norm = (select norm from q)
      or title_english_norm like ((select norm from q) || '%')
      or title_romaji_norm like ((select norm from q) || '%')
      or title_native_norm like ((select norm from q) || '%')
      or (' ' || title_blob) like ('% ' || (select norm from q) || '%')
      or title_blob like ('%' || (select norm from q) || '%')
      or (
        (select tsq from ts) is not null
        and to_tsvector('simple', title_blob) @@ (select tsq from ts)
      )
      or (
        (select norm_len from q) >= 5
        and greatest(
          extensions.similarity(title_english_norm, (select norm from q)),
          extensions.similarity(title_romaji_norm, (select norm from q)),
          extensions.similarity(title_native_norm, (select norm from q)),
          extensions.similarity(title_blob, (select norm from q))
        ) >= 0.35
      )
  ),
  paged as (
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
      rank,
      coalesce(popularity, 0) as popularity_sort
    from ranked
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
      length(nullif(lower(trim(coalesce(p_query, ''))), ''))::int as norm_len,
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
      lower(coalesce(m.title_english, '')) as title_english_norm,
      lower(coalesce(m.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(m.title_native, '')) as title_native_norm,
      lower(trim(
        concat_ws(
          ' ',
          nullif(m.title_english, ''),
          nullif(m.title_romaji, ''),
          nullif(m.title_native, '')
        )
      )) as title_blob
    from public.manga m
    where
      m.is_adult is not true
      and not (m.genres @> array['Hentai']::text[])
      and not (m.genres @> array['Ecchi']::text[])
      and (not coalesce(p_trending, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce(p_new_season, false) or coalesce(m.start_date_year, 0) >= ((select this_year from q) - 1))
      and (not coalesce(p_classics, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce(p_hidden_gems, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ),
  ranked as (
    select
      *,
      (
        case
          when (select norm from q) is null then 0::double precision
          when title_english_norm = (select norm from q)
            or title_romaji_norm = (select norm from q)
            or title_native_norm = (select norm from q)
            then 600::double precision
          when title_english_norm like ((select norm from q) || '%')
            or title_romaji_norm like ((select norm from q) || '%')
            or title_native_norm like ((select norm from q) || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || (select norm from q) || '%')
            then 450::double precision
          when title_blob like ('%' || (select norm from q) || '%')
            then 400::double precision
          when (select tsq from ts) is not null
            and to_tsvector('simple', title_blob) @@ (select tsq from ts)
            then 320::double precision
          when (select norm_len from q) >= 5
            and greatest(
              extensions.similarity(title_english_norm, (select norm from q)),
              extensions.similarity(title_romaji_norm, (select norm from q)),
              extensions.similarity(title_native_norm, (select norm from q)),
              extensions.similarity(title_blob, (select norm from q))
            ) >= 0.35
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      (select norm from q) is null
      or title_english_norm = (select norm from q)
      or title_romaji_norm = (select norm from q)
      or title_native_norm = (select norm from q)
      or title_english_norm like ((select norm from q) || '%')
      or title_romaji_norm like ((select norm from q) || '%')
      or title_native_norm like ((select norm from q) || '%')
      or (' ' || title_blob) like ('% ' || (select norm from q) || '%')
      or title_blob like ('%' || (select norm from q) || '%')
      or (
        (select tsq from ts) is not null
        and to_tsvector('simple', title_blob) @@ (select tsq from ts)
      )
      or (
        (select norm_len from q) >= 5
        and greatest(
          extensions.similarity(title_english_norm, (select norm from q)),
          extensions.similarity(title_romaji_norm, (select norm from q)),
          extensions.similarity(title_native_norm, (select norm from q)),
          extensions.similarity(title_blob, (select norm from q))
        ) >= 0.35
      )
  ),
  paged as (
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
      rank,
      coalesce(popularity, 0) as popularity_sort
    from ranked
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
        (
          p_format is null
          or p_format = ''
        )
        and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
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

-- Rotate Discover "New to You" per user while keeping the rail high-quality.
-- Also exclude ancillary anime formats from this rail (e.g. specials, music videos, TV shorts).

begin;

create table if not exists public.discover_rail_impressions (
  user_id text not null,
  rail_key text not null,
  media_type text not null check (media_type in ('anime', 'manga')),
  media_id integer not null,
  created_at timestamptz not null default now(),
  last_shown_at timestamptz not null default now(),
  primary key (user_id, rail_key, media_type, media_id)
);

create index if not exists discover_rail_impressions_lookup_idx
  on public.discover_rail_impressions (user_id, rail_key, media_type, last_shown_at asc);

revoke all on public.discover_rail_impressions from anon, authenticated;

create or replace function public.discover_bundle(
  p_limit integer default 30,
  p_hours integer default 24
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
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
    from public.mv_anime_newly_added a, params p
    where coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
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
    from public.mv_manga_newly_added m, params p
    where coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    order by m.created_at desc, m.id desc
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
$$;
commit;
