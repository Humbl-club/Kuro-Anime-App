-- 123_catalogue_tag_sources_v1.sql
-- Prepared 20261112100200_catalogue_tag_sources_v1.sql (NOT deployed): the service-only source-label to
-- Kuro-tag map catalogue_tag_source_map, tags.description_kuro, tags.retired_at and the service-only
-- reader catalogue_tag_map_v1() that never returns a retired tag.
-- (Numbered 123 because 122 is the existing race test; the plan named this file 122_.)
-- Covers: no anon/authenticated privilege and RLS on, foreign key to tags, weight check, retired tags
-- are left out of the reader, EXECUTE is service-only, and the Taste read path (media_tag_vectors,
-- anime_tags) is untouched by the two new tags columns.
-- Fixture limit: media_tag_vectors may be absent from the DB fixture; that assertion is skipped with a
-- notice when it is (the tags/anime_tags column checks still run).
-- @requires table public.tags
-- @requires table public.anime_tags
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- ---- 1. posture ---------------------------------------------------------------------
select tests.ok('the map table exists with RLS on and no client policy',
  to_regclass('public.catalogue_tag_source_map') is not null
  and (select relrowsecurity from pg_class where oid = 'public.catalogue_tag_source_map'::regclass)
  and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'catalogue_tag_source_map'));

select tests.ok('anon and authenticated hold no privilege on the map',
  to_regclass('public.catalogue_tag_source_map') is not null
  and not exists (
    select 1
    from unnest(array['anon','authenticated']) r,
         unnest(array['select','insert','update','delete','truncate','references','trigger']) p
    where has_table_privilege(r, 'public.catalogue_tag_source_map', p)));

select tests.ok('service_role can read and write the map',
  to_regclass('public.catalogue_tag_source_map') is not null
  and has_table_privilege('service_role', 'public.catalogue_tag_source_map', 'select')
  and has_table_privilege('service_role', 'public.catalogue_tag_source_map', 'insert')
  and has_table_privilege('service_role', 'public.catalogue_tag_source_map', 'update')
  and has_table_privilege('service_role', 'public.catalogue_tag_source_map', 'delete'));

select tests.ok('tags has description_kuro (text) and retired_at (timestamptz)',
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'tags' and column_name = 'description_kuro' and data_type = 'text')
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'tags' and column_name = 'retired_at' and data_type = 'timestamp with time zone'));

select tests.ok('the reader exists, is plpgsql with the fixed search_path and is service-only',
  to_regprocedure('public.catalogue_tag_map_v1()') is not null
  and (select prolang = (select oid from pg_language where lanname = 'plpgsql') and proconfig @> array['search_path=public, extensions']
       from pg_proc where oid = 'public.catalogue_tag_map_v1()'::regprocedure)
  and not has_function_privilege('anon', 'public.catalogue_tag_map_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.catalogue_tag_map_v1()', 'execute')
  and not has_function_privilege('public', 'public.catalogue_tag_map_v1()', 'execute')
  and has_function_privilege('service_role', 'public.catalogue_tag_map_v1()', 'execute'));

select tests.as_anon();
select tests.denied('anon cannot read the map', $q$select * from public.catalogue_tag_source_map$q$);
select tests.denied('anon cannot run the reader', $q$select * from public.catalogue_tag_map_v1()$q$);
select tests.reset();
select tests.make_user(1230);
select tests.as_user(tests.uid(1230));
select tests.denied('authenticated cannot read the map', $q$select * from public.catalogue_tag_source_map$q$);
select tests.denied('authenticated cannot write the map', $q$insert into public.catalogue_tag_source_map (source, source_label, tag_id) values ('ann', 'x', 1)$q$);
select tests.denied('authenticated cannot run the reader', $q$select * from public.catalogue_tag_map_v1()$q$);
select tests.reset();

-- ---- 2. behaviour ---------------------------------------------------------------------
insert into public.tags (id, name) values (1230001, 'Kuro Test Alpha'), (1230002, 'Kuro Test Beta');
insert into public.catalogue_tag_source_map (source, source_label, tag_id, weight) values
  ('ann', 'action', 1230001, 1),
  ('mangaupdates', 'Action', 1230001, 0.5),
  ('mangaupdates', 'Isekai', 1230002, 1);

select tests.eq('the reader returns every row of live tags',
  (select count(*) from public.catalogue_tag_map_v1() where tag_id in (1230001, 1230002)), 3::bigint);

update public.tags set retired_at = now() where id = 1230002;
select tests.eq('a retired tag is never returned by the reader',
  (select count(*) from public.catalogue_tag_map_v1() where tag_id = 1230002), 0::bigint);
select tests.eq('live tags are still returned',
  (select count(*) from public.catalogue_tag_map_v1() where tag_id = 1230001), 2::bigint);
update public.tags set retired_at = null where id = 1230002;
select tests.eq('an un-retired tag is returned again',
  (select count(*) from public.catalogue_tag_map_v1() where tag_id = 1230002), 1::bigint);

select tests.raises('a map row needs an existing tag',
  $q$insert into public.catalogue_tag_source_map (source, source_label, tag_id) values ('ann', 'ghost', 1230999)$q$,
  '%foreign key%');
select tests.raises('a duplicate (source, label) is rejected',
  $q$insert into public.catalogue_tag_source_map (source, source_label, tag_id) values ('ann', 'action', 1230002)$q$,
  '%duplicate key%');
select tests.raises('a non-positive weight is rejected',
  $q$insert into public.catalogue_tag_source_map (source, source_label, tag_id, weight) values ('ann', 'zero', 1230001, 0)$q$,
  '%check constraint%');
select tests.raises('only the allowed sources can be mapped (AniDB is excluded)',
  $q$insert into public.catalogue_tag_source_map (source, source_label, tag_id) values ('anidb', 'action', 1230001)$q$,
  '%check constraint%');

-- ---- 3. Taste reads are unaffected ----------------------------------------------------------
select tests.ok('anime_tags gained no column',
  (select array_agg(column_name::text order by column_name) from information_schema.columns
   where table_schema = 'public' and table_name = 'anime_tags')
  @> array['anime_id','created_at','id','rank','tag_id']
  and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'anime_tags' and column_name in ('description_kuro','retired_at')));

do $$
begin
  if to_regclass('public.media_tag_vectors') is null then
    raise notice 'TEST skipped: media_tag_vectors is not in the DB fixture';
  else
    perform tests.ok('media_tag_vectors does not reference the new tags columns',
      pg_get_viewdef('public.media_tag_vectors'::regclass) !~ '(description_kuro|retired_at|catalogue_tag)');
  end if;
end $$;

rollback;
