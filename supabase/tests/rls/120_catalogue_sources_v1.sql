-- 120_catalogue_sources_v1.sql
-- Prepared 20261112100000_catalogue_sources_v1.sql (NOT deployed): service-only catalogue source
-- tables (raw source records, id crosswalk, rollback snapshots, shadow values), the per-field-group
-- cutover switch (12 groups seeded in 'anilist') and anime/manga.data_sources.
-- Covers: no anon/authenticated privilege and RLS on, existence trigger on catalogue_id_links
-- (polymorphic kuro_id, no FK), partial unique indexes (23505), delete cleanup of links only.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.staff
-- @requires table public.studios
-- @requires table public.characters
-- @requires table public.authors
-- @requires table public.anime_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- ---- 1. posture --------------------------------------------------------------------
select tests.ok('all five catalogue tables exist',
  (select count(*) from unnest(array['catalogue_source_records','catalogue_id_links',
     'catalogue_rollback_snapshots','catalogue_shadow_values','catalogue_cutover']) t
   where to_regclass('public.' || t) is not null) = 5);

select tests.ok('anon and authenticated hold no privilege on any catalogue table',
  not exists (
    select 1
    from unnest(array['catalogue_source_records','catalogue_id_links',
      'catalogue_rollback_snapshots','catalogue_shadow_values','catalogue_cutover']) t,
         unnest(array['anon','authenticated']) r,
         unnest(array['select','insert','update','delete','truncate','references','trigger']) p
    where to_regclass('public.' || t) is null
       or has_table_privilege(r, 'public.' || t, p)));

select tests.ok('anon and authenticated hold no privilege on the link id sequence',
  to_regclass('public.catalogue_id_links_id_seq') is not null
  and not has_sequence_privilege('anon', 'public.catalogue_id_links_id_seq', 'usage')
  and not has_sequence_privilege('authenticated', 'public.catalogue_id_links_id_seq', 'usage'));

select tests.ok('row level security is enabled on every catalogue table',
  (select count(*) from pg_class
    where oid = any (array[to_regclass('public.catalogue_source_records'), to_regclass('public.catalogue_id_links'),
      to_regclass('public.catalogue_rollback_snapshots'), to_regclass('public.catalogue_shadow_values'),
      to_regclass('public.catalogue_cutover')])
      and relrowsecurity) = 5);

select tests.ok('no client policy exists on any catalogue table',
  not exists (select 1 from pg_policies where schemaname = 'public'
    and tablename in ('catalogue_source_records','catalogue_id_links','catalogue_rollback_snapshots',
                      'catalogue_shadow_values','catalogue_cutover')));

select tests.ok('the catalogue trigger functions set search_path = public, extensions and are not executable by clients',
  (select count(*) = 4
      and bool_and(proconfig @> array['search_path=public, extensions'])
      and bool_and(not prosecdef)
      and bool_and(not has_function_privilege('anon', oid, 'execute'))
      and bool_and(not has_function_privilege('authenticated', oid, 'execute'))
      and bool_and(not has_function_privilege('public', oid, 'execute'))
   from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('catalogue_id_links_check_target', 'catalogue_id_links_cleanup_anime',
                     'catalogue_id_links_cleanup_manga', 'catalogue_id_links_cleanup_entity')));

-- ---- 2. cutover switch ----------------------------------------------------------------
select tests.eq('catalogue_cutover has 12 groups in anilist mode',
  (select count(*) from catalogue_cutover where mode = 'anilist'), 12::bigint);
select tests.eq('catalogue_cutover has exactly 12 rows',
  (select count(*) from catalogue_cutover), 12::bigint);
select tests.eq('the 12 field groups are the specified ones',
  (select array_agg(field_group order by field_group) from catalogue_cutover),
  array['adult','credits','episodes','facts','identity','images','links','popularity','relations','synopsis','tags','titles']);
select tests.raises('an unknown field group is rejected',
  $$insert into catalogue_cutover (field_group) values ('colour')$$, '%catalogue_cutover_field_group_check%');
select tests.raises('an unknown mode is rejected',
  $$update catalogue_cutover set mode = 'both' where field_group = 'facts'$$, '%catalogue_cutover_mode_check%');

-- ---- 3. data_sources columns ----------------------------------------------------------
select tests.ok('anime.data_sources and manga.data_sources are nullable text[] without default',
  (select count(*) = 2 and bool_and(not a.attnotnull) and bool_and(a.atttypid = 'text[]'::regtype)
          and bool_and(not a.atthasdef)
   from pg_attribute a
   where a.attname = 'data_sources' and not a.attisdropped
     and a.attrelid in ('public.anime'::regclass, 'public.manga'::regclass)));

-- ---- 4. rows ------------------------------------------------------------------------
insert into public.anime (id, anilist_id, title_romaji) values (1200001, 1200001, 'Catalogue A'), (1200002, 1200002, 'Catalogue B');
insert into public.manga (id, anilist_id, title_romaji) values (1200001, 1200001, 'Catalogue M');
insert into public.staff (id, anilist_id, name_full) values (1200001, 1200001, 'Staff A');
insert into public.studios (id, anilist_id, name) values (1200001, 1200001, 'Studio A');
insert into public.characters (id, anilist_id, name_full) values (1200001, 1200001, 'Character A');
insert into public.authors (id, anilist_id, name_full) values (1200001, 1200001, 'Author A');
select tests.make_user(1200);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  values (tests.uid(1200)::text, 1200001, 'WATCHING', 1), (tests.uid(1200)::text, 1200002, 'WATCHING', 2);

select tests.raises('a source record needs a medium of anime or manga',
  $$insert into catalogue_source_records (source, source_key, medium, payload, payload_hash, licence)
    values ('wikidata', 'Q1', 'novel', '{}', 'h', 'CC0-1.0')$$, '%catalogue_source_records_medium_check%');
insert into catalogue_source_records (source, source_key, medium, payload, payload_hash, licence)
  values ('wikidata', 'Q1', 'anime', '{"a":1}', 'h1', 'CC0-1.0');
select tests.raises('a source record is unique per (source, source_key, medium)',
  $$insert into catalogue_source_records (source, source_key, medium, payload, payload_hash, licence)
    values ('wikidata', 'Q1', 'anime', '{}', 'h2', 'CC0-1.0')$$, '%catalogue_source_records_pkey%');
select tests.eq('the same source key may exist for the other medium',
  tests.affected($$insert into catalogue_source_records (source, source_key, medium, payload, payload_hash, licence)
    values ('wikidata', 'Q1', 'manga', '{}', 'h3', 'CC0-1.0')$$), 1::bigint);

-- ---- 5. link existence trigger (kuro_id is polymorphic, no FK) ---------------------------
select tests.raises('a staff link to a nonexistent staff id is rejected',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('staff', 1209999, 'ann', 'p1', 'name_match', 'accepted')$$, '%catalogue_id_links: staff 1209999 does not exist%');
select tests.raises('an anime link to a nonexistent media id is rejected',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('anime', 1209999, 'ann', '1', 'wikidata', 'accepted')$$, '%catalogue_id_links: anime 1209999 does not exist%');
select tests.raises('a manga link is checked against manga, not anime',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('manga', 1200002, 'mangaupdates', '9', 'wikidata', 'accepted')$$, '%catalogue_id_links: manga 1200002 does not exist%');
select tests.raises('an unknown kind is rejected (the BEFORE trigger fires ahead of the CHECK)',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('film', 1200001, 'ann', '1', 'wikidata', 'accepted')$$, '%catalogue_id_links: film 1200001 does not exist%');
select tests.raises('an unknown method is rejected',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('anime', 1200001, 'ann', '1', 'guess', 'accepted')$$, '%catalogue_id_links_method_check%');
select tests.raises('an unknown status is rejected',
  $$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('anime', 1200001, 'ann', '1', 'wikidata', 'maybe')$$, '%catalogue_id_links_status_check%');

insert into catalogue_id_links (kind, kuro_id, source, source_key, method, confidence, status, decided_at) values
  ('anime',     1200001, 'ann',          '100', 'wikidata',   1, 'accepted', now()),
  ('anime',     1200002, 'ann',          '200', 'wikidata',   1, 'accepted', now()),
  ('manga',     1200001, 'mangaupdates', '300', 'wikidata',   1, 'accepted', now()),
  ('staff',     1200001, 'ann',          '400', 'name_match', 0.95, 'accepted', now()),
  ('studio',    1200001, 'ann',          '500', 'name_match', 0.95, 'accepted', now()),
  ('character', 1200001, 'ann',          '600', 'name_match', 0.95, 'accepted', now()),
  ('author',    1200001, 'mangaupdates', '700', 'name_match', 0.95, 'accepted', now());
select tests.eq('all six kinds accept an existing target', (select count(*) from catalogue_id_links), 7::bigint);
insert into catalogue_id_links (kind, kuro_id, source, source_key, method) values ('anime', 1200002, 'wikidata', 'Q77', 'title_match');
select tests.eq('status defaults to proposed',
  (select status from catalogue_id_links where source_key = 'Q77'), 'proposed');
delete from catalogue_id_links where source_key = 'Q77';
select tests.raises('repointing an existing link at a nonexistent id is rejected',
  $$update catalogue_id_links set kuro_id = 1209999 where source_key = '100'$$, '%catalogue_id_links: anime 1209999 does not exist%');

-- ---- 6. partial unique indexes ----------------------------------------------------
do $$
begin
  begin
    insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
      values ('anime', 1200002, 'ann', '100', 'title_match', 'accepted');
  exception when unique_violation then
    raise notice 'TEST ok: same source key accepted twice -> SQLSTATE %', sqlstate;
    return;
  end;
  raise exception 'TEST FAIL: duplicate accepted source key was allowed';
end $$;
do $$
begin
  begin
    insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
      values ('anime', 1200001, 'ann', '101', 'title_match', 'accepted');
  exception when unique_violation then
    raise notice 'TEST ok: second accepted ann link for one anime -> SQLSTATE %', sqlstate;
    return;
  end;
  raise exception 'TEST FAIL: second accepted ann link for the same anime was allowed';
end $$;
select tests.eq('proposed and rejected links do not collide with the accepted one',
  tests.affected($$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status) values
    ('anime', 1200001, 'ann', '100', 'title_match', 'proposed'),
    ('anime', 1200001, 'ann', '100', 'title_match', 'rejected'),
    ('anime', 1200001, 'ann', '101', 'title_match', 'proposed')$$), 3::bigint);
do $$
begin
  begin
    insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
      values ('anime', 1200001, 'ann', '101', 'title_match', 'proposed');
  exception when unique_violation then
    raise notice 'TEST ok: duplicate proposed link for (kind, kuro_id, source, source_key) -> SQLSTATE %', sqlstate;
    return;
  end;
  raise exception 'TEST FAIL: a duplicate proposed link was allowed';
end $$;
select tests.eq('another source may link the same anime',
  tests.affected($$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('anime', 1200001, 'wikidata', 'Q42', 'wikidata', 'accepted')$$), 1::bigint);
select tests.eq('the same source key under another kind is a different link',
  tests.affected($$insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status)
    values ('manga', 1200001, 'ann', '100', 'title_match', 'accepted')$$), 1::bigint);

-- ---- 7. delete cleanup (exercised as service_role, the role the importers run as) ----------------
-- The user list rows of the deleted anime and of the other anime. The existing list foreign key
-- decides what happens to the deleted title's own rows; the catalogue triggers must not touch the
-- other title's rows.
create temp table list_fk as
  select coalesce((select confdeltype::text from pg_constraint
                    where conrelid = 'public.anime_user_lists'::regclass and contype = 'f'
                      and confrelid = 'public.anime'::regclass limit 1), 'none') as del;
grant select on list_fk to public;
insert into catalogue_shadow_values (medium, media_id, field, value, source) values
  ('anime', 1200001, 'format', '"TV"', 'ann'),
  ('anime', 1200001, 'review:adult', '{"reason":"x"}', 'composer'),
  ('anime', 1200002, 'format', '"OVA"', 'ann'),
  ('manga', 1200001, 'format', '"MANGA"', 'mangaupdates');
insert into catalogue_rollback_snapshots (field_group, medium, media_id, payload, taken_at) values
  ('facts', 'anime', 1200001, '{"format":"TV"}', now()),
  ('titles', 'anime', 1200001, '{}', now()),
  ('facts', 'manga', 1200001, '{}', now());

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
-- service_role can insert a link (the existence trigger takes FOR KEY SHARE on the target row)
insert into catalogue_id_links (kind, kuro_id, source, source_key, method, status) values ('anime', 1200002, 'wikidata', 'Q88', 'title_match', 'proposed');
delete from public.anime where id = 1200001;
reset role;

select tests.eq('service_role could insert a link on an existing target',
  (select count(*) from catalogue_id_links where source_key = 'Q88'), 1::bigint);
delete from catalogue_id_links where source_key = 'Q88';
select tests.eq('deleting an anime removes its links (every status), as service_role',
  (select count(*) from catalogue_id_links where kind = 'anime' and kuro_id = 1200001), 0::bigint);
select tests.eq('links of the other anime stay',
  (select count(*) from catalogue_id_links where kind = 'anime' and kuro_id = 1200002), 1::bigint);
select tests.eq('manga links with the same numeric id stay',
  (select count(*) from catalogue_id_links where kind = 'manga' and kuro_id = 1200001), 2::bigint);
select tests.eq('deletedTitleRemovesShadowRows: the deleted anime has no shadow rows left',
  (select count(*) from catalogue_shadow_values where medium = 'anime' and media_id = 1200001), 0::bigint);
select tests.eq('deletedTitleRemovesShadowRows: the deleted anime has no rollback snapshots left',
  (select count(*) from catalogue_rollback_snapshots where medium = 'anime' and media_id = 1200001), 0::bigint);
select tests.eq('shadow rows of the other anime and of the manga with the same numeric id stay',
  (select count(*) from catalogue_shadow_values where (medium, media_id) in (('anime', 1200002), ('manga', 1200001))), 2::bigint);
select tests.eq('snapshots of the manga with the same numeric id stay',
  (select count(*) from catalogue_rollback_snapshots where medium = 'manga' and media_id = 1200001), 1::bigint);
select tests.eq('the deleted title''s own list row follows the existing foreign key (cascade removes it, otherwise it stays)',
  (select count(*) from public.anime_user_lists where anime_id = 1200001),
  case when (select del from list_fk) = 'c' then 0::bigint else 1::bigint end);
select tests.eq('the other anime''s list row is untouched (user, anime, progress)',
  (select count(*) from public.anime_user_lists where anime_id = 1200002 and user_id = tests.uid(1200)::text and progress = 2), 1::bigint);
select tests.eq('the source record of the deleted title stays (records are not title-keyed)',
  (select count(*) from catalogue_source_records where source_key = 'Q1' and medium = 'anime'), 1::bigint);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
delete from public.manga where id = 1200001;
reset role;
select tests.eq('deleting a manga removes its manga links only',
  (select count(*) from catalogue_id_links where kind = 'manga' and kuro_id = 1200001), 0::bigint);
select tests.eq('deleting a manga removes its shadow rows and snapshots',
  (select count(*) from catalogue_shadow_values where medium = 'manga' and media_id = 1200001)
  + (select count(*) from catalogue_rollback_snapshots where medium = 'manga' and media_id = 1200001), 0::bigint);
select tests.eq('staff / studio / character / author links stay until their own row goes',
  (select count(*) from catalogue_id_links where kind in ('staff','studio','character','author')), 4::bigint);
set local role service_role;
delete from public.staff where id = 1200001;
delete from public.studios where id = 1200001;
delete from public.characters where id = 1200001;
delete from public.authors where id = 1200001;
reset role;
select tests.eq('deleting an entity row removes its links',
  (select count(*) from catalogue_id_links where kind in ('staff','studio','character','author')), 0::bigint);

-- ---- 8. snapshots and shadow values keys -------------------------------------------
insert into catalogue_rollback_snapshots (field_group, medium, media_id, payload, taken_at)
  values ('facts', 'anime', 1200002, '{"format":"TV"}', now());
select tests.raises('a snapshot is unique per (field_group, medium, media_id)',
  $$insert into catalogue_rollback_snapshots (field_group, medium, media_id, payload, taken_at)
    values ('facts', 'anime', 1200002, '{}', now())$$, '%catalogue_rollback_snapshots_pkey%');
select tests.raises('a shadow value is unique per (medium, media_id, field)',
  $$insert into catalogue_shadow_values (medium, media_id, field, value, source)
    values ('anime', 1200002, 'format', '"OVA"', 'ann'), ('anime', 1200002, 'format', '"TV"', 'ann')$$, '%catalogue_shadow_values_pkey%');

rollback;
