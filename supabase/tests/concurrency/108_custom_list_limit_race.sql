-- 108_custom_list_limit_race.sql -- W9: two sessions create the 50th custom list at the same time.
-- The per-account advisory lock serialises create_custom_list_v1, so exactly one wins and the other gets LIST_LIMIT.
-- Runs in its own clone of the fixture database (this file COMMITs).
-- @requires extension dblink
-- @requires table public.custom_lists
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(108);
insert into public.custom_lists (user_id, name) select tests.uid(108), 'seed' || n from generate_series(1, 49) n;

select tests.actor_open('device_a', :'conn') as device_a \gset
select tests.actor_open('device_b', :'conn') as device_b \gset

select tests.eq('A begins', tests.actor_exec('device_a', 'begin'), 'BEGIN');
select tests.actor_exec('device_a', format('select tests.as_user(%L)', tests.uid(108)));
select tests.ok('A creates list a (uncommitted, holds the account lock)',
  tests.actor_exec('device_a', $q$select (public.create_custom_list_v1('a')) ->> 'name'$q$) = 'a');
select tests.eq('B begins', tests.actor_exec('device_b', 'begin'), 'BEGIN');
select tests.actor_exec('device_b', format('select tests.as_user(%L)', tests.uid(108)));
select tests.actor_send('device_b', $q$select (public.create_custom_list_v1('b')) ->> 'name'$q$);
select tests.ok('B WAITS on the account advisory lock', tests.wait_lock_wait(:device_b) = 'advisory');
select tests.eq('A commits', tests.actor_exec('device_a', 'commit'), 'COMMIT');
select tests.ok('B is refused with LIST_LIMIT', tests.actor_result('device_b') like '%LIST_LIMIT%');
select tests.actor_exec('device_b', 'rollback');
select tests.eq('exactly 50 lists remain', (select count(*) from public.custom_lists where user_id = tests.uid(108)), 50::bigint);
select tests.eq('only list a was created', (select count(*) from public.custom_lists where user_id = tests.uid(108) and name in ('a', 'b')), 1::bigint);

select tests.actor_close('device_a');
select tests.actor_close('device_b');
delete from auth.users where id = tests.uid(108);
