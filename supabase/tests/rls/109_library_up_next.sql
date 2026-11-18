-- W10 Up next: library_up_next_v1 posture, row rules and the 2,000-title plan check.
-- Disposable local fixture only, never hosted.
-- @requires table public.media_relations
-- @requires table public.series_entry_spans
-- @requires table public.taste_signal_events
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;

select tests.ok('library_up_next_v1 is SECURITY INVOKER, STABLE, plpgsql, search_path = public, extensions',
  (select not prosecdef and provolatile='s' and prolang=(select oid from pg_language where lanname='plpgsql')
          and proconfig @> array['search_path=public, extensions']
     from pg_proc where oid='public.library_up_next_v1(text,integer)'::regprocedure));
select tests.ok('authenticated may execute; anon and PUBLIC may not',
  has_function_privilege('authenticated','public.library_up_next_v1(text,integer)','execute')
  and not has_function_privilege('anon','public.library_up_next_v1(text,integer)','execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid='public.library_up_next_v1(text,integer)'::regprocedure and a.grantee=0));
select tests.ok('invoker prerequisites: authenticated can read every relation the body reads',
  has_table_privilege('authenticated','public.media_relations','select')
  and has_table_privilege('authenticated','public.series','select')
  and has_table_privilege('authenticated','public.series_sections','select')
  and has_table_privilege('authenticated','public.series_entry_spans','select')
  and has_table_privilege('authenticated','public.taste_signal_events','select')
  and has_table_privilege('authenticated','public.anime_user_lists','select')
  and has_table_privilege('authenticated','public.manga_user_lists','select'));
select tests.ok('the body never reads media_franchise_components (no client grant: invoker trap)',
  (select prosrc not like '%media_franchise_components%' from pg_proc
    where oid='public.library_up_next_v1(text,integer)'::regprocedure));
select tests.raises('an unknown medium is a typed error in the MESSAGE',
  $$select * from public.library_up_next_v1('film', 30)$$, '%INVALID_MEDIUM%');

-- ---------------------------------------------------------------------------
-- Row rules (ids 1090001+; users 1091 (main), 1092, 1096 (limit)).
-- Seeded as the superuser with triggers skipped (the 102 pattern).
-- ---------------------------------------------------------------------------
select tests.make_user(1091);
select tests.make_user(1092);
select tests.make_user(1096);
set local session_replication_role = replica;

create function pg_temp.a(p_id integer, p_title text, p_format text default 'TV', p_status text default 'FINISHED',
                          p_genres text[] default array['Drama'], p_adult boolean default false) returns void
language plpgsql as $$
begin
  insert into public.anime (id, title_romaji, format, status, genres, is_adult, episodes, season_year)
  values (1090000 + p_id, p_title, p_format, p_status, p_genres, p_adult, 12, 2024)
  on conflict (id) do nothing;
end $$;
create function pg_temp.m(p_id integer, p_title text) returns void
language plpgsql as $$
begin
  insert into public.manga (id, title_romaji, format, status, genres, is_adult, chapters, start_date_year)
  values (1090000 + p_id, p_title, 'MANGA', 'FINISHED', array['Drama'], false, 40, 2020)
  on conflict (id) do nothing;
end $$;
create function pg_temp.l(p_user integer, p_id integer, p_type text, p_ago interval default interval '10 days') returns void
language plpgsql as $$
begin
  insert into public.anime_user_lists (user_id, anime_id, list_type, progress, updated_at)
  values (tests.uid(p_user)::text, 1090000 + p_id, p_type, 0, now() - p_ago);
end $$;
create function pg_temp.rel(p_from integer, p_to integer, p_type text default 'SEQUEL') returns void
language plpgsql as $$
begin
  insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
  values ('ANIME', 1090000 + p_from, p_type, 'ANIME', 1090000 + p_to);
end $$;
create function pg_temp.skip(p_user integer, p_id integer, p_type text, p_ago interval default interval '1 day') returns void
language plpgsql as $$
begin
  insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength, created_at)
  values (tests.uid(p_user), 1090000 + p_id, 'ANIME', p_type, 0, now() - p_ago);
end $$;

-- 1: plain sequel, completed one hour ago (newest predecessor)
select pg_temp.a(101, 'Frieren'); select pg_temp.a(201, 'Frieren S2');
select pg_temp.l(1091, 101, 'COMPLETED', interval '1 hour'); select pg_temp.rel(101, 201);
-- 2: target already in the library
select pg_temp.a(102, 'Owned src'); select pg_temp.a(202, 'Owned target');
select pg_temp.l(1091, 102, 'COMPLETED', interval '1 day'); select pg_temp.l(1091, 202, 'PLANNING'); select pg_temp.rel(102, 202);
-- 3/4/5/6: dismissals (365-day window)
select pg_temp.a(103, 'Skip src'); select pg_temp.a(203, 'Skipped');
select pg_temp.l(1091, 103, 'COMPLETED', interval '2 days'); select pg_temp.rel(103, 203); select pg_temp.skip(1091, 203, 'deck_skip');
select pg_temp.a(104, 'Known src'); select pg_temp.a(204, 'Known');
select pg_temp.l(1091, 104, 'COMPLETED', interval '3 days'); select pg_temp.rel(104, 204); select pg_temp.skip(1091, 204, 'deck_known');
select pg_temp.a(105, 'Pass src'); select pg_temp.a(205, 'Passed');
select pg_temp.l(1091, 105, 'COMPLETED', interval '4 days'); select pg_temp.rel(105, 205); select pg_temp.skip(1091, 205, 'deck_pass');
select pg_temp.a(106, 'Old skip src'); select pg_temp.a(206, 'Old skip');
select pg_temp.l(1091, 106, 'COMPLETED', interval '5 days'); select pg_temp.rel(106, 206); select pg_temp.skip(1091, 206, 'deck_skip', interval '400 days');
-- 7..14: catalogue exclusions (12 NOT_YET_RELEASED is listed)
select pg_temp.a(107, 'Adult src'); select pg_temp.a(207, 'Adult', 'TV', 'FINISHED', array['Drama'], true);
select pg_temp.a(108, 'Hentai src'); select pg_temp.a(208, 'Hentai', 'TV', 'FINISHED', array['Hentai']);
select pg_temp.a(109, 'Ecchi src'); select pg_temp.a(209, 'Ecchi', 'TV', 'FINISHED', array['Ecchi']);
select pg_temp.a(110, 'Music src'); select pg_temp.a(210, 'Music', 'MUSIC');
select pg_temp.a(111, 'Cancelled src'); select pg_temp.a(211, 'Cancelled', 'TV', 'CANCELLED');
select pg_temp.a(112, 'Announced src'); select pg_temp.a(212, 'Announced', 'TV', 'NOT_YET_RELEASED');
select pg_temp.a(113, 'Special src'); select pg_temp.a(213, 'Special', 'SPECIAL');
select pg_temp.a(114, 'Short src'); select pg_temp.a(214, 'Short', 'TV_SHORT');
select pg_temp.l(1091, 107, 'COMPLETED', interval '6 days'); select pg_temp.rel(107, 207);
select pg_temp.l(1091, 108, 'COMPLETED', interval '6 days'); select pg_temp.rel(108, 208);
select pg_temp.l(1091, 109, 'COMPLETED', interval '6 days'); select pg_temp.rel(109, 209);
select pg_temp.l(1091, 110, 'COMPLETED', interval '6 days'); select pg_temp.rel(110, 210);
select pg_temp.l(1091, 111, 'COMPLETED', interval '6 days'); select pg_temp.rel(111, 211);
select pg_temp.l(1091, 112, 'COMPLETED', interval '6 days'); select pg_temp.rel(112, 212);
select pg_temp.l(1091, 113, 'COMPLETED', interval '6 days'); select pg_temp.rel(113, 213);
select pg_temp.l(1091, 114, 'COMPLETED', interval '6 days'); select pg_temp.rel(114, 214);
-- 15: two completed seasons point at one sequel; 115 completed more recently
select pg_temp.a(115, 'Two src A'); select pg_temp.a(125, 'Two src B'); select pg_temp.a(215, 'Two target');
select pg_temp.l(1091, 115, 'COMPLETED', interval '7 days'); select pg_temp.l(1091, 125, 'COMPLETED', interval '8 days');
select pg_temp.rel(115, 215); select pg_temp.rel(125, 215);
-- 16: an anime -> manga SEQUEL edge is not up next
select pg_temp.a(116, 'Adapt src'); select pg_temp.m(216, 'Adapted manga');
select pg_temp.l(1091, 116, 'COMPLETED', interval '9 days');
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
  values ('ANIME', 1090116, 'SEQUEL', 'MANGA', 1090216);
-- 17: only completed titles seed
select pg_temp.a(117, 'Watching src'); select pg_temp.a(217, 'Watching target');
select pg_temp.l(1091, 117, 'WATCHING'); select pg_temp.rel(117, 217);
-- 18: S1 completed, S2 watching, S3 must not appear
select pg_temp.a(118, 'S1'); select pg_temp.a(218, 'S2'); select pg_temp.a(219, 'S3');
select pg_temp.l(1091, 118, 'COMPLETED', interval '9 days'); select pg_temp.l(1091, 218, 'WATCHING');
select pg_temp.rel(118, 218); select pg_temp.rel(218, 219);
-- 19: self edge
select pg_temp.a(120, 'Self'); select pg_temp.l(1091, 120, 'COMPLETED', interval '9 days'); select pg_temp.rel(120, 120);

-- reviewed series: approved verified (320..322), proposed (330..), singleton default (340..), manga-medium (350..)
create function pg_temp.series(p_first integer, p_continuity text, p_state text, p_medium text) returns void
language plpgsql as $$
declare v_s uuid; v_sec uuid; v_i integer;
begin
  insert into public.series (medium, continuity, title, grouping_state)
  values (p_medium, p_continuity, 'Series ' || p_first, p_state) returning id into v_s;
  for v_i in 0..2 loop
    insert into public.series_sections (series_id, kind, ordinal, name, sort_order, provenance, state)
    values (v_s, 'season', v_i + 1, 'S' || (v_i + 1), v_i + 1, 'test', 'approved') returning id into v_sec;
    insert into public.series_entry_spans (series_id, section_id, medium, anime_id)
    values (v_s, v_sec, 'anime', 1090000 + p_first + v_i);
  end loop;
end $$;
select pg_temp.a(320, 'Rev1'); select pg_temp.a(321, 'Rev2'); select pg_temp.a(322, 'Rev3');
select pg_temp.a(330, 'Prop1'); select pg_temp.a(331, 'Prop2'); select pg_temp.a(332, 'Prop3');
select pg_temp.a(340, 'Sing1'); select pg_temp.a(341, 'Sing2'); select pg_temp.a(342, 'Sing3');
select pg_temp.a(350, 'Man1'); select pg_temp.a(351, 'Man2'); select pg_temp.a(352, 'Man3');
select pg_temp.series(320, 'verified', 'approved', 'anime');
select pg_temp.series(330, 'verified', 'proposed', 'anime');
select pg_temp.series(340, 'singleton', 'approved', 'anime');
select pg_temp.series(350, 'verified', 'approved', 'manga');
select pg_temp.l(1091, 320, 'COMPLETED', interval '10 days'); select pg_temp.l(1091, 330, 'COMPLETED', interval '10 days');
select pg_temp.l(1091, 340, 'COMPLETED', interval '10 days'); select pg_temp.l(1091, 350, 'COMPLETED', interval '10 days');
-- 23: a sequel edge and reviewed next section name the same title: reviewed wins
select pg_temp.a(360, 'Both1'); select pg_temp.a(361, 'Both2'); select pg_temp.a(362, 'Both3');
select pg_temp.series(360, 'verified', 'approved', 'anime');
select pg_temp.l(1091, 360, 'COMPLETED', interval '10 days'); select pg_temp.rel(360, 361);
-- manga: completed M410 --SEQUEL--> M411
select pg_temp.m(410, 'Manga one'); select pg_temp.m(411, 'Manga two');
insert into public.manga_user_lists (user_id, manga_id, list_type, progress, updated_at)
  values (tests.uid(1091)::text, 1090410, 'COMPLETED', 0, now() - interval '10 days');
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
  values ('MANGA', 1090410, 'SEQUEL', 'MANGA', 1090411);
-- limit: user 1096 completed 35 titles that each have one sequel
select pg_temp.a(500 + n, 'Lim src ' || n) from generate_series(1, 35) n;
select pg_temp.a(600 + n, 'Lim target ' || n) from generate_series(1, 35) n;
select pg_temp.l(1096, 500 + n, 'COMPLETED', n * interval '1 day') from generate_series(1, 35) n;
select pg_temp.rel(500 + n, 600 + n) from generate_series(1, 35) n;
set local session_replication_role = origin;

select tests.as_user(tests.uid(1091));
select tests.eq('1091 anime up next is exactly the expected targets (sequels, reviewed, announced; no excluded)',
  (select array_agg(media_id order by media_id) from public.library_up_next_v1('anime', 30)),
  array[1090201, 1090205, 1090206, 1090212, 1090215, 1090321, 1090361]);
select tests.ok('sequel row carries "after" and link',
  exists (select 1 from public.library_up_next_v1('anime', 30)
           where media_id = 1090201 and after_media_id = 1090101 and after_title = 'Frieren'
             and link = 'sequel' and title = 'Frieren S2' and media_type = 'anime'
             and format = 'TV' and total_units = 12 and start_year = 2024));
select tests.ok('titles already in the library are not listed', not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090202));
select tests.ok('deck_skip and deck_known within 365 days hide; deck_pass does not; a 400-day-old skip does not',
  not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id in (1090203, 1090204))
  and exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090205)
  and exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090206));
select tests.ok('adult, Hentai, Ecchi, MUSIC, SPECIAL, TV_SHORT and CANCELLED targets are never listed',
  not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id between 1090207 and 1090211 or media_id in (1090213, 1090214)));
select tests.ok('an unreleased sequel is listed',
  exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090212 and status = 'NOT_YET_RELEASED'));
select tests.ok('two completed seasons give exactly one row, named after the more recent',
  (select count(*) = 1 and bool_and(after_media_id = 1090115) from public.library_up_next_v1('anime', 30) where media_id = 1090215));
select tests.ok('an anime -> manga edge is not up next in either call',
  not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090216)
  and not exists (select 1 from public.library_up_next_v1('manga', 30) where media_id = 1090216));
select tests.ok('only completed titles seed (watching source, S2 watching -> no S3, self edge)',
  not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id in (1090217, 1090218, 1090219, 1090120)));
select tests.ok('reviewed series: exactly the next approved section, link reviewed',
  exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090321 and link = 'reviewed' and after_media_id = 1090320)
  and not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1090322));
select tests.ok('proposed, singleton and wrong-medium series give nothing',
  not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id between 1090331 and 1090332
                                                                   or media_id between 1090341 and 1090342
                                                                   or media_id between 1090351 and 1090352));
select tests.ok('a reviewed link wins over a relation naming the same title',
  (select count(*) = 1 and bool_and(link = 'reviewed') from public.library_up_next_v1('anime', 30) where media_id = 1090361));
select tests.ok('order: the most recently completed predecessor comes first',
  (select media_id from public.library_up_next_v1('anime', 30) limit 1) = 1090201);
select tests.ok('manga call lists the manga sequel with chapters as total_units',
  exists (select 1 from public.library_up_next_v1('manga', 30)
           where media_id = 1090411 and media_type = 'manga' and total_units = 40 and after_media_id = 1090410 and link = 'sequel'
             and start_year = 2020)
  and (select count(*) from public.library_up_next_v1('manga', 30)) = 1);
select tests.as_user(tests.uid(1092));
select tests.eq('a user with no completed titles gets nothing', (select count(*) from public.library_up_next_v1('anime', 30)), 0::bigint);
select tests.as_user(tests.uid(1096));
select tests.eq('p_limit 100 is capped at 30', (select count(*) from public.library_up_next_v1('anime', 100)), 30::bigint);
select tests.eq('p_limit 0 returns 1', (select count(*) from public.library_up_next_v1('anime', 0)), 1::bigint);
select tests.eq('p_limit null returns 30', (select count(*) from public.library_up_next_v1('anime', null)), 30::bigint);
select tests.reset();

rollback;
