-- 92_series_progress_race.sql
-- Two authenticated sessions, one list row, same base revision.
-- The second transaction waits on account admission or the row, then conflicts.
-- @requires extension dblink
-- @requires table public.anime_user_lists
-- @requires table public.anime
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(92);
insert into public.anime (id, title_romaji) values (770099, 'Race Probe');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(92)::text, 770099, 'WATCHING', 1);

select lifecycle_id::text as life, server_revision::text as rev
from public.anime_user_lists where anime_id = 770099 \gset
select gen_random_uuid()::text as mut_a \gset
select gen_random_uuid()::text as mut_b \gset

select tests.actor_open('device_a', :'conn') as device_a \gset
select tests.actor_open('device_b', :'conn') as device_b \gset

select tests.eq('A begins', tests.actor_exec('device_a', 'begin'), 'BEGIN');
select tests.actor_exec('device_a', format('select tests.as_user(%L)', tests.uid(92)));
select tests.eq('A applies position 5 and holds the row',
  tests.actor_exec('device_a', format(
    $q$select (public.apply_progress_mutations_v1('[{"mutation_id":"%s","medium":"anime","media_id":770099,"lifecycle_id":"%s","base_revision":%s,"position":5}]'::jsonb) -> 'items' -> 0 ->> 'outcome')$q$,
    :'mut_a', :'life', :'rev'
  )),
  'applied');

select tests.eq('B begins', tests.actor_exec('device_b', 'begin'), 'BEGIN');
select tests.actor_exec('device_b', format('select tests.as_user(%L)', tests.uid(92)));
select tests.actor_send('device_b', format(
  $q$select (public.apply_progress_mutations_v1('[{"mutation_id":"%s","medium":"anime","media_id":770099,"lifecycle_id":"%s","base_revision":%s,"position":1}]'::jsonb) -> 'items' -> 0 ->> 'outcome')$q$,
  :'mut_b', :'life', :'rev'
));
select tests.wait_lock_wait(:device_b) as waited \gset
select tests.ok('B waits on account admission or list row', :'waited' like '%advisory%' or :'waited' like '%tuple%' or :'waited' like '%transactionid%');
select tests.ok('B is specifically blocked by A holding the tracking admission',
 :device_a = any(pg_blocking_pids(:device_b)));
select tests.eq('A commits', tests.actor_exec('device_a', 'commit'), 'COMMIT');
select tests.eq('B conflicts instead of rewinding', tests.actor_result('device_b'), 'conflict');
select tests.actor_exec('device_b', 'rollback');
select tests.eq('canonical progress is the first commit',
  (select progress from public.anime_user_lists where anime_id = 770099), 5);

select tests.actor_close('device_a');
select tests.actor_close('device_b');
