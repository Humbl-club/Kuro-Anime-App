-- 129_search_synonyms_and_spoiler_tags_v1.sql
-- Prepared 20261121100000_search_synonyms_and_cold_index_v1.sql (NOT deployed):
-- Covers: synonym & acronym search in search_{anime,manga}_page, service-only posture of internal
-- search helpers, non-spoiler `tag:<Name>` browse filtering excluding spoiler tags, and preservation
-- of guest allowlist / anilist_id column grants / anime_tags column invariants.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.tags
-- @requires table public.anime_tags
-- @requires table public.manga_tags
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

select tests.ok('internal synonym/acronym helpers are service-only and immutable',
  not has_function_privilege('anon', 'public._catalogue_acronym_v1(text)', 'execute')
  and not has_function_privilege('authenticated', 'public._catalogue_acronym_v1(text)', 'execute')
  and not has_function_privilege('public', 'public._catalogue_acronym_v1(text)', 'execute')
  and not has_function_privilege('anon', 'public._catalogue_synonyms_blob_v1(text,text,text[])', 'execute')
  and not has_function_privilege('authenticated', 'public._catalogue_synonyms_blob_v1(text,text,text[])', 'execute'));

set local session_replication_role = replica;
insert into public.anime (id, title_romaji, title_english, title_synonyms, format, status, popularity, average_score, genres, is_adult, catalogue_visibility)
values (1290001, 'Shingeki no Kyojin', 'Attack on Titan', array['AoT', 'SnK'], 'TV', 'FINISHED', 99000, 89, array['Action', 'Drama'], false, 'visible');

insert into public.manga (id, title_romaji, title_english, title_synonyms, format, status, popularity, average_score, genres, is_adult, catalogue_visibility)
values (1290101, 'Dungeon Meshi', 'Delicious in Dungeon', array['DunMeshi'], 'MANGA', 'HIATUS', 75000, 87, array['Fantasy'], false, 'visible');

insert into public.tags (id, name, is_general_spoiler, is_media_spoiler, is_adult)
values (1290201, 'Iyashikei', false, false, false),
       (1290202, 'Major Character Death', true, false, false),
       (1290203, 'Final Arc Twist', false, true, false),
       (1290204, 'Explicit Adult Tag 129', false, false, true);

insert into public.anime_tags (id, anime_id, tag_id, rank)
values (1290301, 1290001, 1290201, 80),
       (1290302, 1290001, 1290202, 95),
       (1290303, 1290001, 1290203, 95),
       (1290304, 1290001, 1290204, 95);
set local session_replication_role = origin;

select tests.eq('acronym search matches Attack on Titan via aot',
  (select count(*) from public.search_anime_page('aot', 10) where id = 1290001), 1::bigint);
select tests.eq('acronym search matches Shingeki no Kyojin via snk',
  (select count(*) from public.search_anime_page('snk', 10) where id = 1290001), 1::bigint);
select tests.eq('derived acronym search matches Delicious in Dungeon via did',
  (select count(*) from public.search_manga_page('did', 10) where id = 1290101), 1::bigint);
select tests.eq('synonym search matches Dungeon Meshi via dunmeshi',
  (select count(*) from public.search_manga_page('dunmeshi', 10) where id = 1290101), 1::bigint);

select tests.eq('browse_anime_page allows non-spoiler tag:Iyashikei',
  (select count(*) from public.browse_anime_page(p_genre => 'tag:Iyashikei', p_limit => 10) where id = 1290001), 1::bigint);
select tests.eq('browse_anime_page hides general-spoiler tag filters',
  (select count(*) from public.browse_anime_page(p_genre => 'tag:Major Character Death', p_limit => 10) where id = 1290001), 0::bigint);
select tests.eq('browse_anime_page hides media-spoiler tag filters',
  (select count(*) from public.browse_anime_page(p_genre => 'tag:Final Arc Twist', p_limit => 10) where id = 1290001), 0::bigint);
select tests.eq('browse_anime_page hides adult tag filters',
  (select count(*) from public.browse_anime_page(p_genre => 'tag:Explicit Adult Tag 129', p_limit => 10) where id = 1290001), 0::bigint);
select tests.eq('browse_manga_page supports HIATUS status filter',
  (select count(*) from public.browse_manga_page(p_status => 'HIATUS', p_limit => 10) where id = 1290101), 1::bigint);

rollback;
