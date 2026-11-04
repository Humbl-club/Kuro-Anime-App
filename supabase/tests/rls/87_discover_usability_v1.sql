-- 87_discover_usability_v1.sql
-- Prepared 20261104100000_discover_usability_v1.sql (NOT deployed): the Discover usability
-- readers. Proves, for the schema this fixture contains:
--   * posture: SECURITY DEFINER + search_path, STABLE (read-only), grants (readers granted to
--     anon/authenticated; the internal finisher and the franchise table are not client-reachable);
--   * media_franchise_ids_v1: component label or self, both media, cap;
--   * discover_section_page_v1: section predicates and orders, catalogue exclusions, hidden
--     (deck_skip / deck_known of 365 days; deck_pass and older signals do not hide), the owned
--     rule (new_to_you hides, editorial sections mark with list_status), franchise dedupe before
--     the offset, stable ranks across pages, sort (newest = release date), filters, curated rails;
--   * discover_mood_v1: short / cozy / intense (genre fallback without the realm view, realm sets
--     with it), like_last_loved (seed choice, reason, owned exclusion, signed-out/no-seed empty);
--   * typed errors in the MESSAGE.
-- curated_rail_items, media_realm_membership (the mood's realm source since 20261104100100) and the real recommend_ids_similar_to_seeds
-- body do not replay into this fixture: stand-ins (a table, a table, a recording stub) are created
-- INSIDE this rolled-back transaction. That proves the readers' own logic, not the realm scorer.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.taste_signal_events
-- @requires table public.media_franchise_components
-- @requires function public.recommend_ids_similar_to_seeds(text,integer[],integer,boolean)
\set ON_ERROR_STOP on
\o /dev/null
begin;

-- ---- 0. posture ---------------------------------------------------------------
select tests.ok('the three readers and the finisher are SECURITY DEFINER, STABLE, search_path = public, extensions',
  (select bool_and(prosecdef and provolatile = 's' and proconfig @> array['search_path=public, extensions'])
     from pg_proc where oid in (
       'public.media_franchise_ids_v1(integer[],integer[])'::regprocedure,
       'public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)'::regprocedure,
       'public.discover_mood_v1(text,text,integer,integer)'::regprocedure,
       'public._discover_page_v1(uuid,text,integer[],boolean,integer,integer,integer,text)'::regprocedure)));
select tests.ok('anon and authenticated may execute the three readers',
  has_function_privilege('anon', 'public.media_franchise_ids_v1(integer[],integer[])', 'execute')
  and has_function_privilege('authenticated', 'public.media_franchise_ids_v1(integer[],integer[])', 'execute')
  and has_function_privilege('anon', 'public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)', 'execute')
  and has_function_privilege('anon', 'public.discover_mood_v1(text,text,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.discover_mood_v1(text,text,integer,integer)', 'execute'));
select tests.ok('the internal finisher is NOT executable by anon or authenticated (it trusts p_uid)',
  not has_function_privilege('anon', 'public._discover_page_v1(uuid,text,integer[],boolean,integer,integer,integer,text)', 'execute')
  and not has_function_privilege('authenticated', 'public._discover_page_v1(uuid,text,integer[],boolean,integer,integer,integer,text)', 'execute'));
select tests.ok('media_franchise_components stays without client grants',
  not has_table_privilege('anon', 'public.media_franchise_components', 'select')
  and not has_table_privilege('authenticated', 'public.media_franchise_components', 'select'));

-- ---- seed (superuser; rolled back) ------------------------------------------------
select tests.reset();
select tests.ok('precondition: the fixture catalogue holds no other anime or manga (ranks are global)',
  not exists (select 1 from public.anime where id not between 870000 and 879999)
  and not exists (select 1 from public.manga where id not between 870000 and 879999));
select tests.make_user(871);
select tests.make_user(872);
select tests.make_user(873);
select tests.make_user(874);

insert into public.anime (id, anilist_id, title_romaji, title_english, cover_image_large, is_adult, format, status,
                          episodes, duration, season, season_year, start_date_year, start_date_month, start_date_day,
                          average_score, popularity, trending, favourites, genres, next_airing_at) values
  (870001, 1870001, 'Franchise A', 'Franchise A EN', 'https://img.invalid/1.jpg', false, 'TV', 'FINISHED', 12, 24, 'SPRING', 2018, 2018, 4, 1, 90, 1000, 50, 500, array['Action'], null),
  (870002, 1870002, 'Franchise A 2', null, 'https://img.invalid/2.jpg', false, 'TV', 'FINISHED', 12, 24, 'SPRING', 2021, 2021, 4, 1, 88, 900, 60, 400, array['Action'], null),
  (870003, 1870003, 'Solo Long', null, 'https://img.invalid/3.jpg', false, 'TV', 'FINISHED', 64, 24, 'SPRING', 2009, 2009, 4, 5, 86, 800, 40, 300, array['Drama'], null),
  (870004, 1870004, 'Adult', null, 'https://img.invalid/4.jpg', true, 'TV', 'FINISHED', 12, 24, null, 2020, 2020, null, null, 95, 5000, 99, 900, array['Drama'], null),
  (870005, 1870005, 'Coverless', null, '  ', false, 'TV', 'FINISHED', 12, 24, null, 2020, 2020, null, null, 92, 4000, 98, 800, array['Drama'], null),
  (870006, 1870006, 'Special', null, 'https://img.invalid/6.jpg', false, 'SPECIAL', 'FINISHED', 1, 24, null, 2020, 2020, null, null, 91, 3000, 97, 700, array['Drama'], null),
  (870007, 1870007, 'Owned Show', null, 'https://img.invalid/7.jpg', false, 'TV', 'RELEASING', 24, 24, 'FALL', 2026, 2026, 10, 1, 87, 700, 30, 200, array['Drama'], null),
  (870008, 1870008, 'Hidden Skip', null, 'https://img.invalid/8.jpg', false, 'TV', 'FINISHED', 13, 24, null, 2019, 2019, null, null, 89, 600, 70, 100, array['Drama'], null),
  (870009, 1870009, 'Seen Known', null, 'https://img.invalid/9.jpg', false, 'TV', 'FINISHED', 26, 24, null, 2019, 2019, null, null, 85, 500, 20, 90, array['Drama'], null),
  (870010, 1870010, 'Passed', null, 'https://img.invalid/10.jpg', false, 'TV', 'FINISHED', 12, 24, null, 2022, 2022, 1, 1, 84, 400, 10, 80, array['Comedy'], null),
  (870011, 1870011, 'Short Movie', null, 'https://img.invalid/11.jpg', false, 'MOVIE', 'FINISHED', 1, 20, null, 2017, 2017, null, null, 75, 300, 0, 70, array['Drama'], null),
  (870012, 1870012, 'Long Movie', null, 'https://img.invalid/12.jpg', false, 'MOVIE', 'FINISHED', 1, 110, null, 2016, 2016, null, null, 80, 350, 0, 60, array['Drama'], null),
  (870013, 1870013, 'Cozy Show', null, 'https://img.invalid/13.jpg', false, 'TV', 'FINISHED', 12, 24, null, 2015, 2015, null, null, 80, 250, 0, 50, array['Slice of Life'], null),
  (870014, 1870014, 'Scary Show', null, 'https://img.invalid/14.jpg', false, 'TV', 'FINISHED', 12, 24, null, 2014, 2014, null, null, 82, 260, 0, 40, array['Horror', 'Thriller'], null),
  (870015, 1870015, 'Old Skip', null, 'https://img.invalid/15.jpg', false, 'TV', 'FINISHED', 12, 24, null, 2013, 2013, null, null, 81, 380, 0, 30, array['Drama'], null);
insert into public.manga (id, anilist_id, title_romaji, cover_image_large, is_adult, format, status, chapters, volumes,
                          start_date_year, average_score, popularity, trending, favourites, genres) values
  (870101, 1870101, 'Manga Short', 'https://img.invalid/m1.jpg', false, 'MANGA', 'FINISHED', 40, 4, 2015, 80, 100, 3, 10, array['Drama']),
  (870102, 1870102, 'Manga Long', 'https://img.invalid/m2.jpg', false, 'MANGA', 'RELEASING', 300, 30, 2010, 86, 200, 5, 20, array['Action']);

insert into public.media_franchise_components (media_type, media_id, component_label) values
  ('ANIME', 870001, 870001), ('ANIME', 870002, 870001);

-- user 871: owns 870007 (WATCHING); Not interested 870008, Seen it 870009, an undecided deck
-- pass on 870010, a Not interested of 400 days ago on 870015.
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(871)::text, 870007, 'WATCHING', 3);
insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength, created_at) values
  (tests.uid(871), 870008, 'ANIME', 'deck_skip', -0.45, now() - interval '1 day'),
  (tests.uid(871), 870009, 'ANIME', 'deck_known', 0.25, now() - interval '2 days'),
  (tests.uid(871), 870010, 'ANIME', 'deck_pass', 0.0, now() - interval '1 day'),
  (tests.uid(871), 870015, 'ANIME', 'deck_skip', -0.45, now() - interval '400 days');

-- ---- 1. franchise ids ----------------------------------------------------------------
select tests.as_anon();
select tests.eq('franchise: component label for members, the id itself for singletons, both media, unknown ids answered as themselves',
  (select string_agg(media_type || ':' || media_id || ':' || franchise_id, ',' order by media_type, media_id)
     from public.media_franchise_ids_v1(array[870002, 870001, 870003, 870001, null, -4], array[870101, 999999])),
  'ANIME:870001:870001,ANIME:870002:870001,ANIME:870003:870003,MANGA:870101:870101,MANGA:999999:999999');
select tests.eq('franchise: empty input answers no rows',
  (select count(*) from public.media_franchise_ids_v1('{}', '{}')), 0::bigint);
select tests.raises('franchise: more than 300 ids per medium raises TOO_MANY_IDS',
  $q$select * from public.media_franchise_ids_v1((select array_agg(g) from generate_series(1, 301) g), '{}')$q$, 'TOO_MANY_IDS:%');

-- ---- 2. section pages --------------------------------------------------------------------
select tests.as_user(tests.uid(871));
select tests.eq('trending (user): adult/coverless/SPECIAL dropped, Not interested + Seen it hidden, deck pass kept, franchise once (first in order wins), owned marked',
  (select string_agg(rank || ':' || id || ':' || coalesce(list_status, '-') || ':' || franchise_id, ',' order by rank)
     from public.discover_section_page_v1('trending', 'ANIME')),
  '1:870002:-:870001,2:870003:-:870003,3:870007:WATCHING:870007,4:870010:-:870010');
select tests.eq('trending: paging keeps the deduped order and ranks (offset 2, limit 2)',
  (select string_agg(rank || ':' || id, ',' order by rank) from public.discover_section_page_v1('trending', 'anime', null, null, null, null, 2, 2)),
  '3:870007,4:870010');
select tests.eq('trending: card columns (episode_count, null chapter_count, year, genres, medium)',
  (select episode_count || '/' || coalesce(chapter_count::text, 'null') || '/' || season_year || '/' || array_to_string(genres, '+') || '/' || media_type
     from public.discover_section_page_v1('trending', 'ANIME') where id = 870002),
  '12/null/2021/Action/ANIME');
select tests.eq('trending: a row without an English title keeps it null (romaji carried)',
  (select coalesce(title_english, 'null') || '/' || title_romaji from public.discover_section_page_v1('trending', 'ANIME') where id = 870002),
  'null/Franchise A 2');
select tests.eq('trending: an explicit SPECIAL format filter reaches the ancillary format',
  (select string_agg(id::text, ',') from public.discover_section_page_v1('trending', 'ANIME', null, 'special')), '870006');
select tests.eq('trending: length long = 51+ episodes (D10)',
  (select string_agg(id::text, ',') from public.discover_section_page_v1('trending', 'ANIME', null, null, 'long')), '870003');
select tests.eq('trending: length standard = 14-50 episodes (the 64-episode row is long only)',
  (select string_agg(id::text, ',' order by id) from public.discover_section_page_v1('trending', 'ANIME', null, null, 'standard')), '870007');
select tests.eq('trending: status releasing',
  (select string_agg(id::text, ',') from public.discover_section_page_v1('trending', 'ANIME', null, null, null, 'releasing')), '870007');
select tests.eq('trending: newest sorts by RELEASE date (start year/month/day), not created_at',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('trending', 'ANIME', 'newest')),
  '870007,870010,870002,870003');
select tests.eq('trending: top_rated sorts by score; the franchise slot goes to the best-ordered member',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('trending', 'ANIME', 'top_rated')),
  '870001,870007,870003,870010');

select tests.eq('new_to_you (user): score >= 80 by popularity, owned HIDDEN, hidden titles out, a 400-day-old skip shows again, franchise once',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('new_to_you', 'ANIME')),
  '870001,870003,870010,870015,870012,870014,870013');
select tests.eq('new_to_you never returns a list_status (owned titles are hidden there)',
  (select count(*) from public.discover_section_page_v1('new_to_you', 'ANIME') where list_status is not null), 0::bigint);

select tests.as_anon();
select tests.eq('trending (anon): no personal rules (hidden titles shown, nothing marked)',
  (select string_agg(id || ':' || coalesce(list_status, '-'), ',' order by rank) from public.discover_section_page_v1('trending', 'ANIME')),
  '870008:-,870002:-,870003:-,870007:-,870009:-,870010:-');

-- essentials: no curated table -> score >= 85 fallback by favourites
select tests.as_user(tests.uid(871));
select tests.eq('essentials without curated rails: score >= 85 by favourites (owned marked, hidden out)',
  (select string_agg(id || ':' || coalesce(list_status, '-'), ',' order by rank) from public.discover_section_page_v1('essentials', 'ANIME')),
  '870001:-,870003:-,870007:WATCHING');

select tests.reset();
create table public.curated_rail_items (rail_id text not null, media_type text not null, anilist_id integer not null, rank integer not null);
insert into public.curated_rail_items values
  ('gateway_anime', 'ANIME', 1870003, 1), ('gateway_anime', 'ANIME', 1870007, 2),
  ('gateway_anime', 'ANIME', 1870002, 3), ('gateway_anime', 'ANIME', 1870001, 4),
  ('gateway_anime', 'ANIME', 1870008, 5);
select tests.as_user(tests.uid(871));
select tests.eq('essentials with curated rails: curated rank order, franchise once, owned marked, hidden out',
  (select string_agg(id || ':' || coalesce(list_status, '-'), ',' order by rank) from public.discover_section_page_v1('essentials', 'ANIME')),
  '870003:-,870007:WATCHING,870002:-');
select tests.eq('essentials with curated rails, sorted popular: the more popular franchise member wins its slot',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('essentials', 'ANIME', 'popular')),
  '870001,870003,870007');
select tests.eq('classics without a curated classics rail: before 2015, score >= 80, by score',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('classics', 'ANIME')),
  '870003,870014,870015');

-- manga
select tests.eq('manga trending: by trending',
  (select string_agg(id || ':' || coalesce(chapter_count::text, 'null') || ':' || coalesce(episode_count::text, 'null'), ',' order by rank)
     from public.discover_section_page_v1('trending', 'MANGA')),
  '870102:300:null,870101:40:null');
select tests.eq('manga length short = 1-50 chapters',
  (select string_agg(id::text, ',') from public.discover_section_page_v1('top_rated', 'MANGA', null, null, 'short')), '870101');

-- ---- 3. moods -------------------------------------------------------------------------------
select tests.eq('short (anime): finished TV/ONA/OVA of 1-13 episodes or a <= 25 min movie, score >= 70, owned/hidden out, franchise once',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('short', 'ANIME')),
  '870001,870010,870015,870011,870014,870013');
select tests.eq('short (manga): finished, 1-50 chapters',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('short', 'MANGA')), '870101');
select tests.eq('cozy without the realm view: Slice of Life without Horror/Thriller/Psychological',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('cozy', 'ANIME')), '870013');
select tests.eq('intense without the realm view: Thriller/Horror/Psychological',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('intense', 'ANIME')), '870014');

select tests.reset();
-- Since 20261104100100 the mood reads the indexed rules matview media_realm_membership (not the
-- effective view); the stand-in takes that name.
create table public.media_realm_membership (media_type text, media_id integer, realm text, family text, weight real);
insert into public.media_realm_membership (media_type, media_id, realm, weight) values
  ('ANIME', 870013, 'slice-of-life-iyashikei', 0.6),
  ('ANIME', 870003, 'food-craft', 0.3), ('ANIME', 870003, 'horror-dread', 0.3),
  ('ANIME', 870010, 'family-generations', 0.2),
  ('ANIME', 870007, 'slice-of-life-iyashikei', 0.9),
  ('ANIME', 870014, 'horror-dread', 0.7), ('ANIME', 870014, 'psychological-thriller', 0.5),
  ('ANIME', 870001, 'dark-fantasy', 0.4), ('ANIME', 870002, 'dark-fantasy', 0.9),
  ('ANIME', 870008, 'dark-fantasy', 0.95);
select tests.as_user(tests.uid(871));
select tests.eq('cozy with realms: cozy realm >= 0.25, not in a dark realm >= 0.25, owned out, below-threshold out',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('cozy', 'ANIME')), '870013');
select tests.eq('intense with realms: by summed weight, hidden out, franchise once (the heavier member wins)',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('intense', 'ANIME')), '870014,870002,870003');

-- like_last_loved: recording stub for the similar reader (rolled back)
select tests.reset();
create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  perform set_config('tests.similar_args', p_media_type || '|' || array_to_string(p_seed_ids, ',') || '|' || p_limit || '|' || p_allow_gimmicks, true);
  return query select * from (values (870003, 9, 99::real), (870001, 5, 90::real), (870002, 5, 89::real),
    (870012, 4, 80::real), (870013, 3, 70::real)) v(a, b, c) limit p_limit;
end $$;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, updated_at) values
  (tests.uid(872)::text, 870003, 'COMPLETED', 64, 9, now() - interval '2 days'),
  (tests.uid(872)::text, 870012, 'COMPLETED', 1, 6, now() - interval '1 hour');
insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength) values
  (tests.uid(873), 870013, 'ANIME', 'deck_love', 0.55);

select tests.as_user(tests.uid(872));
select tests.eq('like_last_loved: the latest COMPLETED rated >= 8 is the seed (over a newer low rating); seed + owned out; franchise once',
  (select string_agg(id || ':' || reason_media_id || ':' || reason_title, ',' order by rank) from public.discover_mood_v1('like_last_loved', 'ANIME')),
  '870001:870003:Solo Long,870013:870003:Solo Long');
select tests.eq('like_last_loved calls the similar reader with ONE seed, depth 60, gimmicks off',
  current_setting('tests.similar_args', true), 'ANIME|870003|60|false');
select tests.as_user(tests.uid(873));
select tests.eq('like_last_loved: without a COMPLETED title the latest deck love is the seed',
  (select min(reason_media_id) from public.discover_mood_v1('like_last_loved', 'ANIME')), 870013);
select tests.as_user(tests.uid(874));
select tests.eq('like_last_loved: no seed answers no rows',
  (select count(*) from public.discover_mood_v1('like_last_loved', 'ANIME')), 0::bigint);
select tests.as_anon();
select tests.eq('like_last_loved: signed out answers no rows',
  (select count(*) from public.discover_mood_v1('like_last_loved', 'ANIME')), 0::bigint);

-- ---- 3b. pool depth (review fix): exclusions inside the candidate query, pool grows for franchises
-- 370 more anime, more popular than every row above: 0-199 on user 875's list, 200-239 answered
-- (Not interested / Seen it), 240-359 ONE franchise (120 seasons), 360-369 singles. The old fixed
-- pool (offset + limit * 4 + 40 = 60 candidates before any exclusion) answered NO rows here.
select tests.reset();
select tests.make_user(875);
insert into public.anime (id, anilist_id, title_romaji, cover_image_large, is_adult, format, status,
                          episodes, average_score, popularity, trending, favourites, genres)
select 871000 + g, 1871000 + g, 'Pool ' || g, 'https://img.invalid/p' || g || '.jpg', false, 'TV', 'FINISHED',
       12, 90, 100000 - g, 0, 0, array['Drama']
from generate_series(0, 369) g;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
select tests.uid(875)::text, 871000 + g, 'PLANNING', 0 from generate_series(0, 199) g;
insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength, created_at)
select tests.uid(875), 871000 + g, 'ANIME', case when g % 2 = 0 then 'deck_skip' else 'deck_known' end, 0,
       now() - interval '1 day'
from generate_series(200, 239) g;
insert into public.media_franchise_components (media_type, media_id, component_label)
select 'ANIME', 871000 + g, 871240 from generate_series(240, 359) g;
select tests.as_user(tests.uid(875));
select tests.eq('pool depth: 240 owned/answered titles ahead of the rest and a 120-title franchise still fill page 1 (new_to_you, limit 5)',
  (select string_agg(id::text, ',' order by rank) from public.discover_section_page_v1('new_to_you', 'ANIME', null, null, null, null, 5, 0)),
  '871240,871360,871361,871362,871363');
select tests.eq('pool depth: page 2 continues the deduped ranks (offset 5)',
  (select string_agg(rank || ':' || id, ',' order by rank) from public.discover_section_page_v1('new_to_you', 'ANIME', null, null, null, null, 5, 5)),
  '6:871364,7:871365,8:871366,9:871367,10:871368');
select tests.eq('pool depth: the short mood fills its page the same way',
  (select string_agg(id::text, ',' order by rank) from public.discover_mood_v1('short', 'ANIME', 5, 0)),
  '871240,871360,871361,871362,871363');
select tests.eq('pool depth: an editorial section (mark) keeps owned titles and marks them',
  (select string_agg(id || ':' || coalesce(list_status, '-'), ',' order by rank)
     from public.discover_section_page_v1('top_rated', 'ANIME', null, null, null, null, 2, 0)),
  '871000:PLANNING,871001:PLANNING');

-- ---- 4. typed errors ----------------------------------------------------------------------
select tests.raises('unknown medium', $q$select * from public.discover_section_page_v1('trending', 'NOVEL')$q$, 'INVALID_MEDIUM:%');
select tests.raises('unknown section', $q$select * from public.discover_section_page_v1('everything', 'ANIME')$q$, 'INVALID_SECTION:%');
select tests.raises('anime-only section asked for manga', $q$select * from public.discover_section_page_v1('current_season', 'MANGA')$q$, 'INVALID_SECTION:%');
select tests.raises('unknown sort', $q$select * from public.discover_section_page_v1('trending', 'ANIME', 'random')$q$, 'INVALID_SORT:%');
select tests.raises('unknown length', $q$select * from public.discover_section_page_v1('trending', 'ANIME', null, null, 'endless')$q$, 'INVALID_LENGTH:%');
select tests.raises('unknown status', $q$select * from public.discover_section_page_v1('trending', 'ANIME', null, null, null, 'cancelled')$q$, 'INVALID_STATUS:%');
select tests.raises('unknown mood', $q$select * from public.discover_mood_v1('sad', 'ANIME')$q$, 'INVALID_MOOD:%');
select tests.raises('mood: unknown medium', $q$select * from public.discover_mood_v1('short', 'NOVEL')$q$, 'INVALID_MEDIUM:%');

select tests.reset();
rollback;
