-- Prepared 2026-11-09 (docs/plans/2026-11-09-backend-latency-plan.md step 1a).
-- Owner approved deployment to production 2026-11-10 ("do it all").
--
-- Staged Search for search_anime_page / search_manga_page. Bodies derive mechanically from the
-- live 20261109001251 definitions (generator kept out of the repo; the diff is reviewable):
-- the rank CASE, filters, keyset cursor and output are byte-identical inside each stage.
-- pg_trgm.similarity_threshold stays 0.35 (set live by 20261109123758); writing '0.3' here would
-- silently revert that change. Signatures and return types are unchanged, so CREATE OR REPLACE
-- keeps the existing grants.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.search_anime_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Staged (20261109200000): blank query = one popularity-ordered pass (unchanged); otherwise the
-- strong stage (exact 600 / prefix 500 / word 450 / contains 400 / full-text 320) runs first and
-- the trigram stage (rank exactly 250 under the identical rank expression, so never a row the
-- strong stage could return) runs only when the strong stage left the page short. Ranking,
-- keyset cursor (rank, popularity, id) and page size are unchanged.
declare
  v_q text := nullif(lower(trim(coalesce(p_query, ''))), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  v_n bigint := 0;
begin
  if v_q is null then
    return query execute $blank$
with base as (
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
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob
    from public.anime a
    where
      a.is_adult is not true
      and not (a.genres @> array['Hentai']::text[])
      and not (a.genres @> array['Ecchi']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce($6, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(a.season_year, a.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce($10, false) or a.status = 'RELEASING')
      and ($11 is null or a.season = $11)
      and ($12 is null or a.season_year = $12)
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      nullif(lower(trim(coalesce($1, ''))), '') is null
      or title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
      )
      or (
        length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
        and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
          extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
        ) >= 0.35)
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
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
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
  limit greatest(1,least(coalesce($2,30),50));
$blank$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year;
    return;
  end if;
  -- Strong rows rank >= 320: a cursor at or below 250 has already passed all of them.
  if p_cursor_rank is null or p_cursor_rank > 250 then
    return query execute $strong$
with base as (
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
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob
    from public.anime a
    where
      a.is_adult is not true
      and not (a.genres @> array['Hentai']::text[])
      and not (a.genres @> array['Ecchi']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce($6, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(a.season_year, a.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce($10, false) or a.status = 'RELEASING')
      and ($11 is null or a.season = $11)
      and ($12 is null or a.season_year = $12)
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
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
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
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
  limit greatest(1,least(coalesce($2,30),50));
$strong$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year;
    get diagnostics v_n = row_count;
  end if;
  if v_n < v_limit and length(v_q) >= 5 then
    return query execute $fuzzy$
with base as (
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
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob
    from public.anime a
    where
      a.is_adult is not true
      and not (a.genres @> array['Hentai']::text[])
      and not (a.genres @> array['Ecchi']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce($6, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(a.season_year, a.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce($10, false) or a.status = 'RELEASING')
      and ($11 is null or a.season = $11)
      and ($12 is null or a.season_year = $12)
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      (
        length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
        and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
          extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
        ) >= 0.35)
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
      rank = 250::double precision
      and (
        $3 is null
        or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
      )
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
  limit $13;
$fuzzy$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year, (v_limit - v_n)::integer;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_manga_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Staged (20261109200000): blank query = one popularity-ordered pass (unchanged); otherwise the
-- strong stage (exact 600 / prefix 500 / word 450 / contains 400 / full-text 320) runs first and
-- the trigram stage (rank exactly 250 under the identical rank expression, so never a row the
-- strong stage could return) runs only when the strong stage left the page short. Ranking,
-- keyset cursor (rank, popularity, id) and page size are unchanged.
declare
  v_q text := nullif(lower(trim(coalesce(p_query, ''))), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  v_n bigint := 0;
begin
  if v_q is null then
    return query execute $blank$
with base as (
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
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob
    from public.manga m
    where
      m.is_adult is not true
      and not (m.genres @> array['Hentai']::text[])
      and not (m.genres @> array['Ecchi']::text[])
      and (not coalesce($6, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      nullif(lower(trim(coalesce($1, ''))), '') is null
      or title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
      )
      or (
        length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
        and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
          extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
        ) >= 0.35)
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
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
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
  limit greatest(1,least(coalesce($2,30),50));
$blank$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems;
    return;
  end if;
  -- Strong rows rank >= 320: a cursor at or below 250 has already passed all of them.
  if p_cursor_rank is null or p_cursor_rank > 250 then
    return query execute $strong$
with base as (
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
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob
    from public.manga m
    where
      m.is_adult is not true
      and not (m.genres @> array['Hentai']::text[])
      and not (m.genres @> array['Ecchi']::text[])
      and (not coalesce($6, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
      or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
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
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
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
  limit greatest(1,least(coalesce($2,30),50));
$strong$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems;
    get diagnostics v_n = row_count;
  end if;
  if v_n < v_limit and length(v_q) >= 5 then
    return query execute $fuzzy$
with base as (
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
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob
    from public.manga m
    where
      m.is_adult is not true
      and not (m.genres @> array['Hentai']::text[])
      and not (m.genres @> array['Ecchi']::text[])
      and (not coalesce($6, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce($7, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($8, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce($9, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ),
  ranked as (
    select
      *,
      (
        case
          when nullif(lower(trim(coalesce($1, ''))), '') is null then 0::double precision
          when title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
            or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
            then 600::double precision
          when title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 500::double precision
          when (' ' || title_blob) like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
          when length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
            then 250::double precision
          else 0::double precision
        end
      ) as rank
    from base
    where
      (
        length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
        and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
          extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
          extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
        ) >= 0.35)
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
      rank = 250::double precision
      and (
        $3 is null
        or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
      )
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
  limit $10;
$fuzzy$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems, (v_limit - v_n)::integer;
  end if;
end;
$function$;

notify pgrst, 'reload schema';
commit;
