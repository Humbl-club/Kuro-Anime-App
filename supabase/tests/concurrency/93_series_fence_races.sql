-- 93_series_fence_races.sql
-- Progress versus a note, add/delete/add lifecycle, import versus a local edit,
-- and club membership removal versus a comment write.
-- @requires extension dblink
-- @requires table public.anime_user_lists
-- @requires table public.anime
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires table public.title_comments
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.leave_club(uuid)
-- @requires function public.upsert_title_comment(text,integer,text)
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(93);
select tests.make_user(94);
insert into public.anime (id, title_romaji, mal_id) values (770199, 'Fence Probe', 770199);

insert into public.anime_user_lists (user_id, anime_id, list_type, progress, notes)
values (tests.uid(93)::text, 770199, 'WATCHING', 1, 'original');

select lifecycle_id::text as life, server_revision::text as rev
from public.anime_user_lists where anime_id = 770199 \gset
select gen_random_uuid()::text as mut_progress \gset
select gen_random_uuid()::text as mut_stale \gset

select tests.actor_open('progress', :'conn') as progress_pid \gset
select tests.actor_open('note', :'conn') as note_pid \gset

-- Progress holds the row. The note waits, then lands without rewinding progress.
select tests.eq('progress begins', tests.actor_exec('progress', 'begin'), 'BEGIN');
select tests.actor_exec('progress', format('select tests.as_user(%L)', tests.uid(93)));
select tests.eq('progress applies position 5',
  tests.actor_exec('progress', format(
    $q$select (public.apply_progress_mutations_v1('[{"mutation_id":"%s","medium":"anime","media_id":770199,"lifecycle_id":"%s","base_revision":%s,"position":5}]'::jsonb) -> 'items' -> 0 ->> 'outcome')$q$,
    :'mut_progress', :'life', :'rev'
  )),
  'applied');

select tests.eq('note begins', tests.actor_exec('note', 'begin'), 'BEGIN');
select tests.actor_exec('note', format('select tests.as_user(%L)', tests.uid(93)));
select tests.actor_send('note', $q$update public.anime_user_lists set notes = 'from the other device' where anime_id = 770199$q$);
select tests.wait_lock_wait(:note_pid) as note_waited \gset
select tests.ok('note waits on account admission or list row', :'note_waited' like '%advisory%' or :'note_waited' like '%tuple%' or :'note_waited' like '%transactionid%');
select tests.ok('note is blocked by the exact in-flight progress writer',
 :progress_pid = any(pg_blocking_pids(:note_pid)));
select tests.eq('progress commits', tests.actor_exec('progress', 'commit'), 'COMMIT');
select tests.eq('note update finishes', tests.actor_result('note'), 'UPDATE 1');
select tests.actor_exec('note', 'commit');

select tests.eq('progress stayed at the receipt',
  (select progress from public.anime_user_lists where anime_id = 770199), 5);
select tests.eq('note landed after the receipt',
  (select notes from public.anime_user_lists where anime_id = 770199), 'from the other device');

select server_revision::text as after_note
from public.anime_user_lists where anime_id = 770199 \gset
begin;
select tests.as_user(tests.uid(93));
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', :'mut_stale',
  'medium', 'anime',
  'media_id', 770199,
  'lifecycle_id', :'life',
  'base_revision', :'rev',
  'position', 1
))) as stale \gset
select tests.eq('stale progress conflicts after the note', (:'stale'::jsonb -> 'items' -> 0 ->> 'outcome'), 'conflict');
commit;
select tests.eq('conflict did not rewind progress',
  (select progress from public.anime_user_lists where anime_id = 770199), 5);

-- Add, delete, add. The old lifecycle cannot write the new row.
select lifecycle_id::text as first_life from public.anime_user_lists where anime_id = 770199 \gset
select tests.eq('owner deletes the row',
  tests.affected($q$delete from public.anime_user_lists where anime_id = 770199$q$), 1::bigint);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(93)::text, 770199, 'WATCHING', 0);
select lifecycle_id::text as second_life, server_revision::text as second_rev
from public.anime_user_lists where anime_id = 770199 \gset
select tests.ok('the new row has a new lifecycle', :'second_life' <> :'first_life');
begin;
select tests.as_user(tests.uid(93));
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', gen_random_uuid(),
  'medium', 'anime',
  'media_id', 770199,
  'lifecycle_id', :'first_life',
  'base_revision', 1,
  'position', 4
))) as old_life \gset
select tests.eq('old lifecycle is removed', (:'old_life'::jsonb -> 'items' -> 0 ->> 'outcome'), 'removed_entry');
select public.apply_progress_mutations_v1(jsonb_build_array(jsonb_build_object(
  'mutation_id', gen_random_uuid(),
  'medium', 'anime',
  'media_id', 770199,
  'lifecycle_id', :'second_life',
  'base_revision', :'second_rev',
  'position', 2
))) as new_life \gset
select tests.eq('new lifecycle accepts progress', (:'new_life'::jsonb -> 'items' -> 0 ->> 'outcome'), 'applied');
commit;
select tests.eq('new lifecycle progress is 2',
  (select progress from public.anime_user_lists where anime_id = 770199), 2);

-- Import versus a local edit. The local edit holds the row; the chunk then conflicts.
begin;
select tests.as_user(tests.uid(93));
select (public.start_library_import_v1('myanimelist','export','anime','idem-fence-93','abcdef0123456789') ->> 'job_id') as job \gset
commit;
select tests.actor_exec('progress', 'begin');
select tests.actor_exec('progress', format('select tests.as_user(%L)', tests.uid(93)));
select tests.actor_exec('progress', $q$update public.anime_user_lists set progress = 9 where anime_id = 770199$q$);
select tests.actor_exec('note', 'begin');
select tests.actor_exec('note', format('select tests.as_user(%L)', tests.uid(93)));
select tests.actor_send('note', format(
  $q$select (public.apply_import_chunk_v1('%s'::uuid, '[{"medium":"anime","external_id":"770199","status":"watching","progress":1}]'::jsonb) ->> 'conflict')$q$,
  :'job'
));
select tests.wait_lock_wait(:note_pid) as import_waited \gset
select tests.ok('import waits on the local edit admission or row', :'import_waited' like '%advisory%' or :'import_waited' like '%tuple%' or :'import_waited' like '%transactionid%');
select tests.ok('import is blocked by the exact local-edit transaction',
 :progress_pid = any(pg_blocking_pids(:note_pid)));
select tests.actor_exec('progress', 'commit');
select tests.eq('import counts a conflict', tests.actor_result('note'), '1');
select tests.actor_exec('note', 'commit');
select tests.eq('local progress wins',
  (select progress from public.anime_user_lists where anime_id = 770199), 9);

-- Membership removal versus a comment. One shared club. After the membership is gone,
-- the next home bundle has no name and no comment text.
begin;
select tests.as_user(tests.uid(93));
select (public.create_club('Fence Club', null, 'status')) ->> 'club_id' as club \gset
select public.upsert_title_comment('ANIME', 770199, 'between us');
commit;
select invite_code as code from public.clubs where id = :'club' \gset
begin;
select tests.as_user(tests.uid(94));
select public.join_club(:'code');
commit;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(94)::text, 770199, 'WATCHING', 1);

begin;
select tests.as_user(tests.uid(94));
select tests.eq('shared club comment is visible before removal',
  (select (public.home_bundle_v1('anime') -> 'club' -> 'items' -> 0 ->> 'text')), 'between us');
commit;

select tests.actor_exec('progress', 'begin');
select tests.actor_exec('progress', format('select tests.as_user(%L)', tests.uid(94)));
select tests.actor_exec('progress', format('select id from public.clubs where id = %L::uuid for update', :'club'));
select tests.actor_exec('progress', format('select public.leave_club(%L::uuid)', :'club'));
select tests.actor_exec('note', 'begin');
select tests.actor_exec('note', format('select tests.as_user(%L)', tests.uid(93)));
select tests.actor_send('note', format(
  $q$select public.upsert_title_comment('ANIME', 770199, 'too late') from public.clubs where id = %L::uuid for update$q$,
  :'club'
));
select tests.wait_lock_wait(:note_pid) as comment_waited \gset
select tests.ok('comment write waits on the membership change', :'comment_waited' like '%tuple%' or :'comment_waited' like '%transactionid%' or :'comment_waited' like '%relation%');
select tests.actor_exec('progress', 'commit');
select tests.actor_result('note') as comment_result \gset
select tests.actor_exec('note', 'rollback');

begin;
select tests.as_user(tests.uid(94));
select tests.eq('bundle has no comment text after the only shared club is gone',
  (select coalesce(jsonb_path_query_array(public.home_bundle_v1('anime') -> 'club' -> 'items', '$[*].text'), '[]'::jsonb)),
  '[]'::jsonb);
select tests.eq('bundle has no display name after the only shared club is gone',
  (select coalesce(jsonb_path_query_array(public.home_bundle_v1('anime') -> 'club' -> 'items', '$[*].display_name'), '[]'::jsonb)),
  '[]'::jsonb);
commit;

select tests.actor_close('progress');
select tests.actor_close('note');
