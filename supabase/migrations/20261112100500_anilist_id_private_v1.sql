-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 15d). NOT applied.
--
-- AniList ids leave public reads. anilist_id stays in the tables (it is the Wikidata / ANN crosswalk key and the
-- importers' conflict key) but no anon / authenticated read returns it:
--   1. Column-level grants on the 12 tables that carry it: table-level SELECT is revoked from public, anon and
--      authenticated and SELECT on every other column is granted back. A column added later is NOT granted
--      automatically (test 126 compares the granted list with the table's columns).
--   2. The four remaining Discover matviews (mv_{anime,manga}_{trending,top_rated}) are rebuilt without the column.
--   3. mv_anime_newly_added / mv_manga_newly_added are DROPPED (backend latency step 1c, now SUPERSEDED by this
--      file): the newly-added rails read the base tables. discover_bundle already does so in
--      20261112100401_catalogue_visibility_discover_v1.sql, whose body is built on 1c and carries 1c's change
--      with the visibility filter. 100401 sorts BEFORE this file, so replacing discover_bundle here would erase
--      its visibility filter; instead this file REFUSES to run while the live discover_bundle (or any other
--      function / cron command) still names the two matviews. Apply 100401 first. refresh_discover_matviews_v1()
--      is redefined for the four remaining matviews.
--   4. anime_cast_v1, character_voice_actors_v1, staff_voice_roles_v1 are DROP + CREATE with the same names and
--      argument lists and no anilist columns (they are SECURITY INVOKER and would otherwise fail on the revoke).
--   5. rag_retrieve_candidates (SECURITY DEFINER, returns rag_entity_index.anilist_id) is service-only: its one
--      caller, concierge-retrieve-assist, uses the service-role client.
--   _is_blessed_canon stays: it only has a parameter NAMED p_anilist_id and reads canon_seed.media_id.
--
-- ROLLOUT ORDER (load-bearing): (1) ship an app build that no longer reads the column (this commit's Swift side);
-- (2) the owner confirms older builds are retired; (3) only then apply this file. Applied first, the revoke breaks
-- credits, voices, studios and the list export in older builds, and the two dropped matviews break builds before
-- TestFlight 20 that read them through PostgREST.
-- ALSO REQUIRED BEFORE APPLY: concierge-recommend reads tags.anilist_id with the CALLER's client
-- (catalog_repository.ts tagIdsForAnilistIds) and would silently return no tag ids after the revoke; see
-- docs/catalogue-sources-2026-11/anilist-id-readers.md.
-- Requires 20261112100401 (see 3). Rollback: grant select (anilist_id) back on the 12 tables; the matviews and
-- functions are recreated from this file's counterparts in the applied history.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '180s';

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------
do $guard$
declare
  v_users text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_users
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc ~ 'mv_(anime|manga)_newly_added'
    and p.proname <> 'refresh_discover_matviews_v1';
  if v_users is not null then
    raise exception 'anilist_id_private: the newly-added matviews are still named by: % (apply 20261112100401 first)', v_users;
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select string_agg(jobid::text || ' ' || jobname, ', ') from cron.job
               where command ~ 'mv_(anime|manga)_newly_added'$q$ into v_users;
    if v_users is not null then
      raise exception 'anilist_id_private: the newly-added matviews are still named by cron jobs: %', v_users;
    end if;
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------------
-- 1. Matviews: dropped / rebuilt without anilist_id (no CASCADE: a dependent view fails the drop)
-- ---------------------------------------------------------------------------
drop materialized view if exists public.mv_anime_newly_added;
drop materialized view if exists public.mv_manga_newly_added;
drop materialized view if exists public.mv_anime_trending;
drop materialized view if exists public.mv_anime_top_rated;
drop materialized view if exists public.mv_manga_trending;
drop materialized view if exists public.mv_manga_top_rated;

create materialized view public.mv_anime_trending as
select id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   from public.anime
  where ((trending IS NOT NULL) AND (trending > 0))
with data;

create materialized view public.mv_anime_top_rated as
select id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   from public.anime
  where ((average_score IS NOT NULL) AND (average_score >= 80))
with data;

create materialized view public.mv_manga_trending as
select id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    chapters,
    volumes,
    next_chapter_number,
    next_chapter_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   from public.manga
  where ((trending IS NOT NULL) AND (trending > 0))
with data;

create materialized view public.mv_manga_top_rated as
select id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    chapters,
    volumes,
    next_chapter_number,
    next_chapter_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   from public.manga
  where ((average_score IS NOT NULL) AND (average_score >= 80))
with data;

create unique index mv_anime_trending_id_uidx on public.mv_anime_trending (id);
create index idx_mv_anime_trending_trending on public.mv_anime_trending (trending desc);
create index idx_mv_anime_trending_cold_v1 on public.mv_anime_trending ((coalesce(trending,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[]))) and coalesce(format,'') not in ('SPECIAL','MUSIC','TV_SHORT');
revoke all on public.mv_anime_trending from public, anon, authenticated;
grant select on public.mv_anime_trending to anon, authenticated, service_role;
create unique index mv_anime_top_rated_id_uidx on public.mv_anime_top_rated (id);
create index idx_mv_anime_top_rated_score on public.mv_anime_top_rated (average_score desc);
create index idx_mv_anime_score_cold_v1 on public.mv_anime_top_rated ((coalesce(average_score,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[]))) and coalesce(format,'') not in ('SPECIAL','MUSIC','TV_SHORT');
revoke all on public.mv_anime_top_rated from public, anon, authenticated;
grant select on public.mv_anime_top_rated to anon, authenticated, service_role;
create unique index mv_manga_trending_id_uidx on public.mv_manga_trending (id);
create index idx_mv_manga_trending_trending on public.mv_manga_trending (trending desc);
create index idx_mv_manga_trending_cold_v1 on public.mv_manga_trending ((coalesce(trending,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[])));
revoke all on public.mv_manga_trending from public, anon, authenticated;
grant select on public.mv_manga_trending to anon, authenticated, service_role;
create unique index mv_manga_top_rated_id_uidx on public.mv_manga_top_rated (id);
create index idx_mv_manga_top_rated_score on public.mv_manga_top_rated (average_score desc);
create index idx_mv_manga_score_cold_v1 on public.mv_manga_top_rated ((coalesce(average_score,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[])));
revoke all on public.mv_manga_top_rated from public, anon, authenticated;
grant select on public.mv_manga_top_rated to anon, authenticated, service_role;

create or replace function public.refresh_discover_matviews_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v text;
  v_done text[] := '{}';
begin
  foreach v in array array['mv_anime_trending', 'mv_anime_top_rated',
                           'mv_manga_trending', 'mv_manga_top_rated'] loop
    if to_regclass('public.' || v) is null then
      continue;
    end if;
    if (select m.ispopulated from pg_matviews m where m.schemaname = 'public' and m.matviewname = v) then
      execute format('refresh materialized view concurrently public.%I', v);
    else
      execute format('refresh materialized view public.%I', v);  -- first fill cannot be concurrent
    end if;
    v_done := v_done || v;
  end loop;
  return jsonb_build_object('refreshed', to_jsonb(v_done));
end;
$$;
revoke all on function public.refresh_discover_matviews_v1() from public, anon, authenticated;
grant execute on function public.refresh_discover_matviews_v1() to service_role;

-- ---------------------------------------------------------------------------
-- 2. Column-level grants on every table that carries anilist_id
-- ---------------------------------------------------------------------------
do $grants$
declare
  t text;
  v_cols text;
begin
  foreach t in array array['anime', 'manga', 'authors', 'chapters', 'characters', 'curated_rail_items', 'episodes',
                           'rag_entity_index', 'staff', 'studios', 'tags', 'volumes'] loop
    if to_regclass('public.' || t) is null then
      raise notice 'anilist_id_private: public.% does not exist here, skipped', t;
      continue;
    end if;
    select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
    from pg_attribute a
    where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped and a.attname <> 'anilist_id';
    if not exists (select 1 from pg_attribute a
                   where a.attrelid = ('public.' || t)::regclass and a.attname = 'anilist_id' and not a.attisdropped) then
      raise notice 'anilist_id_private: public.% has no anilist_id, skipped', t;
      continue;
    end if;
    execute format('revoke select on table public.%I from public, anon, authenticated', t);
    execute format('grant select (%s) on table public.%I to anon, authenticated', v_cols, t);
  end loop;
end;
$grants$;

-- ---------------------------------------------------------------------------
-- 3. Voice RPCs: same names and argument lists, no anilist columns
-- ---------------------------------------------------------------------------
drop function if exists public.anime_cast_v1(integer, text, integer);
create function public.anime_cast_v1(p_anime_id integer, p_language text default 'JAPANESE',
  p_limit integer default 25)
returns table (
  character_id integer, character_name_full text, character_name_native text,
  character_image_large text, role text,
  staff_id integer, staff_name_full text, staff_name_native text,
  staff_image_large text, language text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_lang text := upper(coalesce(nullif(btrim(p_language), ''), 'JAPANESE'));
  v_limit integer := least(50, greatest(1, coalesce(p_limit, 25)));
begin
  if p_anime_id is null or p_anime_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_anime_id must be a positive id';
  end if;
  if v_lang !~ '^[A-Z_]{2,32}$' then
    raise exception 'INVALID_LANGUAGE: p_language must be an AniList StaffLanguage';
  end if;
  return query
  select c.id, c.name_full, c.name_native, c.image_large, coalesce(ac.role, 'SUPPORTING'),
         va.staff_id, va.name_full, va.name_native, va.image_large, va.language
  from public.anime_characters ac
  join public.characters c on c.id = ac.character_id
  left join lateral (
    select s.id as staff_id, s.name_full, s.name_native, s.image_large, cva.language
    from public.character_voice_actors cva
    join public.staff s on s.id = cva.staff_id
    where cva.anime_id = ac.anime_id
      and cva.character_id = ac.character_id
      and cva.language = v_lang
    order by cva.sort_order, s.id
    limit 1
  ) va on true
  where ac.anime_id = p_anime_id
  order by case upper(coalesce(ac.role, '')) when 'MAIN' then 0 when 'SUPPORTING' then 1 else 2 end, ac.id
  limit v_limit;
end;
$$;
revoke all on function public.anime_cast_v1(integer, text, integer) from public;
grant execute on function public.anime_cast_v1(integer, text, integer) to anon, authenticated, service_role;
comment on function public.anime_cast_v1(integer, text, integer) is
  '20261112100500 (prepared). Public read: up to p_limit (1-50, default 25) characters of one anime (MAIN, SUPPORTING, other; then import order) with the primary voice actor in p_language (default JAPANESE; va columns null when none is stored). No AniList ids. SECURITY INVOKER. Raises INVALID_MEDIA_ID: / INVALID_LANGUAGE:.';

drop function if exists public.character_voice_actors_v1(integer, text);
create function public.character_voice_actors_v1(p_character_id integer, p_language text default 'JAPANESE')
returns table (
  staff_id integer, name_full text, name_native text, image_large text,
  language text, anime_ids integer[]
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_lang text := upper(coalesce(nullif(btrim(p_language), ''), 'JAPANESE'));
begin
  if p_character_id is null or p_character_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_character_id must be a positive id';
  end if;
  if v_lang !~ '^[A-Z_]{2,32}$' then
    raise exception 'INVALID_LANGUAGE: p_language must be an AniList StaffLanguage';
  end if;
  return query
  select s.id, s.name_full, s.name_native, s.image_large, v_lang,
         array_agg(cva.anime_id order by cva.anime_id)
  from public.character_voice_actors cva
  join public.staff s on s.id = cva.staff_id
  join public.anime a on a.id = cva.anime_id
  where cva.character_id = p_character_id
    and cva.language = v_lang
    and coalesce(a.is_adult, false) = false
  group by s.id, s.name_full, s.name_native, s.image_large
  order by min(cva.sort_order), count(*) desc, s.id
  limit 10;
end;
$$;
revoke all on function public.character_voice_actors_v1(integer, text) from public;
grant execute on function public.character_voice_actors_v1(integer, text) to anon, authenticated, service_role;
comment on function public.character_voice_actors_v1(integer, text) is
  '20261112100500 (prepared). Public read: up to 10 voice actors of one character in p_language (default JAPANESE), one row per person with the non-adult anime ids of the role, primary first. No AniList ids. SECURITY INVOKER. Raises INVALID_MEDIA_ID: / INVALID_LANGUAGE:.';

drop function if exists public.staff_voice_roles_v1(integer, integer);
create function public.staff_voice_roles_v1(p_staff_id integer, p_limit integer default 50)
returns table (
  character_id integer, character_name_full text, character_name_native text,
  character_image_large text, role text, language text,
  anime_id integer, title_english text, title_romaji text, title_native text,
  cover_image_large text, format text, season_year integer, start_date_year integer
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 50)));
begin
  if p_staff_id is null or p_staff_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_staff_id must be a positive id';
  end if;
  return query
  select c.id, c.name_full, c.name_native, c.image_large,
         coalesce(ac.role, 'SUPPORTING'), cva.language,
         a.id, a.title_english, a.title_romaji, a.title_native, a.cover_image_large, a.format,
         a.season_year, a.start_date_year
  from public.character_voice_actors cva
  join public.characters c on c.id = cva.character_id
  join public.anime a on a.id = cva.anime_id
  left join public.anime_characters ac on ac.anime_id = cva.anime_id and ac.character_id = cva.character_id
  where cva.staff_id = p_staff_id
    and coalesce(a.is_adult, false) = false
  order by case upper(coalesce(ac.role, '')) when 'MAIN' then 0 when 'SUPPORTING' then 1 else 2 end,
           a.popularity desc nulls last, a.id, c.id
  limit v_limit;
end;
$$;
revoke all on function public.staff_voice_roles_v1(integer, integer) from public;
grant execute on function public.staff_voice_roles_v1(integer, integer) to anon, authenticated, service_role;
comment on function public.staff_voice_roles_v1(integer, integer) is
  '20261112100500 (prepared). Public read: up to p_limit (1-100, default 50) characters one person voiced, one row per (character, anime), non-adult anime only; MAIN roles first, then anime popularity. No AniList ids. SECURITY INVOKER. Raises INVALID_MEDIA_ID:.';

-- ---------------------------------------------------------------------------
-- 4. rag_retrieve_candidates returns rag_entity_index.anilist_id and is SECURITY DEFINER: service-only
-- ---------------------------------------------------------------------------
do $rag$
begin
  if to_regprocedure('public.rag_retrieve_candidates(text,text,integer,integer,text,text[],integer)') is not null then
    revoke execute on function public.rag_retrieve_candidates(text, text, int, int, text, text[], int)
      from public, anon, authenticated;
    grant execute on function public.rag_retrieve_candidates(text, text, int, int, text, text[], int) to service_role;
  end if;
end;
$rag$;

notify pgrst, 'reload schema';
commit;
