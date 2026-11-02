-- 51_account_deletion_barrier.sql  --  F38 deletion/write barrier (single session)
--
-- Contract under test (prepared, NOT deployed):
--   20261005140000_account_deletion_write_barrier.sql
--   * begin_account_deletion(user) (service role only) takes the user's EXCLUSIVE advisory
--     lock and records a barrier row (idempotent, retry-safe).
--   * every INSERT/UPDATE of a user-keyed row that the auth.users cascade would NOT remove
--     (legacy TEXT list/comment tables, telemetry tables without FK, concierge_runs whose
--     FK only SETs NULL) and every new club membership takes the same user's SHARED lock in
--     a BEFORE trigger and is refused (42501 ACCOUNT_DELETION_IN_PROGRESS) once a barrier
--     exists -- for the user's own JWT AND for service-role writers acting for that user.
--   * deletes are never blocked, so cleanup and retries proceed; other users are unaffected.
--   * the barrier outlives the auth user (a still-valid JWT cannot write afterwards) and is
--     purged by a later begin_account_deletion only after 7 days AND only once the auth user
--     is gone.
-- The two-session proofs (in-flight writer vs. barrier, both orders) are in
-- supabase/tests/concurrency/90_deletion_write_barrier.sql.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.anime_comments
-- @requires table public.manga_comments
-- @requires table public.concierge_runs
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(90), tests.make_user(91), tests.make_user(92);
insert into public.anime (id) values (515151), (515152);
insert into public.manga (id) values (515151);
insert into public.anime_user_lists (user_id, anime_id, list_type, notes) values (tests.uid(90)::text, 515151, 'WATCHING', 'before');

select tests.as_user(tests.uid(91));
select (public.create_club('Barrier club', null, 'status')) ->> 'club_id' as b_club \gset
select invite_code as b_code from public.clubs where id = :'b_club' \gset

-- ---- authorization of the entry point ---------------------------------------
select tests.as_user(tests.uid(90));
select tests.denied('an end user cannot start a deletion barrier (service role only)',
  format($q$select public.begin_account_deletion(%L)$q$, tests.uid(90)));
select tests.denied('an end user cannot read barrier rows',
  $q$select * from public.account_deletion_barriers$q$);
select tests.as_anon();
select tests.denied('anon cannot start a deletion barrier', format($q$select public.begin_account_deletion(%L)$q$, tests.uid(90)));

-- ---- before the barrier: normal writes work -----------------------------------
select tests.as_user(tests.uid(90));
select tests.eq('before: owner writes a list row', tests.affected(format(
  $q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515152, 'PLANNING')$q$, auth.uid()::text)), 1::bigint);

-- ---- start the deletion (service role) ---------------------------------------
select tests.reset();
set local role service_role;
select tests.eq('begin_account_deletion succeeds', (public.begin_account_deletion(tests.uid(90))) ->> 'success', 'true');
select tests.eq('begin_account_deletion is idempotent (retry)', (public.begin_account_deletion(tests.uid(90))) ->> 'success', 'true');
select tests.reset();
select tests.eq('exactly one barrier row', (select count(*) from public.account_deletion_barriers where user_id = tests.uid(90)), 1::bigint);

-- ---- after the barrier: every protected write for user 90 is refused -----------
select tests.as_user(tests.uid(90));
select tests.denied('F38: new list row refused (anime, own JWT)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515151, 'WATCHING')$q$, auth.uid()::text));
select tests.denied('F38: new list row refused (manga, own JWT)',
  format($q$insert into public.manga_user_lists (user_id, manga_id, list_type) values (%L, 515151, 'READING')$q$, auth.uid()::text));
select tests.denied('F38: notes-only update of a surviving row refused (the evidence''s second leak)',
  $q$update public.anime_user_lists set notes = 'post-deletion note' where anime_id = 515151$q$);
select tests.denied('F38: an upper-case spelling of the same id is refused too',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515151, 'WATCHING')$q$, upper(auth.uid()::text)));
select tests.denied('F38: joining a club refused (no new membership during deletion)',
  format($q$select public.join_club(%L)$q$, :'b_code'));
select tests.denied('F38: creating a club refused', $q$select public.create_club('late club', null, 'status')$q$);
select tests.eq('deletes are never blocked (cleanup and retries proceed)',
  tests.affected($q$delete from public.anime_user_lists where anime_id = 515152$q$), 1::bigint);
select tests.reset();
set local role service_role;
select tests.denied('F38: a service-role writer acting for the user is refused as well (e.g. an import)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515152, 'PLANNING')$q$, tests.uid(90)::text));
select tests.denied('F38: legacy anime_comments write for the user refused',
  format($q$insert into public.anime_comments (anime_id, user_id, comment) values (515151, %L, 'late')$q$, tests.uid(90)::text));
select tests.denied('F38: concierge_runs write for the user refused (its FK only SETs NULL, the prompt would survive)',
  format($q$insert into public.concierge_runs (user_id, kind) values (%L, 'late')$q$, tests.uid(90)));

-- ---- other users are unaffected ----------------------------------------------
select tests.as_user(tests.uid(92));
select tests.eq('another user writes normally', tests.affected(format(
  $q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515151, 'WATCHING')$q$, auth.uid()::text)), 1::bigint);
select tests.eq('another user joins clubs normally', (public.join_club(:'b_code')) ->> 'club_id', :'b_club');

-- ---- the evidence repro, now with the barrier: nothing survives -----------------
select tests.reset();
delete from public.anime_user_lists where user_id = tests.uid(90)::text;   -- edge-function cleanup step
delete from auth.users where id = tests.uid(90);                             -- GoTrue stand-in (not Supabase Auth)
select tests.eq('F38: no list row survives the deletion', (select count(*) from public.anime_user_lists where user_id = tests.uid(90)::text), 0::bigint);
select tests.as_user(tests.uid(90));   -- a still-valid JWT of the deleted user
select tests.denied('F38: a late write with the deleted user''s JWT is still refused (barrier outlives the auth user)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 515151, 'WATCHING')$q$, auth.uid()::text));

-- ---- bounded retention ---------------------------------------------------------
select tests.reset();
update public.account_deletion_barriers set started_at = now() - interval '8 days' where user_id = tests.uid(90);
insert into public.account_deletion_barriers (user_id, started_at) values (tests.uid(92), now() - interval '8 days');
set local role service_role;
select public.begin_account_deletion(tests.uid(91));
select tests.reset();
select tests.eq('retention: a finished deletion older than 7 days is purged by the next deletion',
  (select count(*) from public.account_deletion_barriers where user_id = tests.uid(90)), 0::bigint);
select tests.eq('retention: an old barrier of a user who still exists (interrupted deletion) is kept',
  (select count(*) from public.account_deletion_barriers where user_id = tests.uid(92)), 1::bigint);

-- ---- posture -------------------------------------------------------------------
select tests.ok('posture: barrier table has RLS enabled',
  (select relrowsecurity from pg_class where oid = 'public.account_deletion_barriers'::regclass));
select tests.ok('posture: begin_account_deletion is SECURITY DEFINER with search_path = public, extensions',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc where oid = 'public.begin_account_deletion(uuid)'::regprocedure));
select tests.ok('posture: only service_role may EXECUTE begin_account_deletion',
  has_function_privilege('service_role', 'public.begin_account_deletion(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.begin_account_deletion(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.begin_account_deletion(uuid)', 'EXECUTE'));
select tests.eq('posture: the barrier trigger guards every no-cascade user-keyed table and new memberships',
  (select string_agg(c.relname, ',' order by c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'account_deletion_barrier' and not t.tgisinternal),
  'anime_comments,anime_user_lists,club_analytics,club_members,concierge_events,concierge_runs,discover_rail_impressions,manga_comments,manga_user_lists,rag_retrieval_feedback');

select tests.reset();
rollback;
