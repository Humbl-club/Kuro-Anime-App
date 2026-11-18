-- 126_anilist_id_private_v1.sql
-- Prepared 20261112100500_anilist_id_private_v1.sql (NOT deployed), catalogue Task 15d: AniList ids leave public reads.
-- Covers: column-level grants on every table that carries anilist_id (anon / authenticated may not read the column;
-- the granted column list equals the table's columns minus anilist_id, so a later column cannot silently go
-- ungranted; other columns still read); the four rebuilt matviews have no anilist_id and the two newly-added
-- matviews are gone; no function callable by anon / authenticated returns an anilist column; the jsonb definer
-- readers (discover_bundle, discover_section_page_v1, curated_rail_cards) carry no anilist key; the three voice RPCs
-- keep their names, argument lists and rows; _is_blessed_canon still runs as a client; rag_retrieve_candidates is
-- service-only; refresh_discover_matviews_v1 lists the four remaining matviews.
-- Fixture limits: tables the fixture lacks (curated_rail_items, rag_entity_index, ...) are skipped by the
-- migration and by the per-table checks; discover_section_page_v1 is checked from its source, not run.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.characters
-- @requires table public.staff
-- @requires table public.anime_characters
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.discover_rail_impressions
-- @requires function public.discover_bundle(integer,integer)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- ---- 1. column grants ---------------------------------------------------------------
create temporary table anilist_tables as
select t as tbl
from unnest(array['anime', 'manga', 'authors', 'chapters', 'characters', 'curated_rail_items', 'episodes',
                  'rag_entity_index', 'staff', 'studios', 'tags', 'volumes']) t
where exists (select 1 from pg_attribute a
              where a.attrelid = to_regclass('public.' || t) and a.attname = 'anilist_id' and not a.attisdropped);
select tests.ok('the fixture carries the core tables with anilist_id',
  (select count(*) filter (where tbl in ('anime', 'manga', 'characters', 'staff')) = 4 from anilist_tables));
select tests.ok('no client role may SELECT anilist_id on any listed table',
  (select coalesce(bool_and(not has_column_privilege(r, ('public.' || tbl)::regclass, 'anilist_id', 'select')
                            and not has_table_privilege(r, ('public.' || tbl)::regclass, 'select')), true)
     from anilist_tables, unnest(array['anon', 'authenticated']) r));
select tests.ok('PUBLIC holds no table-level SELECT on any listed table either',
  (select coalesce(bool_and(not exists (select 1 from aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
                                         where x.grantee = 0 and x.privilege_type = 'SELECT')), true)
     from anilist_tables t join pg_class c on c.oid = ('public.' || t.tbl)::regclass));
-- Granted list equals the columns minus anilist_id.
select tests.eq('granted columns (anon) = all columns minus anilist_id, on every listed table',
  (select count(*) from anilist_tables t
    join pg_attribute a on a.attrelid = ('public.' || t.tbl)::regclass and a.attnum > 0 and not a.attisdropped
   where a.attname <> 'anilist_id' and not has_column_privilege('anon', ('public.' || t.tbl)::regclass, a.attname, 'select')),
  0::bigint);
select tests.eq('granted columns (authenticated) = all columns minus anilist_id, on every listed table',
  (select count(*) from anilist_tables t
    join pg_attribute a on a.attrelid = ('public.' || t.tbl)::regclass and a.attnum > 0 and not a.attisdropped
   where a.attname <> 'anilist_id' and not has_column_privilege('authenticated', ('public.' || t.tbl)::regclass, a.attname, 'select')),
  0::bigint);
select tests.ok('service_role still reads anilist_id (importers and the crosswalk)',
  (select coalesce(bool_and(has_column_privilege('service_role', ('public.' || tbl)::regclass, 'anilist_id', 'select')), true) from anilist_tables));

-- Behaviour as the client roles: named columns read, the AniList column and a star read are denied.
set local session_replication_role = replica;
insert into public.anime (id, anilist_id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, cover_image_large)
values (1260001, 1260001, 'Private Id Anime', 'Private Id Anime', 'TV', 'FINISHED', 10, 5, 85, array['Action'], false, 'https://img.invalid/1.jpg');
insert into public.manga (id, anilist_id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, cover_image_large)
values (1260101, 1260101, 'Private Id Manga', 'Private Id Manga', 'MANGA', 'FINISHED', 10, 5, 85, array['Drama'], false, 'https://img.invalid/2.jpg');
set local session_replication_role = origin;
select tests.as_anon();
select tests.eq('anon reads named catalogue columns', (select count(*) from public.anime where id = 1260001), 1::bigint);
select tests.denied('anon cannot select anime.anilist_id', $q$select anilist_id from public.anime where id = 1260001$q$);
select tests.denied('anon cannot select * from anime', $q$select * from public.anime where id = 1260001$q$);
select tests.denied('anon cannot filter manga by anilist_id', $q$select id from public.manga where anilist_id = 1260101$q$);
select tests.reset();
select tests.make_user(1261);
select tests.as_user(tests.uid(1261));
select tests.eq('authenticated reads named catalogue columns', (select count(*) from public.manga where id = 1260101), 1::bigint);
select tests.denied('authenticated cannot select manga.anilist_id', $q$select anilist_id from public.manga where id = 1260101$q$);
select tests.reset();

-- ---- 2. matviews ----------------------------------------------------------------------
select tests.ok('the two newly-added snapshot matviews are gone',
  to_regclass('public.mv_anime_newly_added') is null and to_regclass('public.mv_manga_newly_added') is null);
select tests.eq('the four trending / top-rated matviews exist',
  (select count(*) from pg_matviews where schemaname = 'public'
     and matviewname in ('mv_anime_trending','mv_anime_top_rated','mv_manga_trending','mv_manga_top_rated')), 4::bigint);
select tests.ok('no public matview or view readable by a client has an anilist_id column',
  not exists (select 1 from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind in ('m', 'v') and a.attname = 'anilist_id' and not a.attisdropped
                and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'))));
select tests.ok('each rebuilt matview keeps its unique id index (REFRESH CONCURRENTLY) and client SELECT',
  (select bool_and(exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.tablename = m and i.indexname = m || '_id_uidx')
                   and has_table_privilege('anon', ('public.' || m)::regclass, 'select')
                   and has_table_privilege('authenticated', ('public.' || m)::regclass, 'select'))
     from unnest(array['mv_anime_trending','mv_anime_top_rated','mv_manga_trending','mv_manga_top_rated']) m));
select tests.eq('refresh_discover_matviews_v1 lists exactly the four remaining matviews',
  (select array_agg(x order by x) from jsonb_array_elements_text(public.refresh_discover_matviews_v1() -> 'refreshed') x),
  array['mv_anime_top_rated','mv_anime_trending','mv_manga_top_rated','mv_manga_trending']);
select tests.ok('refresh_discover_matviews_v1 stays service-only',
  not has_function_privilege('anon', 'public.refresh_discover_matviews_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.refresh_discover_matviews_v1()', 'execute'));
select tests.ok('the rebuilt trending matview holds the fixture row',
  (select count(*) from public.mv_anime_trending where id = 1260001) = 1);

-- ---- 3. functions ----------------------------------------------------------------------
select tests.eq('no function callable by anon / authenticated returns an anilist column',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and pg_get_function_result(p.oid) ~* 'anilist'
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
  0::bigint);
select tests.ok('the three voice RPCs keep their names and argument lists and stay client-callable',
  has_function_privilege('anon', 'public.anime_cast_v1(integer,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.character_voice_actors_v1(integer,text)', 'execute')
  and has_function_privilege('anon', 'public.staff_voice_roles_v1(integer,integer)', 'execute')
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('anime_cast_v1', 'character_voice_actors_v1', 'staff_voice_roles_v1')) = 3);
select tests.eq('the three voice RPCs are still SECURITY INVOKER with search_path = public, extensions',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('anime_cast_v1', 'character_voice_actors_v1', 'staff_voice_roles_v1')
    and not p.prosecdef and p.proconfig @> array['search_path=public, extensions']), 3::bigint);
select tests.ok('no function that runs as the caller names anilist_id in its body (a revoked column would fail it)',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and not p.prosecdef and p.prosrc ~ 'anilist_id'
                and p.proname not in ('_is_blessed_canon', 'catalogue_publish_batch_v1', 'catalogue_relation_source_v1')
                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))));
select tests.ok('rag_retrieve_candidates is service-only',
  to_regprocedure('public.rag_retrieve_candidates(text,text,integer,integer,text,text[],integer)') is null
  or (not has_function_privilege('anon', 'public.rag_retrieve_candidates(text,text,integer,integer,text,text[],integer)', 'execute')
      and not has_function_privilege('authenticated', 'public.rag_retrieve_candidates(text,text,integer,integer,text,text[],integer)', 'execute')
      and has_function_privilege('service_role', 'public.rag_retrieve_candidates(text,text,integer,integer,text,text[],integer)', 'execute')));

-- Voice RPCs return the same rows as before, as anon, with no AniList column.
set local session_replication_role = replica;
insert into public.characters (id, anilist_id, name_full, name_native) values (1260201, 1260201, 'Hero 126', null);
insert into public.staff (id, anilist_id, name_full, name_native, image_large) values (1260301, 1260301, 'Voice 126', null, null);
insert into public.anime_characters (anime_id, character_id, role) values (1260001, 1260201, 'MAIN');
insert into public.character_voice_actors (anime_id, character_id, staff_id, language, sort_order) values (1260001, 1260201, 1260301, 'JAPANESE', 0);
set local session_replication_role = origin;
select tests.as_anon();
select tests.eq('anime_cast_v1 as anon returns the cast row with its voice actor',
  (select character_name_full || '/' || role || '/' || staff_name_full || '/' || language from public.anime_cast_v1(1260001)),
  'Hero 126/MAIN/Voice 126/JAPANESE');
select tests.eq('character_voice_actors_v1 as anon returns the voice actor and the anime id',
  (select name_full || ':' || array_to_string(anime_ids, '+') from public.character_voice_actors_v1(1260201)), 'Voice 126:1260001');
select tests.eq('staff_voice_roles_v1 as anon returns the role',
  (select character_name_full || '@' || title_romaji from public.staff_voice_roles_v1(1260301)), 'Hero 126@Private Id Anime');
do $blessed$
begin
  if to_regprocedure('public._is_blessed_canon(text,integer)') is not null then
    perform public._is_blessed_canon('ANIME', 1260001);
    raise notice 'TEST ok: _is_blessed_canon still runs as a client';
  else
    raise notice '_is_blessed_canon is not in this fixture: not exercised';
  end if;
end;
$blessed$;
select tests.reset();

-- ---- 4. jsonb definer readers carry no anilist key -------------------------------------------
do $standins$
begin
  if to_regclass('public.curated_rail_items') is null then
    create table public.curated_rail_items (rail_id text not null, media_type text not null, anilist_id integer not null, rank integer not null);
  end if;
  if to_regprocedure('public.current_season_name(timestamptz)') is null then
    execute $f$
      create function public.current_season_name(p_at timestamptz default now()) returns text
      language sql immutable as $b$
        select case
          when extract(month from p_at)::int in (12, 1, 2) then 'WINTER'
          when extract(month from p_at)::int in (3, 4, 5) then 'SPRING'
          when extract(month from p_at)::int in (6, 7, 8) then 'SUMMER'
          else 'FALL'
        end $b$ $f$;
  end if;
  if to_regclass('public.user_lists') is null then
    execute $v$
      create view public.user_lists with (security_invoker = on) as
      select aul.id, aul.user_id, aul.anime_id as media_id, 'anime'::text as media_type, aul.list_type as status,
             aul.progress, null::integer as progress_volumes,
             case when aul.rating is null then null::integer else aul.rating * 10 end as score,
             aul.notes, null::timestamptz as started_at, null::timestamptz as completed_at, false as private,
             aul.created_at, aul.updated_at
        from public.anime_user_lists aul
      union all
      select mul.id, mul.user_id, mul.manga_id, 'manga'::text, mul.list_type, mul.progress, null::integer,
             case when mul.rating is null then null::integer else mul.rating * 10 end,
             mul.notes, null::timestamptz, null::timestamptz, false, mul.created_at, mul.updated_at
        from public.manga_user_lists mul $v$;
  end if;
end;
$standins$;
refresh materialized view public.mv_anime_trending;
refresh materialized view public.mv_manga_trending;
select set_config('request.jwt.claims',
  json_build_object('sub', tests.uid(1261)::text, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
select public.discover_bundle(30, 24)::text as bundle \gset
select tests.ok('discover_bundle returned rails (the fixture row is in the trending rail)',
  jsonb_array_length(:'bundle'::jsonb -> 'anime' -> 'trending') >= 1);
select tests.ok('discover_bundle output carries no anilist key or value name',
  :'bundle' !~* 'anilist');
select tests.ok('discover_section_page_v1 and curated_rail_cards output no anilist column / key (source and signature)',
  (select count(*) = 2 and bool_and(p.prosrc !~* '(jsonb_build_object|json_build_object)\s*\([^;]*anilist')
          and bool_and(pg_get_function_result(p.oid) !~* 'anilist')
   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('discover_section_page_v1', 'curated_rail_cards')));
select tests.ok('the discover readers never emit an anilist_id jsonb key (no quoted key literal in their sources)',
  (select bool_and(p.prosrc !~* '''anilist_id''')
   from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('discover_bundle', 'discover_section_page_v1', 'discover_mood_v1', '_discover_page_v1', 'curated_rail_cards')));
\o
rollback;
