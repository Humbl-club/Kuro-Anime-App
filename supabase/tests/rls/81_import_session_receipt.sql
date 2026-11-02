-- 81_import_session_receipt.sql
-- Concierge apply/undo progress and status go through the series receipt fence.
-- Prepared migration 20261007040000 replaces apply_import_session / undo so that
-- progress writes leave a mutation_receipts row. Session idempotency is unchanged.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.catalogue_units
-- @requires table public.mutation_receipts
-- @requires function public.apply_import_session(uuid,uuid,text,jsonb)
\set ON_ERROR_STOP on
\o /dev/null
\set as_service 'select tests.reset(); select set_config(''request.jwt.claims'', ''{"role":"service_role"}'', true); set local role service_role;'
begin;

select tests.ok('pending migration: internal progress writer exists',
  to_regprocedure('public._apply_progress_mutations_for_user(text,jsonb)') is not null);
select tests.ok('pending migration: fence helper exists',
  to_regprocedure('public._fence_set_progress_status(text,text,integer,uuid,integer,text)') is not null);
select tests.ok('grant: authenticated cannot EXECUTE the internal progress writer',
  not has_function_privilege('authenticated', 'public._apply_progress_mutations_for_user(text,jsonb)', 'EXECUTE'));
select tests.ok('grant: authenticated cannot EXECUTE the fence helper',
  not has_function_privilege('authenticated', 'public._fence_set_progress_status(text,text,integer,uuid,integer,text)', 'EXECUTE'));

select tests.make_user(811), tests.make_user(812);
insert into public.anime (id, title_romaji) values (771001, 'Receipt Apply'), (771002, 'Receipt Undo');

-- Seed a watching row, then a local progress receipt (client path).
select tests.as_user(tests.uid(811));
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, notes)
values (tests.uid(811)::text, 771001, 'WATCHING', 2, 'keep-me');

select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'medium', 'anime',
  'media_id', 771001,
  'lifecycle_id', (select lifecycle_id from public.anime_user_lists where anime_id = 771001),
  'base_revision', 1,
  'position', 3
))) as local_prog \gset
select tests.eq('local progress receipt applies', (:'local_prog'::jsonb -> 'items' -> 0 ->> 'outcome'), 'applied');
select tests.eq('local progress is 3',
  (select progress from public.anime_user_lists where anime_id = 771001), 3);

:as_service
select tests.eq('one local receipt exists before import',
  (select count(*) from public.mutation_receipts
    where user_id = tests.uid(811)::text and media_id = 771001), 1::bigint);

-- Apply updates progress through the fence (service_role).
select public.apply_import_session(tests.uid(811), null, 'k-receipt-apply', $j$[
  {"media_type":"ANIME","media_id":771001,"import_action":"update",
   "expected":{"list_type":"WATCHING","progress":3},
   "update_values":{"list_type":"WATCHING","progress":7,"rating":8},
   "journal":{"raw":"ep 7"}}
]$j$::jsonb) as apply_out \gset
select tests.reset();
select (:'apply_out'::jsonb) ->> 'session_id' as apply_sid \gset

:as_service
select tests.eq('apply moved progress to 7',
  (select progress from public.anime_user_lists
    where user_id = tests.uid(811)::text and anime_id = 771001), 7);
select tests.eq('apply wrote rating without dropping notes',
  (select rating || '/' || notes from public.anime_user_lists
    where user_id = tests.uid(811)::text and anime_id = 771001), '8/keep-me');
select tests.eq('apply left a progress receipt (local + import)',
  (select count(*) from public.mutation_receipts
    where user_id = tests.uid(811)::text and media_id = 771001 and outcome = 'applied'), 2::bigint);
select tests.ok('import apply receipt uses the deterministic mutation id',
  exists (
    select 1 from public.mutation_receipts
    where user_id = tests.uid(811)::text
      and mutation_id = public._import_mutation_id('apply', :'apply_sid'::uuid, 'ANIME', 771001)
      and position = 7
  ));

-- Same idempotency key: no second progress change, no second import receipt.
select count(*) as receipts_before_replay
from public.mutation_receipts
where user_id = tests.uid(811)::text and media_id = 771001 \gset
select progress as progress_before_replay
from public.anime_user_lists
where user_id = tests.uid(811)::text and anime_id = 771001 \gset
select server_revision as revision_before_replay
from public.anime_user_lists
where user_id = tests.uid(811)::text and anime_id = 771001 \gset

select public.apply_import_session(tests.uid(811), null, 'k-receipt-apply', $j$[
  {"media_type":"ANIME","media_id":771001,"import_action":"update",
   "expected":{"list_type":"WATCHING","progress":3},
   "update_values":{"list_type":"WATCHING","progress":99},
   "journal":{"raw":"should not write"}}
]$j$::jsonb) as replay_out \gset
select tests.reset();
select tests.eq('idempotent apply is replayed', (:'replay_out'::jsonb) ->> 'replayed', 'true');

:as_service
select tests.eq('idempotent apply does not move progress again',
  (select progress from public.anime_user_lists
    where user_id = tests.uid(811)::text and anime_id = 771001), :'progress_before_replay'::integer);
select tests.eq('idempotent apply does not advance revision',
  (select server_revision from public.anime_user_lists
    where user_id = tests.uid(811)::text and anime_id = 771001), :'revision_before_replay'::bigint);
select tests.eq('idempotent apply does not write a second import receipt',
  (select count(*) from public.mutation_receipts
    where user_id = tests.uid(811)::text and media_id = 771001), :'receipts_before_replay'::bigint);

-- Undo restores progress through the fence and writes an undo receipt.
select public.undo_import_session(tests.uid(811), :'apply_sid'::uuid) as undo_out \gset
select tests.reset();
select tests.eq('undo reports undone', (:'undo_out'::jsonb) ->> 'result', 'undone');

:as_service
select tests.eq('undo restored progress to the pre-import local value',
  (select progress from public.anime_user_lists
    where user_id = tests.uid(811)::text and anime_id = 771001), 3);
select tests.ok('undo left a progress receipt',
  exists (
    select 1 from public.mutation_receipts
    where user_id = tests.uid(811)::text
      and mutation_id = public._import_mutation_id('undo', :'apply_sid'::uuid, 'ANIME', 771001)
      and position = 3
  ));

-- A progress-only apply without a prior local receipt still writes one receipt.
select tests.as_user(tests.uid(812));
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(812)::text, 771002, 'WATCHING', 1);
:as_service
select public.apply_import_session(tests.uid(812), null, 'k-receipt-fresh', $j$[
  {"media_type":"ANIME","media_id":771002,"import_action":"update",
   "expected":{"list_type":"WATCHING","progress":1},
   "update_values":{"progress":4},
   "journal":{"raw":"ep 4"}}
]$j$::jsonb) as fresh_out \gset
select tests.reset();
:as_service
select tests.eq('fresh apply moved progress',
  (select progress from public.anime_user_lists
    where user_id = tests.uid(812)::text and anime_id = 771002), 4);
select tests.eq('fresh apply wrote exactly one receipt',
  (select count(*) from public.mutation_receipts
    where user_id = tests.uid(812)::text and media_id = 771002), 1::bigint);

-- A status-only import must not turn a selected fractional chapter into an
-- integer progress write. Exercise the actual Apply and Undo entrypoints.
select tests.reset();
insert into public.manga (id, title_romaji) values (771003, 'Fractional Receipt');
insert into public.catalogue_units (id, medium, manga_id, label, order_key, edition_key)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'manga', 771003, '4.5', 4.5, 'special-edition');
select tests.as_user(tests.uid(812));
insert into public.manga_user_lists
  (user_id, manga_id, list_type, progress, unit_id, progress_label, notes, rating)
values (tests.uid(812)::text, 771003, 'READING', 4,
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '4.5', 'keep-fractional-notes', 8);
:as_service
select lifecycle_id as fractional_lifecycle, server_revision as fractional_revision
from public.manga_user_lists
where user_id = tests.uid(812)::text and manga_id = 771003 \gset
select public.apply_import_session(tests.uid(812), null, 'k-receipt-status-only', $j$[
  {"media_type":"MANGA","media_id":771003,"import_action":"update",
   "expected":{"list_type":"READING"}, "update_values":{"list_type":"PAUSED"}}
]$j$::jsonb) as status_apply \gset
select (:'status_apply'::jsonb) ->> 'session_id' as status_sid \gset
-- now() is fixed throughout this rolled-back fixture transaction. Give each
-- distinct user gesture its real order instead of relying on random UUID ties.
update public.import_sessions set created_at = clock_timestamp() where id = :'status_sid'::uuid;
select tests.eq('status-only apply changes status while preserving precise tracking and unrelated fields',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label, notes, rating, lifecycle_id)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  jsonb_build_array('PAUSED'::text, 4, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
                   '4.5'::text, 'keep-fractional-notes'::text, 8, :'fractional_lifecycle'::uuid));
select tests.eq('status-only apply advances the confirmed revision once',
  (select server_revision from public.manga_user_lists
   where user_id = tests.uid(812)::text and manga_id = 771003), :'fractional_revision'::bigint + 1);
select public.undo_import_session(tests.uid(812), :'status_sid'::uuid) as status_undo \gset
select tests.eq('status-only undo reports undone', (:'status_undo'::jsonb) ->> 'result', 'undone');
select tests.eq('status-only undo restores status without dropping precise tracking or unrelated fields',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label, notes, rating, lifecycle_id)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  jsonb_build_array('READING'::text, 4, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
                   '4.5'::text, 'keep-fractional-notes'::text, 8, :'fractional_lifecycle'::uuid));
select tests.ok('status-only Apply and Undo each leave a deterministic applied receipt',
  (select count(*) = 2 from public.mutation_receipts
   where user_id = tests.uid(812)::text and media_id = 771003 and medium = 'manga'
     and outcome = 'applied' and mutation_id in (
       public._import_mutation_id('apply', :'status_sid'::uuid, 'MANGA', 771003),
       public._import_mutation_id('undo', :'status_sid'::uuid, 'MANGA', 771003))));

-- An explicit integer update deliberately clears the old unit selection, but
-- Undo must restore all three parts of the original tracking value together.
select public.apply_import_session(tests.uid(812), null, 'k-receipt-precise-progress', $j$[
  {"media_type":"MANGA","media_id":771003,"import_action":"update",
   "expected":{"list_type":"READING","progress":4}, "update_values":{"progress":7}}
]$j$::jsonb) as precise_apply \gset
select (:'precise_apply'::jsonb) ->> 'session_id' as precise_sid \gset
update public.import_sessions set created_at = clock_timestamp() where id = :'precise_sid'::uuid;
select tests.eq('explicit progress Apply clears obsolete unit and label while retaining status',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  '["READING",7,null,null]'::jsonb);
select tests.eq('explicit progress journal includes the exact prior tracking value',
  (select jsonb_build_array(previous_values -> 'progress', previous_values -> 'unit_id',
                           previous_values -> 'progress_label')
   from public.import_session_items where session_id = :'precise_sid'::uuid),
  '[4,"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","4.5"]'::jsonb);
select server_revision as before_precise_undo from public.manga_user_lists
where user_id = tests.uid(812)::text and manga_id = 771003 \gset
select public.undo_import_session(tests.uid(812), :'precise_sid'::uuid) as precise_undo \gset
select tests.eq('progress Undo restores integer compatibility, selected edition unit and fractional label',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label, notes, rating)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  '["READING",4,"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","4.5","keep-fractional-notes",8]'::jsonb);
select tests.eq('coupled precise Undo uses one confirmed revision',
  (select server_revision from public.manga_user_lists
   where user_id = tests.uid(812)::text and manga_id = 771003), :'before_precise_undo'::bigint + 1);

-- A later exact edit with unchanged integer progress blocks coupled progress
-- Undo, while independently unchanged status can still be undone.
select public.apply_import_session(tests.uid(812), null, 'k-receipt-later-exact', $j$[
  {"media_type":"MANGA","media_id":771003,"import_action":"update",
   "expected":{"list_type":"READING","progress":4},
   "update_values":{"list_type":"PAUSED","progress":7}}
]$j$::jsonb) as later_apply \gset
select (:'later_apply'::jsonb) ->> 'session_id' as later_sid \gset
update public.import_sessions set created_at = clock_timestamp() where id = :'later_sid'::uuid;
select tests.as_user(tests.uid(812));
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'medium', 'manga', 'media_id', 771003,
  'lifecycle_id', (select lifecycle_id from public.manga_user_lists where manga_id = 771003),
  'base_revision', (select server_revision from public.manga_user_lists where manga_id = 771003),
  'unit_id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'position_label', '4.5'
))) as later_edit \gset
:as_service
select public.undo_import_session(tests.uid(812), :'later_sid'::uuid) as later_undo \gset
select tests.eq('newer exact tracking edit survives progress Undo while status restores independently',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  '["READING",7,"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","4.5"]'::jsonb);
select tests.ok('coupled tracking conflict is disclosed by Undo',
  jsonb_array_length(:'later_undo'::jsonb -> 'skipped') = 1);

-- New and historical import-created snapshots must both protect a later exact
-- selection, even when its integer compatibility value has not changed.
select tests.reset();
insert into public.anime (id, title_romaji) values
  (771004, 'New Journal Exact Edit'), (771005, 'Old Journal Exact Edit');
insert into public.catalogue_units (id, medium, anime_id, label, order_key) values
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'anime', 771004, '4.5', 4.5),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'anime', 771005, '4.5', 4.5);
:as_service
select public.apply_import_session(tests.uid(812), null, 'k-receipt-created-exact', $j$[
  {"media_type":"ANIME","media_id":771004,"import_action":"add",
   "insert_values":{"list_type":"WATCHING","progress":4}},
  {"media_type":"ANIME","media_id":771005,"import_action":"add",
   "insert_values":{"list_type":"WATCHING","progress":4}}
]$j$::jsonb) as created_apply \gset
select (:'created_apply'::jsonb) ->> 'session_id' as created_sid \gset
update public.import_sessions set created_at = clock_timestamp() where id = :'created_sid'::uuid;
-- Model a persisted pre-repair journal by removing fields that its writer never
-- recorded, retaining the actual Apply-created row and all its other journal data.
update public.import_session_items
set after_values = after_values - 'unit_id' - 'progress_label' - 'lifecycle_id',
    action = jsonb_set(action, '{after}', (action -> 'after') - 'unit_id' - 'progress_label' - 'lifecycle_id')
where session_id = :'created_sid'::uuid and chosen ->> 'mediaId' = '771005';
select tests.as_user(tests.uid(812));
select public.apply_progress_mutations_v1((
  select jsonb_agg(jsonb_build_object(
    'mutation_id', case anime_id when 771004 then 'ffffffff-ffff-4fff-8fff-ffffffffffff'
                              else '99999999-9999-4999-8999-999999999999' end,
    'medium', 'anime', 'media_id', anime_id, 'lifecycle_id', lifecycle_id,
    'base_revision', server_revision,
    'unit_id', case anime_id when 771004 then 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
                            else 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' end,
    'position_label', '4.5'))
  from public.anime_user_lists where anime_id in (771004, 771005)
)) as created_edits \gset
:as_service
select public.undo_import_session(tests.uid(812), :'created_sid'::uuid) as created_undo \gset
select tests.eq('Undo keeps both newly journaled and historical imported rows with later exact edits',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(812)::text
   and anime_id in (771004, 771005) and progress = 4 and progress_label = '4.5'
   and unit_id is not null), 2::bigint);
select tests.eq('Undo discloses both protected imported entries',
  jsonb_array_length(:'created_undo'::jsonb -> 'skipped'), 2);
select tests.ok('legacy Undo honestly skips the title whose entry lifetime cannot be established',
  exists (select 1 from jsonb_array_elements(:'created_undo'::jsonb -> 'skipped') e
          where e ->> 'mediaId' = '771005' and e ->> 'reason' = 'legacy_lifecycle_unavailable'));

-- Zero is an explicit progress write, not the absence marker.
select public.apply_import_session(tests.uid(812), null, 'k-receipt-zero', $j$[
  {"media_type":"ANIME","media_id":771002,"import_action":"update",
   "expected":{"progress":4}, "update_values":{"progress":0}}
]$j$::jsonb) as zero_apply \gset
select tests.eq('explicit zero progress remains a real write and preserves omitted status',
  (select jsonb_build_array(progress, list_type) from public.anime_user_lists
   where user_id = tests.uid(812)::text and anime_id = 771002), '[0,"WATCHING"]'::jsonb);

-- Removing and re-adding equal-looking entries creates a different lifetime.
-- Neither new-row deletion nor existing-row status Undo may touch that lifetime.
select tests.reset();
insert into public.anime (id, title_romaji) values (771006, 'Replacement Lifetime');
:as_service
select public.apply_import_session(tests.uid(812), null, 'k-receipt-lifecycle', $j$[
  {"media_type":"ANIME","media_id":771006,"import_action":"add",
   "insert_values":{"list_type":"WATCHING","progress":4}},
  {"media_type":"MANGA","media_id":771003,"import_action":"update",
   "expected":{"list_type":"READING"}, "update_values":{"list_type":"PAUSED"}}
]$j$::jsonb) as lifecycle_apply \gset
select (:'lifecycle_apply'::jsonb) ->> 'session_id' as lifecycle_sid \gset
update public.import_sessions set created_at = clock_timestamp() where id = :'lifecycle_sid'::uuid;
select lifecycle_id as old_anime_lifecycle from public.anime_user_lists
where user_id = tests.uid(812)::text and anime_id = 771006 \gset
select lifecycle_id as old_manga_lifecycle from public.manga_user_lists
where user_id = tests.uid(812)::text and manga_id = 771003 \gset
select tests.as_user(tests.uid(812));
delete from public.anime_user_lists where anime_id = 771006;
delete from public.manga_user_lists where manga_id = 771003;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(812)::text, 771006, 'WATCHING', 4);
insert into public.manga_user_lists
  (user_id, manga_id, list_type, progress, unit_id, progress_label, notes, rating)
values (tests.uid(812)::text, 771003, 'PAUSED', 7,
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '4.5', 'keep-fractional-notes', 8);
:as_service
select tests.ok('remove and re-add changed both entry lifetimes',
  (select lifecycle_id <> :'old_anime_lifecycle'::uuid from public.anime_user_lists
   where user_id = tests.uid(812)::text and anime_id = 771006)
  and (select lifecycle_id <> :'old_manga_lifecycle'::uuid from public.manga_user_lists
       where user_id = tests.uid(812)::text and manga_id = 771003));
select public.undo_import_session(tests.uid(812), :'lifecycle_sid'::uuid) as lifecycle_undo \gset
select tests.eq('Undo preserves the equal-looking replacement of an import-created entry',
  (select jsonb_build_array(list_type, progress) from public.anime_user_lists
   where user_id = tests.uid(812)::text and anime_id = 771006), '["WATCHING",4]'::jsonb);
select tests.eq('Undo preserves all values of the replacement of an updated entry',
  (select jsonb_build_array(list_type, progress, unit_id, progress_label, notes, rating)
   from public.manga_user_lists where user_id = tests.uid(812)::text and manga_id = 771003),
  '["PAUSED",7,"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","4.5","keep-fractional-notes",8]'::jsonb);
select tests.eq('Undo discloses both removed lifetimes rather than claiming either was reverted',
  (select count(*) from jsonb_array_elements(:'lifecycle_undo'::jsonb -> 'skipped') e
   where e ->> 'reason' = 'removed_since_import'), 2::bigint);
select tests.eq('lifecycle skips produce no mutation receipts for replacement entries',
  (select count(*) from public.mutation_receipts
   where user_id = tests.uid(812)::text and mutation_id in (
     public._import_mutation_id('undo', :'lifecycle_sid'::uuid, 'ANIME', 771006),
     public._import_mutation_id('undo', :'lifecycle_sid'::uuid, 'MANGA', 771003))), 0::bigint);

rollback;
