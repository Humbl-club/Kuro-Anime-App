-- 132_live_chapters_and_airing_schedule_v1.sql
-- Prepared 20261121200000_live_chapters_and_airing_schedule_v1.sql:
-- Covers: manga.latest_chapter / latest_chapter_at columns + check constraint + column grants,
-- collection_feed_page ongoing chapter fallback, home_bundle_v1 active latest_chapter &
-- next_airing_at fields, and W5 anon / public execute denial.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires function public.home_bundle_v1(text,text,integer,integer,integer,text)
-- @requires function public.collection_feed_page(integer,timestamptz,integer,integer,text,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- 1. Columns and column-level privileges
select tests.ok('manga carries latest_chapter and latest_chapter_at columns',
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'manga' and column_name = 'latest_chapter')
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'manga' and column_name = 'latest_chapter_at'));

select tests.ok('anon and authenticated can SELECT latest_chapter and latest_chapter_at',
  has_column_privilege('anon', 'public.manga'::regclass, 'latest_chapter', 'select')
  and has_column_privilege('authenticated', 'public.manga'::regclass, 'latest_chapter', 'select')
  and has_column_privilege('anon', 'public.manga'::regclass, 'latest_chapter_at', 'select')
  and has_column_privilege('authenticated', 'public.manga'::regclass, 'latest_chapter_at', 'select'));

set local session_replication_role = replica;
insert into public.anime (id, anilist_id, title_romaji, title_english, format, status, next_episode_number, next_airing_at, is_adult)
values (1320001, 1320001, 'Sched Anime', 'Sched Anime', 'TV', 'RELEASING', 9, now() + interval '2 days', false);

insert into public.manga (id, anilist_id, title_romaji, title_english, format, status, chapters, latest_chapter, latest_chapter_at, is_adult)
values (1320101, 1320101, 'Ongoing Manga', 'Ongoing Manga', 'MANGA', 'RELEASING', null, 1198.5, now(), false);
set local session_replication_role = origin;

select tests.raises('latest_chapter <= 0 is rejected',
  $q$update public.manga set latest_chapter = 0 where id = 1320101$q$,
  '%check constraint%');

-- 2. RPC payloads & W5 denial
select tests.ok('home_bundle_v1 and collection_feed_page remain denied to anon and public',
  not has_function_privilege('anon', 'public.home_bundle_v1(text,text,integer,integer,integer,text)', 'execute')
  and not has_function_privilege('public', 'public.home_bundle_v1(text,text,integer,integer,integer,text)', 'execute')
  and not has_function_privilege('anon', 'public.collection_feed_page(integer,timestamptz,integer,integer,text,text)', 'execute')
  and not has_function_privilege('public', 'public.collection_feed_page(integer,timestamptz,integer,integer,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.home_bundle_v1(text,text,integer,integer,integer,text)', 'execute')
  and has_function_privilege('authenticated', 'public.collection_feed_page(integer,timestamptz,integer,integer,text,text)', 'execute'));

select tests.make_user(1320);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(1320)::text, 1320001, 'WATCHING', 8);
insert into public.manga_user_lists (user_id, manga_id, list_type, progress)
values (tests.uid(1320)::text, 1320101, 'READING', 24);

select tests.as_user(tests.uid(1320));

select tests.eq('collection_feed_page uses floor(latest_chapter) when ongoing chapters is null',
  (select chapter_count from public.collection_feed_page(20, null, null, null, null, null) where media_type = 'MANGA' and id = 1320101),
  1198);

select tests.eq('home_bundle_v1 anime item exposes next_episode_number',
  (select (item ->> 'next_episode_number')::int
   from jsonb_array_elements(public.home_bundle_v1('anime', 'en', 7, 12, 20, null) -> 'active') item
   where (item ->> 'media_id')::int = 1320001),
  9);

select tests.ok('home_bundle_v1 manga item exposes latest_chapter',
  (select (item ->> 'latest_chapter')::numeric = 1198.5
   from jsonb_array_elements(public.home_bundle_v1('manga', 'en', 7, 12, 20, null) -> 'active') item
   where (item ->> 'media_id')::int = 1320101));

select tests.reset();
rollback;
