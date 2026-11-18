-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 15b). NOT applied.
--
-- Browse visibility for `list_only` titles. A title no allowed source knows (no accepted catalogue_id_links
-- link) is hidden from browse, search, Discover, rails and recommendations once the identity group is
-- 'new', but it stays readable everywhere else: the user's list, export identity lookup, detail pages,
-- import resolution and get_media_ladder do not filter (Review Focus 5, spec section 4 item 6).
--
--   anime.catalogue_visibility / manga.catalogue_visibility text not null default 'visible'
--     check in ('visible', 'list_only'). Adding a column with a constant default does not rewrite the table.
--   catalogue_apply_visibility_v1(medium, limit): service-only. While identity is 'new' it sets list_only on
--     titles with no accepted link and visible on titles that have one; otherwise it makes every title visible
--     again (rollback of identity). Batched by `limit` (default 5000); returns the rows changed.
--   The readers below are CREATE OR REPLACE of their LATEST definition in supabase/migrations +
--   prepared-migrations (same signature, same attributes, so grants are kept). Each filter is a plain
--   `<alias>.catalogue_visibility = 'visible'` added next to the reader's existing adult predicate on the same
--   table alias, parenthesised so OR-structure is kept. It is a plain comparison, not a function call, so the
--   planner keeps using the created_at/popularity indexes (a function filter changed the newly-added rail plan
--   in test 104). The generator checked that no predicate lands inside a single-quoted string.
--   The inventory with every reader, its definition file and what is NOT filtered, and why, is
--   docs/catalogue-sources-2026-11/visibility-readers.md.
-- Not filtered here: rag_retrieve_candidates (reads rag_entity_index, no catalogue table), the Swift
-- RecommendationsReader genre fallback (a PostgREST table read in the app: needs an app change after this is
-- applied), and every list/detail/export/import reader. See the inventory.
-- Rollout: apply before any group is switched; with no list_only rows every filter passes everything.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
-- Two readers are LANGUAGE sql (curated_rail_cards, _recommend_ids_similar_to_seeds_live): their bodies are
-- unchanged apart from the predicate and valid in production. Skipping body validation lets the local DB
-- fixture (which lacks curated_rail_items) create them so the source check in test 125 can see them.
set local check_function_bodies = off;

alter table public.anime add column if not exists catalogue_visibility text not null default 'visible';
alter table public.manga add column if not exists catalogue_visibility text not null default 'visible';
alter table public.anime drop constraint if exists anime_catalogue_visibility_check;
alter table public.anime add constraint anime_catalogue_visibility_check check (catalogue_visibility in ('visible', 'list_only'));
alter table public.manga drop constraint if exists manga_catalogue_visibility_check;
alter table public.manga add constraint manga_catalogue_visibility_check check (catalogue_visibility in ('visible', 'list_only'));

create or replace function public.catalogue_apply_visibility_v1(p_medium text, p_limit integer default 5000)
returns integer
language plpgsql
set search_path = public, extensions
as $$
declare
  _identity text;
  _limit integer;
  _hidden integer := 0;
  _shown integer := 0;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_apply_visibility_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  _limit := greatest(1, least(coalesce(p_limit, 5000), 20000));
  select mode into _identity from public.catalogue_cutover where field_group = 'identity';

  if _identity = 'new' then
    execute format($q$
      with todo as (
        select t.id from public.%1$I t
         where t.catalogue_visibility = 'visible'
           and not exists (select 1 from public.catalogue_id_links l
                            where l.kind = %2$L and l.kuro_id = t.id and l.status = 'accepted')
         order by t.id limit $1)
      update public.%1$I t set catalogue_visibility = 'list_only' from todo where t.id = todo.id
    $q$, p_medium, p_medium) using _limit;
    get diagnostics _hidden = row_count;
    execute format($q$
      with todo as (
        select t.id from public.%1$I t
         where t.catalogue_visibility = 'list_only'
           and exists (select 1 from public.catalogue_id_links l
                        where l.kind = %2$L and l.kuro_id = t.id and l.status = 'accepted')
         order by t.id limit $1)
      update public.%1$I t set catalogue_visibility = 'visible' from todo where t.id = todo.id
    $q$, p_medium, p_medium) using _limit;
    get diagnostics _shown = row_count;
  else
    execute format($q$
      with todo as (select t.id from public.%1$I t where t.catalogue_visibility = 'list_only' order by t.id limit $1)
      update public.%1$I t set catalogue_visibility = 'visible' from todo where t.id = todo.id
    $q$, p_medium) using _limit;
    get diagnostics _shown = row_count;
  end if;
  return _hidden + _shown;
end;
$$;

revoke all on function public.catalogue_apply_visibility_v1(text, integer) from public, anon, authenticated;
grant execute on function public.catalogue_apply_visibility_v1(text, integer) to service_role;

-- browse_anime_page: latest definition 20261109001251_load_hotpaths_v1.sql; 1 anime/manga/matview references, 1 visibility predicates added
create or replace function public.browse_anime_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_episodes integer DEFAULT NULL::integer, p_max_episodes integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
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
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
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

-- browse_manga_page: latest definition 20261109001251_load_hotpaths_v1.sql; 1 anime/manga/matview references, 1 visibility predicates added
create or replace function public.browse_manga_page(p_genre text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_min_chapters integer DEFAULT NULL::integer, p_max_chapters integer DEFAULT NULL::integer, p_sort text DEFAULT 'popular'::text, p_cursor_int integer DEFAULT NULL::integer, p_cursor_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id integer DEFAULT NULL::integer, p_limit integer DEFAULT 60, p_min_year integer DEFAULT NULL::integer, p_max_year integer DEFAULT NULL::integer, p_format text DEFAULT NULL::text)
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
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
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

-- search_anime_page: latest definition 20261109200000_search_staged_v1.sql; 3 anime/manga/matview references, 3 visibility predicates added
create or replace function public.search_anime_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
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

-- search_manga_page: latest definition 20261109200000_search_staged_v1.sql; 3 anime/manga/matview references, 3 visibility predicates added
create or replace function public.search_manga_page(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
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

-- curated_rail_cards: latest definition 20260205231000_curated_rails.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.curated_rail_cards(
  p_rail_id text,
  p_limit integer default 30,
  p_exclude_seen boolean default true
)
returns table (
  media_type text,
  media_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_medium text,
  average_score integer,
  year integer,
  format text,
  status text,
  site_url text,
  genres text[],
  signals text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select greatest(1, least(coalesce(p_limit, 30), 120))::int as lim
  ),
  flags as (
    select
      (case when p_rail_id ilike 'classics%' then true else false end) as is_classics,
      (case when p_rail_id ilike 'gateway%' or p_rail_id ilike 'start_here%' then true else false end) as is_gateway
  ),
  anime_items as (
    select
      'ANIME'::text as media_type,
      a.id as media_id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_medium,
      a.average_score,
      a.start_date_year as year,
      a.format,
      a.status,
      a.site_url,
      a.genres,
      array_remove(array[
        case when (select is_classics from flags) then 'CLASSIC' else null end,
        case when (select is_gateway from flags) then 'GATEWAY' else null end
      ], null) as signals,
      i.rank as r
    from public.curated_rail_items i
    join public.anime a on a.anilist_id = i.anilist_id
    where i.rail_id = p_rail_id
      and i.media_type = 'ANIME'
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        p_exclude_seen = false
        or auth.uid() is null
        or not exists (
          select 1 from public.user_lists ul
          where ul.user_id = auth.uid()::text
            and ul.media_type = 'anime'
            and ul.media_id = a.id
        )
      )
  ),
  manga_items as (
    select
      'MANGA'::text as media_type,
      m.id as media_id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_medium,
      m.average_score,
      m.start_date_year as year,
      m.format,
      m.status,
      m.site_url,
      m.genres,
      array_remove(array[
        case when (select is_classics from flags) then 'CLASSIC' else null end,
        case when (select is_gateway from flags) then 'GATEWAY' else null end
      ], null) as signals,
      i.rank as r
    from public.curated_rail_items i
    join public.manga m on m.anilist_id = i.anilist_id
    where i.rail_id = p_rail_id
      and i.media_type = 'MANGA'
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        p_exclude_seen = false
        or auth.uid() is null
        or not exists (
          select 1 from public.user_lists ul
          where ul.user_id = auth.uid()::text
            and ul.media_type = 'manga'
            and ul.media_id = m.id
        )
      )
  )
  select
    x.media_type,
    x.media_id,
    x.title_english,
    x.title_romaji,
    x.title_native,
    x.cover_image_medium,
    x.average_score,
    x.year,
    x.format,
    x.status,
    x.site_url,
    x.genres,
    x.signals
  from (
    select * from anime_items
    union all
    select * from manga_items
  ) x, params p
  order by x.r asc, x.media_id asc
  limit (select lim from params);
$$;

-- fetch_tonight_shelf: latest definition 20260806010000_serving_fixes_v1.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_tonight_shelf(p_limit integer default 12)
returns table (
  realm text,
  display_name text,
  blurb text,
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim int := greatest(1, least(coalesce(p_limit, 12), 40));
  v_realm text;
  v_display text;
  v_blurb text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb
    into v_display, v_blurb
  from public.realm_meta rm
  where rm.realm = v_realm;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier,
      case t.tier
        when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1
      end as tier_rank,
      m.weight as mem_weight
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and m.weight >= 0.35
  ),
  anime_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.cover_image_medium,
      a.cover_image_color,
      a.genres,
      a.average_score,
      a.format,
      coalesce(a.season_year, a.start_date_year) as year,
      left(coalesce(a.description_normalized, ''), 300) as synopsis,
      a.episodes,
      null::integer as chapters,
      null::integer as volumes,
      coalesce(a.popularity, 0) as popularity
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and a.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )
  ),
  manga_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.cover_image_medium,
      m.cover_image_color,
      m.genres,
      m.average_score,
      m.format,
      m.start_date_year,
      left(coalesce(m.description_normalized, ''), 300),
      null::integer,
      m.chapters,
      m.volumes,
      coalesce(m.popularity, 0)
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and m.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  ranked as (
    select * from anime_cards
    union all
    select * from manga_cards
  ),
  capped as (
    -- Franchise runaway cap (20260806010000): <= 2 titles per franchise
    -- cluster on the shelf. Label = media_franchise_components via the
    -- owner-read accessor; singletons label as themselves (collision-free —
    -- 20260804140000: a component's min-member id is itself a member).
    -- media_type is in the partition key because component labels are
    -- per-type integers. Running cap: the cluster's two best entries under
    -- the shelf ordering keep their rank positions; the rest fall out.
    select
      r.*,
      row_number() over (
        partition by r.media_type, coalesce(fc.component_label, r.media_id)
        order by r.tier_rank desc, r.average_score desc nulls last, r.mem_weight desc, r.media_id desc
      ) as franchise_rn
    from ranked r
    left join public._franchise_component_labels() fc
      on fc.media_type = r.media_type
     and fc.media_id = r.media_id
  )
  select
    v_realm,
    v_display,
    v_blurb,
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.cover_image_medium,
    c.cover_image_color,
    c.genres,
    c.average_score,
    c.format,
    c.year,
    c.synopsis,
    c.episodes,
    c.chapters,
    c.volumes
  from capped c
  where c.franchise_rn <= 2
  order by c.tier_rank desc, c.average_score desc nulls last, c.mem_weight desc, c.media_id desc
  limit v_lim;
end;
$$;

-- fetch_daily_feature: latest definition 20260805100000_daily_feature_display_synopsis.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_daily_feature()
 RETURNS TABLE(media_type text, media_id integer, title text, cover_image_large text, banner_image text, genres text[], score integer, year integer, format text, argument text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  return query
  with pool as (
    select
      b.weight,
      b.label,
      'ANIME'::text as p_media_type,
      a.id as p_media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as p_title,
      a.cover_image_large as p_cover,
      a.banner_image as p_banner,
      a.genres as p_genres,
      a.average_score as p_score,
      coalesce(a.season_year, a.start_date_year) as p_year,
      a.format as p_format,
      case
        when a.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
          then a.synopsis_enhanced
        else a.description
      end as p_synopsis
    from public.editorial_boosts b
    join public.anime a on a.id = b.media_id
    where b.media_type = 'ANIME'
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and (a.cover_image_large is not null or a.banner_image is not null)

    union all

    select
      b.weight,
      b.label,
      'MANGA'::text,
      m.id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      case
        when m.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
          then m.synopsis_enhanced
        else m.description
      end
    from public.editorial_boosts b
    join public.manga m on m.id = b.media_id
    where b.media_type = 'MANGA'
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and (m.cover_image_large is not null or m.banner_image is not null)
  ),
  numbered as (
    select
      p.*,
      row_number() over (order by p.weight desc, p.p_media_type, p.p_media_id) as rn,
      count(*) over () as n
    from pool p
  )
  select
    numbered.p_media_type,
    numbered.p_media_id,
    numbered.p_title,
    numbered.p_cover,
    numbered.p_banner,
    numbered.p_genres,
    numbered.p_score,
    numbered.p_year,
    numbered.p_format,
    case
      -- Substantive editorial label (>= 4 words) wins; tags like "classic" do not.
      when nullif(btrim(numbered.label), '') is not null
       and array_length(regexp_split_to_array(btrim(numbered.label), '\s+'), 1) >= 4
        then btrim(numbered.label)
      else nullif(public._discover_sentence_trim(numbered.p_synopsis, 320), '')
    end as argument
  from numbered
  where numbered.rn = ((extract(doy from now()))::integer - 1) % numbered.n + 1;
end;
$function$
;

-- fetch_personalized_new_to_you: latest definition 20260731070000_taste_math_v2_hotfix.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_personalized_new_to_you(
  p_limit integer default 20,
  p_media_type text default 'ANIME'
)
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text
)
language plpgsql
volatile
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_type text := upper(trim(coalesce(p_media_type, 'ANIME')));
  v_lim integer := greatest(1, least(coalesce(p_limit, 20), 60));
  v_profile jsonb;
  v_avoided jsonb := '[]'::jsonb;
  v_unorm double precision := 0;
  v_evidence double precision := 0;
  v_w double precision := 0;
  v_ids integer[] := '{}'::integer[];
  r record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;

  select p.vector into v_profile
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_profile is not null then
    v_evidence := coalesce((v_profile->>'evidence')::double precision, 0);
    v_avoided := coalesce(v_profile->'avoided_tags', '[]'::jsonb);
    select coalesce(sqrt(sum(uv.uval * uv.uval)), 0)
      into v_unorm
    from (
      select value::double precision as uval
      from jsonb_each_text(v_profile->'vector')
    ) uv;
  end if;

  -- Contract-capped ramp: w = 0.20 * n/(n+20); n = 0 -> pure editorial fallback.
  v_w := case
    when v_evidence > 0 and v_unorm > 0
      then 0.20 * v_evidence / (v_evidence + 20.0)
    else 0.0
  end;

  if v_type = 'ANIME' then
    for r in
      with candidates as (
        select
          a.id as media_id,
          coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
          a.cover_image_large,
          a.cover_image_medium,
          a.cover_image_color,
          a.genres,
          a.average_score,
          a.format,
          coalesce(a.season_year, a.start_date_year) as year,
          left(coalesce(a.description_normalized, ''), 300) as synopsis,
          coalesce(a.popularity, 0) as popularity,
          coalesce(a.favourites, 0) as favourites
        from public.anime a
        where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
          and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
          and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
          and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
          and coalesce(a.average_score, 0) >= 80
          and not exists (
            select 1 from public.anime_user_lists ul
            where ul.user_id = v_uid::text
              and ul.anime_id = a.id
          )
          and not (a.id = any (public._taste_recent_impressed_ids('discover_new_to_you', 'anime')))
        order by coalesce(a.popularity, 0) desc, coalesce(a.average_score, 0) desc,
                 coalesce(a.favourites, 0) desc, a.id desc
        limit greatest(v_lim * 6, 60)
      ),
      scored as (
        select
          c.*,
          case
            when coalesce(max(c.popularity) over (), 0) > 0
              then c.popularity::double precision / max(c.popularity) over ()
            else 0.0
          end as editorial_prior,
          -- Cosine fit in the shared vector space; -0.5 avoided-tag penalty
          -- (rank >= 60) on fit, then clamped to [-1, 1].
          least(greatest(
            case
              when v_w > 0 and f.tnorm > 0
                then least(greatest(f.dot / (v_unorm * f.tnorm), -1.0), 1.0)
              else 0.0
            end
            -- Narrowed penalty (hotfix P3): -0.5 only when the title's genres
            -- match an avoided 'genre:*' key, or it carries an avoided tag of
            -- category 'Genre' with rank >= 60. Broad Theme tags (e.g. 'male
            -- protagonist') no longer nuke the candidate pool.
            + case when exists (
                select 1
                from unnest(coalesce(c.genres, '{}'::text[])) as g
                where v_avoided ? ('genre:' || lower(g))
              ) or exists (
                select 1
                from public.anime_tags at3
                join public.tags t3 on t3.id = at3.tag_id
                where at3.anime_id = c.media_id
                  and at3.rank >= 60
                  and t3.category = 'Genre'
                  and v_avoided ? lower(t3.name)
              ) then -0.5 else 0.0 end,
            -1.0), 1.0) as fit
        from candidates c
        left join lateral (
          select
            sum(v.w::double precision * uv.uval) as dot,
            max(v.l2_norm)::double precision as tnorm
          from public.media_tag_vectors v
          join (
            select key, value::double precision as uval
            from jsonb_each_text(v_profile->'vector')
          ) uv on uv.key = v.tag_key
          where v.media_type = 'ANIME'
            and v.media_id = c.media_id
        ) f on true
      )
      select
        'ANIME'::text as media_type,
        s.media_id,
        s.title,
        s.cover_image_large,
        s.cover_image_medium,
        s.cover_image_color,
        s.genres,
        s.average_score,
        s.format,
        s.year,
        s.synopsis
      from scored s
      order by
        ((1.0 - v_w) * s.editorial_prior + v_w * s.fit) desc,
        s.popularity desc,
        s.average_score desc,
        s.favourites desc,
        s.media_id desc
      limit v_lim
    loop
      v_ids := v_ids || r.media_id;
      media_type := r.media_type;
      media_id := r.media_id;
      title := r.title;
      cover_image_large := r.cover_image_large;
      cover_image_medium := r.cover_image_medium;
      cover_image_color := r.cover_image_color;
      genres := r.genres;
      average_score := r.average_score;
      format := r.format;
      year := r.year;
      synopsis := r.synopsis;
      return next;
    end loop;
    perform public._taste_stamp_impressions('discover_new_to_you', 'anime', v_ids);
  else
    for r in
      with candidates as (
        select
          m.id as media_id,
          coalesce(nullif(m.title_english, ''), m.title_romaji) as title,
          m.cover_image_large,
          m.cover_image_medium,
          m.cover_image_color,
          m.genres,
          m.average_score,
          m.format,
          m.start_date_year as year,
          left(coalesce(m.description_normalized, ''), 300) as synopsis,
          coalesce(m.popularity, 0) as popularity,
          coalesce(m.favourites, 0) as favourites
        from public.manga m
        where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
          and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
          and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
          and coalesce(m.average_score, 0) >= 80
          and not exists (
            select 1 from public.manga_user_lists ul
            where ul.user_id = v_uid::text
              and ul.manga_id = m.id
          )
          and not (m.id = any (public._taste_recent_impressed_ids('discover_new_to_you', 'manga')))
        order by coalesce(m.popularity, 0) desc, coalesce(m.average_score, 0) desc,
                 coalesce(m.favourites, 0) desc, m.id desc
        limit greatest(v_lim * 6, 60)
      ),
      scored as (
        select
          c.*,
          case
            when coalesce(max(c.popularity) over (), 0) > 0
              then c.popularity::double precision / max(c.popularity) over ()
            else 0.0
          end as editorial_prior,
          least(greatest(
            case
              when v_w > 0 and f.tnorm > 0
                then least(greatest(f.dot / (v_unorm * f.tnorm), -1.0), 1.0)
              else 0.0
            end
            -- Narrowed penalty (hotfix P3): same rule as the anime branch.
            + case when exists (
                select 1
                from unnest(coalesce(c.genres, '{}'::text[])) as g
                where v_avoided ? ('genre:' || lower(g))
              ) or exists (
                select 1
                from public.manga_tags mt3
                join public.tags t3 on t3.id = mt3.tag_id
                where mt3.manga_id = c.media_id
                  and mt3.rank >= 60
                  and t3.category = 'Genre'
                  and v_avoided ? lower(t3.name)
              ) then -0.5 else 0.0 end,
            -1.0), 1.0) as fit
        from candidates c
        left join lateral (
          select
            sum(v.w::double precision * uv.uval) as dot,
            max(v.l2_norm)::double precision as tnorm
          from public.media_tag_vectors v
          join (
            select key, value::double precision as uval
            from jsonb_each_text(v_profile->'vector')
          ) uv on uv.key = v.tag_key
          where v.media_type = 'MANGA'
            and v.media_id = c.media_id
        ) f on true
      )
      select
        'MANGA'::text as media_type,
        s.media_id,
        s.title,
        s.cover_image_large,
        s.cover_image_medium,
        s.cover_image_color,
        s.genres,
        s.average_score,
        s.format,
        s.year,
        s.synopsis
      from scored s
      order by
        ((1.0 - v_w) * s.editorial_prior + v_w * s.fit) desc,
        s.popularity desc,
        s.average_score desc,
        s.favourites desc,
        s.media_id desc
      limit v_lim
    loop
      v_ids := v_ids || r.media_id;
      media_type := r.media_type;
      media_id := r.media_id;
      title := r.title;
      cover_image_large := r.cover_image_large;
      cover_image_medium := r.cover_image_medium;
      cover_image_color := r.cover_image_color;
      genres := r.genres;
      average_score := r.average_score;
      format := r.format;
      year := r.year;
      synopsis := r.synopsis;
      return next;
    end loop;
    perform public._taste_stamp_impressions('discover_new_to_you', 'manga', v_ids);
  end if;

  return;
end;
$$;

-- fetch_realm_hidden_gem: latest definition 20260806020000_serving_hardening_v1.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_realm_hidden_gem()
returns table (
  realm text,
  display_name text,
  blurb text,
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  banner_image text,
  genres text[],
  score integer,
  year integer,
  format text,
  argument text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_realm text;
  v_display text;
  v_blurb text;
  v_week int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb into v_display, v_blurb
  from public.realm_meta rm where rm.realm = v_realm;

  v_week := (extract(epoch from date_trunc('week', now() at time zone 'utc')) / 86400)::int;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and t.tier in ('canon', 'acclaimed')
      and m.weight >= 0.35
  ),
  fr_labels as (
    -- One materialization of the franchise labels (referenced by
    -- known_franchises and both scored branches).
    select fc.media_type, fc.media_id, fc.component_label
    from public._franchise_component_labels() fc
  ),
  known_franchises as (
    -- Franchise-familiarity (20260806010000): components containing any title
    -- the user already knows — on their list, or deck-signalled love/known
    -- (deck_skip is disinterest in that title, not franchise familiarity).
    -- Driven from the user's own rows (small) joined to labels, never a
    -- full components scan per candidate.
    select distinct fc.media_type, fc.component_label
    from (
      select
        case when ul.media_type = 'anime' then 'ANIME' else 'MANGA' end as mt,
        ul.media_id as mid
      from public.user_lists ul
      where ul.user_id = v_uid::text
      union
      select e.media_type, e.media_id
      from public.taste_signal_events e
      where e.user_id = v_uid
        and e.event_type in ('deck_love', 'deck_known')
    ) k
    join fr_labels fc
      on fc.media_type = k.mt
     and fc.media_id = k.mid
  ),
  scored as (
    select
      p.media_type,
      p.media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.banner_image,
      a.genres,
      a.average_score as score,
      coalesce(a.season_year, a.start_date_year) as year,
      a.format,
      coalesce(a.popularity, 0) as popularity,
      public._discover_sanitize_synopsis(
        case
          when a.synopsis_enhanced_state = 'ready'
           and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
            then a.synopsis_enhanced
          else a.description
        end
      ) as argument,
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      ) as has_seasonal
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    left join fr_labels fc
      on fc.media_type = p.media_type
     and fc.media_id = p.media_id
    where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and a.cover_image_large is not null
      and coalesce(a.average_score, 0) >= 75
      and coalesce(a.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'anime' and ul.media_id = a.id
      )
      and not exists (
        select 1 from known_franchises kf
        where kf.media_type = p.media_type
          and kf.component_label = fc.component_label
      )

    union all

    select
      p.media_type,
      p.media_id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      coalesce(m.popularity, 0),
      public._discover_sanitize_synopsis(
        case
          when m.synopsis_enhanced_state = 'ready'
           and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
            then m.synopsis_enhanced
          else m.description
        end
      ),
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      )
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    left join fr_labels fc
      on fc.media_type = p.media_type
     and fc.media_id = p.media_id
    where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and m.cover_image_large is not null
      and coalesce(m.average_score, 0) >= 75
      and coalesce(m.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'manga' and ul.media_id = m.id
      )
      and not exists (
        select 1 from known_franchises kf
        where kf.media_type = p.media_type
          and kf.component_label = fc.component_label
      )
  ),
  cut as (
    select s.*,
           percent_rank() over (order by s.popularity asc) as pop_pct,
           row_number() over (
             order by
               (case when s.has_seasonal then 0 else 1 end),
               (hashtext(s.media_type || ':' || s.media_id::text || ':' || v_week::text))
           ) as rn
    from scored s
  )
  select
    v_realm,
    v_display,
    v_blurb,
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.banner_image,
    c.genres,
    c.score,
    c.year,
    c.format,
    -- The One Thing treatment (20260731110000): sentence-trim at 320,
    -- capitalize the first letter; empty collapses to null.
    nullif(
      upper(left(t.argument, 1)) || substring(t.argument from 2),
    '') as argument
  from cut c
  cross join lateral (
    select public._discover_sentence_trim(
      coalesce(nullif(c.argument, ''), v_blurb),
      320
    ) as argument
  ) t
  where c.pop_pct <= 0.55 or c.has_seasonal
  order by c.rn
  limit 1;
end;
$$;

-- fetch_because_you_rail: latest definition 20260731150000_realm_graph_v1.sql; 4 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_because_you_rail(p_limit integer default 12)
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer,
  reason_title text,
  realm text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(1, least(coalesce(p_limit, 12), 40));
  v_seed_count integer := 0;
  v_anime_seeds integer[] := '{}'::integer[];
  v_manga_seeds integer[] := '{}'::integer[];
  v_seed1_type text;
  v_seed1_id integer;
  v_reason text;
  v_anime_recs integer[] := '{}'::integer[];
  v_manga_recs integer[] := '{}'::integer[];
  v_out_types text[] := '{}'::text[];
  v_out_ids integer[] := '{}'::integer[];
  v_a_len integer;
  v_m_len integer;
  v_i integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Top 3 positive titles by summed positive strength (deterministic ties).
  with positive as (
    select
      e.media_type,
      e.media_id,
      sum(e.event_strength) as s,
      max(e.created_at) as last_at
    from public.taste_signal_events e
    where e.user_id = v_uid
      and e.event_strength > 0
    group by e.media_type, e.media_id
  ),
  ranked as (
    select
      p.media_type,
      p.media_id,
      row_number() over (order by p.s desc, p.last_at desc, p.media_type, p.media_id) as rn
    from positive p
  )
  select
    count(*),
    coalesce(array_agg(r.media_id) filter (where r.media_type = 'ANIME'), '{}'::integer[]),
    coalesce(array_agg(r.media_id) filter (where r.media_type = 'MANGA'), '{}'::integer[]),
    max(r.media_type) filter (where r.rn = 1),
    max(r.media_id) filter (where r.rn = 1)
  into v_seed_count, v_anime_seeds, v_manga_seeds, v_seed1_type, v_seed1_id
  from ranked r
  where r.rn <= 3;

  -- Below confidence: not enough distinct positive evidence -> 0 rows.
  if v_seed_count < 2 then
    return;
  end if;

  -- The reason names the #1 seed.
  if v_seed1_type = 'ANIME' then
    select coalesce(nullif(a.title_english, ''), a.title_romaji)
      into v_reason
      from public.anime a
     where a.id = v_seed1_id;
  else
    select coalesce(nullif(m.title_english, ''), m.title_romaji)
      into v_reason
      from public.manga m
     where m.id = v_seed1_id;
  end if;

  -- Per-type candidates from the v4 similarity RPC (list dedupe built in).
  if array_length(v_anime_seeds, 1) is not null then
    select array_agg(x.media_id order by x.score desc, x.media_id desc)
      into v_anime_recs
      from public.recommend_ids_similar_to_seeds('ANIME', v_anime_seeds, v_lim, false) x;
  end if;
  if array_length(v_manga_seeds, 1) is not null then
    select array_agg(x.media_id order by x.score desc, x.media_id desc)
      into v_manga_recs
      from public.recommend_ids_similar_to_seeds('MANGA', v_manga_seeds, v_lim, false) x;
  end if;

  -- Interleave when both types have candidates; otherwise one list alone.
  v_a_len := coalesce(array_length(v_anime_recs, 1), 0);
  v_m_len := coalesce(array_length(v_manga_recs, 1), 0);
  for v_i in 1..greatest(v_a_len, v_m_len) loop
    if v_i <= v_a_len and coalesce(array_length(v_out_ids, 1), 0) < v_lim then
      v_out_types := v_out_types || 'ANIME'::text;
      v_out_ids := v_out_ids || v_anime_recs[v_i];
    end if;
    if v_i <= v_m_len and coalesce(array_length(v_out_ids, 1), 0) < v_lim then
      v_out_types := v_out_types || 'MANGA'::text;
      v_out_ids := v_out_ids || v_manga_recs[v_i];
    end if;
  end loop;

  return query
  with ordered as (
    select t.mt, t.mi, t.ord
    from unnest(v_out_types, v_out_ids) with ordinality as t(mt, mi, ord)
  ),
  cards as (
    select
      o.ord,
      'ANIME'::text as c_media_type,
      a.id as c_media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as c_title,
      a.cover_image_large as c_cover_large,
      a.cover_image_medium as c_cover_medium,
      a.cover_image_color as c_cover_color,
      a.genres as c_genres,
      a.average_score as c_score,
      a.format as c_format,
      coalesce(a.season_year, a.start_date_year) as c_year,
      left(coalesce(a.description_normalized, ''), 300) as c_synopsis,
      a.episodes as c_episodes,
      null::integer as c_chapters,
      null::integer as c_volumes
    from ordered o
    join public.anime a on o.mt = 'ANIME' and a.id = o.mi
    where a.catalogue_visibility = 'visible'
      and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'ANIME'
        and e.media_id = a.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )

    union all

    select
      o.ord,
      'MANGA'::text,
      m.id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.cover_image_medium,
      m.cover_image_color,
      m.genres,
      m.average_score,
      m.format,
      m.start_date_year,
      left(coalesce(m.description_normalized, ''), 300),
      null::integer,
      m.chapters,
      m.volumes
    from ordered o
    join public.manga m on o.mt = 'MANGA' and m.id = o.mi
    where m.catalogue_visibility = 'visible'
      and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'MANGA'
        and e.media_id = m.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )
  )
  select
    cards.c_media_type,
    cards.c_media_id,
    cards.c_title,
    cards.c_cover_large,
    cards.c_cover_medium,
    cards.c_cover_color,
    cards.c_genres,
    cards.c_score,
    cards.c_format,
    cards.c_year,
    cards.c_synopsis,
    cards.c_episodes,
    cards.c_chapters,
    cards.c_volumes,
    v_reason,
    rt.realm
  from cards
  left join public.media_realm_tier rt
    on rt.media_type = cards.c_media_type
   and rt.media_id = cards.c_media_id
  order by cards.ord;
end;
$$;

-- fetch_taste_deck_batch: latest definition 20260731150000_realm_graph_v1.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.fetch_taste_deck_batch(p_limit integer default 12)
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer,
  seasons_count integer,
  has_dub boolean,
  has_sub boolean
)
language plpgsql
volatile
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(2, least(coalesce(p_limit, 12), 40));
  v_half integer;
  v_pool_lim integer;
  v_profile jsonb;
  v_avoided jsonb := '[]'::jsonb;
  v_unorm double precision := 0;
  v_evidence double precision := 0;
  v_explore_ratio double precision;
  v_explore_slots integer;
  v_exploit_slots integer;
  v_cluster_cap integer;
  v_franchise_cap integer;
  v_a_count integer;
  v_m_count integer;
  v_a_take integer;
  v_m_take integer;
  v_pa integer := 0;
  v_pm integer := 0;
  v_picked integer := 0;
  v_explore_target integer;
  v_prog boolean;
  v_clusters text[] := array['action', 'drama', 'fantasy', 'scifi', 'comedy', 'dark'];
  v_strata text[] := array['head', 'mid', 'gems'];
  v_ci integer;
  v_si integer;
  v_min_s double precision;
  v_max_s double precision;
  v_mmr double precision;
  v_best_mmr double precision;
  v_max_ovl double precision;
  v_tags text[];
  v_slot text;
  r record;
  v_best record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  v_half := v_lim / 2;
  -- Deeper than v1 (v_lim per type) so the dealing policy has room to work;
  -- <= 60 rows for the default batch of 12.
  v_pool_lim := greatest(v_lim + 18, 24);
  -- Hard caps, scaled from the spec's <=4/12 cluster and <=2/12 franchise.
  v_cluster_cap := greatest(1, (v_lim * 4) / 12);
  v_franchise_cap := greatest(1, (v_lim * 2) / 12);

  select p.vector into v_profile
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_profile is not null then
    v_evidence := coalesce((v_profile->>'evidence')::double precision, 0);
    v_avoided := coalesce(v_profile->'avoided_tags', '[]'::jsonb);
    select coalesce(sqrt(sum(uv.uval * uv.uval)), 0)
      into v_unorm
    from (
      select value::double precision as uval
      from jsonb_each_text(v_profile->'vector')
    ) uv;
  end if;

  -- Explore/exploit split from evidence mass (new user -> 0.75 -> 9 of 12 explore).
  v_explore_ratio := greatest(0.25, 0.75 * exp(-v_evidence / 50.0));
  v_explore_slots := greatest(0, least(v_lim, round(v_lim * v_explore_ratio)::integer));
  v_exploit_slots := v_lim - v_explore_slots;

  create temporary table if not exists taste_deck_cand (
    media_type text not null,
    media_id integer not null,
    title text,
    cover_image_large text,
    cover_image_medium text,
    cover_image_color text,
    genres text[],
    average_score integer,
    format text,
    year integer,
    synopsis text,
    episodes integer,
    chapters integer,
    volumes integer,
    mirrored boolean,
    popularity integer,
    cluster text,
    stratum text,
    fit double precision default 0,
    ucb double precision default 1,
    slot text,
    slot_raw double precision,
    slot_score double precision,
    franchise text,
    top_tags text[],
    picked boolean not null default false,
    primary key (media_type, media_id)
  ) on commit drop;
  delete from taste_deck_cand where true; -- P0: pg_safeupdate blocks bare DELETE

  -- Realm Graph v1: families the user signaled in the last 30 days (explore
  -- family axis; see the boost application below the UCB computation).
  create temporary table if not exists taste_deck_signaled_families (
    family text primary key
  ) on commit drop;
  delete from taste_deck_signaled_families where true; -- pg_safeupdate

  -- Selection pool: identical eligibility to v1 (score >= 70, not adult, no
  -- Ecchi/Hentai, ancillary formats excluded, not in lists, no prior deck
  -- signal), mirrored-first pull, just deeper.
  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'ANIME', a.id,
    coalesce(nullif(a.title_english, ''), a.title_romaji),
    a.cover_image_large, a.cover_image_medium, a.cover_image_color,
    a.genres, a.average_score, a.format,
    coalesce(a.season_year, a.start_date_year),
    left(coalesce(a.description_normalized, ''), 300),
    a.episodes, null::integer, null::integer,
    (a.cover_image_large like '%/storage/v1/%'),
    coalesce(a.popularity, 0)
  from public.anime a
  where (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
    and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    and coalesce(a.average_score, 0) >= 70
    and a.cover_image_large is not null
    and not exists (
      select 1 from public.anime_user_lists ul
      where ul.user_id = v_uid::text
        and ul.anime_id = a.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'ANIME'
        and e.media_id = a.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )
  order by (a.cover_image_large like '%/storage/v1/%') desc, coalesce(a.popularity, 0) desc, a.id desc
  limit v_pool_lim;

  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'MANGA', m.id,
    coalesce(nullif(m.title_english, ''), m.title_romaji),
    m.cover_image_large, m.cover_image_medium, m.cover_image_color,
    m.genres, m.average_score, m.format,
    m.start_date_year,
    left(coalesce(m.description_normalized, ''), 300),
    null::integer, m.chapters, m.volumes,
    (m.cover_image_large like '%/storage/v1/%'),
    coalesce(m.popularity, 0)
  from public.manga m
  where (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
    and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    and coalesce(m.average_score, 0) >= 70
    and m.cover_image_large is not null
    and not exists (
      select 1 from public.manga_user_lists ul
      where ul.user_id = v_uid::text
        and ul.manga_id = m.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'MANGA'
        and e.media_id = m.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )
  order by (m.cover_image_large like '%/storage/v1/%') desc, coalesce(m.popularity, 0) desc, m.id desc
  limit v_pool_lim;

  update taste_deck_cand c
  set cluster = public._taste_genre_cluster(c.genres)
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

  -- Popularity strata over the pool (percent_rank ascending by popularity):
  -- head pr >= 0.9; gems pr < 0.4 with average_score >= 75; mid 0.1 <= pr < 0.6;
  -- anything left (bottom decile without the gems score, 0.4-0.6 without mid is
  -- impossible) -> 'tail' (only reachable via exploit or starvation fill).
  with s as (
    select
      c.media_type,
      c.media_id,
      percent_rank() over (order by c.popularity asc, c.media_id asc) as pr
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set stratum = case
    when s.pr >= 0.9 then 'head'
    when s.pr < 0.4 and c.average_score >= 75 then 'gems'
    when s.pr >= 0.1 and s.pr < 0.6 then 'mid'
    else 'tail'
  end
  from s
  where s.media_type = c.media_type
    and s.media_id = c.media_id;

  -- Exploit fit: cosine(user vector, title vector) in the shared space.
  -- The stored user vector is L2-normalized; v_unorm recomputes its true norm
  -- (jsonb rounding) so the cosine stays exact.
  if v_unorm > 0 then
    update taste_deck_cand c
    set fit = f.fit
    from (
      select
        c2.media_type,
        c2.media_id,
        case
          when max(v.l2_norm)::double precision > 0
            then least(greatest(
              coalesce(sum(uv.uval * v.w::double precision), 0.0)
                / (v_unorm * max(v.l2_norm)::double precision),
              -1.0), 1.0)
          else 0.0
        end as fit
      from taste_deck_cand c2
      left join public.media_tag_vectors v
        on v.media_type = c2.media_type
       and v.media_id = c2.media_id
      left join (
        select key, value::double precision as uval
        from jsonb_each_text(v_profile->'vector')
      ) uv on uv.key = v.tag_key
      group by c2.media_type, c2.media_id
    ) f
    where f.media_type = c.media_type
      and f.media_id = c.media_id;
  end if;

  -- Explore UCB: mean over the title's deck-stats keys (rank >= 40 tags plus
  -- 'genre:' keys) of (alpha+1)/(alpha+beta+2) + 0.5/sqrt(alpha+beta+1);
  -- missing stat rows -> alpha = beta = 0 (Beta(1,1) prior baked in).
  update taste_deck_cand c
  set ucb = x.ucb
  from (
    select
      c2.media_type,
      c2.media_id,
      avg(
        (coalesce(s.alpha, 0)::double precision + 1.0)
          / (coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 2.0)
        + 0.5 / sqrt(coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 1.0)
      ) as ucb
    from taste_deck_cand c2
    left join lateral (
      select k.tag_key
      from public._taste_deck_title_tag_keys(c2.media_type, c2.media_id) k
    ) keys on true
    left join public.taste_tag_stats s
      on s.user_id = v_uid
     and s.tag_key = keys.tag_key
    group by c2.media_type, c2.media_id
  ) x
  where x.media_type = c.media_type
    and x.media_id = c.media_id;

  -- Realm Graph v1 (family axis): collect the families signaled in the last
  -- 30 days, then lift explore scoring x1.5 for candidates whose top-realm
  -- family is untouched. Runs AFTER the base UCB update so slot_raw records
  -- the boosted value; candidates with no realm row keep their base UCB.
  insert into taste_deck_signaled_families (family)
  select distinct rm.family
  from public.taste_signal_events e
  join public.media_realm_tier t
    on t.media_type = e.media_type
   and t.media_id = e.media_id
  join public.realm_meta rm on rm.realm = t.realm
  where e.user_id = v_uid
    and e.event_type <> 'deck_pass'
    and e.created_at > now() - interval '30 days'
  on conflict (family) do nothing;

  update taste_deck_cand c
  set ucb = c.ucb * 1.5
  where exists (
    select 1
    from public.media_realm_tier t
    join public.realm_meta rm on rm.realm = t.realm
    where t.media_type = c.media_type
      and t.media_id = c.media_id
      and not exists (
        select 1
        from taste_deck_signaled_families sf
        where sf.family = rm.family
      )
  );

  -- Slot candidates. Buffers (+6 each side) give MMR and the hard caps room
  -- to skip without starving the batch.
  with ranked as (
    select
      c.media_type,
      c.media_id,
      c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) as es,
      row_number() over (
        order by c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) desc,
                 c.popularity desc, c.media_id desc
      ) as rn
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set slot = 'exploit',
      slot_raw = rk.es
  from ranked rk
  where rk.media_type = c.media_type
    and rk.media_id = c.media_id
    and rk.rn <= v_exploit_slots + 6;

  -- Stratified explore: round-robin over 6 clusters x 3 strata, best UCB per
  -- cell, skipping cells that run dry. A title already slotted for exploit is
  -- not double-dealt as explore.
  v_explore_target := v_explore_slots + 6;
  <<explore_loop>>
  while (select count(*) from taste_deck_cand where slot = 'explore') < v_explore_target loop
    v_prog := false;
    for v_ci in 1..6 loop
      for v_si in 1..3 loop
        select c2.media_type, c2.media_id, c2.ucb
          into r
        from taste_deck_cand c2
        where c2.slot is null
          and c2.cluster = v_clusters[v_ci]
          and c2.stratum = v_strata[v_si]
        order by c2.ucb desc, c2.popularity desc, c2.media_id desc
        limit 1;
        if found then
          update taste_deck_cand c
          set slot = 'explore', slot_raw = r.ucb
          where c.media_type = r.media_type
            and c.media_id = r.media_id;
          v_prog := true;
          exit explore_loop when (select count(*) from taste_deck_cand where slot = 'explore') >= v_explore_target;
        end if;
      end loop;
    end loop;
    exit when not v_prog;
  end loop;

  -- Negative-space probe: p = 0.10 per batch, from the *avoided* list only.
  if random() < 0.10 and coalesce(jsonb_array_length(v_avoided), 0) > 0 then
    select c2.media_type, c2.media_id, c2.ucb
      into r
    from taste_deck_cand c2
    where c2.slot is null
      and exists (
        select 1
        from public.anime_tags at
        join public.tags t on t.id = at.tag_id
        where c2.media_type = 'ANIME'
          and at.anime_id = c2.media_id
          and coalesce(at.rank, 0) >= 60
          and v_avoided ? lower(t.name)
        union all
        select 1
        from public.manga_tags mt
        join public.tags t on t.id = mt.tag_id
        where c2.media_type = 'MANGA'
          and mt.manga_id = c2.media_id
          and coalesce(mt.rank, 0) >= 60
          and v_avoided ? lower(t.name)
      )
    order by c2.ucb desc, c2.popularity desc, c2.media_id desc
    limit 1;
    if found then
      -- Drop the weakest explore pick; the probe takes its slot.
      update taste_deck_cand c
      set slot = null, slot_raw = null
      where c.slot = 'explore'
        and (c.media_type, c.media_id) = (
          select c3.media_type, c3.media_id
          from taste_deck_cand c3
          where c3.slot = 'explore'
          order by c3.slot_raw asc, c3.popularity asc, c3.media_id asc
          limit 1
        );
      update taste_deck_cand c
      set slot = 'explore', slot_raw = r.ucb
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
    end if;
  end if;

  -- Franchise labels: connected components over media_relations restricted to
  -- pool titles (same approach as the profile recompute).
  with recursive
  nodes as (
    select c.media_type, c.media_id from taste_deck_cand c
  ),
  edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from edges
    union
    select b_t, b_i, a_t, a_i from edges
  ),
  reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from nodes n
    union
    select r2.s_t, r2.s_i, a.nt, a.ni
    from reach r2
    join adj a on a.t = r2.t and a.i = r2.i
  ),
  labels as (
    select r2.t as media_type, r2.i as media_id,
           min(r2.s_t || ':' || r2.s_i::text) as label
    from reach r2
    group by r2.t, r2.i
  )
  update taste_deck_cand c
  set franchise = coalesce(l.label, c.media_type || ':' || c.media_id::text)
  from labels l
  where l.media_type = c.media_type
    and l.media_id = c.media_id;

  update taste_deck_cand c
  set franchise = c.media_type || ':' || c.media_id::text
  where c.franchise is null;

  -- MMR overlap space: each title's top 15 tags by |w|.
  update taste_deck_cand c
  set top_tags = (
    select array_agg(v.tag_key)
    from (
      select v2.tag_key
      from public.media_tag_vectors v2
      where v2.media_type = c.media_type
        and v2.media_id = c.media_id
      order by abs(v2.w) desc
      limit 15
    ) v
  )
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

  -- slot_score: min-max normalize per slot group so UCB (0..~1.5) and cosine
  -- exploit scores (-1..1) compete on a shared 0..1 scale. Degenerate group:
  -- all-equal positives -> 1.0, all-zero -> 0.0.
  for v_slot in select 'exploit' union select 'explore' loop
    select min(c.slot_raw), max(c.slot_raw)
      into v_min_s, v_max_s
    from taste_deck_cand c
    where c.slot = v_slot;
    if v_max_s is null then
      continue;
    elsif v_max_s > v_min_s then
      update taste_deck_cand c
      set slot_score = (c.slot_raw - v_min_s) / (v_max_s - v_min_s)
      where c.slot = v_slot;
    elsif v_max_s > 0 then
      update taste_deck_cand c set slot_score = 1.0 where c.slot = v_slot;
    else
      update taste_deck_cand c set slot_score = 0.0 where c.slot = v_slot;
    end if;
  end loop;

  -- Half anime / half manga with v1 cross-fill on starvation.
  select
    count(*) filter (where c.media_type = 'ANIME'),
    count(*) filter (where c.media_type = 'MANGA')
  into v_a_count, v_m_count
  from taste_deck_cand c;
  v_a_take := least(v_a_count, v_lim - least(v_m_count, v_half));
  v_m_take := least(v_m_count, v_lim - v_a_take);

  -- MMR assembly (lambda = 0.7) with hard caps.
  while v_picked < v_lim loop
    v_best := null;
    v_best_mmr := null;
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.cluster = r.cluster
      ) >= v_cluster_cap;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.franchise = r.franchise
      ) >= v_franchise_cap;

      v_tags := r.top_tags;
      select coalesce(max(o.ovl), 0.0)
        into v_max_ovl
      from (
        select (
          select count(*)::double precision
          from (select unnest(v_tags) intersect select unnest(p2.top_tags)) i
        ) / nullif((
          select count(*)::double precision
          from (select unnest(v_tags) union select unnest(p2.top_tags)) u
        ), 0) as ovl
        from taste_deck_cand p2
        where p2.picked
      ) o;

      v_mmr := 0.7 * r.slot_score - 0.3 * coalesce(v_max_ovl, 0.0);
      if v_best_mmr is null or v_mmr > v_best_mmr then
        v_best := r;
        v_best_mmr := v_mmr;
      end if;
    end loop;
    exit when v_best is null;

    update taste_deck_cand c
    set picked = true
    where c.media_type = v_best.media_type
      and c.media_id = v_best.media_id;
    if v_best.media_type = 'ANIME' then
      v_pa := v_pa + 1;
    else
      v_pm := v_pm + 1;
    end if;
    v_picked := v_picked + 1;
  end loop;

  -- Starvation fill 1: remaining slotted candidates, caps relaxed, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Starvation fill 2: unslotted pool in v1 mirrored-first order, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where not c.picked
      order by c.mirrored desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Final output keeps v1's mirrored-first ordering and the 050000 meta strip.
  return query
  select
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.cover_image_medium,
    c.cover_image_color,
    c.genres,
    c.average_score,
    c.format,
    c.year,
    c.synopsis,
    c.episodes,
    c.chapters,
    c.volumes,
    case
      when c.media_type = 'ANIME' and c.format = 'TV'
        then public._taste_deck_seasons_count(c.media_id)
      else null
    end as seasons_count,
    avail.has_dub,
    avail.has_sub
  from taste_deck_cand c
  left join lateral (
    select
      bool_or(exists (
        select 1
        from unnest(pa.audio_langs) as lang
        where lower(trim(lang)) not in ('', 'ja', 'jpn', 'japanese', 'unknown')
      )) as has_dub,
      bool_or(coalesce(array_length(pa.subtitle_langs, 1), 0) > 0) as has_sub
    from public.provider_availability pa
    where pa.media_type = c.media_type
      and pa.media_id = c.media_id
  ) avail on true
  where c.picked
  order by c.mirrored desc, c.popularity desc, c.media_id desc;
end;
$$;

-- recommend_ids_similar_to_seeds: latest definition 20260806020000_serving_hardening_v1.sql; 2 anime/manga/matview references, 1 visibility predicates added
create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_has_pre boolean;
begin
  -- Gimmick calls: the baked score already contains the penalty term and the
  -- stored top-30 was selected under penalty ordering — serve them live.
  if coalesce(p_allow_gimmicks, false) then
    return query
    select l.media_id, l.overlap_count, l.score
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l
    where not exists (
      -- Own-franchise exclusion (20260806020000): never serve a member of a
      -- seed's OWN franchise component (sequel-in-rail / recap-in-rail).
      -- Singleton candidates (no component row) share a cluster with no seed.
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = l.media_id
        and ss.media_id = any(p_seed_ids)
    );
    return;
  end if;

  select exists (
    select 1 from public.media_similar_titles s
    where s.seed_media_type = p_media_type
      and p_seed_ids is not null
      and s.seed_media_id = any(p_seed_ids)
  ) into v_has_pre;

  -- No precomputed seed at all -> degrade to the old live scorer (never empty
  -- just because the store hasn't met this seed). Mixed seeds: precomputed
  -- only — the hot path never blocks on the live scorer.
  if not v_has_pre then
    return query
    select l.media_id, l.overlap_count, l.score
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l
    where not exists (
      -- Own-franchise exclusion (20260806020000): never serve a member of a
      -- seed's OWN franchise component (sequel-in-rail / recap-in-rail).
      -- Singleton candidates (no component row) share a cluster with no seed.
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = l.media_id
        and ss.media_id = any(p_seed_ids)
    );
    return;
  end if;

  return query
  with req as (
    select greatest(1, least(coalesce(p_limit, 10), 50))::int as lim
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  hits as (
    select s.media_id as cand_id, s.overlap_count as oc, s.score as sc
    from public.media_similar_titles s
    where s.seed_media_type = p_media_type
      and s.seed_media_id = any(p_seed_ids)
      and not (s.media_id = any(p_seed_ids))
  ),
  blended as (
    -- Multi-seed blend: sum score per candidate (a title near several seeds
    -- rises), keep max overlap_count for the reporting column.
    select h.cand_id, max(h.oc)::integer as oc, sum(h.sc)::real as sc
    from hits h
    group by h.cand_id
  ),
  visible as (
    -- Per-user exclusion BEFORE franchise dedupe (live-scorer order: the
    -- user_lists filter sits inside `ranked`, franchise DISTINCT ON after),
    -- so an excluded best member yields its franchise slot to the next-best
    -- member instead of erasing the franchise from the results.
    select b.cand_id, b.oc, b.sc,
           coalesce(a.popularity, m.popularity, 0) as pop
    from blended b
    left join public.anime a on p_media_type = 'ANIME' and a.id = b.cand_id
    left join public.manga m on p_media_type = 'MANGA' and m.id = b.cand_id
    where coalesce(case when p_media_type = 'ANIME' then a.catalogue_visibility = 'visible'
                        else m.catalogue_visibility = 'visible' end, true)
      and not exists (
      select 1 from public.user_lists ul
      where (select me.user_id from me) is not null
        and ul.user_id = (select me.user_id from me)
        and ul.media_type = case when p_media_type = 'ANIME' then 'anime' else 'manga' end
        and ul.media_id = b.cand_id
    )
    -- Own-franchise exclusion (20260806020000): the read-time filter that
    -- kills sequel-in-rail and recap-in-rail for all seeds WITHOUT a store
    -- rebuild — store rows carry no stage marker, so this covers Stage A
    -- edge rows and Stage B cosine rows alike. A candidate sharing a
    -- franchise component with ANY seed is dropped; singleton candidates
    -- (no component row) are kept: they share a cluster with no seed, and
    -- seeds themselves are already excluded in `hits`.
    and not exists (
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = b.cand_id
        and ss.media_id = any(p_seed_ids)
    )
  ),
  franchise_deduped as (
    -- 20260804140000 (finding 3): each per-seed store is franchise-deduped at
    -- build time, but a multi-seed blend could still carry two members of the
    -- same franchise (each seed contributed its own best member). Keep only
    -- the highest-blended entry per component; singletons label as themselves
    -- (collision-free: a component's min-member label is itself a member).
    -- Single-seed calls collapse nothing here — the store already deduped.
    select distinct on (coalesce(fc.component_label, v.cand_id))
      v.cand_id, v.oc, v.sc, v.pop
    from visible v
    left join public.media_franchise_components fc
      on fc.media_type = p_media_type and fc.media_id = v.cand_id
    order by coalesce(fc.component_label, v.cand_id),
             v.sc desc, v.pop desc, v.cand_id desc
  )
  select d.cand_id, d.oc, d.sc
  from franchise_deduped d
  order by d.sc desc, d.pop desc, d.cand_id desc
  limit (select req.lim from req);
end;
$$;

-- _recommend_ids_similar_to_seeds_live: latest definition 20260804130000_media_similar_titles_precompute.sql; 8 anime/manga/matview references, 2 visibility predicates added
create or replace function public._recommend_ids_similar_to_seeds_live(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language sql
stable
security definer
set search_path = public, extensions
as $function$
  with recursive req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  seed_vec as (
    -- Seed set vector = element-wise average of the seed title vectors.
    select v.tag_key, avg(v.w)::double precision as w
    from public.media_tag_vectors v
    where v.media_type = p_media_type
      and p_seed_ids is not null
      and v.media_id = any(p_seed_ids)
    group by v.tag_key
  ),
  seed_norm as (
    select nullif(sqrt(sum(sv.w * sv.w)), 0)::double precision as n
    from seed_vec sv
  ),
  seed_tier_rank as (
    -- Highest tier among seeds (canon 4 / acclaimed 3 / solid 2 / tail 1).
    select max(case t.tier
                 when 'canon' then 4
                 when 'acclaimed' then 3
                 when 'solid' then 2
                 else 1
               end) as r
    from public.media_realm_tier t
    where t.media_type = p_media_type
      and p_seed_ids is not null
      and t.media_id = any(p_seed_ids)
  ),
  seed_realm_w as (
    -- S: the seed realm set WITH weights. No entry cliff (the old >= 0.35 /
    -- >= 0.25 tests are weight terms now — see cand_realm_cost.mem_term).
    select m.realm, min(m.family) as family, max(m.weight)::double precision as w
    from public.media_realm_membership_effective m
    where m.media_type = p_media_type
      and p_seed_ids is not null
      and m.media_id = any(p_seed_ids)
    group by m.realm
  ),
  seed_families as (
    select distinct s.family from seed_realm_w s where s.family is not null
  ),
  seed_rails as (
    -- curated_rails rails containing any seed (items key on AniList ids).
    select distinct i.rail_id
    from public.curated_rail_items i
    where p_seed_ids is not null
      and (
        (p_media_type = 'ANIME' and i.media_type = 'ANIME' and i.anilist_id in (
          select a2.anilist_id from public.anime a2 where a2.id = any(p_seed_ids)))
        or
        (p_media_type = 'MANGA' and i.media_type = 'MANGA' and i.anilist_id in (
          select m2.anilist_id from public.manga m2 where m2.id = any(p_seed_ids)))
      )
  ),
  rail_cands_anime as (
    select distinct a3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.anime a3 on a3.anilist_id = i.anilist_id
    where i.media_type = 'ANIME'
      and p_media_type = 'ANIME'
  ),
  rail_cands_manga as (
    select distinct m3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.manga m3 on m3.anilist_id = i.anilist_id
    where i.media_type = 'MANGA'
      and p_media_type = 'MANGA'
  ),
  seed_genres_anime as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.anime a
    cross join unnest(coalesce(a.genres, '{}'::text[])) as g
    where p_media_type = 'ANIME'
      and p_seed_ids is not null
      and a.id = any(p_seed_ids)
  ),
  seed_genres_manga as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.manga m
    cross join unnest(coalesce(m.genres, '{}'::text[])) as g
    where p_media_type = 'MANGA'
      and p_seed_ids is not null
      and m.id = any(p_seed_ids)
  ),
  cand_cos as (
    -- Full cosine over the shared vector space. No popularity/score/recency.
    select
      v.media_id,
      count(*)::integer as overlap_count,
      sum(v.w::double precision * sv.w)
        / ((select n from seed_norm) * max(v.l2_norm)::double precision) as similarity
    from public.media_tag_vectors v
    join seed_vec sv on sv.tag_key = v.tag_key
    where v.media_type = p_media_type
      and not (v.media_id = any(p_seed_ids))
    group by v.media_id
    having max(v.l2_norm) > 0
  ),
  cand_top_realm as (
    -- Candidate top realm = its highest-weight effective membership row
    -- (deterministic; same ordering as the media_realm_tier build).
    select s.media_id, s.realm, s.family
    from (
      select
        m.media_id,
        m.realm,
        m.family,
        row_number() over (
          partition by m.media_id
          order by m.weight desc, m.realm asc
        ) as rn
      from public.media_realm_membership_effective m
      join cand_cos cc on cc.media_id = m.media_id
      where m.media_type = p_media_type
    ) s
    where s.rn = 1
  ),
  cand_shared as (
    -- Per-candidate shared-realm strength: max over shared realms of
    -- least(seed weight, candidate weight). Set-based on purpose — the
    -- effective view's FULL OUTER JOIN defeats index probes, so correlated
    -- per-candidate subqueries would rescan it per row.
    select
      cm.media_id,
      max(least(s.w, cm.weight::double precision)) as shared_w
    from public.media_realm_membership_effective cm
    join seed_realm_w s on s.realm = cm.realm
    join cand_cos cc on cc.media_id = cm.media_id
    where cm.media_type = p_media_type
    group by cm.media_id
  ),
  cand_family as (
    -- Candidates holding ANY realm whose family matches a seed family.
    select distinct f.media_id
    from public.media_realm_membership_effective f
    join seed_families sf on sf.family = f.family
    join cand_cos cc on cc.media_id = f.media_id
    where f.media_type = p_media_type
  ),
  top_adj as (
    -- Per realm: max affinity to the seed realm set (40x40 space — tiny).
    select e.realm_a as realm, max(e.affinity)::double precision as aff
    from public.realm_affinity_effective e
    join seed_realm_w s on s.realm = e.realm_b
    group by e.realm_a
  ),
  cand_realm_cost as (
    -- Gates -> costs (spec §3.2). realm_mult NULL = the only realm hard
    -- exclusion left: no shared family AND top-realm affinity < 0.6.
    -- Ladder: top realm in S x1.0 · adjacent (affinity >= 0.6) x0.85 ·
    -- same family only x0.65. Seeds with no realm data: neutral, no exclusion.
    select
      cc.media_id,
      case
        when not exists (select 1 from seed_realm_w) then 1.0
        when ctr.media_id is null then null
        when s_top.realm is not null then 1.0
        when coalesce(adj.aff, 0) >= 0.6 then 0.85
        when cf.media_id is not null then 0.65
        else null
      end::double precision as realm_mult,
      case
        when not exists (select 1 from seed_realm_w) then 1.0
        else
          -- The converted membership cliffs (old >= 0.35 / >= 0.25 entry
          -- tests): full contribution at the old 0.35 anchor, smooth ramp
          -- below, floor 0.5 (adjacency/family entrants with no shared realm).
          0.5 + 0.5 * least(1.0, coalesce(cs.shared_w, 0) / 0.35)
      end::double precision as mem_term
    from cand_cos cc
    left join cand_top_realm ctr on ctr.media_id = cc.media_id
    left join seed_realm_w s_top on s_top.realm = ctr.realm
    left join top_adj adj on adj.realm = ctr.realm
    left join cand_family cf on cf.media_id = cc.media_id
    left join cand_shared cs on cs.media_id = cc.media_id
  ),
  anime_pen as (
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_pen as (
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id
  ),
  anime_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%director%'
          and ys.role ilike '%director%'
      ) as shared_creator,
      exists (
        select 1
        from public.anime_studios xs
        join public.anime_studios ys
          on ys.studio_id = xs.studio_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
      ) as shared_studio,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%creator%'
          and ys.role ilike '%creator%'
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'ANIME'
  ),
  manga_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
          and xs.role ilike '%story%'
          and ys.role ilike '%story%'
      ) as shared_creator,
      false as shared_studio,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'MANGA'
  ),
  ranked as (
    select
      p_media_type as mt,
      a.id as media_id,
      cc.overlap_count as overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(ac.shared_creator, false)::int
            + 0.15 * coalesce(ac.shared_studio, false)::int
            + 0.5 * coalesce(ac.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
          * crc.realm_mult
          * crc.mem_term
        + case when (select allow_gimmicks from req) then 0.0
               else coalesce(ap.penalty, 0)::double precision end
      )::real as score,
      coalesce(a.popularity, 0) as popularity
    from cand_cos cc
    join public.anime a on a.id = cc.media_id
    join cand_realm_cost crc on crc.media_id = cc.media_id
    left join anime_craft ac on ac.media_id = cc.media_id
    left join anime_pen ap on ap.media_id = cc.media_id
    left join rail_cands_anime rc on rc.media_id = cc.media_id
    where p_media_type = 'ANIME'
      and cc.similarity is not null
      and a.cover_image_large is not null
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_anime), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(a.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_anime)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_anime), 0) >= 4 then 2
              else 1
            end
      )
      -- Realm hard exclusion (b): no shared family AND affinity < 0.6.
      -- Everything softer is a cost inside cand_realm_cost.
      and crc.realm_mult is not null
      -- Realm hard exclusion (a): tier distance > 1. Missing candidate tier
      -- counts as 'solid' (rank 2) so backlog titles are demotable, not dropped.
      and (
        (select r from seed_tier_rank) is null
        or abs(
             coalesce((
               select case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
               from public.media_realm_tier ct
               where ct.media_type = p_media_type
                 and ct.media_id = a.id
             ), 2)
             - (select r from seed_tier_rank)
           ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000): within-realm tier
        -- measures *good for its kind*; cross-realm gates to legend-tier
        -- require absolute merit. Non-canon seeds: no floor (tier
        -- compatibility alone). canon_seed.media_id = AniList id (150000).
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(a.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = a.anilist_id
            and cs.blessed = true
        )
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      p_media_type,
      m.id,
      cc.overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(mc.shared_creator, false)::int
            + 0.15 * coalesce(mc.shared_studio, false)::int
            + 0.5 * coalesce(mc.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
          * crc.realm_mult
          * crc.mem_term
        + case when (select allow_gimmicks from req) then 0.0
               else coalesce(mp.penalty, 0)::double precision end
      )::real,
      coalesce(m.popularity, 0)
    from cand_cos cc
    join public.manga m on m.id = cc.media_id
    join cand_realm_cost crc on crc.media_id = cc.media_id
    left join manga_craft mc on mc.media_id = cc.media_id
    left join manga_pen mp on mp.media_id = cc.media_id
    left join rail_cands_manga rc on rc.media_id = cc.media_id
    where p_media_type = 'MANGA'
      and cc.similarity is not null
      and m.cover_image_large is not null
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_manga), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(m.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_manga)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_manga), 0) >= 4 then 2
              else 1
            end
      )
      -- Realm hard exclusion (b): no shared family AND affinity < 0.6.
      and crc.realm_mult is not null
      -- Realm hard exclusion (a): tier distance > 1, missing tier = 'solid'.
      and (
        (select r from seed_tier_rank) is null
        or abs(
             coalesce((
               select case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
               from public.media_realm_tier ct
               where ct.media_type = p_media_type
                 and ct.media_id = m.id
             ), 2)
             - (select r from seed_tier_rank)
           ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000), manga branch.
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(m.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = m.anilist_id
            and cs.blessed = true
        )
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  -- Franchise clusters over gate-passing candidates: connected components of
  -- media_relations (UNION keeps the recursion cycle-safe), labeled by the
  -- lexicographically smallest member key. Titles with no relations are
  -- singleton clusters via the coalesce in the final select.
  fr_nodes as (
    select ranked.mt as media_type, ranked.media_id from ranked
  ),
  fr_edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join fr_nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join fr_nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  fr_adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from fr_edges
    union
    select b_t, b_i, a_t, a_i from fr_edges
  ),
  fr_reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from fr_nodes n
    union
    select r.s_t, r.s_i, a.nt, a.ni
    from fr_reach r
    join fr_adj a on a.t = r.t and a.i = r.i
  ),
  fr_labels as (
    select r.t as media_type, r.i as media_id,
           min(r.s_t || ':' || r.s_i::text) as label
    from fr_reach r
    group by r.t, r.i
  )
  -- <= 1 candidate per franchise cluster: DISTINCT ON keeps the
  -- highest-scoring entry of each cluster (ties: popularity, then media_id).
  select d.media_id, d.overlap_count, d.score
  from (
    select distinct on (coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text))
      ranked.media_id,
      ranked.overlap_count,
      ranked.score,
      ranked.popularity
    from ranked
    left join fr_labels fr
      on fr.media_type = ranked.mt
     and fr.media_id = ranked.media_id
    order by coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text),
             ranked.score desc,
             ranked.popularity desc,
             ranked.media_id desc
  ) d
  order by d.score desc, d.popularity desc, d.media_id desc
  limit (select lim from req);
$function$;

-- media_similar_v1: latest definition 20261103100100_media_similar_v1.sql; 2 anime/manga/matview references, 2 visibility predicates added
create or replace function public.media_similar_v1(p_media_type text, p_media_id integer, p_limit integer default 12)
returns table (
  media_type text, rank integer, similarity_score real,
  id integer, title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episodes integer, chapters integer, volumes integer,
  season text, season_year integer, start_date_year integer,
  next_episode_number integer, next_airing_at timestamptz,
  average_score integer, popularity integer, trending integer, favourites integer, genres text[],
  is_adult boolean, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_limit integer := least(30, greatest(1, coalesce(p_limit, 12)));
  -- A few extra ids so the adult/cover filter rarely leaves the rail short.
  v_fetch integer := least(50, least(30, greatest(1, coalesce(p_limit, 12))) + 8);
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if p_media_id is null or p_media_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_media_id must be a positive id';
  end if;

  if v_type = 'ANIME' then
    return query
    select 'ANIME'::text, (row_number() over (order by r.ord))::integer, r.score,
           a.id, a.title_english, a.title_romaji, a.title_native,
           a.cover_image_large, a.cover_image_medium, a.banner_image,
           a.format, a.status, a.episodes, null::integer, null::integer,
           a.season, a.season_year, a.start_date_year,
           a.next_episode_number, a.next_airing_at,
           a.average_score, a.popularity, a.trending, a.favourites, a.genres,
           a.is_adult, a.created_at, a.updated_at
    from public.recommend_ids_similar_to_seeds('ANIME', array[p_media_id], v_fetch, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    join public.anime a on a.id = r.media_id
    where a.id <> p_media_id
      and (coalesce(a.is_adult, false) = false and a.catalogue_visibility = 'visible')
      and nullif(btrim(a.cover_image_large), '') is not null
    order by r.ord
    limit v_limit;
  else
    return query
    select 'MANGA'::text, (row_number() over (order by r.ord))::integer, r.score,
           m.id, m.title_english, m.title_romaji, m.title_native,
           m.cover_image_large, m.cover_image_medium, null::text,
           m.format, m.status, null::integer, m.chapters, m.volumes,
           null::text, null::integer, m.start_date_year,
           null::integer, null::timestamptz,
           m.average_score, m.popularity, m.trending, m.favourites, m.genres,
           m.is_adult, m.created_at, m.updated_at
    from public.recommend_ids_similar_to_seeds('MANGA', array[p_media_id], v_fetch, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    join public.manga m on m.id = r.media_id
    where m.id <> p_media_id
      and (coalesce(m.is_adult, false) = false and m.catalogue_visibility = 'visible')
      and nullif(btrim(m.cover_image_large), '') is not null
    order by r.ord
    limit v_limit;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
