-- PREPARED ONLY (W4): owner approval required to apply.
-- W4 (tracker gaps): additive search_{anime,manga}_page_v2 return {"items": [...v1 rows...],
-- "hidden_adult": n|null}. v1 (the staged bodies of 20261109200000) is NOT touched. Adult =
-- is_adult is true or genres @> {Hentai}. pg_trgm.similarity_threshold stays 0.35 (as v1).
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

CREATE FUNCTION public._search_hidden_adult_anime_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean, p_hidden_gems boolean, p_airing_only boolean, p_season text, p_season_year integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Bounded (100) count of adult titles that pass every OTHER filter of search_anime_page and its
-- text-match predicate (strong stage OR trigram stage). Ecchi is not a condition. Internal only.
declare
  v_count integer;
begin
  execute $count$
select count(*)::int from (
  select 1
  from (
    select
      a.genres,
      a.is_adult,
      lower(coalesce(a.title_english, '')) as title_english_norm,
      lower(coalesce(a.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(a.title_native, '')) as title_native_norm,
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob
    from public.anime a
    where
      (a.is_adult is true or a.genres @> array['Hentai']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce($2, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce($3, false) or coalesce(a.season_year, a.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($4, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce($5, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce($6, false) or a.status = 'RELEASING')
      and ($7 is null or a.season = $7)
      and ($8 is null or a.season_year = $8)
  ) b
  where
      (
        nullif(lower(trim(coalesce($1, ''))), '') is not null
        and (
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
          or (
            length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
          )
        )
      )
  limit 100
) s
$count$ into v_count using p_query, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year;
  return coalesce(v_count, 0);
end;
$function$;

CREATE FUNCTION public._search_hidden_adult_manga_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean, p_hidden_gems boolean)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Bounded (100) count of adult titles that pass every OTHER filter of search_manga_page and its
-- text-match predicate (strong stage OR trigram stage). Ecchi is not a condition. Internal only.
declare
  v_count integer;
begin
  execute $count$
select count(*)::int from (
  select 1
  from (
    select
      m.genres,
      m.is_adult,
      lower(coalesce(m.title_english, '')) as title_english_norm,
      lower(coalesce(m.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(m.title_native, '')) as title_native_norm,
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob
    from public.manga m
    where
      (m.is_adult is true or m.genres @> array['Hentai']::text[])
      and (not coalesce($2, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce($3, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($4, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce($5, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ) b
  where
      (
        nullif(lower(trim(coalesce($1, ''))), '') is not null
        and (
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
          or (
            length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
          )
        )
      )
  limit 100
) s
$count$ into v_count using p_query, p_trending, p_new_season, p_classics, p_hidden_gems;
  return coalesce(v_count, 0);
end;
$function$;

CREATE FUNCTION public.search_anime_page_v2(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- {"items": <search_anime_page rows in v1 order>, "hidden_adult": <0..100> | null}. v1 does all
-- ranking, filtering and paging; hidden_adult is only computed for page 1 of a >= 2 character query.
declare
  v_items jsonb;
  v_hidden integer := null;
begin
  select coalesce(jsonb_agg(to_jsonb(r) - 'ordinality' order by r.ordinality), '[]'::jsonb)
    into v_items
    from public.search_anime_page(p_query, p_limit, p_cursor_rank, p_cursor_popularity, p_cursor_id, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year) with ordinality r;
  if p_cursor_id is null and length(btrim(coalesce(p_query, ''))) >= 2 then
    v_hidden := public._search_hidden_adult_anime_v1(p_query, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year);
  end if;
  return jsonb_build_object('items', v_items, 'hidden_adult', v_hidden);
end;
$function$;

CREATE FUNCTION public.search_manga_page_v2(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- {"items": <search_manga_page rows in v1 order>, "hidden_adult": <0..100> | null}. v1 does all
-- ranking, filtering and paging; hidden_adult is only computed for page 1 of a >= 2 character query.
declare
  v_items jsonb;
  v_hidden integer := null;
begin
  select coalesce(jsonb_agg(to_jsonb(r) - 'ordinality' order by r.ordinality), '[]'::jsonb)
    into v_items
    from public.search_manga_page(p_query, p_limit, p_cursor_rank, p_cursor_popularity, p_cursor_id, p_trending, p_new_season, p_classics, p_hidden_gems) with ordinality r;
  if p_cursor_id is null and length(btrim(coalesce(p_query, ''))) >= 2 then
    v_hidden := public._search_hidden_adult_manga_v1(p_query, p_trending, p_new_season, p_classics, p_hidden_gems);
  end if;
  return jsonb_build_object('items', v_items, 'hidden_adult', v_hidden);
end;
$function$;

revoke all on function public._search_hidden_adult_anime_v1(text,boolean,boolean,boolean,boolean,boolean,text,integer), public._search_hidden_adult_manga_v1(text,boolean,boolean,boolean,boolean) from public, anon, authenticated;
revoke all on function public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer), public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) from public;
grant execute on function public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer), public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Import staging: a match to an adult catalogue row becomes 'unmatched' with the stable detail
-- code ADULT_NOT_LISTED (no new disposition value: TestFlight 25 decodes a closed enum).
-- The trigger covers every staging path (prepare_import_chunk_v2 insert and its ON CONFLICT
-- update, manual mapping, re-review). Rows already applied/undone ('added','updated','unchanged',
-- 'pending','conflict', ...) are outside the WHEN clause and are never touched.
-- Legacy apply_import_chunk_v1 (series_foundation_v1 off) is out of scope.
create function public._import_item_adult_guard_v1() returns trigger
 language plpgsql
 set search_path to 'public', 'extensions'
as $function$
declare
  v_adult boolean;
begin
  if new.medium = 'anime' then
    select (a.is_adult is true or a.genres @> array['Hentai']::text[]) into v_adult from public.anime a where a.id = new.media_id;
  else
    select (m.is_adult is true or m.genres @> array['Hentai']::text[]) into v_adult from public.manga m where m.id = new.media_id;
  end if;
  if coalesce(v_adult, false) then
    new.disposition := 'unmatched';
    new.detail := 'ADULT_NOT_LISTED: 18+ title, not listed in Kuro';
    new.media_id := null;
    new.identity_resolved := false;
    new.manual_resolved := false;
    new.current_values := null;
    new.changed_fields := '[]'::jsonb;
    new.expected_revision := null;
    new.expected_lifecycle := null;
    new.baseline_tombstones := '[]'::jsonb;
  end if;
  return new;
end;
$function$;
revoke all on function public._import_item_adult_guard_v1() from public, anon, authenticated;

drop trigger if exists library_import_items_adult_guard_v1 on public.library_import_items;
create trigger library_import_items_adult_guard_v1
  before insert or update of media_id, disposition on public.library_import_items
  for each row
  when (new.media_id is not null and new.disposition in ('new', 'existing', 'changes'))
  execute function public._import_item_adult_guard_v1();

-- Same keys and filters as before, plus adult_not_listed.
create or replace function public._import_v2_counts(p_job uuid) returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'extensions'
as $function$
begin
  return (
    select jsonb_build_object(
      'added', count(*) filter (where disposition = 'added'),
      'updated', count(*) filter (where disposition = 'updated'),
      'unchanged', count(*) filter (where disposition = 'unchanged'),
      'conflict', count(*) filter (where disposition in ('conflict', 'source_changed')),
      'unmatched', count(*) filter (where disposition = 'unmatched'),
      'invalid', count(*) filter (where disposition = 'invalid'),
      'pending', count(*) filter (where not terminal and disposition in ('new', 'existing', 'changes', 'pending')),
      'adult_not_listed', count(*) filter (where disposition = 'unmatched' and detail like 'ADULT\_NOT\_LISTED:%')
    )
    from public.library_import_items where job_id = p_job
  );
end;
$function$;

notify pgrst, 'reload schema';
commit;
