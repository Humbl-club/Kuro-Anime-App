-- Frozen pre-remediation production definitions for differential regression only.
-- Loaded only by 102_load_hotpaths.sql inside a rolled-back disposable DB fixture.
CREATE OR REPLACE FUNCTION pg_temp.old_browse_anime_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_episodes integer DEFAULT NULL::integer, p_max_episodes integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION pg_temp.old_search_anime_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION pg_temp.old_browse_manga_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_chapters integer DEFAULT NULL::integer, p_max_chapters integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION pg_temp.old_search_manga_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
