-- 10_user_lists.sql  --  (a) anime_user_lists / manga_user_lists
-- Legacy TEXT user_id compared with auth.uid()::text under policy
-- "Users can manage their own lists" (FOR ALL TO authenticated).
-- All user-visible assertions run as role `authenticated` / `anon`.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
\o /dev/null
begin;

-- seed (superuser session): two users, one anime and one manga with the SAME numeric id
select tests.make_user(1), tests.make_user(2);
insert into public.anime (id) values (424242);
insert into public.manga (id) values (424242);
insert into public.anime (id) values (424243);
insert into public.manga (id) values (424243);

-- policy shape the tests rely on (so a changed policy fails loudly here)
select tests.eq('anime_user_lists has exactly the owner FOR ALL policy',
  (select count(*) from pg_policies where schemaname='public' and tablename='anime_user_lists'
     and policyname='Users can manage their own lists' and cmd='ALL' and roles = '{authenticated}'), 1::bigint);
select tests.eq('manga_user_lists has exactly the owner FOR ALL policy',
  (select count(*) from pg_policies where schemaname='public' and tablename='manga_user_lists'
     and policyname='Users can manage their own lists' and cmd='ALL' and roles = '{authenticated}'), 1::bigint);
select tests.eq('no other policies on the list tables',
  (select count(*) from pg_policies where schemaname='public' and tablename in ('anime_user_lists','manga_user_lists')), 2::bigint);

-- ---- owner (user 1): select / insert / update / delete own rows -------------
select tests.as_user(tests.uid(1));
select tests.eq('owner inserts own anime row',
  tests.affected(format($q$insert into public.anime_user_lists (user_id, anime_id, list_type, progress, notes)
                            values (%L, 424242, 'WATCHING', 3, 'anime-note')$q$, auth.uid()::text)), 1::bigint);
select tests.eq('owner inserts own manga row with the SAME numeric id',
  tests.affected(format($q$insert into public.manga_user_lists (user_id, manga_id, list_type, progress, notes)
                            values (%L, 424242, 'READING', 7, 'manga-note')$q$, auth.uid()::text)), 1::bigint);
select tests.eq('owner reads own anime row', (select count(*) from public.anime_user_lists), 1::bigint);
select tests.eq('owner reads own manga row', (select count(*) from public.manga_user_lists), 1::bigint);

-- same numeric media id in anime vs manga lists stays distinct
select tests.eq('anime 424242 progress is 3', (select progress from public.anime_user_lists where anime_id = 424242), 3);
select tests.eq('manga 424242 progress is 7', (select progress from public.manga_user_lists where manga_id = 424242), 7);
select tests.eq('updating anime 424242 touches exactly one row',
  tests.affected($q$update public.anime_user_lists set progress = 4 where anime_id = 424242$q$), 1::bigint);
select tests.eq('...and the manga row with the same id is unchanged',
  (select progress from public.manga_user_lists where manga_id = 424242), 7);
select tests.eq('updating manga 424242 does not touch the anime row',
  tests.affected($q$update public.manga_user_lists set progress = 8 where manga_id = 424242$q$), 1::bigint);
select tests.eq('...anime progress still 4', (select progress from public.anime_user_lists where anime_id = 424242), 4);
select tests.raises('unique key is (user_id, anime_id): a duplicate own anime row is rejected',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424242, 'PLANNING')$q$, auth.uid()::text),
  '%duplicate key value violates unique constraint%');

-- a second, distinct anime row for delete test
select tests.eq('owner inserts a second anime row',
  tests.affected(format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'PLANNING')$q$, auth.uid()::text)), 1::bigint);
select tests.eq('owner deletes own second anime row',
  tests.affected($q$delete from public.anime_user_lists where anime_id = 424243$q$), 1::bigint);

-- owner cannot reassign own row to another user (WITH CHECK)
select tests.denied('owner cannot UPDATE own row to user_id of another user',
  format($q$update public.anime_user_lists set user_id = %L where anime_id = 424242$q$, tests.uid(2)::text));

-- F16 (prepared 20261005180000_list_user_id_canonical_case.sql): a client that sends the
-- UPPER-case uuidString (Swift's default) for its OWN id is normalized to the canonical
-- lower-case text BEFORE the RLS WITH CHECK runs, so the owner is accepted and the row is
-- stored exactly as auth.uid()::text. tests.uid(n) contains hex letters on purpose.
select tests.ok('F16 precondition: the test uuid contains hex letters (case is meaningful)',
  auth.uid()::text <> upper(auth.uid()::text));
select tests.eq('F16: owner insert with the UPPER-case spelling of their own id is accepted',
  tests.affected(format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'PLANNING')$q$, upper(auth.uid()::text))), 1::bigint);
select tests.eq('F16: ...and stored canonically (lower-case = auth.uid()::text), readable by the owner',
  (select user_id from public.anime_user_lists where anime_id = 424243), auth.uid()::text);
select tests.eq('F16: manga list normalizes the same way',
  tests.affected(format($q$insert into public.manga_user_lists (user_id, manga_id, list_type) values (%L, 424243, 'PLANNING')$q$, upper(auth.uid()::text))), 1::bigint);
select tests.eq('F16: an UPDATE that re-spells the owner id upper-case keeps the canonical value',
  tests.affected(format($q$update public.manga_user_lists set user_id = %L where manga_id = 424243$q$, upper(auth.uid()::text))), 1::bigint);
select tests.eq('F16: ...still lower-case', (select user_id from public.manga_user_lists where manga_id = 424243), auth.uid()::text);
select tests.raises('F16: the upper-case spelling cannot create a second row for the same title (unique key on the canonical id)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'WATCHING')$q$, upper(auth.uid()::text)),
  '%duplicate key value violates unique constraint%');
select tests.eq('cleanup: owner removes the F16 rows', tests.affected($q$delete from public.anime_user_lists where anime_id = 424243$q$)
  + tests.affected($q$delete from public.manga_user_lists where manga_id = 424243$q$), 2::bigint);

-- ---- user 2 cannot see or modify user 1 rows --------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('user 2 sees 0 anime rows (user 1 has 1)', (select count(*) from public.anime_user_lists), 0::bigint);
select tests.eq('user 2 sees 0 manga rows (user 1 has 1)', (select count(*) from public.manga_user_lists), 0::bigint);
select tests.eq('user 2 UPDATE of user 1 anime row affects 0 rows',
  tests.affected($q$update public.anime_user_lists set progress = 99$q$), 0::bigint);
select tests.eq('user 2 DELETE of user 1 manga row affects 0 rows',
  tests.affected($q$delete from public.manga_user_lists$q$), 0::bigint);
select tests.denied('user 2 cannot INSERT a row owned by user 1 (anime)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'PLANNING')$q$, tests.uid(1)::text));
select tests.denied('user 2 cannot INSERT a row owned by user 1 (manga)',
  format($q$insert into public.manga_user_lists (user_id, manga_id, list_type) values (%L, 424243, 'PLANNING')$q$, tests.uid(1)::text));
select tests.denied('F16: user 2 cannot INSERT a row for user 1 through the UPPER-case spelling (normalized, then denied)',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'PLANNING')$q$, upper(tests.uid(1)::text)));
-- user 2 can still use the same media id independently (no cross-user uniqueness leak)
select tests.eq('user 2 inserts own row for the same anime id',
  tests.affected(format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424242, 'DROPPED')$q$, auth.uid()::text)), 1::bigint);
select tests.eq('user 2 sees only their own row', (select count(*) from public.anime_user_lists), 1::bigint);

-- ---- anon -------------------------------------------------------------------
select tests.as_anon();
select tests.eq('anon sees 0 anime list rows', (select count(*) from public.anime_user_lists), 0::bigint);
select tests.eq('anon sees 0 manga list rows', (select count(*) from public.manga_user_lists), 0::bigint);
select tests.denied('anon cannot insert an anime list row',
  format($q$insert into public.anime_user_lists (user_id, anime_id, list_type) values (%L, 424243, 'PLANNING')$q$, tests.uid(1)::text));

-- ---- superuser readback proves user 1's data was untouched by user 2 --------
select tests.reset();
select tests.eq('readback: user 1 anime row intact', (select progress from public.anime_user_lists where user_id = tests.uid(1)::text and anime_id = 424242), 4);
select tests.eq('readback: user 1 manga row intact', (select progress from public.manga_user_lists where user_id = tests.uid(1)::text and manga_id = 424242), 8);
select tests.eq('readback: user 2 anime row is the only user-2 row', (select count(*) from public.anime_user_lists where user_id = tests.uid(2)::text), 1::bigint);

-- ---- F40 legacy view public.user_lists (fixture-reconstructed) ---------------
-- The view is NOT in the baseline capture and not in the replayed chain
-- (20260206150000 that sets security_invoker on it does not replay), and it has live
-- callers (concierge-recommend reads it with the user's JWT; the recommend RPCs filter
-- it by auth.uid()), so it is kept and hardened, not retired. Rebuild it verbatim from
-- legacy_sql/08 (the risky shape) and apply the ACTUAL prepared migration file to it.
-- This proves the migration on the reconstruction, NOT production's current state.
\ir ../../../legacy_sql/08_create_user_lists_view.sql
select tests.as_user(tests.uid(2));
select tests.ok('F40 red half: the reconstructed view (owner semantics) leaks user 1 rows to user 2 before the fix',
  (select count(*) from public.user_lists where user_id = tests.uid(1)::text) > 0);
select tests.reset();
\ir ../../prepared-migrations/20261005170000_user_lists_view_security_invoker.sql
select tests.ok('F40: the prepared migration set security_invoker on the existing view',
  (select reloptions @> array['security_invoker=true'] or reloptions @> array['security_invoker=on']
     from pg_class where oid = 'public.user_lists'::regclass));
select tests.as_user(tests.uid(2));
select tests.eq('F40: other user reads 0 of user 1''s rows through the view',
  (select count(*) from public.user_lists where user_id = tests.uid(1)::text), 0::bigint);
select tests.eq('F40: other user still reads their OWN rows through the view',
  (select count(*) from public.user_lists where user_id = auth.uid()::text), 1::bigint);
select tests.as_user(tests.uid(1));
select tests.eq('F40: owner reads own anime + manga rows through the view',
  (select count(*) from public.user_lists where user_id = auth.uid()::text), 2::bigint);
select tests.as_anon();
select tests.eq('F40: anon reads 0 rows through the view (base-table policy is authenticated-only; grants unchanged)',
  (select count(*) from public.user_lists), 0::bigint);
select tests.requires_live('production state of public.user_lists (existence, security_invoker, grants)',
  'whether the deployed view leaks is UNVERIFIED: absent from the baseline capture and 20260206150000 does not replay; run supabase/tests/prerequisites/delete_account_prereqs.sql (user_lists rows) on an approved target');

select tests.reset();
rollback;
