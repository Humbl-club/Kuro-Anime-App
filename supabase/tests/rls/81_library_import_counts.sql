-- 81_library_import_counts.sql
-- Structured import counts: empty, one, fifty, score 0, private notes, omission, local edit.
-- A small-table EXPLAIN is recorded only as a smoke check. It is not a 100k/1M/10M capacity proof.
-- @requires table public.anime
-- @requires table public.anime_user_lists
-- @requires table public.title_comments
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(81);
insert into public.anime (id, title_romaji, mal_id)
select 771000 + n, 'Import ' || n, 771000 + n
from generate_series(1, 50) as n;

select tests.as_user(tests.uid(81));
select (public.start_library_import_v1('myanimelist','export','anime','idem-empty-81','abcdef0123456789') ->> 'job_id') as empty_job \gset
select public.apply_import_chunk_v1(:'empty_job'::uuid, '[]'::jsonb) as empty_chunk \gset
select tests.eq('zero items add nothing', (:'empty_chunk'::jsonb ->> 'added')::integer, 0);
select public.finish_library_import_v1(:'empty_job'::uuid, true);

select (public.start_library_import_v1('myanimelist','export','anime','idem-one-81','abcdef0123456789') ->> 'job_id') as one_job \gset
select public.apply_import_chunk_v1(:'one_job'::uuid, jsonb_build_array(jsonb_build_object(
  'medium', 'anime', 'external_id', '771001', 'status', 'watching', 'progress', 1,
  'score_raw', '0', 'notes', 'secret', 'private', true
))) as zero_score \gset
select tests.eq('one private row is added', (:'zero_score'::jsonb ->> 'added')::integer, 1);
select tests.eq('score 0 stays unset',
  (select score_raw is null from public.anime_user_lists where anime_id = 771001), true);
select tests.eq('private note is retained on the owner-only list',
  (select notes from public.anime_user_lists where anime_id = 771001), 'secret');
select tests.eq('private note is not a club comment',
  (select count(*) from public.title_comments where media_id = 771001), 0::bigint);

select tests.raises('changed terminal item payload cannot masquerade as retry',
 format($q$select public.apply_import_chunk_v1(%L::uuid,'[{"medium":"anime","external_id":"771001","status":"completed","progress":4,"score_raw":"9"}]'::jsonb)$q$,:'one_job'),
 '%IDEMPOTENCY_CONFLICT%');
select tests.eq('rejected replay leaves the committed first item unchanged',
  (select progress from public.anime_user_lists where anime_id = 771001),1);

insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
values (tests.uid(81)::text, 771002, 'WATCHING', 6);
select public.apply_import_chunk_v1(:'one_job'::uuid, jsonb_build_array(jsonb_build_object(
  'medium', 'anime', 'external_id', '771003', 'status', 'planning', 'progress', 0
))) as omission \gset
select tests.eq('a later source omission does not delete the local title',
  (select progress from public.anime_user_lists where anime_id = 771002), 6);

-- A same-transaction clock cannot prove "newer". The two-session proof is
-- 93_series_fence_races.sql: the local edit holds the row, then the chunk conflicts.
select public.finish_library_import_v1(:'one_job'::uuid, true);

select (public.start_library_import_v1('myanimelist','export','anime','idem-fifty-81','abcdef0123456789') ->> 'job_id') as fifty_job \gset
select public.apply_import_chunk_v1(:'fifty_job'::uuid, (
  select jsonb_agg(jsonb_build_object(
    'medium', 'anime', 'external_id', (771000 + n)::text, 'status', 'watching', 'progress', 1
  ))
  from generate_series(1, 50) as n
)) as fifty \gset
select tests.eq('fifty items are counted',
  ((:'fifty'::jsonb ->> 'added')::integer + (:'fifty'::jsonb ->> 'updated')::integer), 50);

\o docs/handoffs/2026-10-07-home-series-evidence/db/explain-small-fixture.txt
explain select public.home_bundle_v1('anime');
explain select public.series_detail_bundle_v1('anime', 771001);
explain select public.collection_series_page_v1('anime');
\o /dev/null

select tests.reset();
rollback;
