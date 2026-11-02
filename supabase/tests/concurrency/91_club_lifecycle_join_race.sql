-- 91_club_lifecycle_join_race.sql  --  F39 (and F37 ordering) with TWO real database sessions
--
-- The evidence (90_review_deletion_interleaving.sql) showed the old sweep: count members
-- (0), another user joins, then an unconditional DELETE removes the club and cascades the
-- new membership. The lifecycle now locks the club row before it decides, re-checks
-- emptiness in a fresh statement under that lock, and join_club takes the same row lock
-- before it inserts, so the two are serialized in either order:
-- Order A: the deletion lifecycle holds the lock and deletes the empty club first; the
--          concurrent join WAITS and then finds no club (INVALID_CODE); no stray membership.
-- Order B: the join holds the lock first; the deletion lifecycle WAITS, then sees the new
--          member, transfers ownership to them and keeps the club.
-- Actors: joiner = end user (role authenticated + claims); deleter = service role.
-- Runs in its own clone of the fixture database (this file COMMITs).
-- @requires extension dblink
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4);

-- user 1 owns solo club A; user 3 owns solo club B (committed setup through the RPC)
begin;
select tests.as_user(tests.uid(1));
select (public.create_club('Race A', null, 'status')) ->> 'club_id' as a_club \gset
select tests.as_user(tests.uid(3));
select (public.create_club('Race B', null, 'status')) ->> 'club_id' as b_club \gset
select tests.reset();
commit;
select invite_code as a_code from public.clubs where id = :'a_club' \gset
select invite_code as b_code from public.clubs where id = :'b_club' \gset

select tests.actor_open('joiner', :'conn') as joiner_pid \gset
select tests.actor_open('deleter', :'conn') as deleter_pid \gset
select tests.actor_exec('deleter', 'set role service_role');

-- ============================== Order A ======================================
select tests.actor_exec('deleter', 'begin');
select tests.actor_exec('deleter', format('select public.begin_account_deletion(%L)::text', tests.uid(1)));
select tests.eq('A: deletion lifecycle removes the owner''s membership and deletes the now-empty club (uncommitted)',
  ((tests.actor_exec('deleter', format('select public.delete_account_club_memberships(%L)::text', tests.uid(1))))::jsonb ->> 'clubs_deleted')::int, 1);
select tests.actor_exec('joiner', 'begin');
select tests.actor_exec('joiner', format('select tests.as_user(%L)', tests.uid(2)));
select tests.actor_send('joiner', format('select public.join_club(%L)::text', :'a_code'));
select tests.ok('A: the concurrent join WAITS on the club row lock held by the lifecycle',
  tests.wait_lock_wait(:joiner_pid) in ('transactionid', 'tuple'));
select tests.eq('A: deletion commits', tests.actor_exec('deleter', 'commit'), 'COMMIT');
select tests.ok('A: the join then finds no club (INVALID_CODE), instead of resurrecting it',
  tests.actor_result('joiner') like 'ERROR: INVALID_CODE%');
select tests.actor_exec('joiner', 'rollback');
select tests.eq('A: club A is gone', (select count(*) from public.clubs where id = :'a_club'), 0::bigint);
select tests.eq('A: no stray membership for the joiner', (select count(*) from public.club_members where user_id = tests.uid(2)), 0::bigint);

-- ============================== Order B ======================================
select tests.actor_exec('joiner', 'begin');
select tests.actor_exec('joiner', format('select tests.as_user(%L)', tests.uid(4)));
select tests.eq('B: user 4 joins club B (uncommitted, holds the club row lock)',
  (tests.actor_exec('joiner', format('select public.join_club(%L)::text', :'b_code')))::jsonb ->> 'club_id', :'b_club');
select tests.actor_exec('deleter', 'begin');
select tests.actor_exec('deleter', format('select public.begin_account_deletion(%L)::text', tests.uid(3)));
select tests.actor_send('deleter', format('select public.delete_account_club_memberships(%L)::text', tests.uid(3)));
select tests.ok('B: the deletion lifecycle WAITS for the in-flight join',
  tests.wait_lock_wait(:deleter_pid) in ('transactionid', 'tuple'));
select tests.eq('B: join commits', tests.actor_exec('joiner', 'commit'), 'COMMIT');
select tests.eq('B: the lifecycle then sees the new member and deletes no club',
  ((tests.actor_result('deleter'))::jsonb ->> 'clubs_deleted')::int, 0);
select tests.eq('B: deletion commits', tests.actor_exec('deleter', 'commit'), 'COMMIT');
select tests.eq('B: F39 closed -- club B survives', (select count(*) from public.clubs where id = :'b_club'), 1::bigint);
select tests.eq('B: the joiner kept their membership and became the owner',
  (select role from public.club_members where club_id = :'b_club' and user_id = tests.uid(4)), 'owner');
select tests.eq('B: the deleting user holds no membership', (select count(*) from public.club_members where user_id = tests.uid(3)), 0::bigint);

select tests.actor_close('joiner');
select tests.actor_close('deleter');
