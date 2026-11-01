-- 20261101010000_perf_hotpaths.sql
-- PREPARED, NOT DEPLOYED (2026-11-01 overnight production pass, lane 1 / SQL).
-- Deploying needs explicit owner approval. It changes the commands of two EXISTING cron jobs
-- (realm-similar-nightly, kuro-refresh-matviews) when they exist; it schedules nothing new.
-- Evidence: docs/overnight-2026-11-01/understand/schema.md sections 2, 5, 9 (P0-1, P0-2,
-- P0-3, P0-5). The duplicate-index drops (P0-4) and the unused audit-state index drop need
-- DROP INDEX CONCURRENTLY, which cannot run in a transaction: they are in the separate file
-- 20261101010100_perf_drop_duplicate_indexes.sql (apply with psql, not in a transaction).
--
-- 1. Similar-titles driver gate (P0-1; 97% of DB time). The existing
--    rebuild_media_similar_titles(integer) is RENAMED to _rebuild_media_similar_titles_core_v1
--    (body untouched). A new rebuild_media_similar_titles(integer) with the same signature
--    (the 5-minute cron keeps calling it unchanged) returns 0 immediately, without the global
--    franchise rebuild, when NOTHING it depends on changed and no seed is stale. "Changed" is
--    a sequence bumped by row-level triggers that fire only on real change:
--      media_relations       insert, delete, update of the endpoints
--      franchise_component_cut  any write (when the table exists)
--      anime / manga         insert of a visible title (non-adult with cover), delete, and
--                            updates that move the seed universe or entry points (crossing
--                            average_score 70, is_adult, cover null-ness, format, start year)
--    ON CONFLICT DO UPDATE with identical endpoints therefore does not trip the gate.
--    built_graph_rev advances only after a core run that returned >= 0 (-1 = lock busy).
-- 2. The nightly blanket re-stale (`update media_similar_seed_state set stale = true`,
--    ~76 heavy fires a day) is replaced by media_similar_nightly_v1(): one forced gate bump
--    (a single universe/franchise sync as a safety net) plus re-staling one seventh of the
--    seeds (seed_media_id % 7 = ISO weekday % 7). FRESHNESS CHANGE: each seed's similar list
--    is now rebuilt at least weekly (was nightly); realm/tag refreshes reach a seed within
--    7 days. Owner may revert by rescheduling the old command.
-- 3. catalog_safety_audit retention (P0-2): prune_catalog_safety_audit_v1(limit) deletes a row
--    only when it is outside the newest 3 rows of its media AND older than 90 days, in
--    bounded batches. NOT scheduled; suggested (owner action):
--      select cron.schedule('catalog-safety-audit-prune', '20 3 * * *',
--        $$select public.prune_catalog_safety_audit_v1(20000)$$);
--    After the first purge: VACUUM (ANALYZE) public.catalog_safety_audit.
-- 4. Discover matviews (P0-5): refresh_discover_matviews_v1() refreshes the six read
--    matviews CONCURRENTLY (unique id indexes exist since the baseline) so readers (iOS
--    reads mv_anime_trending directly) are never blocked; kuro-refresh-matviews calls it.
--    mv_anime_current_season has no reader in functions, views, edge code, scripts or iOS
--    (git history included): dropped WITHOUT cascade, so a hidden dependent fails loudly.
-- 5. Change-aware updated_at for anime/manga (P0-3 step 1): the triggers keep their names
--    (update_anime_updated_at / update_manga_updated_at, so BEFORE-trigger order is
--    unchanged) and point at update_catalog_updated_at_v1(), which leaves updated_at alone
--    when only last_synced_at (and/or updated_at) changed. The shared
--    update_updated_at_column() used by the other tables is not changed.
--    Not in this file (open): synopsis queue index rebuild without updated_at, fillfactor.
-- 6. assert_exact_duplicate_index_v1(dup, survivor): guard used by 20261101010100.
--
-- Rollback: rename the core back over the wrapper, drop the triggers/sequence/gate table and
-- the new functions, reschedule the two cron commands from 20260804130000 / the baseline,
-- recreate mv_anime_current_season from the baseline, repoint the two triggers to
-- update_updated_at_column().

begin;

set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. Similar-titles gate
-- ---------------------------------------------------------------------------
create sequence if not exists public.media_similar_graph_rev_seq;
revoke all on sequence public.media_similar_graph_rev_seq from public, anon, authenticated;

create table if not exists public.media_similar_rebuild_gate (
  id smallint primary key default 1 check (id = 1),
  built_graph_rev bigint not null default -1,
  last_core_run_at timestamptz
);
insert into public.media_similar_rebuild_gate (id) values (1) on conflict (id) do nothing;
alter table public.media_similar_rebuild_gate enable row level security;
revoke all on public.media_similar_rebuild_gate from public, anon, authenticated;
grant select, update on public.media_similar_rebuild_gate to service_role;
drop policy if exists media_similar_rebuild_gate_service_only on public.media_similar_rebuild_gate;
create policy media_similar_rebuild_gate_service_only on public.media_similar_rebuild_gate
  for all to service_role using (true) with check (true);
comment on table public.media_similar_rebuild_gate is
  '20261101010000: single row. built_graph_rev = media_similar_graph_rev_seq value the last successful core run of rebuild_media_similar_titles started from. Service role / definer functions only.';

create or replace function public.bump_media_similar_graph_rev_v1()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform nextval('public.media_similar_graph_rev_seq');
  return null;
end;
$$;
revoke all on function public.bump_media_similar_graph_rev_v1() from public, anon, authenticated;

drop trigger if exists media_similar_graph_rev_ins on public.media_relations;
create trigger media_similar_graph_rev_ins after insert on public.media_relations
  for each row execute function public.bump_media_similar_graph_rev_v1();
drop trigger if exists media_similar_graph_rev_upd on public.media_relations;
create trigger media_similar_graph_rev_upd after update on public.media_relations
  for each row
  when ((old.from_media_type, old.from_media_id, old.to_media_type, old.to_media_id)
        is distinct from (new.from_media_type, new.from_media_id, new.to_media_type, new.to_media_id))
  execute function public.bump_media_similar_graph_rev_v1();
drop trigger if exists media_similar_graph_rev_del on public.media_relations;
create trigger media_similar_graph_rev_del after delete on public.media_relations
  for each row execute function public.bump_media_similar_graph_rev_v1();

do $$
declare t text;
begin
  if to_regclass('public.franchise_component_cut') is not null then
    execute 'drop trigger if exists media_similar_graph_rev_any on public.franchise_component_cut';
    execute 'create trigger media_similar_graph_rev_any after insert or update or delete on public.franchise_component_cut
               for each row execute function public.bump_media_similar_graph_rev_v1()';
  else
    raise notice 'franchise_component_cut absent here: its gate trigger is not created';
  end if;
  foreach t in array array['anime', 'manga'] loop
    execute format('drop trigger if exists media_similar_graph_rev_ins on public.%I', t);
    execute format($f$create trigger media_similar_graph_rev_ins after insert on public.%I
      for each row when (coalesce(new.is_adult, false) = false and new.cover_image_large is not null)
      execute function public.bump_media_similar_graph_rev_v1()$f$, t);
    execute format('drop trigger if exists media_similar_graph_rev_upd on public.%I', t);
    execute format($f$create trigger media_similar_graph_rev_upd
      after update of average_score, is_adult, cover_image_large, format, start_date_year on public.%I
      for each row when (
        ((coalesce(old.average_score, 0) >= 70) is distinct from (coalesce(new.average_score, 0) >= 70))
        or (coalesce(old.is_adult, false) is distinct from coalesce(new.is_adult, false))
        or ((old.cover_image_large is null) is distinct from (new.cover_image_large is null))
        or (old.format is distinct from new.format)
        or (old.start_date_year is distinct from new.start_date_year))
      execute function public.bump_media_similar_graph_rev_v1()$f$, t);
    execute format('drop trigger if exists media_similar_graph_rev_del on public.%I', t);
    execute format($f$create trigger media_similar_graph_rev_del after delete on public.%I
      for each row execute function public.bump_media_similar_graph_rev_v1()$f$, t);
  end loop;
end $$;

-- Rename the existing driver (body untouched) to the core, once.
do $$
begin
  if to_regprocedure('public._rebuild_media_similar_titles_core_v1(integer)') is null
     and to_regprocedure('public.rebuild_media_similar_titles(integer)') is not null then
    alter function public.rebuild_media_similar_titles(integer) rename to _rebuild_media_similar_titles_core_v1;
  end if;
  if to_regprocedure('public._rebuild_media_similar_titles_core_v1(integer)') is not null then
    revoke all on function public._rebuild_media_similar_titles_core_v1(integer) from public, anon, authenticated;
    grant execute on function public._rebuild_media_similar_titles_core_v1(integer) to service_role;
    comment on function public._rebuild_media_similar_titles_core_v1(integer) is
      'Former rebuild_media_similar_titles body (20260807010000), renamed by 20261101010000. Called only through the gated rebuild_media_similar_titles(integer).';
  else
    raise notice 'rebuild_media_similar_titles(integer) absent here: the gate wrapper has no core to call';
  end if;
end $$;

create or replace function public.rebuild_media_similar_titles(p_batch integer default 100)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_last bigint;
  v_called boolean;
  v_rev bigint;
  v_built bigint;
  v_result integer;
begin
  select last_value, is_called into v_last, v_called from public.media_similar_graph_rev_seq;
  v_rev := case when v_called then v_last else 0 end;
  select built_graph_rev into v_built from public.media_similar_rebuild_gate where id = 1;

  -- Nothing changed since the last successful core run and nothing is stale: the converged
  -- state is current. Skip the global franchise rebuild entirely.
  if v_built is not distinct from v_rev
     and not exists (select 1 from public.media_similar_seed_state where stale) then
    return 0;
  end if;

  v_result := public._rebuild_media_similar_titles_core_v1(p_batch);
  if v_result >= 0 then
    -- v_rev was read BEFORE the core ran: a change committed meanwhile keeps the gate open.
    update public.media_similar_rebuild_gate
       set built_graph_rev = v_rev, last_core_run_at = now()
     where id = 1;
  end if;
  return v_result;
end;
$$;
revoke all on function public.rebuild_media_similar_titles(integer) from public, anon, authenticated;
grant execute on function public.rebuild_media_similar_titles(integer) to service_role;
comment on function public.rebuild_media_similar_titles(integer) is
  '20261101010000 gate: returns 0 without work when media_similar_graph_rev_seq equals media_similar_rebuild_gate.built_graph_rev and no seed is stale; otherwise runs _rebuild_media_similar_titles_core_v1(p_batch) and records the revision it started from (only when the core returned >= 0).';

create or replace function public.media_similar_nightly_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_part integer := extract(isodow from now())::integer % 7;
  v_n bigint;
begin
  perform nextval('public.media_similar_graph_rev_seq');  -- one safety-net universe/franchise sync
  update public.media_similar_seed_state
     set stale = true
   where stale = false and (seed_media_id % 7) = v_part;
  get diagnostics v_n = row_count;
  return jsonb_build_object('restaled', v_n, 'partition', v_part);
end;
$$;
revoke all on function public.media_similar_nightly_v1() from public, anon, authenticated;
grant execute on function public.media_similar_nightly_v1() to service_role;

-- ---------------------------------------------------------------------------
-- 2. catalog_safety_audit retention (not scheduled)
-- ---------------------------------------------------------------------------
create or replace function public.prune_catalog_safety_audit_v1(p_limit integer default 20000)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_limit integer := least(100000, greatest(1, coalesce(p_limit, 20000)));
  v_n bigint;
begin
  with doomed as (
    select a.id
    from public.catalog_safety_audit a
    where a.scanned_at < now() - interval '90 days'
      and (select count(*) from (
             select 1 from public.catalog_safety_audit b
             where b.media_type = a.media_type and b.media_id = a.media_id
               and (b.scanned_at, b.id) > (a.scanned_at, a.id)
             limit 3) newer) >= 3
    limit v_limit
  )
  delete from public.catalog_safety_audit t using doomed d where t.id = d.id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('deleted', v_n, 'has_more', v_n = v_limit);
end;
$$;
revoke all on function public.prune_catalog_safety_audit_v1(integer) from public, anon, authenticated;
grant execute on function public.prune_catalog_safety_audit_v1(integer) to service_role;
comment on function public.prune_catalog_safety_audit_v1(integer) is
  '20261101010000 retention: deletes up to p_limit audit rows that are BOTH outside the newest 3 of their (media_type, media_id) AND older than 90 days. Returns {deleted, has_more}. Uses idx_catalog_safety_audit_lookup.';

-- ---------------------------------------------------------------------------
-- 3. Discover matviews: CONCURRENTLY refresh; drop the unread matview
-- ---------------------------------------------------------------------------
create or replace function public.refresh_discover_matviews_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v text;
  v_done text[] := '{}';
begin
  foreach v in array array['mv_anime_trending', 'mv_anime_top_rated', 'mv_anime_newly_added',
                           'mv_manga_trending', 'mv_manga_top_rated', 'mv_manga_newly_added'] loop
    if to_regclass('public.' || v) is null then
      continue;
    end if;
    if (select m.ispopulated from pg_matviews m where m.schemaname = 'public' and m.matviewname = v) then
      execute format('refresh materialized view concurrently public.%I', v);
    else
      execute format('refresh materialized view public.%I', v);  -- first fill cannot be concurrent
    end if;
    v_done := v_done || v;
  end loop;
  return jsonb_build_object('refreshed', to_jsonb(v_done));
end;
$$;
revoke all on function public.refresh_discover_matviews_v1() from public, anon, authenticated;
grant execute on function public.refresh_discover_matviews_v1() to service_role;

-- ---------------------------------------------------------------------------
-- 4. Cron command changes for EXISTING jobs only (pg_cron present and job present)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and to_regnamespace('cron') is not null then
    if exists (select 1 from cron.job where jobname = 'kuro-refresh-matviews') then
      perform cron.unschedule(jobid) from cron.job where jobname = 'kuro-refresh-matviews';
      perform cron.schedule('kuro-refresh-matviews', '30 1 * * *',
        $cmd$select public.refresh_discover_matviews_v1();$cmd$);
    end if;
    if exists (select 1 from cron.job where jobname = 'realm-similar-nightly') then
      perform cron.unschedule(jobid) from cron.job where jobname = 'realm-similar-nightly';
      perform cron.schedule('realm-similar-nightly', '10 5 * * *',
        $cmd$select public.media_similar_nightly_v1();$cmd$);
    else
      raise notice 'cron job realm-similar-nightly absent here: nothing rescheduled';
    end if;
  end if;
end $$;

drop materialized view if exists public.mv_anime_current_season;

-- ---------------------------------------------------------------------------
-- 5. Change-aware updated_at on anime / manga
-- ---------------------------------------------------------------------------
create or replace function public.update_catalog_updated_at_v1()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if (to_jsonb(new) - 'updated_at' - 'last_synced_at') is distinct from (to_jsonb(old) - 'updated_at' - 'last_synced_at') then
    new.updated_at := now();
  else
    -- a sync touch only: keep updated_at, so the synopsis queue indexes (which contain
    -- updated_at) are not rewritten and the update can stay HOT
    new.updated_at := old.updated_at;
  end if;
  return new;
end;
$$;
revoke all on function public.update_catalog_updated_at_v1() from public, anon, authenticated;

drop trigger if exists update_anime_updated_at on public.anime;
create trigger update_anime_updated_at before update on public.anime
  for each row execute function public.update_catalog_updated_at_v1();
drop trigger if exists update_manga_updated_at on public.manga;
create trigger update_manga_updated_at before update on public.manga
  for each row execute function public.update_catalog_updated_at_v1();

-- ---------------------------------------------------------------------------
-- 6. Guard used by 20261101010100 before each DROP INDEX CONCURRENTLY
--    Returns false when p_duplicate does not exist (nothing to drop). Raises
--    NOT_EXACT_DUPLICATE: unless p_duplicate is a plain, valid, non-unique, non-partial,
--    non-expression index on the same table with the same columns, operator classes,
--    collations and sort options as p_survivor, and p_survivor is a valid PRIMARY KEY or
--    UNIQUE index. Owner only.
-- ---------------------------------------------------------------------------
create or replace function public.assert_exact_duplicate_index_v1(p_duplicate text, p_survivor text)
returns boolean
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  d pg_index%rowtype;
  s pg_index%rowtype;
  v_dup regclass := to_regclass(p_duplicate);
  v_sur regclass := to_regclass(p_survivor);
begin
  if v_dup is null then
    return false;
  end if;
  if v_sur is null then
    raise exception 'NOT_EXACT_DUPLICATE: survivor % does not exist (would drop the only copy of %)', p_survivor, p_duplicate;
  end if;
  select * into d from pg_index where indexrelid = v_dup;
  select * into s from pg_index where indexrelid = v_sur;
  if d.indexrelid is null or s.indexrelid is null then
    raise exception 'NOT_EXACT_DUPLICATE: % or % is not an index', p_duplicate, p_survivor;
  end if;
  if d.indrelid <> s.indrelid
     or d.indkey::text <> s.indkey::text
     or d.indclass::text <> s.indclass::text
     or d.indcollation::text <> s.indcollation::text
     or d.indoption::text <> s.indoption::text
     or d.indexprs is not null or s.indexprs is not null
     or d.indpred is not null or s.indpred is not null
     or d.indisunique
     or not (s.indisunique or s.indisprimary)
     or not s.indisvalid
     or (select relam from pg_class where oid = v_dup) <> (select relam from pg_class where oid = v_sur) then
    raise exception 'NOT_EXACT_DUPLICATE: % is not an exact plain duplicate of unique/primary %', p_duplicate, p_survivor;
  end if;
  return true;
end;
$$;
revoke all on function public.assert_exact_duplicate_index_v1(text, text) from public, anon, authenticated;

commit;
