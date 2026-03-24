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
