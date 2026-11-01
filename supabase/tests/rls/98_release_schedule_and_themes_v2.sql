-- 98_release_schedule_and_themes_v2.sql
-- Prepared 20261101000000_release_schedule_and_themes_v2.sql (NOT deployed):
-- RPC authorization (user schedule = authenticated only, public reads = anon + authenticated,
-- writers = service_role only), certainty filter (estimates only at confidence >= 0.7 and
-- never in the live home_events_page_v1), tracked-status scope, per-title next unit,
-- anime.next_airing_at fallback, idempotent natural-key upserts, all-or-nothing validation,
-- theme ordering/flags and convergence with finish_series_enrichment_v1's key.
-- Review repairs (2026-11-01): confirmed = instant only (D10), per-source credit-link hosts,
-- the 0.70 real/numeric confidence boundary, ISO-only instants, and finish_series_enrichment_v1
-- no longer deleting rows owned by upsert_theme_links_v1.
-- The tables and home_events_page_v1 come from 20261007040000 (live since 2026-10-08), so
-- they are prerequisites; every object this migration adds is the subject under test.
-- @requires table public.release_events
-- @requires table public.theme_links
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires function public.home_events_page_v1(text,integer,integer,text)
\set ON_ERROR_STOP on
\o /dev/null
\set as_service 'select tests.reset(); select set_config(''request.jwt.claims'', ''{"role":"service_role"}'', true); set local role service_role;'
begin;

-- ---- 0. posture ---------------------------------------------------------------
select tests.eq('all six new functions exist',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('user_release_schedule_v1', 'media_release_schedule_v1', 'media_themes_v1',
      'upsert_release_events_v1', 'upsert_theme_links_v1', '_release_schedule_units_v1')), 6::bigint);
select tests.eq('each new function is SECURITY DEFINER with search_path = public, extensions',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('user_release_schedule_v1', 'media_release_schedule_v1', 'media_themes_v1',
      'upsert_release_events_v1', 'upsert_theme_links_v1', '_release_schedule_units_v1')
      and p.prosecdef and p.proconfig @> array['search_path=public, extensions']), 6::bigint);
select tests.ok('user schedule: anon has no EXECUTE, authenticated has',
  not has_function_privilege('anon', 'public.user_release_schedule_v1(text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.user_release_schedule_v1(text,integer)', 'execute'));
select tests.ok('public reads: anon and authenticated have EXECUTE',
  has_function_privilege('anon', 'public.media_release_schedule_v1(text,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.media_release_schedule_v1(text,integer,integer)', 'execute')
  and has_function_privilege('anon', 'public.media_themes_v1(integer)', 'execute'));
select tests.ok('writers and helper: no EXECUTE for anon/authenticated; writers granted to service_role',
  not has_function_privilege('anon', 'public.upsert_release_events_v1(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.upsert_release_events_v1(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.upsert_theme_links_v1(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.upsert_theme_links_v1(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public._release_schedule_units_v1(integer[],integer[])', 'execute')
  and not has_function_privilege('authenticated', 'public._release_schedule_units_v1(integer[],integer[])', 'execute')
  and has_function_privilege('service_role', 'public.upsert_release_events_v1(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.upsert_theme_links_v1(jsonb)', 'execute'));
select tests.ok('release_events and theme_links keep RLS on',
  (select bool_and(relrowsecurity) from pg_class where oid in ('public.release_events'::regclass, 'public.theme_links'::regclass)));

-- ---- seed ----------------------------------------------------------------------
select tests.make_user(981), tests.make_user(982);
insert into public.anime (id, title_romaji, cover_image_large, anilist_id, next_episode_number, next_airing_at) values
  (990001, 'Fallback Show', 'https://img.invalid/990001.jpg', 12345, 7, now() + interval '2 days'),
  (990002, 'Delayed Show', null, 12346, 3, now() + interval '20 hours'),  -- stale cache: v2 says later
  (990003, 'Finished For Me', null, null, 9, now() + interval '1 day'),
  (990004, 'Nobody Tracks', null, null, 1, now() + interval '1 day');
insert into public.manga (id, title_english) values
  (990101, 'Weekly Manga'), (990102, 'Irregular Manga'), (990103, 'Volume Manga'),
  (990104, 'Boundary Manga'), (990105, 'Below Boundary Manga');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values
  (tests.uid(981)::text, 990001, 'WATCHING', 6),
  (tests.uid(981)::text, 990002, 'PLANNING', 0),
  (tests.uid(981)::text, 990003, 'COMPLETED', 9),
  (tests.uid(982)::text, 990004, 'WATCHING', 0);
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values
  (tests.uid(981)::text, 990101, 'READING', 100),
  (tests.uid(981)::text, 990102, 'READING', 5),
  (tests.uid(981)::text, 990103, 'PAUSED', 0);

-- ---- 1. writer authorization ---------------------------------------------------
select tests.as_user(tests.uid(981));
select tests.denied('authenticated cannot call upsert_release_events_v1',
  $q$select public.upsert_release_events_v1('[]'::jsonb)$q$);
select tests.denied('authenticated cannot call upsert_theme_links_v1',
  $q$select public.upsert_theme_links_v1('[]'::jsonb)$q$);
select tests.denied('authenticated cannot call the internal helper',
  $q$select * from public._release_schedule_units_v1(array[990001], null)$q$);
select tests.denied('authenticated cannot write release_events through the table API',
  $q$insert into public.release_events (medium, anime_id, kind, precision, status) values ('anime', 990001, 'x', 'unknown', 'announced')$q$);
select tests.denied('authenticated cannot write theme_links through the table API',
  $q$insert into public.theme_links (anime_id, role, match_state) values (990001, 'op', 'search')$q$);
select tests.as_anon();
select tests.denied('anon cannot call upsert_release_events_v1', $q$select public.upsert_release_events_v1('[]'::jsonb)$q$);
select tests.denied('anon cannot call user_release_schedule_v1', $q$select * from public.user_release_schedule_v1()$q$);

-- ---- 2. writes (service role) ---------------------------------------------------
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990002, 'unit_kind', 'episode', 'unit_number', 3,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '3 days', 'external_id', 'airing:555',
    'source_url', 'https://anilist.co/anime/12346'),
  jsonb_build_object('medium', 'anime', 'media_id', 990002, 'unit_kind', 'episode', 'unit_number', 2,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '4 days'),
  jsonb_build_object('medium', 'manga', 'media_id', 990101, 'unit_kind', 'chapter', 'unit_number', 101,
    'basis', 'estimated', 'source', 'kuro_estimate', 'confidence', 0.8, 'release_at', now() + interval '5 days'),
  jsonb_build_object('medium', 'manga', 'media_id', 990101, 'unit_kind', 'chapter', 'unit_number', 100,
    'basis', 'announced', 'source', 'mangaupdates', 'precision', 'day', 'status', 'released',
    'source_local_date', to_char(now() - interval '2 days', 'YYYY-MM-DD'), 'source_zone', 'Asia/Tokyo',
    'source_url', 'https://www.mangaupdates.com/series/pb8uwds'),
  jsonb_build_object('medium', 'manga', 'media_id', 990102, 'unit_kind', 'chapter', 'unit_number', 6,
    'basis', 'estimated', 'source', 'kuro_estimate', 'confidence', 0.5, 'release_at', now() + interval '1 day'),
  jsonb_build_object('medium', 'manga', 'media_id', 990103, 'unit_kind', 'volume', 'unit_number', 12,
    'basis', 'announced', 'source', 'publisher', 'precision', 'month',
    'source_local_date', to_char(date_trunc('month', now()) + interval '2 months', 'YYYY-MM-DD'))
)) as w1 \gset
select tests.reset();
select tests.eq('first write inserts six rows', :'w1'::jsonb, '{"inserted":6,"updated":0,"unchanged":0}'::jsonb);
select tests.eq('defaults: past confirmed instant is released, announced is announced, estimate is scheduled',
  (select string_agg(unit_label || '=' || status, ',' order by unit_label) from public.release_events
    where coalesce(anime_id, manga_id) in (990002, 990101, 990103)),
  'Ch. 100=released,Ch. 101=scheduled,Ep. 2=released,Ep. 3=scheduled,Vol. 12=announced');
select tests.eq('natural keys (estimate keyed per title + kind as :next)',
  (select string_agg(source_identity, ',' order by source_identity) from public.release_events where coalesce(anime_id, manga_id) in (990002, 990101)),
  'anilist:anime:990002:episode:2,anilist:anime:990002:episode:3,kuro_estimate:manga:990101:chapter:next,mangaupdates:manga:990101:chapter:100');
select tests.eq('kind (legacy readers) mirrors unit_label; evidence carries the external id',
  (select kind || '|' || evidence from public.release_events where source_identity = 'anilist:anime:990002:episode:3'),
  'Ep. 3|anilist:airing:555');

-- ---- 3. user_release_schedule_v1 ------------------------------------------------
select tests.as_user(tests.uid(981));
select tests.eq('user 981: one next unit per tracked title (COMPLETED excluded, low-confidence estimate hidden)',
  (select string_agg(media_id || ':' || unit_label || ':' || basis || ':' || source, ' | ' order by release_at nulls last, media_id)
     from public.user_release_schedule_v1()),
  '990001:Ep. 7:confirmed:anilist | 990002:Ep. 3:confirmed:anilist | 990101:Ch. 101:estimated:kuro_estimate | 990103:Vol. 12:announced:publisher');
select tests.eq('ordering is release_at ascending',
  (select string_agg(media_id::text, ',') from public.user_release_schedule_v1()),
  '990001,990002,990101,990103');
select tests.eq('fallback row: AniList next episode with confidence 1 and an AniList link',
  (select unit_kind || '/' || unit_number || '/' || confidence || '/' || source_url || '/' || release_precision || '/' || title || '/' || cover_image
     from public.user_release_schedule_v1() where media_id = 990001),
  'episode/7/1/https://anilist.co/anime/12345/instant/Fallback Show/https://img.invalid/990001.jpg');
select tests.ok('a fresher v2 AniList row suppresses the stale anime.next_airing_at (delay is honoured)',
  (select release_at > now() + interval '2 days' from public.user_release_schedule_v1() where media_id = 990002));
select tests.eq('estimate carries its confidence',
  (select confidence from public.user_release_schedule_v1() where media_id = 990101), 0.8::real);
select tests.eq('announced month window: release_at is the window start at 00:00 UTC, precision month',
  (select to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || '/' || release_precision
     from public.user_release_schedule_v1() where media_id = 990103),
  to_char(date_trunc('month', now()) + interval '2 months', 'YYYY-MM-DD') || ' 00:00/month');
select tests.eq('p_medium filters', (select count(*) from public.user_release_schedule_v1('manga')), 2::bigint);
select tests.eq('p_limit caps', (select count(*) from public.user_release_schedule_v1(null, 1)), 1::bigint);
select tests.raises('invalid medium raises INVALID_MEDIUM',
  $q$select * from public.user_release_schedule_v1('novel')$q$, 'INVALID_MEDIUM:%');
select tests.as_user(tests.uid(982));
select tests.eq('user 982 sees only their own tracked title',
  (select string_agg(media_id::text, ',') from public.user_release_schedule_v1()), '990004');
select tests.reset();
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
select tests.raises('a JWT without a user raises UNAUTHENTICATED',
  $q$select * from public.user_release_schedule_v1()$q$, 'UNAUTHENTICATED:%');
select tests.reset();

-- ---- 4. estimates never reach the live Home RPC ----------------------------------
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'manga', 'media_id', 990101, 'unit_kind', 'chapter', 'unit_number', 101,
    'basis', 'estimated', 'source', 'kuro_estimate', 'confidence', 0.95, 'release_at', now() + interval '2 days'),
  jsonb_build_object('medium', 'manga', 'media_id', 990102, 'unit_kind', 'chapter', 'unit_number', 6,
    'basis', 'confirmed', 'source', 'mangaupdates', 'release_at', now() + interval '3 days')
)) as w_home \gset
select tests.as_user(tests.uid(981));
select public.home_events_page_v1('manga', 7, 50, null) as home_manga \gset
select tests.eq('home_events_page_v1 (manga): the confirmed chapter is listed (not vacuous)',
  (select count(*) from jsonb_array_elements((:'home_manga'::jsonb) -> 'items') e where (e ->> 'media_id')::int = 990102), 1::bigint);
select tests.eq('home_events_page_v1 (manga): no estimated row is shown as a fact',
  (select count(*) from jsonb_array_elements((:'home_manga'::jsonb) -> 'items') e where (e ->> 'media_id')::int = 990101), 0::bigint);
select public.home_events_page_v1('anime', 7, 50, null) as home_anime \gset
select tests.ok('home_events_page_v1 (anime) still lists the confirmed v2 episode',
  exists (select 1 from jsonb_array_elements((:'home_anime'::jsonb) -> 'items') e
          where (e ->> 'media_id')::int = 990002 and e ->> 'unit_label' = 'Ep. 3'));
select tests.reset();

-- ---- 5. media_release_schedule_v1 (anon) ----------------------------------------
select tests.as_anon();
select tests.eq('anime 990002: last confirmed past unit first (is_past), then upcoming',
  (select string_agg(unit_label || ':' || is_past, ',') from public.media_release_schedule_v1('anime', 990002)),
  'Ep. 2:true,Ep. 3:false');
select tests.eq('manga 990101: an announced (day) past chapter is not the "last confirmed" unit; the replaced estimate (Ch. 101 @ 0.95) is',
  (select string_agg(unit_label || ':' || basis || ':' || is_past || ':' || release_precision, ',') from public.media_release_schedule_v1('manga', 990101)),
  'Ch. 101:estimated:false:instant');
select tests.reset();
select tests.eq('day precision release_at is local midnight in source_zone (helper, as owner)',
  (select to_char(release_at at time zone 'Asia/Tokyo', 'HH24:MI') || '/' || basis || '/' || is_past
     from public._release_schedule_units_v1(null, array[990101]) where unit_number = 100), '00:00/announced/true');
select tests.as_anon();
select tests.eq('anime 990001: fallback row for anon', (select count(*) from public.media_release_schedule_v1('anime', 990001)), 1::bigint);
select tests.eq('unknown id: empty, not an error', (select count(*) from public.media_release_schedule_v1('anime', 999999)), 0::bigint);
select tests.raises('invalid medium raises INVALID_MEDIUM', $q$select * from public.media_release_schedule_v1('film', 1)$q$, 'INVALID_MEDIUM:%');
select tests.raises('missing id raises INVALID_MEDIA_ID', $q$select * from public.media_release_schedule_v1('anime', null)$q$, 'INVALID_MEDIA_ID:%');
select tests.reset();

-- ---- 5b. AniList's live next pointer beats a stale v2 AniList row (long delay / hiatus) ----
-- The intake only rewrites rows inside [now-6h, now+8d]. When AniList moves ep 7 three weeks out,
-- bulk-import moves anime.next_airing_at but the v2 ep-7 row keeps the cancelled instant.
--   990005: AFTER the old instant (v2 ep 7 in the past, still 'scheduled'; ep 6 really released)
--   990006: BEFORE the old instant (v2 ep 7 at +2 days; an ep 8 row at +9 days that cannot air
--           before ep 7 is stale too)
-- Own user and ids, so the section-3 per-user aggregates above are unaffected.
select tests.make_user(983);
insert into public.anime (id, title_romaji, anilist_id, next_episode_number, next_airing_at) values
  (990005, 'Long Delay Show', 12347, 7, now() + interval '21 days'),
  (990006, 'Pre Delay Show', 12348, 7, now() + interval '21 days');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values
  (tests.uid(983)::text, 990005, 'WATCHING', 6),
  (tests.uid(983)::text, 990006, 'WATCHING', 6);
select to_char(next_airing_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') as t2_utc
  from public.anime where id = 990005 \gset
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990005, 'unit_kind', 'episode', 'unit_number', 6,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '8 days'),
  jsonb_build_object('medium', 'anime', 'media_id', 990005, 'unit_kind', 'episode', 'unit_number', 7,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '1 day', 'status', 'scheduled'),
  jsonb_build_object('medium', 'anime', 'media_id', 990006, 'unit_kind', 'episode', 'unit_number', 7,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '2 days'),
  jsonb_build_object('medium', 'anime', 'media_id', 990006, 'unit_kind', 'episode', 'unit_number', 8,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '9 days')
)) as w_stale \gset
select tests.reset();
select tests.eq('stale-row seed: four rows, ep 6 released, the stale ep 7 still scheduled',
  (select string_agg(anime_id || ':' || unit_label || '=' || status, ',' order by anime_id, unit_number)
     from public.release_events where anime_id in (990005, 990006)),
  '990005:Ep. 6=released,990005:Ep. 7=scheduled,990006:Ep. 7=scheduled,990006:Ep. 8=scheduled');
select tests.as_user(tests.uid(983));
select tests.eq('after the cancelled instant: the user schedule keeps the title, ep 7 at the pointer''s new time',
  (select unit_label || '@' || to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '/' || basis || '/' || source
     from public.user_release_schedule_v1() where media_id = 990005),
  'Ep. 7@' || :'t2_utc' || '/confirmed/anilist');
select tests.eq('before the cancelled instant: ep 7 at the pointer''s new time, not the stale +2 days',
  (select unit_label || '@' || to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
     from public.user_release_schedule_v1() where media_id = 990006),
  'Ep. 7@' || :'t2_utc');
select tests.reset();
select tests.as_anon();
select tests.eq('media schedule 990005: the past row is the released ep 6, never the un-aired ep 7; ep 7 upcoming at the new time',
  (select string_agg(unit_label || ':' || is_past || '@' || to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ',')
     from public.media_release_schedule_v1('anime', 990005) where unit_number = 7 or is_past),
  'Ep. 6:true@' || to_char((select utc_instant from public.release_events where source_identity = 'anilist:anime:990005:episode:6') at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
    || ',Ep. 7:false@' || :'t2_utc');
select tests.eq('media schedule 990005: no is_past row claims ep 7 aired',
  (select count(*) from public.media_release_schedule_v1('anime', 990005) where is_past and unit_number = 7), 0::bigint);
select tests.eq('media schedule 990006: only ep 7 at the new time (stale ep 7 and the impossible earlier ep 8 dropped)',
  (select string_agg(unit_label || ':' || is_past || '@' || to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'), ',')
     from public.media_release_schedule_v1('anime', 990006)),
  'Ep. 7:false@' || :'t2_utc');
select tests.reset();
-- a v2 row LATER than the pointer for the same episode still wins (fresh delay, cached pointer lags)
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990006, 'unit_kind', 'episode', 'unit_number', 7,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '28 days', 'status', 'delayed')
)) as w_later \gset
select tests.reset();
select tests.as_anon();
select tests.ok('a v2 ep 7 later than the pointer suppresses the fallback (one ep 7, at +28 days)',
  (select count(*) = 1 and min(release_at) > now() + interval '27 days'
     from public.media_release_schedule_v1('anime', 990006) where unit_number = 7));
select tests.reset();
-- each rule on its own (the pointer-drop above would otherwise mask them):
--   990007: no pointer at all, so nothing is dropped; a passed but never-released ep 4 must not
--           be the "last aired" unit (status rule in media_release_schedule_v1)
--   990008: a RELEASED v2 ep 7 is kept (not stale), the pointer says ep 7 is next at +21 days;
--           the upcoming fallback must win the unit over the past row (is_past-first DISTINCT ON)
insert into public.anime (id, title_romaji, anilist_id, next_episode_number, next_airing_at) values
  (990007, 'No Pointer Show', 12349, null, null),
  (990008, 'Released Then Moved Show', 12350, 7, now() + interval '21 days');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values
  (tests.uid(983)::text, 990007, 'WATCHING', 3),
  (tests.uid(983)::text, 990008, 'WATCHING', 6);
select to_char(next_airing_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') as t2_008_utc
  from public.anime where id = 990008 \gset
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990007, 'unit_kind', 'episode', 'unit_number', 3,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '10 days'),
  jsonb_build_object('medium', 'anime', 'media_id', 990007, 'unit_kind', 'episode', 'unit_number', 4,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '1 day', 'status', 'scheduled'),
  jsonb_build_object('medium', 'anime', 'media_id', 990008, 'unit_kind', 'episode', 'unit_number', 7,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() - interval '1 day', 'status', 'released')
)) as w_rules \gset
select tests.reset();
select tests.as_anon();
select tests.eq('media schedule 990007: the last aired unit is the released ep 3, not the passed-but-scheduled ep 4',
  (select string_agg(unit_label, ',') from public.media_release_schedule_v1('anime', 990007) where is_past), 'Ep. 3');
select tests.reset();
select tests.as_user(tests.uid(983));
select tests.eq('user schedule 990008: the upcoming fallback ep 7 wins the unit over a past released ep 7 row',
  (select unit_label || '@' || to_char(release_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
     from public.user_release_schedule_v1() where media_id = 990008),
  'Ep. 7@' || :'t2_008_utc');
select tests.reset();

-- ---- 6. idempotency and natural keys --------------------------------------------
select revision as rev_before from public.release_events where source_identity = 'anilist:anime:990002:episode:3' \gset
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990002, 'unit_kind', 'episode', 'unit_number', 3,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '3 days', 'external_id', 'airing:555',
    'source_url', 'https://anilist.co/anime/12346'))) as w_same \gset
select tests.reset();
select tests.eq('identical re-run: unchanged, nothing inserted or updated', :'w_same'::jsonb, '{"inserted":0,"updated":0,"unchanged":1}'::jsonb);
select tests.eq('identical re-run does not advance revision',
  (select revision from public.release_events where source_identity = 'anilist:anime:990002:episode:3'), :'rev_before'::bigint);
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'anime', 'media_id', 990002, 'unit_kind', 'episode', 'unit_number', 3,
    'basis', 'confirmed', 'source', 'anilist', 'release_at', now() + interval '10 days', 'status', 'delayed',
    'external_id', 'airing:555', 'source_url', 'https://anilist.co/anime/12346'))) as w_delay \gset
select tests.reset();
select tests.eq('a delay updates the same row', :'w_delay'::jsonb, '{"inserted":0,"updated":1,"unchanged":0}'::jsonb);
select tests.eq('one row per natural key, revision advanced once, status delayed',
  (select count(*) || '/' || max(revision) || '/' || max(status) from public.release_events where source_identity = 'anilist:anime:990002:episode:3'),
  '1/' || (:'rev_before'::bigint + 1) || '/delayed');
select tests.eq('estimates do not pile up: one kuro_estimate row per title and kind',
  (select count(*) from public.release_events where manga_id = 990101 and basis = 'estimated'), 1::bigint);

-- ---- 7. validation: codes in the message, all-or-nothing --------------------------
select count(*) as n_before from public.release_events \gset
:as_service
select tests.raises('not an array -> INVALID_PAYLOAD', $q$select public.upsert_release_events_v1('{}'::jsonb)$q$, 'INVALID_PAYLOAD:%');
select tests.raises('unknown media -> MEDIA_NOT_FOUND (and the valid first row is not written)',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z"},
                                             {"medium":"anime","media_id":999999,"unit_kind":"episode","unit_number":1,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z"}]'::jsonb)$q$,
  'MEDIA_NOT_FOUND:%');
select tests.raises('chapter on anime -> INVALID_UNIT_KIND',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"chapter","unit_number":1,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z"}]'::jsonb)$q$,
  'INVALID_UNIT_KIND:%');
select tests.raises('estimate without confidence -> INVALID_CONFIDENCE',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":102,"basis":"estimated","source":"kuro_estimate","release_at":"2030-01-01T00:00:00Z"}]'::jsonb)$q$,
  'INVALID_CONFIDENCE:%');
select tests.raises('estimate claiming a provider source -> INVALID_SOURCE',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":102,"basis":"estimated","source":"mangaupdates","confidence":0.9,"release_at":"2030-01-01T00:00:00Z"}]'::jsonb)$q$,
  'INVALID_SOURCE:%');
select tests.raises('confirmed with only a month -> INVALID_PRECISION',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990103,"unit_kind":"volume","unit_number":13,"basis":"confirmed","source":"publisher","precision":"month","source_local_date":"2030-03-01"}]'::jsonb)$q$,
  'INVALID_PRECISION:%');
select tests.raises('month window not starting on the 1st -> INVALID_PRECISION',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990103,"unit_kind":"volume","unit_number":13,"basis":"announced","source":"publisher","precision":"month","source_local_date":"2030-03-15"}]'::jsonb)$q$,
  'INVALID_PRECISION:%');
select tests.raises('non-https source_url -> INVALID_SOURCE_URL',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z","source_url":"javascript:alert(1)"}]'::jsonb)$q$,
  'INVALID_SOURCE_URL:%');
select tests.raises('unknown zone -> INVALID_SOURCE_ZONE',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":103,"basis":"announced","source":"mangaupdates","source_local_date":"2030-01-01","source_zone":"Mars/Base"}]'::jsonb)$q$,
  'INVALID_SOURCE_ZONE:%');
select tests.raises('D10: confirmed with only a day (no time) -> INVALID_PRECISION',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":103,"basis":"confirmed","source":"mangaupdates","source_local_date":"2030-01-01"}]'::jsonb)$q$,
  'INVALID_PRECISION:%');
select tests.raises('credit link on a foreign host for anilist -> INVALID_SOURCE_URL',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z","source_url":"https://any-host.example/anime/12345"}]'::jsonb)$q$,
  'INVALID_SOURCE_URL:%');
select tests.raises('look-alike host (mangaupdates.com.evil.example) -> INVALID_SOURCE_URL',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":103,"basis":"announced","source":"mangaupdates","source_local_date":"2030-01-01","source_url":"https://mangaupdates.com.evil.example/series/pb8uwds"}]'::jsonb)$q$,
  'INVALID_SOURCE_URL:%');
select tests.raises('an estimate crediting a non-MangaUpdates host -> INVALID_SOURCE_URL',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990101,"unit_kind":"chapter","unit_number":103,"basis":"estimated","source":"kuro_estimate","confidence":0.9,"source_local_date":"2030-01-01","source_url":"https://anilist.co/manga/1"}]'::jsonb)$q$,
  'INVALID_SOURCE_URL:%');
select tests.raises('publisher rows carry no link until a publisher host list exists -> INVALID_SOURCE_URL',
  $q$select public.upsert_release_events_v1('[{"medium":"manga","media_id":990103,"unit_kind":"volume","unit_number":13,"basis":"announced","source":"publisher","precision":"month","source_local_date":"2030-03-01","source_url":"https://publisher.example/x"}]'::jsonb)$q$,
  'INVALID_SOURCE_URL:%');
select tests.raises('release_at ''infinity'' -> INVALID_RELEASE_AT',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"infinity"}]'::jsonb)$q$,
  'INVALID_RELEASE_AT:%');
select tests.raises('release_at ''tomorrow'' -> INVALID_RELEASE_AT',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"tomorrow"}]'::jsonb)$q$,
  'INVALID_RELEASE_AT:%');
select tests.raises('release_at far in the future -> INVALID_RELEASE_AT',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"9999-01-01T00:00:00Z"}]'::jsonb)$q$,
  'INVALID_RELEASE_AT:%');
select tests.raises('observed_at ''epoch'' -> INVALID_OBSERVED_AT',
  $q$select public.upsert_release_events_v1('[{"medium":"anime","media_id":990001,"unit_kind":"episode","unit_number":8,"basis":"confirmed","source":"anilist","release_at":"2030-01-01T00:00:00Z","observed_at":"epoch"}]'::jsonb)$q$,
  'INVALID_OBSERVED_AT:%');
select tests.reset();
select tests.eq('failed calls wrote nothing', (select count(*) from public.release_events), :'n_before'::bigint);
select tests.raises('table constraint backstop: a direct estimated row without confidence is rejected',
  $q$insert into public.release_events (medium, manga_id, kind, precision, utc_instant, status, unit_kind, unit_number, unit_label, basis, source, observed_at)
     values ('manga', 990101, 'Ch. 9', 'instant', now(), 'scheduled', 'chapter', 9, 'Ch. 9', 'estimated', 'kuro_estimate', now())$q$,
  '%release_events_estimate_check%');
select tests.raises('table constraint backstop: a direct row crediting a foreign host is rejected',
  $q$insert into public.release_events (medium, anime_id, kind, precision, utc_instant, status, unit_kind, unit_number, unit_label, basis, source, source_url, observed_at)
     values ('anime', 990001, 'Ep. 9', 'instant', now(), 'scheduled', 'episode', 9, 'Ep. 9', 'confirmed', 'anilist', 'https://evil.example/anime/1', now())$q$,
  '%release_events_source_url_check%');
select tests.raises('table constraint backstop: a direct confirmed day row is rejected (D10)',
  $q$insert into public.release_events (medium, manga_id, kind, precision, source_local_date, status, unit_kind, unit_number, unit_label, basis, source, observed_at)
     values ('manga', 990101, 'Ch. 9', 'day', '2030-01-01', 'scheduled', 'chapter', 9, 'Ch. 9', 'confirmed', 'mangaupdates', now())$q$,
  '%release_events_confirmed_instant_check%');

-- ---- 7b. confidence boundary: 0.70 is shown, 0.69 is hidden (real vs numeric) ---------
:as_service
select public.upsert_release_events_v1(jsonb_build_array(
  jsonb_build_object('medium', 'manga', 'media_id', 990104, 'unit_kind', 'chapter', 'unit_number', 50,
    'basis', 'estimated', 'source', 'kuro_estimate', 'confidence', 0.7, 'precision', 'day',
    'source_local_date', to_char(now() + interval '6 days', 'YYYY-MM-DD'),
    'source_url', 'https://www.mangaupdates.com/series/abc'),
  jsonb_build_object('medium', 'manga', 'media_id', 990105, 'unit_kind', 'chapter', 'unit_number', 50,
    'basis', 'estimated', 'source', 'kuro_estimate', 'confidence', 0.69, 'precision', 'day',
    'source_local_date', to_char(now() + interval '6 days', 'YYYY-MM-DD'))
)) as w_bound \gset
select tests.as_anon();
select tests.eq('an estimate scored exactly 0.70 is returned',
  (select count(*) from public.media_release_schedule_v1('manga', 990104) where basis = 'estimated'), 1::bigint);
select tests.eq('an estimate scored 0.69 is hidden',
  (select count(*) from public.media_release_schedule_v1('manga', 990105)), 0::bigint);
select tests.reset();

-- ---- 8. themes -------------------------------------------------------------------
-- a row as finish_series_enrichment_v1 writes it (no source column), plus a curated and an unmatched row
insert into public.theme_links (anime_id, role, sequence_order, song_title, artist, match_state, evidence, source_identity) values
  (990001, 'op', 1, 'Old Title', 'Old Artist', 'search', 'Exact external ID: 12345 / ', 'animethemes:990001:t1'),
  (990001, 'ed', 2, 'Curated Ending', 'Someone', 'verified', 'curated', null),
  (990001, 'op', 9, 'Unmatched', null, 'unmatched', 'x', null);
:as_service
select public.upsert_theme_links_v1(jsonb_build_array(
  jsonb_build_object('anime_id', 990001, 'source_id', 't1', 'kind', 'OP', 'sequence', 1, 'title', 'First Light',
    'artist', 'Band A', 'episodes', '1-12', 'source_url', 'https://animethemes.moe/anime/x'),
  jsonb_build_object('anime_id', 990001, 'source_id', 't2', 'kind', 'ED', 'sequence', 1, 'title', 'Night Walk',
    'artist', 'Singer B', 'episodes', '1-11'),
  jsonb_build_object('anime_id', 990001, 'source_id', 't3', 'kind', 'IN', 'sequence', 1, 'title', 'Battle Hymn',
    'version', 2, 'is_spoiler', true, 'is_nsfw', true),
  jsonb_build_object('anime_id', 990001, 'source_id', 't4', 'kind', 'OP', 'sequence', 2, 'title', 'Second Light')
)) as t1 \gset
select tests.reset();
select tests.eq('theme upsert: one converged update (finish_series row), three inserts',
  :'t1'::jsonb, '{"inserted":3,"updated":1,"unchanged":0}'::jsonb);
select tests.eq('the finish_series_enrichment_v1 row was converged, not duplicated',
  (select count(*) || '/' || max(song_title) || '/' || max(source) || '/' || max(match_state) || '/' || coalesce(max(external_url), 'null')
     from public.theme_links where source_identity = 'animethemes:990001:t1'),
  '1/First Light/animethemes/search/null');
select tests.as_anon();
select tests.eq('media_themes_v1: OP, ED, IN order; sequence; unmatched hidden; curated kept',
  (select string_agg(kind || sequence || ':' || title, ',') from public.media_themes_v1(990001)),
  'OP1:First Light,OP2:Second Light,ED1:Night Walk,ED2:Curated Ending,IN1:Battle Hymn');
select tests.eq('flags, version, episodes and source come back',
  (select string_agg(coalesce(episodes, '-') || '/' || coalesce(version::text, '-') || '/' || is_spoiler || '/' || is_nsfw || '/' || coalesce(source, '-'), ',')
     from public.media_themes_v1(990001)),
  '1-12/-/false/false/animethemes,-/-/false/false/animethemes,1-11/-/false/false/animethemes,-/-/false/false/-,-/2/true/true/animethemes');
select tests.eq('no themes: empty', (select count(*) from public.media_themes_v1(990004)), 0::bigint);
select tests.reset();
:as_service
select public.upsert_theme_links_v1(jsonb_build_array(
  jsonb_build_object('anime_id', 990001, 'source_id', 't2', 'kind', 'ED', 'sequence', 1, 'title', 'Night Walk',
    'artist', 'Singer B', 'episodes', '1-11'))) as t_same \gset
select tests.raises('theme validation: bad kind -> INVALID_KIND',
  $q$select public.upsert_theme_links_v1('[{"anime_id":990001,"source_id":"t9","kind":"BGM","title":"x"}]'::jsonb)$q$, 'INVALID_KIND:%');
select tests.raises('theme validation: unknown anime -> MEDIA_NOT_FOUND',
  $q$select public.upsert_theme_links_v1('[{"anime_id":999999,"source_id":"t9","kind":"OP","title":"x"}]'::jsonb)$q$, 'MEDIA_NOT_FOUND:%');
select tests.raises('theme validation: unsafe source_id -> INVALID_SOURCE_ID',
  $q$select public.upsert_theme_links_v1('[{"anime_id":990001,"source_id":"a:b","kind":"OP","title":"x"}]'::jsonb)$q$, 'INVALID_SOURCE_ID:%');
select tests.reset();
select tests.eq('identical theme re-run is unchanged', :'t_same'::jsonb, '{"inserted":0,"updated":0,"unchanged":1}'::jsonb);
select tests.eq('theme rows for the anime (4 producer + 2 others)', (select count(*) from public.theme_links where anime_id = 990001), 6::bigint);
:as_service
select tests.raises('theme validation: credit link on a foreign host -> INVALID_SOURCE_URL',
  $q$select public.upsert_theme_links_v1('[{"anime_id":990001,"source_id":"t9","kind":"OP","title":"x","source_url":"https://evil.example/anime/x"}]'::jsonb)$q$, 'INVALID_SOURCE_URL:%');
select tests.reset();
select tests.raises('theme table constraint backstop: a foreign credit host is rejected',
  $q$insert into public.theme_links (anime_id, role, match_state, source_url) values (990001, 'op', 'search', 'https://animethemes.moe.evil.example/x')$q$,
  '%theme_links_source_url_check%');

-- ---- 9. finish_series_enrichment_v1 cannot delete rows owned by upsert_theme_links_v1 ----
-- a legacy finish-written row (source NULL) that the incoming set drops IS deleted (its own key
-- space); the upsert-owned rows t2/t3/t4 (source animethemes) are kept.
insert into public.theme_links (anime_id, role, sequence_order, song_title, match_state, evidence, source_identity)
values (990001, 'op', 5, 'Legacy Only', 'search', 'Exact external ID: 12345 / ', 'animethemes:990001:t9');
insert into public.series_enrichment_jobs (medium, media_id, source_revision, payload, lease_token, lease_until)
values ('anime', 990001, 'rev-98', '{}'::jsonb, '00000000-0000-0000-0000-000000000098', now() + interval '1 hour')
on conflict (medium, media_id) do update set source_revision = excluded.source_revision, payload = excluded.payload,
  lease_token = excluded.lease_token, lease_until = excluded.lease_until;
:as_service
select public.finish_series_enrichment_v1('anime', 990001, 'rev-98', '00000000-0000-0000-0000-000000000098', null, null,
  '[{"source_id":"t1","role":"op","sequence_order":1,"song_title":"First Light","artist":"Band A"}]'::jsonb) as fin \gset
select tests.reset();
select tests.eq('finish with p_themes applied', :'fin'::jsonb ->> 'outcome', 'applied');
select tests.eq('finish deleted only its own dropped key (t9); upsert-owned t2/t3/t4 survive',
  (select string_agg(source_identity, ',' order by source_identity) from public.theme_links
     where anime_id = 990001 and source_identity like 'animethemes:%'),
  'animethemes:990001:t1,animethemes:990001:t2,animethemes:990001:t3,animethemes:990001:t4');

select tests.reset();
rollback;
