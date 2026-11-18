-- PREPARED: 100-active-user load remediation. Existing RPC contracts and RLS remain.
-- Forward-only: exact ranking/cursors; indexable candidate search and custom Browse plans.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local search_path = public, extensions;

create or replace function public.catalogue_search_blob_v1(p_english text,p_romaji text,p_native text)
returns text language sql immutable parallel safe
set search_path = public, extensions
as $blob$
select lower(btrim(
 coalesce(nullif(p_english,''),'') ||
 case when nullif(p_english,'') is not null and nullif(p_romaji,'') is not null then ' ' else '' end ||
 coalesce(nullif(p_romaji,''),'') ||
 case when nullif(p_native,'') is not null and (nullif(p_english,'') is not null or nullif(p_romaji,'') is not null) then ' ' else '' end ||
 coalesce(nullif(p_native,''),'')
));
$blob$;
revoke all on function public.catalogue_search_blob_v1(text,text,text) from public;
grant execute on function public.catalogue_search_blob_v1(text,text,text) to anon,authenticated,service_role;
create index if not exists idx_anime_load_popular_v1 on public.anime ((coalesce(popularity,0)) desc,id desc);
create index if not exists idx_anime_load_trending_v1 on public.anime ((coalesce(trending,0)) desc,id desc);
create index if not exists idx_anime_load_score_v1 on public.anime ((coalesce(average_score,0)) desc,id desc);
create index if not exists idx_anime_load_created_v1 on public.anime (created_at desc nulls last,id desc);
create index if not exists idx_anime_load_title_english_v1 on public.anime using gin ((lower(coalesce(title_english,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_romaji_v1 on public.anime using gin ((lower(coalesce(title_romaji,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_native_v1 on public.anime using gin ((lower(coalesce(title_native,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_blob_v1 on public.anime using gin ((public.catalogue_search_blob_v1(title_english,title_romaji,title_native)) gin_trgm_ops);
create index if not exists idx_anime_load_title_fts_v1 on public.anime using gin (to_tsvector('simple',public.catalogue_search_blob_v1(title_english,title_romaji,title_native)));
create index if not exists idx_manga_load_popular_v1 on public.manga ((coalesce(popularity,0)) desc,id desc);
create index if not exists idx_manga_load_trending_v1 on public.manga ((coalesce(trending,0)) desc,id desc);
create index if not exists idx_manga_load_score_v1 on public.manga ((coalesce(average_score,0)) desc,id desc);
create index if not exists idx_manga_load_created_v1 on public.manga (created_at desc nulls last,id desc);
create index if not exists idx_manga_load_title_english_v1 on public.manga using gin ((lower(coalesce(title_english,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_romaji_v1 on public.manga using gin ((lower(coalesce(title_romaji,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_native_v1 on public.manga using gin ((lower(coalesce(title_native,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_blob_v1 on public.manga using gin ((public.catalogue_search_blob_v1(title_english,title_romaji,title_native)) gin_trgm_ops);
create index if not exists idx_manga_load_title_fts_v1 on public.manga using gin (to_tsvector('simple',public.catalogue_search_blob_v1(title_english,title_romaji,title_native)));

CREATE OR REPLACE FUNCTION public.browse_anime_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_episodes integer DEFAULT NULL::integer, p_max_episodes integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
declare
 v_order text := case when p_sort='newlyAdded' then 'b.created_at desc nulls last,b.id desc' else 'b.sort_int desc,b.id desc' end;
begin
 return query execute replace($query$
with base as (
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
        when $5 = 'trending' then coalesce(a.trending, 0)
        when $5 = 'topRated' then coalesce(a.average_score, 0)
        else coalesce(a.popularity, 0)
      end as sort_int
    from public.anime a
    where coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and ($1 is null or $1 = '' or a.genres @> array[$1]::text[])
      and ($2 is null or $2 = '' or a.status = $2)
      and ($3 is null or coalesce(a.episodes, 0) >= $3)
      and ($4 is null or coalesce(a.episodes, 0) <= $4)
      and (
        $10 is null
        or coalesce(a.season_year, a.start_date_year) >= $10
      )
      and (
        $11 is null
        or coalesce(a.season_year, a.start_date_year) <= $11
      )
      and (
        (
          $12 is null
          or $12 = ''
        )
        and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
        or upper(coalesce(a.format, '')) = upper($12)
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
  from base b
  where
    case
      when $5 = 'newlyAdded' then
        (
          $7 is null
          or (b.created_at < $7)
          or (b.created_at = $7 and b.id < $8)
        )
      else
        (
          $6 is null
          or (b.sort_int < $6)
          or (b.sort_int = $6 and b.id < $8)
        )
    end
  order by __KURO_ORDER__
  limit greatest(1,least(coalesce($9,60),120));
$query$,'__KURO_ORDER__',v_order) using p_genre,p_status,p_min_episodes,p_max_episodes,coalesce(nullif(p_sort,''),'popular'),p_cursor_int,p_cursor_ts,p_cursor_id,p_limit,p_min_year,p_max_year,p_format;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_anime_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.3'
AS $function$
begin
 return query execute $query$
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
$query$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year;
end;
$function$;

CREATE OR REPLACE FUNCTION public.browse_manga_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_chapters integer DEFAULT NULL::integer, p_max_chapters integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
declare
 v_order text := case when p_sort='newlyAdded' then 'b.created_at desc nulls last,b.id desc' else 'b.sort_int desc,b.id desc' end;
begin
 return query execute replace($query$
with base as (
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
        when $5 = 'trending' then coalesce(m.trending, 0)
        when $5 = 'topRated' then coalesce(m.average_score, 0)
        else coalesce(m.popularity, 0)
      end as sort_int
    from public.manga m
    where coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and ($1 is null or $1 = '' or m.genres @> array[$1]::text[])
      and ($2 is null or $2 = '' or m.status = $2)
      and ($3 is null or coalesce(m.chapters, 0) >= $3)
      and ($4 is null or coalesce(m.chapters, 0) <= $4)
      and ($10 is null or m.start_date_year >= $10)
      and ($11 is null or m.start_date_year <= $11)
      and (
        $12 is null
        or $12 = ''
        or upper(coalesce(m.format, '')) = upper($12)
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
  from base b
  where
    case
      when $5 = 'newlyAdded' then
        (
          $7 is null
          or (b.created_at < $7)
          or (b.created_at = $7 and b.id < $8)
        )
      else
        (
          $6 is null
          or (b.sort_int < $6)
          or (b.sort_int = $6 and b.id < $8)
        )
    end
  order by __KURO_ORDER__
  limit greatest(1,least(coalesce($9,60),120));
$query$,'__KURO_ORDER__',v_order) using p_genre,p_status,p_min_chapters,p_max_chapters,coalesce(nullif(p_sort,''),'popular'),p_cursor_int,p_cursor_ts,p_cursor_id,p_limit,p_min_year,p_max_year,p_format;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_manga_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 RETURNS TABLE(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.3'
AS $function$
begin
 return query execute $query$
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
$query$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems;
end;
$function$;

alter function public.discover_mood_v1(text,text,integer,integer) set jit to 'off';
alter function public.discover_bundle(integer,integer) set jit to 'off';
alter function public.discover_bundle(integer,integer) set search_path to public, extensions;
alter function public.series_detail_bundle_v1(text,integer,uuid,text) set jit to 'off';
alter function public.home_bundle_v1(text,text,integer,integer,integer,text) set jit to 'off';
notify pgrst, 'reload schema';
commit;
