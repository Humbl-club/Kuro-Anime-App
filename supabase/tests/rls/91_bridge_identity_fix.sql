-- 91_bridge_identity_fix.sql
-- Prepared 20261101020000_bridge_identity_fix.sql (NOT deployed): the legacy unit bridge
-- keys units/events on (medium, media_id, number) instead of the surrogate source row id,
-- survives the importer's delete-all + re-insert cycle, drops an undated unit's own stale
-- withdrawal marker, never overwrites a unit another source owns, and the one-time repair
-- re-keys old rows with the explicit collision rule (non-withdrawn > latest freshness >
-- highest revision > lowest id) and removes stale withdrawals. Idempotent.
-- Tables and triggers come from 20261007040000 (live since 2026-10-08): prerequisites.
-- @requires table public.catalogue_units
-- @requires table public.release_events
-- @requires table public.episodes
-- @requires table public.chapters
-- @requires function public.legacy_unit_bridge_trigger_v1()
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.ok('repair function: no EXECUTE for anon/authenticated, granted to service_role',
  not has_function_privilege('anon', 'public.repair_legacy_bridge_identity_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.repair_legacy_bridge_identity_v1()', 'execute')
  and has_function_privilege('service_role', 'public.repair_legacy_bridge_identity_v1()', 'execute'));
select tests.ok('bridge keeps search_path = public, extensions and SECURITY DEFINER',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc
    where oid = 'public._bridge_legacy_unit_v1(text,integer,integer,integer,text,text,text,date,timestamp with time zone,boolean)'::regprocedure));

insert into public.anime (id, title_romaji) values (992001, 'Bridge Show'), (992002, 'Repair Show'), (992003, 'Owned Show');
insert into public.manga (id, title_romaji) values (992102, 'Repair Manga');

-- ---- 1. natural key + delete-all / re-insert cycle (dated) -----------------------
insert into public.episodes (id, anime_id, number, title, air_at) values (99200101, 992001, 1, 'Ep one', now() - interval '3 days');
select tests.eq('dated episode: one unit and one released event under the natural key',
  (select count(*) from public.catalogue_units where anime_id = 992001 and order_key = 1 and source_provenance = 'legacy:anime:992001:1')
  || '/' || (select status from public.release_events where source_identity = 'legacy:anime:992001:1'), '1/released');
delete from public.episodes where id = 99200101;
select tests.eq('import delete: unit unavailable, event withdrawn',
  (select available::text from public.catalogue_units where anime_id = 992001 and order_key = 1)
  || '/' || (select status from public.release_events where source_identity = 'legacy:anime:992001:1'), 'false/withdrawn');
insert into public.episodes (id, anime_id, number, title, air_at) values (99200199, 992001, 1, 'Ep one (re-imported)', now() - interval '3 days');
select tests.eq('re-insert with a NEW source id updates the same unit (was locked out before the fix)',
  (select count(*) || '/' || bool_and(available) || '/' || max(title) from public.catalogue_units where anime_id = 992001 and order_key = 1),
  '1/true/Ep one (re-imported)');
select tests.eq('re-insert brings the same event row back to released (revision advanced)',
  (select count(*) || '/' || max(status) || '/' || (max(revision) > 1) from public.release_events where anime_id = 992001),
  '1/released/true');

-- ---- 2. undated re-insert drops its own withdrawal marker ------------------------
insert into public.episodes (id, anime_id, number, title) values (99200102, 992001, 2, 'Ep two');
select tests.eq('undated episode: unit exists, no event', (select count(*) from public.release_events where source_identity = 'legacy:anime:992001:2'), 0::bigint);
delete from public.episodes where id = 99200102;
select tests.eq('undated delete writes a withdrawal marker', (select status from public.release_events where source_identity = 'legacy:anime:992001:2'), 'withdrawn');
insert into public.episodes (id, anime_id, number, title) values (99200122, 992001, 2, 'Ep two again');
select tests.eq('undated re-insert removes the stale withdrawal marker', (select count(*) from public.release_events where source_identity = 'legacy:anime:992001:2'), 0::bigint);
select tests.eq('...and updates the unit (one row)', (select count(*) || '/' || max(title) from public.catalogue_units where anime_id = 992001 and order_key = 2), '1/Ep two again');

-- ---- 3. a unit owned by another source is never overwritten ----------------------
insert into public.catalogue_units (medium, anime_id, label, order_key, edition_key, available, title, source_provenance)
values ('anime', 992003, '5', 5, 'legacy_catalogue', true, 'Curated five', 'publisher:verified');
insert into public.episodes (id, anime_id, number, title, air_at) values (99200305, 992003, 5, 'Imported five', now() - interval '1 day');
select tests.eq('foreign-owned unit kept, no legacy event written',
  (select title || '/' || source_provenance from public.catalogue_units where anime_id = 992003 and order_key = 5)
  || '/' || (select count(*) from public.release_events where anime_id = 992003), 'Curated five/publisher:verified/0');

-- ---- 4. one-time repair of old-format rows ---------------------------------------
insert into public.catalogue_units (medium, anime_id, label, order_key, edition_key, available, source_provenance)
values ('anime', 992002, '1', 1, 'legacy_catalogue', false, 'legacy:anime:111:992002:1');
insert into public.release_events (medium, anime_id, manga_id, kind, precision, status, evidence, freshness, revision, source_identity) values
  ('anime', 992002, null, 'Episode 1', 'unknown', 'withdrawn', 'legacy:anime:111:992002:1', now() - interval '1 day', 1, 'legacy:anime:111:992002:1'),
  ('anime', 992002, null, 'Episode 1', 'unknown', 'released',  'legacy:anime:222:992002:1', now() - interval '9 days', 1, 'legacy:anime:222:992002:1'),
  ('anime', 992002, null, 'Episode 2', 'unknown', 'withdrawn', 'legacy:anime:333:992002:2', now() - interval '2 days', 1, 'legacy:anime:333:992002:2'),
  ('anime', 992002, null, 'Episode 3', 'unknown', 'withdrawn', 'legacy:anime:444:992002:3', now() - interval '5 days', 4, 'legacy:anime:444:992002:3'),
  ('anime', 992002, null, 'Episode 3', 'unknown', 'withdrawn', 'legacy:anime:555:992002:3', now() - interval '1 day', 1, 'legacy:anime:555:992002:3'),
  ('manga', null, 992102, 'Chapter 7', 'unknown', 'scheduled', 'legacy:manga:666:992102:7', now(), 1, 'legacy:manga:666:992102:7');
-- the episode-2 source row exists again (undated: the bridge writes a unit, no event)
insert into public.episodes (id, anime_id, number, title) values (99200202, 992002, 2, 'Back again');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select public.repair_legacy_bridge_identity_v1() as rep1 \gset
select public.repair_legacy_bridge_identity_v1() as rep2 \gset
select tests.reset();
select tests.eq('repair counts: 1 unit, 2 collisions, 4 events re-keyed, 1 stale withdrawal',
  :'rep1'::jsonb, '{"units_rekeyed":1,"event_collisions_removed":2,"events_rekeyed":4,"stale_withdrawals_removed":1}'::jsonb);
select tests.eq('repair is idempotent', :'rep2'::jsonb,
  '{"units_rekeyed":0,"event_collisions_removed":0,"events_rekeyed":0,"stale_withdrawals_removed":0}'::jsonb);
select tests.eq('no old-format legacy key is left',
  (select count(*) from public.release_events where source_identity ~ '^legacy:(anime|manga):[0-9]+:[0-9]+:[0-9]+$')
  + (select count(*) from public.catalogue_units where source_provenance ~ '^legacy:(anime|manga):[0-9]+:[0-9]+:[0-9]+$'), 0::bigint);
select tests.eq('collision rule 1: the non-withdrawn event wins even though it is older',
  (select count(*) || '/' || max(status) || '/' || max(evidence) from public.release_events where source_identity = 'legacy:anime:992002:1'),
  '1/released/legacy:anime:992002:1');
select tests.eq('collision rule 2: among withdrawn events the latest freshness wins (not the higher revision)',
  (select count(*) || '/' || max(revision) from public.release_events where source_identity = 'legacy:anime:992002:3'), '1/1');
select tests.eq('stale withdrawal of a unit whose source row exists again is removed',
  (select count(*) from public.release_events where source_identity = 'legacy:anime:992002:2'), 0::bigint);
select tests.eq('manga event re-keyed', (select status from public.release_events where source_identity = 'legacy:manga:992102:7'), 'scheduled');
select tests.eq('re-keyed unit is owned by the bridge again: a dated re-import updates it in place',
  (select source_provenance from public.catalogue_units where anime_id = 992002 and order_key = 1), 'legacy:anime:992002:1');
insert into public.episodes (id, anime_id, number, title, air_at) values (99200201, 992002, 1, 'One back', now() - interval '1 day');
select tests.eq('...one unit, available, one event for the key',
  (select count(*) || '/' || bool_and(available) from public.catalogue_units where anime_id = 992002 and order_key = 1)
  || '/' || (select count(*) from public.release_events where source_identity = 'legacy:anime:992002:1'), '1/true/1');

select tests.as_user(tests.make_user(912));
select tests.denied('authenticated cannot run the repair', $q$select public.repair_legacy_bridge_identity_v1()$q$);
select tests.reset();
rollback;
