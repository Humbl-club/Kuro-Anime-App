-- 108_organisation_two_devices.sql -- W9: ONE account on two devices (same user in two real sessions).
--  1. A stale tags-and-lists sheet saves a DELTA, so the other device's additions are kept.
--  2. Two concurrent reorders of one list: the second is refused as STALE_LIST (revision guard read after the lock).
-- Runs in its own clone of the fixture database (this file COMMITs).
-- @requires extension dblink
-- @requires table public.custom_lists
-- @requires table public.anime_user_lists
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(109);
insert into public.anime (id, title_romaji) select 770100 + n, 'Two devices ' || n from generate_series(1, 10) n on conflict (id) do nothing;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  select tests.uid(109)::text, 770100 + n, 'PLANNING', 0 from generate_series(1, 10) n;
insert into public.custom_lists (user_id, name) values (tests.uid(109), 'L1'), (tests.uid(109), 'L2'), (tests.uid(109), 'L3');
select id as l1 from public.custom_lists where user_id = tests.uid(109) and name = 'L1' \gset
select id as l2 from public.custom_lists where user_id = tests.uid(109) and name = 'L2' \gset
select id as l3 from public.custom_lists where user_id = tests.uid(109) and name = 'L3' \gset
-- anime 770101: tag comfy and list L1 (committed setup through the RPC as the user)
begin;
select tests.as_user(tests.uid(109));
select public.apply_title_organisation_delta_v1('anime', 770101, array['comfy'], null, array[:'l1'::uuid], null);
-- L3 holds ten items
select public.apply_title_organisation_delta_v1('anime', 770100 + n, null, null, array[:'l3'::uuid], null) from generate_series(1, 10) n;
select tests.reset();
commit;

select tests.actor_open('device_a', :'conn') as device_a \gset
select tests.actor_open('device_b', :'conn') as device_b \gset
select tests.eq('A begins', tests.actor_exec('device_a', 'begin'), 'BEGIN');
select tests.actor_exec('device_a', format('select tests.as_user(%L)', tests.uid(109)));
select tests.eq('B begins', tests.actor_exec('device_b', 'begin'), 'BEGIN');
select tests.actor_exec('device_b', format('select tests.as_user(%L)', tests.uid(109)));

-- 1. stale sheet keeps the other device's additions ----------------------------------------------------------------
select tests.eq('A sheet snapshot holds {comfy}',
  tests.actor_exec('device_a', $q$select (select tags from public.library_tag_index_v1() where media_id = 770101)::text$q$), '{comfy}');
select tests.ok('B adds rewatch and L2',
  tests.actor_exec('device_b', format($q$select (public.apply_title_organisation_delta_v1('anime',770101,array['rewatch'],null,array[%L::uuid],null)) ->> 'tags'$q$, :'l2')) like '%rewatch%');
select tests.eq('B commits', tests.actor_exec('device_b', 'commit'), 'COMMIT');
select tests.ok('A saves its own delta; the returned server state already includes B''s tag',
  tests.actor_exec('device_a', format($q$select (public.apply_title_organisation_delta_v1('anime',770101,array['slow burn'],array['comfy'],null,array[%L::uuid])) ->> 'tags'$q$, :'l1')) = '["rewatch", "slow burn"]');
select tests.eq('A commits', tests.actor_exec('device_a', 'commit'), 'COMMIT');
select tests.eq('final tags are exactly rewatch and slow burn',
  (select array_agg(tag order by tag_key) from public.library_tags where user_id = tests.uid(109) and media_id = 770101),
  array['rewatch', 'slow burn']);
select tests.eq('final membership is exactly L2 and L3 (L3 untouched by either delta)',
  (select array_agg(list_id order by list_id) from public.custom_list_items where user_id = tests.uid(109) and media_id = 770101),
  (select array_agg(x order by x) from unnest(array[:'l2'::uuid, :'l3'::uuid]) x));
select tests.eq('L1 membership was removed by A only',
  (select count(*) from public.custom_list_items where user_id = tests.uid(109) and media_id = 770101 and list_id = :'l1'::uuid), 0::bigint);

-- 2. two concurrent reorders ---------------------------------------------------------------------------------------
select revision as r from public.custom_lists where id = :'l3'::uuid \gset
select id as item9 from public.custom_list_items where list_id = :'l3'::uuid and media_id = 770109 \gset
select id as item5 from public.custom_list_items where list_id = :'l3'::uuid and media_id = 770105 \gset
select position as pos5 from public.custom_list_items where id = :'item5'::uuid \gset
select tests.eq('A begins again', tests.actor_exec('device_a', 'begin'), 'BEGIN');
select tests.actor_exec('device_a', format('select tests.as_user(%L)', tests.uid(109)));
select tests.eq('B begins again', tests.actor_exec('device_b', 'begin'), 'BEGIN');
select tests.actor_exec('device_b', format('select tests.as_user(%L)', tests.uid(109)));
select tests.ok('A moves item 9 (uncommitted, holds the lock)',
  tests.actor_exec('device_a', format($q$select (public.move_custom_list_item_v1(%L,%L,1024,2048,%s)) ->> 'revision'$q$, :'l3', :'item9', :'r')) = (:'r'::bigint + 1)::text);
select tests.actor_send('device_b', format($q$select public.move_custom_list_item_v1(%L,%L,7168,8192,%s)::text$q$, :'l3', :'item5', :'r'));
select tests.ok('B WAITS on the account lock', tests.wait_lock_wait(:device_b) = 'advisory');
select tests.eq('A commits the move', tests.actor_exec('device_a', 'commit'), 'COMMIT');
select tests.ok('second reorder is refused as stale', tests.actor_result('device_b') like '%STALE_LIST%');
select tests.actor_exec('device_b', 'rollback');
select tests.eq('final revision is r + 1', (select revision from public.custom_lists where id = :'l3'::uuid), :'r'::bigint + 1);
select tests.eq('only item 9 moved', (select position from public.custom_list_items where id = :'item9'::uuid), 1536::float8);
select tests.eq('item 5 kept its position', (select position from public.custom_list_items where id = :'item5'::uuid), :'pos5'::float8);

select tests.actor_close('device_a');
select tests.actor_close('device_b');
delete from auth.users where id = tests.uid(109);
