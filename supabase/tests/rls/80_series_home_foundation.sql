-- 80_series_home_foundation.sql
-- Revision fence, receipts, Home bundle isolation, mapping publication and
-- MAL export merge. The migration under test is prepared, not deployed.
-- @requires table public.anime_user_lists
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(81), tests.make_user(82);
insert into public.anime (id, title_romaji, mal_id) values (770001, 'Fence Probe', null);
insert into public.anime (id, title_romaji, mal_id) values (770002, 'MAL Probe', 880002);
insert into public.manga (id, title_romaji) values (770003, 'Unread Manga');

select tests.as_user(tests.uid(81));
select tests.eq('owner inserts a watching row',
  tests.affected(format($q$insert into public.anime_user_lists (user_id, anime_id, list_type, progress, notes)
                            values (%L, 770001, 'WATCHING', 3, 'keep-me')$q$, auth.uid()::text)), 1::bigint);

select tests.eq('inserted revision starts at 1',
  (select server_revision from public.anime_user_lists where anime_id = 770001), 1::bigint);
select tests.ok('inserted lifecycle is assigned',
  (select lifecycle_id is not null from public.anime_user_lists where anime_id = 770001));

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '11111111-1111-4111-8111-111111111111',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 770001),
  'base_revision', 1,
  'position', 4
))) as applied \gset

select tests.eq('progress mutation applies', (:'applied'::jsonb -> 'items' -> 0 ->> 'outcome'), 'applied');
select tests.eq('progress is the absolute position',
  (select progress from public.anime_user_lists where anime_id = 770001), 4);
select tests.eq('notes are not overwritten',
  (select notes from public.anime_user_lists where anime_id = 770001), 'keep-me');
select tests.eq('revision advanced once',
  (select server_revision from public.anime_user_lists where anime_id = 770001), 2::bigint);

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '11111111-1111-4111-8111-111111111111',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 770001),
  'base_revision', 1,
  'position', 4
))) as replay \gset
select tests.eq('identical replay is already applied', (:'replay'::jsonb -> 'items' -> 0 ->> 'outcome'), 'already_applied');
select tests.eq('replay does not move progress',
  (select progress from public.anime_user_lists where anime_id = 770001), 4);
select tests.eq('replay does not advance revision',
  (select server_revision from public.anime_user_lists where anime_id = 770001), 2::bigint);

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '11111111-1111-4111-8111-111111111111',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 770001),
  'base_revision', 2,
  'position', 9
))) as clash \gset
select tests.eq('same mutation id with a different payload is rejected',
  (:'clash'::jsonb -> 'items' -> 0 ->> 'outcome'), 'rejected_payload');
select tests.eq('rejected payload leaves progress',
  (select progress from public.anime_user_lists where anime_id = 770001), 4);

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '22222222-2222-4222-8222-222222222222',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 770001),
  'base_revision', 1,
  'position', 1
))) as stale \gset
select tests.eq('stale base revision conflicts', (:'stale'::jsonb -> 'items' -> 0 ->> 'outcome'), 'conflict');
select tests.eq('conflict leaves the newer progress',
  (select progress from public.anime_user_lists where anime_id = 770001), 4);

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '33333333-3333-4333-8333-333333333333',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 770001),
  'base_revision', (select server_revision from public.anime_user_lists where anime_id = 770001),
  'position', 4,
  'position_label', '4.5'
))) as fractional \gset
select tests.eq('fractional label applies', (:'fractional'::jsonb -> 'items' -> 0 ->> 'outcome'), 'applied');
select tests.eq('fractional label does not round the integer progress',
  (select progress from public.anime_user_lists where anime_id = 770001), 4);
select tests.eq('fractional label is stored',
  (select progress_label from public.anime_user_lists where anime_id = 770001), '4.5');

select tests.eq('home bundle returns the caller watching row',
  (select jsonb_array_length(public.home_bundle_v1('anime') -> 'active')), 1);
select tests.eq('home bundle media id is the caller row',
  (select (public.home_bundle_v1('anime') -> 'active' -> 0 ->> 'media_id')::integer), 770001);

select lifecycle_id::text as removed_life from public.anime_user_lists where anime_id = 770001 \gset
select tests.eq('owner deletes the row',
  tests.affected($q$delete from public.anime_user_lists where anime_id = 770001$q$), 1::bigint);
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '44444444-4444-4444-8444-444444444444',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', :'removed_life',
  'base_revision', 1,
  'position', 8
))) as removed \gset
select tests.eq('old lifecycle cannot recreate the row', (:'removed'::jsonb -> 'items' -> 0 ->> 'outcome'), 'removed_entry');
select tests.eq('row stays absent',
  (select count(*) from public.anime_user_lists where anime_id = 770001), 0::bigint);

select tests.as_user(tests.uid(82));
select tests.eq('other user home bundle is empty',
  (select jsonb_array_length(public.home_bundle_v1('anime') -> 'active')), 0);
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', '55555555-5555-4555-8555-555555555555',
  'medium', 'anime',
  'media_id', 770001,
  'lifecycle_id', :'removed_life',
  'base_revision', 1,
  'position', 8
))) as foreign_write \gset
select tests.eq('other user cannot target a row they do not own',
  (:'foreign_write'::jsonb -> 'items' -> 0 ->> 'outcome'), 'invalid_target');

select tests.as_anon();
select tests.raises('anon cannot read the home bundle',
  $q$select public.home_bundle_v1('anime')$q$, '%UNAUTHENTICATED%');

select tests.as_user(tests.uid(81));
select public.start_library_import_v1('myanimelist','account','anime','idem-account-1','abcdef0123456789')->>'job_id' as account_job \gset
select tests.eq('MAL account input uses the structured job contract',
 public.import_job_status_v1(:'account_job'::uuid)->>'source_kind','account');
select public.finish_library_import_v1(:'account_job'::uuid,true);
select (public.start_library_import_v1('myanimelist','export','anime','idem-export-01','abcdef0123456789') ->> 'job_id') as mal_job \gset
select public.apply_import_chunk_v1(:'mal_job'::uuid, jsonb_build_array(jsonb_build_object(
  'medium', 'anime',
  'external_id', '880002',
  'status', 'watching',
  'progress', 2,
  'notes', 'from mal',
  'score_raw', '7',
  'score_scale', 'MAL_10',
  'repeat_count', 1
))) as mal_chunk \gset
select tests.eq('MAL export chunk applies by mal id', (:'mal_chunk'::jsonb ->> 'applied')::integer, 1);
select tests.eq('MAL progress is stored on the catalogue id',
  (select progress from public.anime_user_lists where anime_id = 770002), 2);
select tests.eq('MAL raw score is kept beside the integer rating',
  (select score_raw from public.anime_user_lists where anime_id = 770002), 7::numeric);
select tests.eq('MAL note stays on the list row',
  (select notes from public.anime_user_lists where anime_id = 770002), 'from mal');

select tests.reset();
insert into public.series (id, medium, title)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'anime', 'Probe');
insert into public.series_sections (id, series_id, kind, ordinal, name, sort_order, provenance)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'season', 1, 'Season 1', 1, 'test');
insert into public.series_entry_spans (series_id, section_id, medium, anime_id)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'anime', 770001);
select tests.eq('previous span is present before the failed publish',
  (select count(*) from public.series_entry_spans where anime_id = 770001), 1::bigint);
insert into public.mapping_revisions (id, series_id, state, source, rule_revision)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'proposed', 'test', 'r1');
insert into public.mapping_revision_spans
  (revision_id, medium, anime_id, section_kind, section_ordinal, section_name, sort_order)
values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'anime', 42424299, 'season', 1, 'Missing', 1);
select tests.raises('unresolved target does not publish',
  $q$select public.publish_mapping_revision('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$q$,
  '%UNRESOLVED_TARGET%');
select tests.eq('failed publish keeps the previous span',
  (select count(*) from public.series_entry_spans where anime_id = 770001), 1::bigint);

select tests.as_user(tests.uid(81));
select tests.raises('authenticated cannot publish mappings',
  $q$select public.publish_mapping_revision('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$q$,
  '%NOT_AUTHORIZED%');

select tests.reset();
rollback;
