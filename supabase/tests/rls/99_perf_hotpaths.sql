-- 99_perf_hotpaths.sql
-- Prepared 20261101010000_perf_hotpaths.sql + 20261101010100_perf_drop_duplicate_indexes.sql
-- (NOT deployed): similar-titles change gate (a transactional dirty row only on real change;
-- the wrapper's skip/run decision, the lock-busy path and the nightly rolling re-stale),
-- catalog_safety_audit retention rule and batching, CONCURRENTLY matview refresh and the
-- unread matview drop, cron command rewrites, change-aware updated_at on anime/manga only,
-- and the duplicate-index drops with their exactness guard.
-- The real media_similar_seed_state (20260804130000) does not replay into this fixture: when it
-- is absent a minimal stand-in (seed_media_type, seed_media_id, stale) is created inside this
-- test's transaction, and the core is replaced by a counting stub (also rolled back). That
-- proves the WRAPPER's decision logic; it does not run the real core.
-- Not provable in one session: a writer still in flight while the core runs keeps its dirty
-- row (MVCC visibility; argued in the migration's comments).
-- @requires table public.media_relations
-- @requires table public.catalog_safety_audit
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.episodes
\set ON_ERROR_STOP on
\o /dev/null
begin;

-- ---- 1. similar-titles gate: posture -------------------------------------------
select tests.ok('the former driver body is kept as _rebuild_media_similar_titles_core_v1',
  to_regprocedure('public._rebuild_media_similar_titles_core_v1(integer)') is not null);
select tests.ok('rebuild_media_similar_titles(integer) is now the gate wrapper (same signature for the cron)',
  (select prosrc like '%media_similar_graph_dirty%' and prosecdef and proconfig @> array['search_path=public, extensions']
     from pg_proc where oid = 'public.rebuild_media_similar_titles(integer)'::regprocedure));
select tests.ok('wrapper, core, nightly, retention and refresh functions: no EXECUTE for anon/authenticated',
  not has_function_privilege('anon', 'public.rebuild_media_similar_titles(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.rebuild_media_similar_titles(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public._rebuild_media_similar_titles_core_v1(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.media_similar_nightly_v1()', 'execute')
  and not has_function_privilege('anon', 'public.prune_catalog_safety_audit_v1(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.prune_catalog_safety_audit_v1(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.refresh_discover_matviews_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.assert_exact_duplicate_index_v1(text,text)', 'execute'));
select tests.ok('gate and dirty tables: RLS on, a policy each, no API-role grants',
  (select bool_and(relrowsecurity) from pg_class
     where oid in ('public.media_similar_rebuild_gate'::regclass, 'public.media_similar_graph_dirty'::regclass))
  and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'media_similar_rebuild_gate')
  and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'media_similar_graph_dirty')
  and not has_table_privilege('anon', 'public.media_similar_rebuild_gate', 'select')
  and not has_table_privilege('authenticated', 'public.media_similar_rebuild_gate', 'select')
  and not has_table_privilege('anon', 'public.media_similar_graph_dirty', 'select')
  and not has_table_privilege('authenticated', 'public.media_similar_graph_dirty', 'insert'));
select tests.ok('no non-transactional revision sequence is left behind',
  to_regclass('public.media_similar_graph_rev_seq') is null);
select tests.ok('gate starts open (the migration left a dirty row: the first fire runs the core once)',
  exists (select 1 from public.media_similar_graph_dirty));
select tests.eq('the gate triggers use CREATE OR REPLACE-able plain triggers on the hot tables (3 each on anime, manga, media_relations)',
  (select count(*) from pg_trigger where tgname like 'media_similar_graph_rev_%'
     and tgrelid in ('public.anime'::regclass, 'public.manga'::regclass, 'public.media_relations'::regclass)), 9::bigint);

-- ---- 2. similar-titles gate: a dirty row only on real change ----------------------
-- One dirty row per transaction: clear this transaction's row before each probe.
create or replace function pg_temp.clear_dirty() returns void language sql as
  $$ delete from public.media_similar_graph_dirty where xid = pg_current_xact_id() $$;
create or replace function pg_temp.dirty() returns boolean language sql as
  $$ select exists (select 1 from public.media_similar_graph_dirty where xid = pg_current_xact_id()) $$;

select pg_temp.clear_dirty();
insert into public.anime (id, title_romaji, average_score, cover_image_large, is_adult)
values (991002, 'Gate B', 90, null, false);
select tests.eq('insert of a title without cover: no dirty row', pg_temp.dirty(), false);
insert into public.anime (id, title_romaji, average_score, cover_image_large, is_adult)
values (991001, 'Gate A', 60, 'https://img.invalid/a.jpg', false);
select tests.eq('insert of a visible title: dirty (not vacuous)', pg_temp.dirty(), true);
insert into public.anime (id, title_romaji, average_score, cover_image_large, is_adult)
values (991004, 'Gate C', 60, 'https://img.invalid/c.jpg', false);
select tests.eq('one dirty row per transaction, however many changes', (select count(*) from public.media_similar_graph_dirty
  where xid = pg_current_xact_id()), 1::bigint);

select pg_temp.clear_dirty();
update public.anime set popularity = 12345, trending = 9, last_synced_at = now() where id = 991001;
select tests.eq('popularity / trending / sync touch: not dirty', pg_temp.dirty(), false);
update public.anime set average_score = 65 where id = 991001;
select tests.eq('score change below the 70 threshold: not dirty', pg_temp.dirty(), false);
update public.anime set average_score = 75 where id = 991001;
select tests.eq('score crossing 70: dirty', pg_temp.dirty(), true);
select pg_temp.clear_dirty();
update public.anime set average_score = 82 where id = 991001;
select tests.eq('score change above the threshold: not dirty', pg_temp.dirty(), false);
update public.anime set format = 'MOVIE' where id = 991001;
select tests.eq('format change (entry-point rule): dirty', pg_temp.dirty(), true);

select pg_temp.clear_dirty();
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
values ('ANIME', 991001, 'SEQUEL', 'ANIME', 991002);
select tests.eq('new relation: dirty', pg_temp.dirty(), true);
select pg_temp.clear_dirty();
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
values ('ANIME', 991001, 'SEQUEL', 'ANIME', 991002)
on conflict (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
do update set updated_at = now();
select tests.eq('ON CONFLICT DO UPDATE with identical endpoints (hourly import shape): not dirty', pg_temp.dirty(), false);
insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
values ('ANIME', 991001, 'SEQUEL', 'ANIME', 991002)
on conflict do nothing;
select tests.eq('ON CONFLICT DO NOTHING: not dirty', pg_temp.dirty(), false);
delete from public.media_relations where from_media_id = 991001 and to_media_id = 991002;
select tests.eq('relation delete: dirty', pg_temp.dirty(), true);

-- ---- 2b. similar-titles gate: the wrapper's skip/run decision (stub core) ---------
do $$
begin
  if to_regclass('public.media_similar_seed_state') is null then
    create table public.media_similar_seed_state (seed_media_type text not null, seed_media_id integer not null,
      stale boolean not null default false, primary key (seed_media_type, seed_media_id));
  end if;
end $$;
update public.media_similar_seed_state set stale = false where stale;
create table public._core_stub_ctl (ret integer not null, calls integer not null);
insert into public._core_stub_ctl values (5, 0);
create or replace function public._rebuild_media_similar_titles_core_v1(p_batch integer default 100) returns integer
language plpgsql as $$
begin
  update public._core_stub_ctl set calls = calls + 1;
  return (select ret from public._core_stub_ctl);
end $$;
create or replace function pg_temp.calls() returns integer language sql as $$ select calls from public._core_stub_ctl $$;

delete from public.media_similar_graph_dirty;   -- converged state: nothing changed, nothing stale
update public.media_similar_rebuild_gate set last_core_run_at = null where id = 1;
select tests.eq('unchanged and nothing stale: returns 0 WITHOUT calling the core',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '0/0');

insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
values ('ANIME', 991001, 'SEQUEL', 'ANIME', 991004);
select tests.eq('a real media_relations change: the core runs and its result is returned',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '5/1');
select tests.ok('after a successful core run: the seen dirty row is consumed and last_core_run_at is set',
  not exists (select 1 from public.media_similar_graph_dirty)
  and (select last_core_run_at from public.media_similar_rebuild_gate where id = 1) = now());
select tests.eq('next fire with no change: skipped again',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '0/1');

insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id)
values ('ANIME', 991001, 'SEQUEL', 'ANIME', 991004)
on conflict (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
do update set updated_at = now();
select tests.eq('an identical ON CONFLICT DO UPDATE does not reopen the gate',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '0/1');

insert into public.media_similar_seed_state (seed_media_type, seed_media_id, stale) values ('ANIME', 991001, true)
on conflict (seed_media_type, seed_media_id) do update set stale = true;
select tests.eq('a stale seed: the core runs although nothing is dirty',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '5/2');
update public.media_similar_seed_state set stale = false where stale;

delete from public.media_relations where from_media_id = 991001 and to_media_id = 991004;
update public._core_stub_ctl set ret = -1;
update public.media_similar_rebuild_gate set last_core_run_at = null where id = 1;
select tests.eq('lock busy: the core result -1 is returned',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '-1/3');
select tests.ok('lock busy: the dirty row is kept and last_core_run_at is not advanced',
  exists (select 1 from public.media_similar_graph_dirty)
  and (select last_core_run_at from public.media_similar_rebuild_gate where id = 1) is null);
update public._core_stub_ctl set ret = 0;
select tests.eq('next fire after lock busy: the core runs again (0 = ran, nothing to do)',
  public.rebuild_media_similar_titles(100)::text || '/' || pg_temp.calls(), '0/4');
select tests.ok('... and only then is the dirty row consumed', not exists (select 1 from public.media_similar_graph_dirty));

-- nightly: one forced sync (dirty row) + re-stale one seventh of the seeds
delete from public.media_similar_seed_state;
insert into public.media_similar_seed_state (seed_media_type, seed_media_id, stale)
select 'ANIME', g, false from generate_series(1, 14) g;
select public.media_similar_nightly_v1() as nightly \gset
select tests.eq('nightly re-stales exactly the seeds of today''s partition (2 of 14)',
  (:'nightly'::jsonb ->> 'restaled')::int || '/' || (select count(*) from public.media_similar_seed_state where stale)
    || '/' || (select bool_and(seed_media_id % 7 = (:'nightly'::jsonb ->> 'partition')::int) from public.media_similar_seed_state where stale),
  '2/2/true');
select tests.ok('nightly writes one dirty row (the forced universe/franchise sync)', pg_temp.dirty());

-- ---- 3. cron command rewrites and the unread matview ----------------------------
select tests.eq('kuro-refresh-matviews now calls refresh_discover_matviews_v1()',
  (select btrim(command) from cron.job where jobname = 'kuro-refresh-matviews'), 'select public.refresh_discover_matviews_v1();');
select tests.eq('kuro-refresh-matviews keeps its 01:30 schedule',
  (select schedule from cron.job where jobname = 'kuro-refresh-matviews'), '30 1 * * *');
select tests.eq('no cron job still runs the blanket re-stale command',
  (select count(*) from cron.job where command ilike '%set stale = true where stale = false%'), 0::bigint);
select tests.ok('mv_anime_current_season is dropped', to_regclass('public.mv_anime_current_season') is null);
select tests.eq('the six read matviews remain', (select count(*) from pg_matviews where schemaname = 'public'
  and matviewname in ('mv_anime_trending','mv_anime_top_rated','mv_anime_newly_added','mv_manga_trending','mv_manga_top_rated','mv_manga_newly_added')), 6::bigint);
select tests.eq('refresh_discover_matviews_v1 refreshes all six (CONCURRENTLY works inside the job transaction)',
  jsonb_array_length(public.refresh_discover_matviews_v1() -> 'refreshed'), 6);

-- ---- 4. catalog_safety_audit retention ------------------------------------------
-- media A: 1 recent + 5 old rows -> the 3 oldest are outside the newest 3 AND > 90 days
-- media B: 2 old rows -> both inside the newest 3, kept
-- media C: 5 recent rows -> all younger than 90 days, kept
insert into public.catalog_safety_audit (media_type, media_id, title, decision_state, scanned_at)
select 'ANIME', 880001, 'A', 'safe', now() - interval '1 day' union all
select 'ANIME', 880001, 'A', 'safe', now() - (interval '100 days' + g * interval '1 day') from generate_series(1, 5) g union all
select 'MANGA', 880002, 'B', 'safe', now() - (interval '200 days' + g * interval '1 day') from generate_series(1, 2) g union all
select 'ANIME', 880003, 'C', 'safe', now() - g * interval '1 day' from generate_series(1, 5) g;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select public.prune_catalog_safety_audit_v1(2) as p1 \gset
select public.prune_catalog_safety_audit_v1(2) as p2 \gset
select tests.reset();
select tests.eq('first batch deletes up to the limit and reports more', :'p1'::jsonb, '{"deleted":2,"has_more":true}'::jsonb);
select tests.eq('second batch finishes', :'p2'::jsonb, '{"deleted":1,"has_more":false}'::jsonb);
select tests.eq('A keeps its newest 3 (1 recent + 2 old)', (select count(*) from public.catalog_safety_audit where media_id = 880001), 3::bigint);
select tests.eq('A: the oldest rows were the ones removed',
  (select min(scanned_at) > now() - interval '103 days' from public.catalog_safety_audit where media_id = 880001)::text, 'true');
select tests.eq('B (old but within newest 3) kept', (select count(*) from public.catalog_safety_audit where media_id = 880002), 2::bigint);
select tests.eq('C (recent) kept', (select count(*) from public.catalog_safety_audit where media_id = 880003), 5::bigint);
select tests.as_user(tests.make_user(991));
select tests.denied('authenticated cannot prune', $q$select public.prune_catalog_safety_audit_v1(10)$q$);
select tests.reset();

-- ---- 5. change-aware updated_at -------------------------------------------------
insert into public.manga (id, title_romaji, updated_at, last_synced_at) values (991101, 'Touch Manga', '2020-01-01', '2020-01-01');
insert into public.anime (id, title_romaji, updated_at) values (991003, 'Touch Anime', '2020-01-01');
update public.anime set last_synced_at = now() where id = 991003;
update public.manga set last_synced_at = now() where id = 991101;
select tests.eq('anime: a last_synced_at-only touch keeps updated_at',
  (select updated_at from public.anime where id = 991003), '2020-01-01'::timestamptz);
select tests.eq('manga: a last_synced_at-only touch keeps updated_at',
  (select updated_at from public.manga where id = 991101), '2020-01-01'::timestamptz);
update public.anime set title_english = 'Touch', last_synced_at = now() where id = 991003;
update public.manga set description = 'new text' where id = 991101;
select tests.eq('anime: a real change bumps updated_at', (select updated_at from public.anime where id = 991003), now());
select tests.eq('manga: a real change (incl. the normalized-description trigger) bumps updated_at',
  (select updated_at from public.manga where id = 991101), now());
select tests.eq('triggers keep their names and point at the new function on anime/manga only',
  (select string_agg(tgrelid::regclass::text || ':' || tgname || ':' || tgfoid::regproc::text, ',' order by tgrelid::regclass::text)
     from pg_trigger where tgname in ('update_anime_updated_at', 'update_manga_updated_at', 'update_episodes_updated_at')),
  'anime:update_anime_updated_at:update_catalog_updated_at_v1,episodes:update_episodes_updated_at:update_updated_at_column,manga:update_manga_updated_at:update_catalog_updated_at_v1');

-- ---- 6. duplicate indexes (20261101010100) --------------------------------------
select tests.eq('all 22 exact duplicates are gone',
  (select count(*) from unnest(array['idx_anime_id','idx_manga_id','idx_characters_id','idx_staff_id','idx_authors_id','idx_studios_id',
     'idx_tags_id','idx_volumes_id','idx_anime_anilist_id','idx_manga_anilist_id','idx_characters_anilist_id','idx_staff_anilist_id',
     'idx_authors_anilist_id','idx_studios_anilist_id','idx_tags_anilist_id','idx_anime_mal_id','idx_manga_mal_id','idx_characters_mal_id',
     'idx_staff_mal_id','idx_authors_mal_id','idx_studios_mal_id','idx_tags_mal_id']) n where to_regclass('public.' || n) is not null), 0::bigint);
select tests.eq('every survivor (pkey / unique key) is still there and valid',
  (select count(*) from unnest(array['anime_pkey','manga_pkey','characters_pkey','staff_pkey','authors_pkey','studios_pkey','tags_pkey',
     'volumes_pkey','anime_anilist_id_key','manga_anilist_id_key','characters_anilist_id_key','staff_anilist_id_key','authors_anilist_id_key',
     'studios_anilist_id_key','tags_anilist_id_key','anime_mal_id_key','manga_mal_id_key','characters_mal_id_key','staff_mal_id_key',
     'authors_mal_id_key','studios_mal_id_key','tags_mal_id_key']) n
     join pg_index i on i.indexrelid = to_regclass('public.' || n) where i.indisvalid and (i.indisunique or i.indisprimary)), 22::bigint);
select tests.ok('idx_catalog_safety_audit_state dropped, idx_catalog_safety_audit_lookup kept',
  to_regclass('public.idx_catalog_safety_audit_state') is null and to_regclass('public.idx_catalog_safety_audit_lookup') is not null);
select tests.ok('prefix-only / unproven candidates are NOT dropped (idx_anime_status, idx_external_links_media, idx_anime_popularity)',
  to_regclass('public.idx_anime_status') is not null and to_regclass('public.idx_external_links_media') is not null
  and to_regclass('public.idx_anime_popularity') is not null);

-- the guard itself, on a scratch table
create table public._dup_probe (id integer primary key, x integer unique, y integer);
create index _dup_probe_id_plain on public._dup_probe (id);
create index _dup_probe_id_desc on public._dup_probe (id desc);
create index _dup_probe_x_partial on public._dup_probe (x) where x > 0;
create index _dup_probe_y on public._dup_probe (y);
create unique index _dup_probe_id_unique on public._dup_probe (id);
select tests.eq('guard: plain copy of the pkey is an exact duplicate',
  public.assert_exact_duplicate_index_v1('public._dup_probe_id_plain', 'public._dup_probe_pkey'), true);
select tests.eq('guard: an already-dropped index is skipped (false)',
  public.assert_exact_duplicate_index_v1('public._dup_probe_gone', 'public._dup_probe_pkey'), false);
select tests.raises('guard: different sort order is not a duplicate',
  $q$select public.assert_exact_duplicate_index_v1('public._dup_probe_id_desc', 'public._dup_probe_pkey')$q$, 'NOT_EXACT_DUPLICATE:%');
select tests.raises('guard: a partial index is not a duplicate',
  $q$select public.assert_exact_duplicate_index_v1('public._dup_probe_x_partial', 'public._dup_probe_x_key')$q$, 'NOT_EXACT_DUPLICATE:%');
select tests.raises('guard: survivor must be unique/primary',
  $q$select public.assert_exact_duplicate_index_v1('public._dup_probe_id_plain', 'public._dup_probe_y')$q$, 'NOT_EXACT_DUPLICATE:%');
select tests.raises('guard: a unique index is never treated as the droppable copy',
  $q$select public.assert_exact_duplicate_index_v1('public._dup_probe_id_unique', 'public._dup_probe_pkey')$q$, 'NOT_EXACT_DUPLICATE:%');
select tests.raises('guard: a missing survivor refuses',
  $q$select public.assert_exact_duplicate_index_v1('public._dup_probe_id_plain', 'public._dup_probe_nope')$q$, 'NOT_EXACT_DUPLICATE:%');

select tests.reset();
rollback;
