-- Proves the shared 2,000-title library fixture and its plan-uses-index helper (F3.2).
-- W9's plan checks (107/108) reuse both. Disposable local fixture only, never hosted.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;
\ir ../fixtures/library_2000.sql

select tests.make_user(1);

select tests.eq('2,000 rows for the user', pg_temp.load_library_2000(tests.uid(1)), 2000);

select tests.eq('1,400 anime and 600 manga rows belong to the user',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(1)::text) * 1000
  + (select count(*) from public.manga_user_lists where user_id = tests.uid(1)::text),
  1400::bigint * 1000 + 600);

select tests.eq('noise users hold their own rows',
  (select count(*) from public.anime_user_lists where user_id <> tests.uid(1)::text)
  + (select count(*) from public.manga_user_lists where user_id <> tests.uid(1)::text),
  100000::bigint);

-- Index names pinned from the fixture (\di public.anime_user_lists*): the planner serves an
-- owner-scoped list read from idx_anime_user_lists_user_id (single column, cheaper than the
-- composite unique key), and a (user, title) point lookup from the unique key.
select tests.ok('an owner-scoped list read uses idx_anime_user_lists_user_id',
  pg_temp.plan_uses_index(
    format('select anime_id from public.anime_user_lists where user_id=%L', tests.uid(1)::text),
    'idx_anime_user_lists_user_id'));

select tests.ok('a (user_id, anime_id) point lookup uses the unique index',
  pg_temp.plan_uses_index(
    format('select id from public.anime_user_lists where user_id=%L and anime_id=9100007', tests.uid(1)::text),
    'anime_user_lists_user_id_anime_id_key'));

-- Negative controls, permanent parts of this test (rolled back with the transaction): once an
-- index is gone the same query must not be reported as using it, so the positive checks mean something.
drop index public.idx_anime_user_lists_user_id;
alter table public.anime_user_lists drop constraint anime_user_lists_user_id_anime_id_key;

select tests.ok('without idx_anime_user_lists_user_id the owner-scoped read is not reported as using it',
  not pg_temp.plan_uses_index(
    format('select anime_id from public.anime_user_lists where user_id=%L', tests.uid(1)::text),
    'idx_anime_user_lists_user_id'));

select tests.ok('without the unique index the point lookup is not reported as using it',
  not pg_temp.plan_uses_index(
    format('select id from public.anime_user_lists where user_id=%L and anime_id=9100007', tests.uid(1)::text),
    'anime_user_lists_user_id_anime_id_key'));

rollback;
