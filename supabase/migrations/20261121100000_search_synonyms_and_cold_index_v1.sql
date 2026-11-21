-- PREPARED ONLY (Wave 1): search synonym/acronym indexing, cold-start partial GIN indexes,
-- blank-query short-circuit, and non-spoiler tag filtering on browse_{anime,manga}_page.
-- Keeps exact function signatures, RETURNS TABLE columns, rank tiers (600/500/450/400/320/250),
-- SECURITY DEFINER + search_path/jit/similarity_threshold settings, and zero table DDL on
-- anime/manga/anime_tags/manga_tags so tests 102, 105, 113, 114, 123, 125, 126 hold.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local search_path = public, extensions;

-- 1. Pure helpers for synonym + acronym indexing (service_role only; used in expression GIN indexes & DEFINER RPCs).
create or replace function public._catalogue_acronym_v1(p_title text)
returns text
language sql
immutable
parallel safe
set search_path = public, extensions
as $acronym$
  select case
    when nullif(btrim(coalesce(p_title, '')), '') is null then ''
    else (
      select case
        when count(*) >= 3 and count(*) <= 10 then string_agg(left(tok, 1), '' order by ord)
        else ''
      end
      from (
        select tok, ord
        from unnest(
          regexp_split_to_array(
            lower(btrim(regexp_replace(p_title, '[^A-Za-z]+', ' ', 'g'))),
            '\s+'
          )
        ) with ordinality as t(tok, ord)
        where tok ~ '^[a-z]{2,}$'
      ) words
    )
  end;
$acronym$;

create or replace function public._catalogue_synonyms_blob_v1(p_english text, p_romaji text, p_synonyms text[])
returns text
language sql
immutable
parallel safe
set search_path = public, extensions
as $synblob$
  select nullif(btrim(
    concat_ws(
      ' ',
      nullif(lower(btrim(array_to_string(coalesce(p_synonyms, '{}'::text[]), ' '))), ''),
      nullif(public._catalogue_acronym_v1(p_english), ''),
      nullif(public._catalogue_acronym_v1(p_romaji), '')
    )
  ), '');
$synblob$;

revoke all on function public._catalogue_acronym_v1(text), public._catalogue_synonyms_blob_v1(text, text, text[]) from public, anon, authenticated;
grant execute on function public._catalogue_acronym_v1(text), public._catalogue_synonyms_blob_v1(text, text, text[]) to service_role;

-- 2. Partial GIN indexes (names contain _load_title_ for index-plan assertions) to eliminate cold scans on Hentai/Ecchi/hidden rows.
create index if not exists idx_anime_load_title_vis_blob_v2
  on public.anime using gin ((public.catalogue_search_blob_v1(title_english, title_romaji, title_native)) extensions.gin_trgm_ops)
  where is_adult is not true
    and catalogue_visibility = 'visible'
    and not (genres @> array['Hentai']::text[])
    and not (genres @> array['Ecchi']::text[]);

create index if not exists idx_anime_load_title_syn_trgm_v2
  on public.anime using gin ((public._catalogue_synonyms_blob_v1(title_english, title_romaji, title_synonyms)) extensions.gin_trgm_ops)
  where is_adult is not true
    and catalogue_visibility = 'visible';

create index if not exists idx_anime_load_title_adult_blob_v2
  on public.anime using gin ((public.catalogue_search_blob_v1(title_english, title_romaji, title_native)) extensions.gin_trgm_ops)
  where is_adult is true or genres @> array['Hentai']::text[];

create index if not exists idx_manga_load_title_vis_blob_v2
  on public.manga using gin ((public.catalogue_search_blob_v1(title_english, title_romaji, title_native)) extensions.gin_trgm_ops)
  where is_adult is not true
    and catalogue_visibility = 'visible'
    and not (genres @> array['Hentai']::text[])
    and not (genres @> array['Ecchi']::text[]);

create index if not exists idx_manga_load_title_syn_trgm_v2
  on public.manga using gin ((public._catalogue_synonyms_blob_v1(title_english, title_romaji, title_synonyms)) extensions.gin_trgm_ops)
  where is_adult is not true
    and catalogue_visibility = 'visible';

create index if not exists idx_manga_load_title_adult_blob_v2
  on public.manga using gin ((public.catalogue_search_blob_v1(title_english, title_romaji, title_native)) extensions.gin_trgm_ops)
  where is_adult is true or genres @> array['Hentai']::text[];

-- 3. Browse RPCs: support non-spoiler tag filters (`tag:<Name>`) alongside standard genres.
create or replace function public.browse_anime_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_episodes integer DEFAULT NULL::integer, p_max_episodes integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 returns table(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
 set jit to 'off'
as $function$
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
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        $1 is null
        or $1 = ''
        or (
          case
            when $1 like 'tag:%' then exists (
              select 1
              from public.anime_tags at
              join public.tags t on t.id = at.tag_id
              where at.anime_id = a.id
                and lower(t.name) = lower(btrim(substr($1, 5)))
                and coalesce(t.is_adult, false) = false
                and t.retired_at is null
                and coalesce(t.is_general_spoiler, false) = false
                and coalesce(t.is_media_spoiler, false) = false
            )
            else a.genres @> array[$1]::text[]
          end
        )
      )
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

create or replace function public.browse_manga_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_chapters integer DEFAULT NULL::integer, p_max_chapters integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
 returns table(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
 set jit to 'off'
as $function$
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
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        $1 is null
        or $1 = ''
        or (
          case
            when $1 like 'tag:%' then exists (
              select 1
              from public.manga_tags mt
              join public.tags t on t.id = mt.tag_id
              where mt.manga_id = m.id
                and lower(t.name) = lower(btrim(substr($1, 5)))
                and coalesce(t.is_adult, false) = false
                and t.retired_at is null
                and coalesce(t.is_general_spoiler, false) = false
                and coalesce(t.is_media_spoiler, false) = false
            )
            else m.genres @> array[$1]::text[]
          end
        )
      )
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

-- 4. Staged search RPCs: short-circuit blank pass & match title_synonyms + acronyms in $strong$.
create or replace function public.search_anime_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 returns table(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, banner_image text, format text, status text, episode_count integer, season_year integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
 set jit to 'off'
 set pg_trgm.similarity_threshold to '0.35'
as $function$
declare
  v_q text := nullif(lower(trim(coalesce(p_query, ''))), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  v_n bigint := 0;
begin
  if v_q is null then
    return query execute $blank$
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
  0::double precision as rank
from public.anime a
where
  (a.is_adult is not true and a.catalogue_visibility = 'visible')
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
  and (
    $3 is null
    or (0::double precision, coalesce(a.popularity, 0), a.id) < ($3, coalesce($4, 0), $5)
  )
order by 0::double precision desc, coalesce(a.popularity, 0) desc, a.id desc
limit greatest(1, least(coalesce($2, 30), 50));
$blank$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year;
    return;
  end if;

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
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob,
      public._catalogue_synonyms_blob_v1(a.title_english,a.title_romaji,a.title_synonyms) as synonyms_blob
    from public.anime a
    where
      (a.is_adult is not true and a.catalogue_visibility = 'visible')
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
            or (' ' || coalesce(synonyms_blob, '') || ' ') like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || ' %')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when coalesce(synonyms_blob, '') like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 380::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
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
      or synonyms_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
      )
  ),
  paged as (
    select
      id, title_english, title_romaji, title_native,
      cover_image_large, cover_image_medium, banner_image,
      format, status, episode_count, season_year, start_date_year,
      average_score, popularity, trending, favourites, genres, created_at,
      rank,
      coalesce(popularity, 0) as popularity_sort
    from ranked
    where
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
  )
  select
    id, title_english, title_romaji, title_native,
    cover_image_large, cover_image_medium, banner_image,
    format, status, episode_count, season_year, start_date_year,
    average_score, popularity, trending, favourites, genres, created_at, rank
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
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob,
      public._catalogue_synonyms_blob_v1(a.title_english,a.title_romaji,a.title_synonyms) as synonyms_blob
    from public.anime a
    where
      (a.is_adult is not true and a.catalogue_visibility = 'visible')
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
            or (' ' || coalesce(synonyms_blob, '') || ' ') like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || ' %')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when coalesce(synonyms_blob, '') like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 380::double precision
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
      id, title_english, title_romaji, title_native,
      cover_image_large, cover_image_medium, banner_image,
      format, status, episode_count, season_year, start_date_year,
      average_score, popularity, trending, favourites, genres, created_at,
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
    id, title_english, title_romaji, title_native,
    cover_image_large, cover_image_medium, banner_image,
    format, status, episode_count, season_year, start_date_year,
    average_score, popularity, trending, favourites, genres, created_at, rank
  from paged
  order by rank desc, popularity_sort desc, id desc
  limit $13;
$fuzzy$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems,p_airing_only,p_season,p_season_year, (v_limit - v_n)::integer;
  end if;
end;
$function$;

create or replace function public.search_manga_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 returns table(id integer, title_english text, title_romaji text, title_native text, cover_image_large text, cover_image_medium text, format text, status text, chapter_count integer, start_date_year integer, average_score integer, popularity integer, trending integer, favourites integer, genres text[], created_at timestamp with time zone, rank double precision)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
 set jit to 'off'
 set pg_trgm.similarity_threshold to '0.35'
as $function$
declare
  v_q text := nullif(lower(trim(coalesce(p_query, ''))), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  v_n bigint := 0;
begin
  if v_q is null then
    return query execute $blank$
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
  0::double precision as rank
from public.manga m
where
  (m.is_adult is not true and m.catalogue_visibility = 'visible')
  and not (m.genres @> array['Hentai']::text[])
  and not (m.genres @> array['Ecchi']::text[])
  and (not coalesce($6, false) or coalesce(m.trending, 0) > 0)
  and (not coalesce($7, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
  and (not coalesce($8, false) or coalesce(m.start_date_year, 9999) < 2010)
  and (not coalesce($9, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  and (
    $3 is null
    or (0::double precision, coalesce(m.popularity, 0), m.id) < ($3, coalesce($4, 0), $5)
  )
order by 0::double precision desc, coalesce(m.popularity, 0) desc, m.id desc
limit greatest(1, least(coalesce($2, 30), 50));
$blank$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems;
    return;
  end if;

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
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob,
      public._catalogue_synonyms_blob_v1(m.title_english,m.title_romaji,m.title_synonyms) as synonyms_blob
    from public.manga m
    where
      (m.is_adult is not true and m.catalogue_visibility = 'visible')
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
            or (' ' || coalesce(synonyms_blob, '') || ' ') like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || ' %')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when coalesce(synonyms_blob, '') like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 380::double precision
          when (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
            then 320::double precision
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
      or synonyms_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
      or (
        (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
        and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
      )
  ),
  paged as (
    select
      id, title_english, title_romaji, title_native,
      cover_image_large, cover_image_medium,
      format, status, chapter_count, start_date_year,
      average_score, popularity, trending, favourites, genres, created_at,
      rank,
      coalesce(popularity, 0) as popularity_sort
    from ranked
    where
      $3 is null
      or (rank, coalesce(popularity, 0), id) < ($3, coalesce($4, 0), $5)
  )
  select
    id, title_english, title_romaji, title_native,
    cover_image_large, cover_image_medium,
    format, status, chapter_count, start_date_year,
    average_score, popularity, trending, favourites, genres, created_at, rank
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
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob,
      public._catalogue_synonyms_blob_v1(m.title_english,m.title_romaji,m.title_synonyms) as synonyms_blob
    from public.manga m
    where
      (m.is_adult is not true and m.catalogue_visibility = 'visible')
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
            or (' ' || coalesce(synonyms_blob, '') || ' ') like ('% ' || nullif(lower(trim(coalesce($1, ''))), '') || ' %')
            then 450::double precision
          when title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 400::double precision
          when coalesce(synonyms_blob, '') like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
            then 380::double precision
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
      id, title_english, title_romaji, title_native,
      cover_image_large, cover_image_medium,
      format, status, chapter_count, start_date_year,
      average_score, popularity, trending, favourites, genres, created_at,
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
    id, title_english, title_romaji, title_native,
    cover_image_large, cover_image_medium,
    format, status, chapter_count, start_date_year,
    average_score, popularity, trending, favourites, genres, created_at, rank
  from paged
  order by rank desc, popularity_sort desc, id desc
  limit $10;
$fuzzy$ using p_query,p_limit,p_cursor_rank,p_cursor_popularity,p_cursor_id,p_trending,p_new_season,p_classics,p_hidden_gems, (v_limit - v_n)::integer;
  end if;
end;
$function$;

-- Reassert explicit grants (preserving 20261118110000 allowlist: never PUBLIC)
revoke all on function public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text) from public;
grant execute on function public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text) to anon, authenticated, service_role;

revoke all on function public.browse_manga_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text) from public;
grant execute on function public.browse_manga_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text) to anon, authenticated, service_role;

revoke all on function public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer) from public;
grant execute on function public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer) to anon, authenticated, service_role;

revoke all on function public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) from public;
grant execute on function public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) to anon, authenticated, service_role;

commit;
