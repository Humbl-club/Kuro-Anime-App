-- W10 Up next: signed-out callers and account scope. Disposable local fixture only, never hosted.
-- @requires table public.media_relations
-- @requires table public.series_entry_spans
-- @requires table public.taste_signal_events
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;

select tests.make_user(1093);
select tests.make_user(1094);
set local session_replication_role = replica;
insert into public.anime (id, title_romaji, format, status, genres, is_adult)
select 1093000 + n, 'Scope ' || n, 'TV', 'FINISHED', array['Drama'], false from generate_series(30, 33) n;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values
  (tests.uid(1093)::text, 1093030, 'COMPLETED', 0),
  (tests.uid(1094)::text, 1093032, 'COMPLETED', 0);
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id) values
  ('ANIME', 1093030, 'SEQUEL', 'ANIME', 1093031),
  ('ANIME', 1093032, 'SEQUEL', 'ANIME', 1093033);
set local session_replication_role = origin;

select tests.as_anon();
select tests.denied('anon cannot execute library_up_next_v1 (signed-out caller gets nothing)',
  $$select * from public.library_up_next_v1('anime', 30)$$);
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
select tests.eq('an authenticated token without sub returns 0 rows',
  (select count(*) from public.library_up_next_v1('anime', 30)), 0::bigint);
select tests.as_user(tests.uid(1093));
select tests.ok('the account comes from the token: 1093 sees 1093031 and never 1094''s 1093033',
  exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1093031)
  and not exists (select 1 from public.library_up_next_v1('anime', 30) where media_id = 1093033));
select tests.ok('the RPC takes no user id parameter',
  (select pronargs = 2 and not (coalesce(proargnames, '{}') @> array['p_user_id']) from pg_proc
    where oid = 'public.library_up_next_v1(text,integer)'::regprocedure));
select tests.reset();

rollback;
