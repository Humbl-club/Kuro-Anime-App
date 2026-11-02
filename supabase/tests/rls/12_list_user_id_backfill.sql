-- 12_list_user_id_backfill.sql  --  F16 historical rows (opt-in repair, never auto-applied)
--
-- Subject under test: supabase/prepared-migrations/opt-in/20261005180100_list_user_id_lowercase_backfill.sql
-- (applied here with \ir inside this rolled-back transaction; it is NOT part of the fixture
-- replay). Historical rows are constructed as the superuser with the canonical-case
-- trigger disabled for the insert (that is how such rows could only have been written).
--   * default mode refuses when a collision exists and changes nothing
--   * explicit keep_newest mode: no duplicate and no surviving non-canonical row; per
--     (user, title) the most recently updated row wins; rows of other users untouched
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3);
insert into public.anime (id) values (121212), (121213);
insert into public.manga (id) values (121212);

alter table public.anime_user_lists disable trigger list_user_id_canonical_case;
alter table public.manga_user_lists disable trigger list_user_id_canonical_case;
-- user 1: only UPPER-case rows (no collision)
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (upper(tests.uid(1)::text), 121212, 'WATCHING', 4);
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values (upper(tests.uid(1)::text), 121212, 'READING', 9);
-- user 2: the same title in both spellings (collision); the UPPER row is newer
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, updated_at) values (tests.uid(2)::text, 121212, 'PLANNING', 0, now() - interval '2 days');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, updated_at) values (upper(tests.uid(2)::text), 121212, 'COMPLETED', 12, now() - interval '1 day');
insert into public.anime_user_lists (user_id, anime_id, list_type) values (upper(tests.uid(2)::text), 121213, 'PLANNING');
alter table public.anime_user_lists enable trigger list_user_id_canonical_case;
alter table public.manga_user_lists enable trigger list_user_id_canonical_case;
-- user 3: canonical rows only (must be untouched)
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(3)::text, 121212, 'DROPPED', 2);

select tests.eq('setup: 4 non-canonical rows across 2 users',
  (select count(*) from public.anime_user_lists where user_id <> lower(user_id))
  + (select count(*) from public.manga_user_lists where user_id <> lower(user_id)), 4::bigint);
select tests.as_user(tests.uid(1));
select tests.eq('setup (the defect): the owner cannot see their own UPPER-case rows under the captured RLS',
  (select count(*) from public.anime_user_lists), 0::bigint);
select tests.reset();

-- ---- default mode: a collision makes the script refuse and change nothing ----------
savepoint before_default;
-- the repair is one DO statement, so its refusal is the only error (kept in LAST_ERROR_MESSAGE)
\set ON_ERROR_STOP off
\ir ../../prepared-migrations/opt-in/20261005180100_list_user_id_lowercase_backfill.sql
\set ON_ERROR_STOP on
rollback to savepoint before_default;
select tests.ok('default mode refuses on a collision (COLLISIONS_PRESENT)', :'LAST_ERROR_MESSAGE' like 'COLLISIONS_PRESENT:%');
select tests.eq('default mode: refusal left all 4 non-canonical rows unchanged',
  (select count(*) from public.anime_user_lists where user_id <> lower(user_id))
  + (select count(*) from public.manga_user_lists where user_id <> lower(user_id)), 4::bigint);

-- ---- explicit keep_newest ------------------------------------------------------------
\set resolve_collisions keep_newest
\ir ../../prepared-migrations/opt-in/20261005180100_list_user_id_lowercase_backfill.sql
\unset resolve_collisions
select tests.eq('keep_newest: no non-canonical row remains',
  (select count(*) from public.anime_user_lists where user_id <> lower(user_id))
  + (select count(*) from public.manga_user_lists where user_id <> lower(user_id)), 0::bigint);
select tests.eq('keep_newest: no duplicate (user, title) row',
  (select count(*) from (select user_id, anime_id from public.anime_user_lists group by 1, 2 having count(*) > 1) d), 0::bigint);
select tests.eq('keep_newest: the newer row of the collision won (COMPLETED/12)',
  (select list_type || '/' || progress from public.anime_user_lists where user_id = tests.uid(2)::text and anime_id = 121212), 'COMPLETED/12');
select tests.eq('keep_newest: a non-colliding UPPER row is kept and normalized',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(2)::text and anime_id = 121213), 1::bigint);
select tests.eq('keep_newest: user 3''s canonical row untouched', (select progress from public.anime_user_lists where user_id = tests.uid(3)::text), 2);
select tests.as_user(tests.uid(1));
select tests.eq('F16 closed for history: the owner now sees their own anime + manga rows',
  (select count(*) from public.anime_user_lists) + (select count(*) from public.manga_user_lists), 2::bigint);
select tests.as_user(tests.uid(2));
select tests.eq('...and another user still sees nothing of user 1', (select count(*) from public.anime_user_lists where user_id = tests.uid(1)::text), 0::bigint);

select tests.reset();
rollback;
