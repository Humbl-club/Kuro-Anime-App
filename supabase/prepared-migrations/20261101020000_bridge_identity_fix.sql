-- 20261101020000_bridge_identity_fix.sql
-- PREPARED, NOT DEPLOYED (2026-11-01 overnight production pass, lane 1 / SQL).
-- Deploying needs explicit owner approval. Must be applied BEFORE any episode re-import,
-- backfill_legacy_series_units_v1 run or placeholder cleanup touches the bridge.
--
-- Defect (schema.md section 1 item 6 / P0-6, intake.md 5.2): _bridge_legacy_unit_v1 keyed a
-- legacy unit on the SURROGATE source row id ('legacy:<medium>:<episodes.id>:<media>:<n>').
-- The anime importer deletes and re-inserts every episode of a title, so after one cycle the
-- delete trigger had marked the unit unavailable and written a 'withdrawn' event, and the
-- re-inserted row (new id) no longer matched the unit's provenance: it could never update
-- that unit or event again.
--
-- Fix:
--   1. Natural key: 'legacy:<medium>:<media_id>:<number>' for both
--      catalogue_units.source_provenance and release_events.source_identity/evidence.
--      The function signature is unchanged (p_source_id is accepted and ignored), so the
--      episodes/chapters triggers, backfill_legacy_series_units_v1 and grants stay valid.
--   2. Re-insert after withdrawal: a dated re-insert updates the same event row (status back
--      to released/scheduled, revision + 1); an UNDATED re-insert deletes that unit's own
--      'withdrawn' marker (the unit exists again; no date means no event, as before).
--      A unit owned by another (non-legacy) provenance is still never overwritten.
--   3. One-time repair of existing rows, repair_legacy_bridge_identity_v1(), called once
--      below (service role may re-run it; it is idempotent):
--        a. catalogue_units: old-format provenance is re-keyed (cannot collide: the table is
--           unique per media, edition and order_key).
--        b. release_events COLLISION RULE: all legacy events that map to one natural key
--           compete; exactly one survives, chosen by (1) not 'withdrawn' first, (2) latest
--           freshness, (3) highest revision, (4) lowest id. The others are deleted, then the
--           survivor is re-keyed (evidence too, when it held the old key).
--        c. A surviving 'withdrawn' legacy event whose source row (episodes/chapters with the
--           same media and number) exists now is stale (the old re-insert lock-out) and is
--           deleted, the same rule as 2.
--      The unit rows' own fields (available/title) are refreshed by the next bridge write or
--      a bounded backfill run (owner decision; do not backfill placeholder chapters).
--
-- Rollback: re-create _bridge_legacy_unit_v1 from 20261007040000 (the old key format), drop
-- repair_legacy_bridge_identity_v1. The re-keyed rows stay valid for the new key only.

begin;

-- The repair LOCKs catalogue_units / release_events (SHARE ROW EXCLUSIVE; both tables are
-- tiny on live, schema.md section 1): fail fast on a busy lock and retry instead of queueing.
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

create or replace function public._bridge_legacy_unit_v1(p_medium text, p_source_id integer, p_media_id integer,
 p_number integer, p_title text, p_synopsis text, p_image text, p_day date, p_instant timestamptz, p_removed boolean default false)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  -- natural key: the source row id (p_source_id) is deliberately NOT part of it
  v_source text := 'legacy:' || p_medium || ':' || p_media_id || ':' || p_number;
  v_available boolean;
begin
  if p_medium not in ('anime', 'manga') or p_number < 0 then
    raise exception 'INVALID_SOURCE_UNIT: medium must be anime or manga and number >= 0';
  end if;
  v_available := not p_removed and case when p_instant is not null then p_instant <= now()
    when p_day is not null then p_day < (now() at time zone 'UTC')::date else false end;
  if p_medium = 'anime' then
    insert into public.catalogue_units(medium, anime_id, label, order_key, edition_key, available, title, synopsis, image_url, source_provenance)
    values ('anime', p_media_id, p_number::text, p_number, 'legacy_catalogue', v_available, p_title, p_synopsis, p_image, v_source)
    on conflict (anime_id, edition_key, order_key) where anime_id is not null do update set
      available = excluded.available, title = excluded.title, synopsis = excluded.synopsis, image_url = excluded.image_url
      where catalogue_units.source_provenance = excluded.source_provenance returning id into v_id;
  else
    insert into public.catalogue_units(medium, manga_id, label, order_key, edition_key, available, title, synopsis, image_url, source_provenance)
    values ('manga', p_media_id, p_number::text, p_number, 'legacy_catalogue', v_available, p_title, p_synopsis, p_image, v_source)
    on conflict (manga_id, edition_key, order_key) where manga_id is not null do update set
      available = excluded.available, title = excluded.title, synopsis = excluded.synopsis, image_url = excluded.image_url
      where catalogue_units.source_provenance = excluded.source_provenance returning id into v_id;
  end if;
  if v_id is null then
    return; -- another verified source owns this unit; do not overwrite it.
  end if;
  if p_day is not null or p_instant is not null or p_removed then
    insert into public.release_events(medium, anime_id, manga_id, kind, precision, source_local_date, utc_instant, status, evidence, freshness, source_identity)
    values (p_medium, case when p_medium = 'anime' then p_media_id end, case when p_medium = 'manga' then p_media_id end,
      case when p_medium = 'anime' then 'Episode ' else 'Chapter ' end || p_number,
      case when p_instant is not null then 'instant' when p_day is not null then 'day' else 'unknown' end,
      p_day::text, p_instant, case when p_removed then 'withdrawn' when v_available then 'released' else 'scheduled' end,
      v_source, now(), v_source)
    on conflict (source_identity) where source_identity is not null do update set
      precision = excluded.precision, source_local_date = excluded.source_local_date, utc_instant = excluded.utc_instant,
      status = excluded.status, evidence = excluded.evidence, freshness = excluded.freshness, revision = release_events.revision + 1;
  else
    -- undated (re)insert: the unit exists again, so its own withdrawal marker is stale
    delete from public.release_events where source_identity = v_source and status = 'withdrawn';
  end if;
end;
$$;
revoke all on function public._bridge_legacy_unit_v1(text, integer, integer, integer, text, text, text, date, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public._bridge_legacy_unit_v1(text, integer, integer, integer, text, text, text, date, timestamptz, boolean) to service_role;

create or replace function public.repair_legacy_bridge_identity_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old constant text := '^legacy:(anime|manga):[0-9]+:([0-9]+):([0-9]+)$';
  v_units bigint;
  v_collisions bigint;
  v_events bigint;
  v_stale bigint;
  v_stale_m bigint;
begin
  -- no bridge write may interleave with the re-key
  lock table public.catalogue_units, public.release_events in share row exclusive mode;

  update public.catalogue_units
     set source_provenance = regexp_replace(source_provenance, v_old, 'legacy:\1:\2:\3')
   where source_provenance ~ v_old;
  get diagnostics v_units = row_count;

  with keyed as (
    select e.id, e.status, e.freshness, e.revision,
           case when e.source_identity ~ v_old then regexp_replace(e.source_identity, v_old, 'legacy:\1:\2:\3')
                else e.source_identity end as nk
    from public.release_events e
    where e.source_identity ~ '^legacy:(anime|manga):[0-9]+:[0-9]+(:[0-9]+)?$'
  ), ranked as (
    select k.id, row_number() over (partition by k.nk
             order by (k.status <> 'withdrawn') desc, k.freshness desc nulls last, k.revision desc, k.id) as rn
    from keyed k
  )
  delete from public.release_events e using ranked r where e.id = r.id and r.rn > 1;
  get diagnostics v_collisions = row_count;

  update public.release_events
     set source_identity = regexp_replace(source_identity, v_old, 'legacy:\1:\2:\3'),
         evidence = case when evidence ~ v_old then regexp_replace(evidence, v_old, 'legacy:\1:\2:\3') else evidence end
   where source_identity ~ v_old;
  get diagnostics v_events = row_count;

  delete from public.release_events e
   where e.status = 'withdrawn' and e.medium = 'anime' and e.source_identity ~ '^legacy:anime:[0-9]+:[0-9]+$'
     and exists (select 1 from public.episodes s
                 where s.anime_id = e.anime_id and s.number = split_part(e.source_identity, ':', 4)::integer);
  get diagnostics v_stale = row_count;
  delete from public.release_events e
   where e.status = 'withdrawn' and e.medium = 'manga' and e.source_identity ~ '^legacy:manga:[0-9]+:[0-9]+$'
     and exists (select 1 from public.chapters s
                 where s.manga_id = e.manga_id and s.number = split_part(e.source_identity, ':', 4)::integer);
  get diagnostics v_stale_m = row_count;

  return jsonb_build_object('units_rekeyed', v_units, 'event_collisions_removed', v_collisions,
    'events_rekeyed', v_events, 'stale_withdrawals_removed', v_stale + v_stale_m);
end;
$$;
revoke all on function public.repair_legacy_bridge_identity_v1() from public, anon, authenticated;
grant execute on function public.repair_legacy_bridge_identity_v1() to service_role;
comment on function public.repair_legacy_bridge_identity_v1() is
  '20261101020000: re-keys legacy bridge rows to legacy:<medium>:<media_id>:<number>. Collision rule for release_events: keep non-withdrawn, then latest freshness, then highest revision, then lowest id; delete the rest. Then deletes withdrawn legacy events whose source row exists again. Idempotent; returns counts.';

do $$
declare r jsonb;
begin
  r := public.repair_legacy_bridge_identity_v1();
  raise notice 'repair_legacy_bridge_identity_v1: %', r;
end $$;

commit;
