-- 90_deletion_write_barrier.sql  --  F38 with TWO real database sessions
--
-- Replaces the single-session evidence shape of
-- docs/handoffs/2026-10-05-modularity-completion-evidence/90_review_deletion_interleaving.sql
-- (where a write committed after the TEXT-list cleanup survived the auth deletion) with
-- controlled interleavings of two backends:
--   writer  = the user's own PostgREST-style session (role authenticated + JWT claims)
--   deleter = the delete-account edge function's service-role session
-- Order A: the writer's transaction is IN FLIGHT when the deletion starts. The barrier
--          must wait for it (no row can slip in after the cleanup), then the cleanup
--          removes it, and every later write is refused.
-- Order B: the deletion holds the barrier first. A concurrent write must wait and then be
--          refused; nothing is written.
-- The orchestrator (this psql session, superuser) waits on pg_locks state, never sleeps.
-- Runs in its own clone of the fixture database (this file COMMITs).
-- @requires extension dblink
-- @requires table public.anime_user_lists
-- @requires table public.anime
\set ON_ERROR_STOP on
\o /dev/null

select tests.make_user(90), tests.make_user(91);
insert into public.anime (id) values (909090), (909091), (909092);

select tests.actor_open('writer', :'conn') as writer_pid \gset
select tests.actor_open('deleter', :'conn') as deleter_pid \gset

-- ============================== Order A ======================================
select tests.eq('A: writer opens a transaction', tests.actor_exec('writer', 'begin'), 'BEGIN');
select tests.actor_exec('writer', format('select tests.as_user(%L)', tests.uid(90)));
select tests.eq('A: writer inserts a list row (uncommitted, holds the user''s shared lock)',
  tests.actor_exec('writer', format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 909090, 'WATCHING')$q$, tests.uid(90))),
  'INSERT 0 1');
select tests.actor_exec('deleter', 'set role service_role');
select tests.actor_send('deleter', format('select public.begin_account_deletion(%L)::text', tests.uid(90)));
select tests.eq('A: the deletion barrier WAITS for the in-flight writer (advisory lock wait observed)',
  tests.wait_lock_wait(:deleter_pid), 'advisory');
select tests.eq('A: writer commits', tests.actor_exec('writer', 'commit'), 'COMMIT');
select tests.ok('A: the barrier is established after the writer committed',
  (tests.actor_result('deleter'))::jsonb ->> 'success' = 'true');
select tests.eq('A: the writer''s row exists before cleanup (it committed before the barrier)',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(90)::text), 1::bigint);
select tests.actor_exec('writer', 'begin');
select tests.actor_exec('writer', format('select tests.as_user(%L)', tests.uid(90)));
select tests.ok('A: a notes-only update of the surviving row is refused once the barrier exists',
  tests.actor_exec('writer', $q$update public.anime_user_lists set notes = 'post-deletion note' where anime_id = 909090$q$)
  like 'ERROR: ACCOUNT_DELETION_IN_PROGRESS%');
select tests.actor_exec('writer', 'rollback');
-- edge-function cleanup step (service role) after the barrier
select tests.eq('A: cleanup deletes the user''s list rows',
  tests.actor_exec('deleter', format('delete from public.anime_user_lists where user_id = %L', tests.uid(90))), 'DELETE 1');
-- the still-authenticated client tries again after the cleanup: refused
select tests.actor_exec('writer', 'begin');
select tests.actor_exec('writer', format('select tests.as_user(%L)', tests.uid(90)));
select tests.ok('A: a write after the cleanup is refused (ACCOUNT_DELETION_IN_PROGRESS)',
  tests.actor_exec('writer', format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 909091, 'WATCHING')$q$, tests.uid(90)))
  like 'ERROR: ACCOUNT_DELETION_IN_PROGRESS%');
select tests.actor_exec('writer', 'rollback');
-- auth deletion last (superuser stands in for GoTrue: NOT Supabase Auth)
delete from auth.users where id = tests.uid(90);
select tests.eq('A: F38 closed -- no private list row survives the deletion',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(90)::text), 0::bigint);

-- ============================== Order B ======================================
select tests.actor_exec('deleter', 'begin');
select tests.ok('B: the deletion takes the barrier first (transaction still open)',
  (tests.actor_exec('deleter', format('select public.begin_account_deletion(%L)::text', tests.uid(91))))::jsonb ->> 'success' = 'true');
select tests.actor_exec('writer', 'begin');
select tests.actor_exec('writer', format('select tests.as_user(%L)', tests.uid(91)));
select tests.actor_send('writer', format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 909092, 'WATCHING')$q$, tests.uid(91)));
select tests.eq('B: the concurrent write WAITS for the deletion''s exclusive lock',
  tests.wait_lock_wait(:writer_pid), 'advisory');
select tests.eq('B: deletion commits the barrier', tests.actor_exec('deleter', 'commit'), 'COMMIT');
select tests.ok('B: the waiting write is then refused (ACCOUNT_DELETION_IN_PROGRESS)',
  tests.actor_result('writer') like 'ERROR: ACCOUNT_DELETION_IN_PROGRESS%');
select tests.actor_exec('writer', 'rollback');
select tests.eq('B: nothing was written for the user',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(91)::text), 0::bigint);

select tests.actor_close('writer');
select tests.actor_close('deleter');
