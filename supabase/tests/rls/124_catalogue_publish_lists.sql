-- 124_catalogue_publish_lists.sql
-- Prepared 20261112100150_catalogue_publish_v1.sql (NOT deployed): the transactional half of the
-- catalogue `publish` and `restore` (Task 15) and the relation-reader source filter.
-- Covers: posture (plpgsql, search_path, invoker, service_role only); refusal while the group is not
-- 'new'; snapshot before first replacement and never overwritten; only shadow values publish (a null or
-- absent shadow never blanks); is_adult never clears; date triple follows its year; unchanged = no write;
-- credits lists and media_relations source='kuro' replaced while 'anilist'/'editorial' rows stay;
-- get_media_ladder hides the writer that does not own the relations group; restore returns columns and
-- linked rows exactly (ids included) and refuses while the group is 'new';
-- unlinkedListTitleStaysReadable (Review Focus 5); a 2,000-title rehearsal timing of publish and restore.
-- Fixture limits: the DB fixture has no media_relations table and no get_media_ladder, so the test creates
-- a stand-in media_relations (same columns as 20260307120000, rolled back with the transaction) and the
-- ladder under test is the copy this migration carries. The fixture is not production; hosted behavior is
-- not proven.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.staff
-- @requires table public.studios
-- @requires table public.characters
-- @requires table public.authors
-- @requires table public.anime_staff
-- @requires table public.anime_studios
-- @requires table public.anime_characters
-- @requires table public.manga_authors
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

create table if not exists public.media_relations (
  id bigserial primary key,
  from_media_type text not null check (from_media_type in ('ANIME', 'MANGA')),
  from_media_id int not null,
  relation_type text not null check (relation_type in ('SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF')),
  to_media_type text not null check (to_media_type in ('ANIME', 'MANGA')),
  to_media_id int not null,
  source text not null default 'anilist',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
);

-- ---- 1. posture ---------------------------------------------------------------------
select tests.ok('publish, restore and relation-source helper exist, plpgsql, fixed search_path, invoker',
  (select count(*) = 3 and bool_and(proconfig @> array['search_path=public, extensions'])
          and bool_and(prolang = (select oid from pg_language where lanname = 'plpgsql'))
          and bool_and(not prosecdef)
   from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('catalogue_publish_batch_v1', 'catalogue_restore_batch_v1', 'catalogue_relation_source_v1')));
select tests.ok('EXECUTE only for service_role',
  not exists (
    select 1 from pg_proc p, unnest(array['anon', 'authenticated', 'public']) r
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('catalogue_publish_batch_v1', 'catalogue_restore_batch_v1', 'catalogue_relation_source_v1')
       and has_function_privilege(r, p.oid, 'execute'))
  and (select bool_and(has_function_privilege('service_role', p.oid, 'execute')) from pg_proc p
        where p.pronamespace = 'public'::regnamespace
          and p.proname in ('catalogue_publish_batch_v1', 'catalogue_restore_batch_v1', 'catalogue_relation_source_v1')));

-- ---- 2. fixture ---------------------------------------------------------------------
delete from public.manga_user_lists;
delete from public.media_relations;
delete from catalogue_shadow_values;
delete from catalogue_rollback_snapshots;
delete from catalogue_id_links;
delete from public.anime_staff; delete from public.anime_studios; delete from public.anime_characters;
delete from public.manga_authors;
delete from public.anime;
delete from public.manga;
delete from public.staff; delete from public.studios; delete from public.characters; delete from public.authors;
update catalogue_cutover set mode = 'anilist';

insert into public.anime (id, anilist_id, title_english, title_romaji, title_native, format, status,
                          start_date_year, start_date_month, start_date_day, episodes, is_adult, popularity) values
  (1240001, 1240001, 'Old English', 'Old Romaji', 'Old Native', 'TV', 'FINISHED', 2000, 5, 6, 12, false, 100),
  (1240002, 1240002, 'Adult Old', 'Adult Old R', null, 'TV', 'FINISHED', 2001, 1, 2, 12, true, 90),
  (1240003, 1240003, 'No Shadow', 'No Shadow R', null, 'TV', 'FINISHED', 2002, 1, 2, 12, false, 80),
  (1240004, 1240004, 'Kuro Sequel', 'Kuro Sequel R', null, 'TV', 'FINISHED', 2003, 1, 2, 12, false, 70);
insert into public.manga (id, anilist_id, title_english, title_romaji, format, status) values
  (1240101, 1240101, 'Unlinked Manga', 'Unlinked Manga R', 'MANGA', 'FINISHED');
insert into public.staff (id, anilist_id, name_full) values (1240201, 1240201, 'Old Staff'), (1240202, null, 'New Staff A'), (1240203, null, 'New Staff B');
insert into public.studios (id, anilist_id, name) values (1240301, null, 'New Studio');
insert into public.authors (id, anilist_id, name_full) values (1240401, null, 'New Author');
insert into public.anime_staff (id, anime_id, staff_id, role) values (1240901, 1240001, 1240201, 'Old Role');
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source) values
  ('ANIME', 1240001, 'SEQUEL', 'ANIME', 1240003, 'anilist'),
  ('ANIME', 1240001, 'SIDE_STORY', 'ANIME', 1240003, 'editorial');

insert into catalogue_shadow_values (medium, media_id, field, value, source) values
  ('anime', 1240001, 'title_english', '"New English"', 'wikidata'),
  ('anime', 1240001, 'title_native',  'null', 'wikidata'),
  ('anime', 1240001, 'start_date_year', '2001', 'wikidata'),
  ('anime', 1240001, 'start_date_month', '7', 'wikidata'),
  ('anime', 1240001, 'format', '"MOVIE"', 'ann'),
  ('anime', 1240001, 'data_sources', '["wikidata","ann"]', 'composer'),
  ('anime', 1240001, 'credits:staff', '[{"kuro_id":1240202,"role":"Director"},{"kuro_id":1240203,"role":"Music"},{"kuro_id":1240203,"role":"Duplicate"},{"kuro_id":999999999,"role":"Ghost"}]', 'ann'),
  ('anime', 1240001, 'credits:studios', '[{"kuro_id":1240301,"role":"Animation Production"}]', 'ann'),
  ('anime', 1240001, 'relations', '[{"type":"SEQUEL","kind":"anime","target_id":1240004,"sources":["wikidata"],"status":"accepted"},{"type":"PREQUEL","kind":"anime","target_id":1240003,"sources":["ann"],"status":"proposed"}]', 'wikidata,ann'),
  ('anime', 1240002, 'is_adult', 'false', 'ann');

-- ---- 3. refusals --------------------------------------------------------------------
select tests.raises('publish refuses a group that is not new',
  $q$select public.catalogue_publish_batch_v1('anime', 'titles', array[1240001], array['title_english'])$q$, '%is anilist, not new%');
select tests.raises('an unknown group is refused',
  $q$select public.catalogue_publish_batch_v1('anime', 'colour', array[1240001], array['title_english'])$q$, '%unknown group%');
update catalogue_cutover set mode = 'new' where field_group = 'titles';
select tests.raises('an unknown column is refused',
  $q$select public.catalogue_publish_batch_v1('anime', 'titles', array[1240001], array['no_such_column'])$q$, '%not a publishable column%');
select tests.raises('anilist_id is never publishable',
  $q$select public.catalogue_publish_batch_v1('anime', 'titles', array[1240001], array['anilist_id'])$q$, '%not a publishable column%');
select tests.raises('more than 500 titles are refused',
  $q$select public.catalogue_publish_batch_v1('anime', 'titles', (select array_agg(g) from generate_series(1, 501) g), array['title_english'])$q$, '%at most 500%');

-- ---- 4. titles group: only the new group is written, shadow-only, snapshot first ------
update catalogue_cutover set mode = 'new' where field_group = 'titles';
select public.catalogue_publish_batch_v1('anime', 'titles', array[1240001, 1240002, 1240003],
  array['title_english', 'title_romaji', 'title_native', 'title_synonyms'], true);
select tests.eq('shadow title replaces the column', (select title_english from public.anime where id = 1240001), 'New English');
select tests.eq('no shadow value leaves the column (romaji)', (select title_romaji from public.anime where id = 1240001), 'Old Romaji');
select tests.eq('a null shadow value never blanks the column (native)', (select title_native from public.anime where id = 1240001), 'Old Native');
select tests.eq('a group that is not new is not written (format)', (select format from public.anime where id = 1240001), 'TV');
select tests.eq('title without shadow is untouched', (select title_english from public.anime where id = 1240003), 'No Shadow');
select tests.eq('data_sources copied by publish', (select data_sources from public.anime where id = 1240001), array['wikidata', 'ann']);
select tests.eq('snapshot holds the pre-switch columns',
  (select payload -> 'columns' ->> 'title_english' from catalogue_rollback_snapshots where field_group = 'titles' and medium = 'anime' and media_id = 1240001), 'Old English');
select tests.eq('snapshot exists for every published title', (select count(*) from catalogue_rollback_snapshots where field_group = 'titles'), 3::bigint);
update catalogue_shadow_values set value = '"Newer English"' where medium = 'anime' and media_id = 1240001 and field = 'title_english';
select tests.eq('a second publish writes the changed value only', (public.catalogue_publish_batch_v1('anime', 'titles', array[1240001, 1240002, 1240003],
  array['title_english', 'title_romaji', 'title_native', 'title_synonyms'], true) ->> 'columns_updated')::int, 1);
select tests.eq('the snapshot is not overwritten by the second publish',
  (select payload -> 'columns' ->> 'title_english' from catalogue_rollback_snapshots where field_group = 'titles' and medium = 'anime' and media_id = 1240001), 'Old English');
select tests.eq('an unchanged publish writes nothing', (public.catalogue_publish_batch_v1('anime', 'titles', array[1240001, 1240002, 1240003],
  array['title_english', 'title_romaji', 'title_native', 'title_synonyms'], true) ->> 'columns_updated')::int, 0);

-- ---- 5. adult never clears; date triple follows its year --------------------------------
update catalogue_cutover set mode = 'new' where field_group in ('adult', 'facts');
select public.catalogue_publish_batch_v1('anime', 'adult', array[1240002], array['is_adult']);
select tests.eq('adult today stays adult although the shadow says false', (select is_adult from public.anime where id = 1240002), true);
select public.catalogue_publish_batch_v1('anime', 'facts', array[1240001],
  array['format', 'status', 'start_date_year', 'start_date_month', 'start_date_day', 'episodes']);
select tests.eq('facts: format published', (select format from public.anime where id = 1240001), 'MOVIE');
select tests.eq('facts: year and month published', (select start_date_year * 100 + start_date_month from public.anime where id = 1240001), 200107);
select tests.eq('facts: a day missing from a shadow triple becomes null with the new year', (select start_date_day from public.anime where id = 1240001), null::integer);
select tests.eq('facts: episodes without shadow stay', (select episodes from public.anime where id = 1240001), 12);

-- ---- 6. credits and relations: linked rows ----------------------------------------------
update catalogue_cutover set mode = 'new' where field_group in ('credits', 'relations');
select public.catalogue_publish_batch_v1('anime', 'credits', array[1240001], '{}');
select public.catalogue_publish_batch_v1('anime', 'relations', array[1240001], '{}');
select tests.eq('firstPublishSnapshotsThenReplacesLinkedRows: staff replaced (ghost entity and duplicate dropped)',
  (select array_agg(staff_id order by staff_id) from public.anime_staff where anime_id = 1240001), array[1240202, 1240203]);
select tests.eq('the first credit per person wins', (select role from public.anime_staff where anime_id = 1240001 and staff_id = 1240203), 'Music');
select tests.eq('studios replaced', (select count(*) from public.anime_studios where anime_id = 1240001), 1::bigint);
select tests.eq('snapshot kept the old staff rows with their ids',
  (select (payload -> 'tables' -> 'anime_staff' -> 0 ->> 'id')::int from catalogue_rollback_snapshots where field_group = 'credits' and medium = 'anime' and media_id = 1240001), 1240901);
select tests.eq('titles with no credits shadow keep their rows', (select count(*) from public.anime_staff where anime_id = 1240003), 0::bigint);
select tests.eq('relationsKeepAniListRowsAndAddKuroRows: anilist and editorial rows stay',
  (select count(*) from public.media_relations where from_media_id = 1240001 and source in ('anilist', 'editorial')), 2::bigint);
select tests.eq('only the accepted relation is published as source=kuro',
  (select array_agg(relation_type || ':' || to_media_id) from public.media_relations where from_media_id = 1240001 and source = 'kuro'), array['SEQUEL:1240004']);
select tests.eq('a second credits and relations publish writes no linked rows',
  (public.catalogue_publish_batch_v1('anime', 'credits', array[1240001], '{}') ->> 'tables_replaced')::int
  + (public.catalogue_publish_batch_v1('anime', 'relations', array[1240001], '{}') ->> 'tables_replaced')::int, 0);

-- ---- 7. ladder reads one source per mode ------------------------------------------------
select tests.eq('relation source is kuro while relations is new', public.catalogue_relation_source_v1(), 'kuro');
select tests.eq('ladder (relations new) shows the kuro sequel only, no anilist sequel',
  (select jsonb_array_length(public.get_media_ladder('ANIME', 1240001) -> 'sequels')), 1);
select tests.eq('the kuro sequel points at the kuro target',
  (public.get_media_ladder('ANIME', 1240001) -> 'sequels' -> 0 ->> 'media_id')::int, 1240004);
select tests.eq('editorial side story still shows', (select jsonb_array_length(public.get_media_ladder('ANIME', 1240001) -> 'side_stories')), 1);

-- ---- 8. restore ---------------------------------------------------------------------
select tests.raises('restore refuses while the group is still new',
  $q$select public.catalogue_restore_batch_v1('anime', 'titles')$q$, '%still new%');
update catalogue_cutover set mode = 'anilist' where field_group in ('titles', 'adult', 'facts', 'credits', 'relations');
select tests.eq('relation source is anilist after the switch back', public.catalogue_relation_source_v1(), 'anilist');
select tests.eq('ladder (relations anilist) shows the anilist sequel to 1240003 only',
  (public.get_media_ladder('ANIME', 1240001) -> 'sequels' -> 0 ->> 'media_id')::int, 1240003);
select tests.eq('restore titles: batch result', public.catalogue_restore_batch_v1('anime', 'titles') , jsonb_build_object('restored', 3, 'remaining', 0));
select tests.eq('titles restored exactly (english)', (select title_english from public.anime where id = 1240001), 'Old English');
select tests.eq('titles restored exactly (native stays)', (select title_native from public.anime where id = 1240001), 'Old Native');
select tests.eq('titles snapshot rows are gone after restore', (select count(*) from catalogue_rollback_snapshots where field_group = 'titles'), 0::bigint);
select public.catalogue_restore_batch_v1('anime', 'facts');
select public.catalogue_restore_batch_v1('anime', 'adult');
select tests.eq('facts restored: format, date', (select format || start_date_year || start_date_month || start_date_day from public.anime where id = 1240001), 'TV200056');
select public.catalogue_restore_batch_v1('anime', 'credits');
select public.catalogue_restore_batch_v1('anime', 'relations');
select tests.eq('credits restored with the original row id',
  (select array_agg(id || ':' || staff_id || ':' || role) from public.anime_staff where anime_id = 1240001), array['1240901:1240201:Old Role']);
select tests.eq('studios restored to none', (select count(*) from public.anime_studios where anime_id = 1240001), 0::bigint);
select tests.eq('kuro relation rows removed by restore',
  (select count(*) from public.media_relations where source = 'kuro'), 0::bigint);
select tests.eq('anilist and editorial relation rows still there',
  (select count(*) from public.media_relations where from_media_id = 1240001), 2::bigint);

-- ---- 9. unlinkedListTitleStaysReadable (Review Focus 5) --------------------------------
update catalogue_cutover set mode = 'new' where field_group in ('identity', 'titles', 'facts', 'images');
select tests.make_user(1241);
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values (tests.uid(1241)::text, 1240101, 'READING', 3);
select public.catalogue_publish_batch_v1('manga', 'identity', array[1240101], array['mal_id']);
select public.catalogue_publish_batch_v1('manga', 'titles', array[1240101], array['title_english', 'title_romaji']);
select tests.eq('unlinkedListTitleStaysReadable: row and stored title survive a publish run',
  (select title_english from public.manga where id = 1240101), 'Unlinked Manga');
select tests.eq('unlinkedListTitleStaysReadable: list membership survives',
  (select count(*) from public.manga_user_lists where manga_id = 1240101), 1::bigint);
select tests.eq('unlinkedListTitleStaysReadable: the Kuro id is unchanged', (select id from public.manga where anilist_id = 1240101), 1240101);
update catalogue_cutover set mode = 'anilist';
select public.catalogue_restore_batch_v1('manga', 'identity');
select public.catalogue_restore_batch_v1('manga', 'titles');

-- ---- 10. rehearsal: 2,000 titles, publish then restore, per group ------------------------
delete from public.manga_user_lists;
delete from catalogue_shadow_values;
delete from catalogue_rollback_snapshots;
delete from public.media_relations;
delete from public.anime_staff;
delete from public.anime;
insert into public.anime (id, anilist_id, title_english, title_romaji, format, status, start_date_year, episodes, is_adult)
  select 1250000 + g, 1250000 + g, 'T' || g, 'R' || g, 'TV', 'FINISHED', 1990 + g % 30, 12, false from generate_series(1, 2000) g;
insert into catalogue_shadow_values (medium, media_id, field, value, source)
  select 'anime', 1250000 + g, f.field, f.value, 'wikidata'
    from generate_series(1, 2000) g,
         lateral (values ('title_english', to_jsonb('N' || g)), ('title_romaji', to_jsonb('NR' || g)), ('format', '"MOVIE"'::jsonb),
                  ('start_date_year', to_jsonb(2000 + g % 20)), ('episodes', '1'::jsonb), ('is_adult', 'false'::jsonb),
                  ('credits:staff', jsonb_build_array(jsonb_build_object('kuro_id', 1240201, 'role', 'X'))),
                  ('relations', jsonb_build_array(jsonb_build_object('type', 'SEQUEL', 'kind', 'anime', 'target_id', 1250000 + (g % 2000) + 1, 'status', 'accepted')))) f(field, value);
create temp table _rehearsal (grp text, publish_ms numeric, restore_ms numeric, restored int);
create or replace function pg_temp.rehearse(p_group text, p_cols text[]) returns void language plpgsql as $f$
declare t0 timestamptz; t1 timestamptz; t2 timestamptz; _r jsonb; _n int := 0; _ids integer[]; _p int;
begin
  update catalogue_cutover set mode = 'new' where field_group = p_group;
  t0 := clock_timestamp();
  for _p in 0..3 loop
    select array_agg(id) into _ids from (select id from public.anime where id between 1250001 + _p * 500 and 1250000 + (_p + 1) * 500) x;
    perform public.catalogue_publish_batch_v1('anime', p_group, _ids, p_cols, false);
  end loop;
  t1 := clock_timestamp();
  update catalogue_cutover set mode = 'anilist' where field_group = p_group;
  loop
    _r := public.catalogue_restore_batch_v1('anime', p_group, 500);
    _n := _n + (_r ->> 'restored')::int;
    exit when (_r ->> 'remaining')::int = 0 or (_r ->> 'restored')::int = 0;
  end loop;
  t2 := clock_timestamp();
  insert into _rehearsal values (p_group, extract(epoch from t1 - t0) * 1000, extract(epoch from t2 - t1) * 1000, _n);
end $f$;
select pg_temp.rehearse('titles', array['title_english', 'title_romaji']);
select pg_temp.rehearse('facts', array['format', 'start_date_year', 'episodes']);
select pg_temp.rehearse('adult', array['is_adult']);
select pg_temp.rehearse('credits', '{}');
select pg_temp.rehearse('relations', '{}');
select tests.eq('rehearsal: every group restored all 2,000 titles', (select min(restored) from _rehearsal), 2000);
select tests.eq('rehearsal: titles are back to their pre-switch values', (select count(*) from public.anime where id > 1250000 and (title_english not like 'T%' or format <> 'TV')), 0::bigint);
select tests.eq('rehearsal: no kuro relation row is left', (select count(*) from public.media_relations where source = 'kuro'), 0::bigint);
select tests.eq('rehearsal: no snapshot is left', (select count(*) from catalogue_rollback_snapshots), 0::bigint);
do $r$
declare _r record;
begin
  for _r in select * from _rehearsal order by grp loop
    raise notice 'REHEARSAL % publish_ms=% restore_ms=% restored=%', _r.grp, round(_r.publish_ms), round(_r.restore_ms), _r.restored;
  end loop;
end $r$;
rollback;
