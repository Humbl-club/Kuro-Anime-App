-- W6 grouping: the reviewed-membership read of CatalogStore+SeriesMembership (one PostgREST GET per
-- medium and batch of 300 ids). A characterisation test of the live schema (20261007040000), no new SQL:
-- it pins what the client's filters return, that the anime_id index serves a 300-id read, the FK names the
-- embed hints use, and that clients can only read. Disposable local fixture only, never hosted.
-- @requires table public.series_entry_spans
-- @requires table public.series
-- @requires table public.series_sections
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
begin;
set local jit = off;

-- Avoid unrelated ingestion triggers only in this local test transaction. Never hosted.
set local session_replication_role = replica;
insert into public.anime(id, title_romaji, title_english)
select 7110000 + n, 'Series read title ' || n, 'Series read english ' || n
from generate_series(1, 20000) n;
insert into public.manga(id, title_romaji, title_english) values (7116005, 'Series read manga', 'Series read manga');

-- 2,000 published series of 3 seasons (6,000 spans), exactly what publish_mapping_revision leaves:
-- continuity verified, series approved, sections approved. Titles 7110001..7116000.
insert into public.series(id, medium, continuity, title, grouping_state)
select md5('pub' || k)::uuid, 'anime', 'verified', 'Published ' || k, 'approved'
from generate_series(1, 2000) k;
insert into public.series_sections(id, series_id, kind, ordinal, name, sort_order, provenance, state)
select md5('sec' || k || '-' || s)::uuid, md5('pub' || k)::uuid, 'season', s, 'Season ' || s, s, 'test', 'approved'
from generate_series(1, 2000) k cross join generate_series(1, 3) s;
insert into public.series_entry_spans(series_id, section_id, medium, anime_id)
select md5('pub' || k)::uuid, md5('sec' || k || '-' || s)::uuid, 'anime', 7110000 + (k - 1) * 3 + s
from generate_series(1, 2000) k cross join generate_series(1, 3) s;

-- Loophole 1: a series inserted with its defaults is 'approved' but 'singleton' (2 spans: 7116001/2).
insert into public.series(id, medium, title) values (md5('default')::uuid, 'anime', 'Default inserted');
insert into public.series_sections(id, series_id, kind, ordinal, name, sort_order, provenance)
values (md5('dsec1')::uuid, md5('default')::uuid, 'season', 1, 'S1', 1, 'test'),
       (md5('dsec2')::uuid, md5('default')::uuid, 'season', 2, 'S2', 2, 'test');
insert into public.series_entry_spans(series_id, section_id, medium, anime_id)
values (md5('default')::uuid, md5('dsec1')::uuid, 'anime', 7116001),
       (md5('default')::uuid, md5('dsec2')::uuid, 'anime', 7116002);

-- Loophole 2: a verified series whose section is superseded (7116003).
insert into public.series(id, medium, continuity, title) values (md5('superseded')::uuid, 'anime', 'verified', 'Superseded section');
insert into public.series_sections(id, series_id, kind, ordinal, name, sort_order, provenance, state)
values (md5('ssec')::uuid, md5('superseded')::uuid, 'season', 1, 'S1', 1, 'test', 'superseded');
insert into public.series_entry_spans(series_id, section_id, medium, anime_id)
values (md5('superseded')::uuid, md5('ssec')::uuid, 'anime', 7116003);

-- Cross-medium 1: a verified MANGA series holding an anime span (7116004). The PostgREST request cannot
-- compare series.medium with the span's medium, so the server returns it and the client drops it.
insert into public.series(id, medium, continuity, title) values (md5('xm1')::uuid, 'manga', 'verified', 'Manga series, anime span');
insert into public.series_sections(id, series_id, kind, ordinal, name, sort_order, provenance)
values (md5('xm1sec')::uuid, md5('xm1')::uuid, 'season', 1, 'S1', 1, 'test');
insert into public.series_entry_spans(series_id, section_id, medium, anime_id)
values (md5('xm1')::uuid, md5('xm1sec')::uuid, 'anime', 7116004);

-- Cross-medium 2: a verified ANIME series holding a manga span (manga 7116005).
insert into public.series(id, medium, continuity, title) values (md5('xm2')::uuid, 'anime', 'verified', 'Anime series, manga span');
insert into public.series_sections(id, series_id, kind, ordinal, name, sort_order, provenance)
values (md5('xm2sec')::uuid, md5('xm2')::uuid, 'season', 1, 'S1', 1, 'test');
insert into public.series_entry_spans(series_id, section_id, medium, manga_id)
values (md5('xm2')::uuid, md5('xm2sec')::uuid, 'manga', 7116005);
set local session_replication_role = origin;

analyze public.anime;
analyze public.series;
analyze public.series_sections;
analyze public.series_entry_spans;

-- The ids of one membership read: 295 published titles (of the 2,000-title library) plus the five
-- loophole titles 7116001..7116005 = 300 ids.
create temporary table read_ids(ids text);
grant all on read_ids to public;
insert into read_ids
select string_agg(id::text, ',')
from (select 7110000 + n as id from generate_series(1, 295) n
      union all select 7116000 + n from generate_series(1, 5) n) q;

-- The server filter, written as SQL equal to the PostgREST request:
--   series_entry_spans?select=...,series!..!inner(..),series_sections!..!inner(..)&medium=eq.anime
--   &anime_id=in.(...)&series.continuity=eq.verified&series.grouping_state=eq.approved&series_sections.state=eq.approved
-- It has NO s.medium = sp.medium predicate: PostgREST cannot compare columns across an embed.
create or replace function pg_temp.filter_sql(p_medium text, p_ids text) returns text language sql as $$
  select format($q$
    select sp.anime_id, sp.manga_id, sp.medium, s.id as series_id, s.medium as series_medium, sec.kind, sec.ordinal
    from public.series_entry_spans sp
    join public.series s on s.id = sp.series_id
    join public.series_sections sec on sec.id = sp.section_id
    where sp.medium = %L and sp.%I = any(array[%s])
      and s.continuity = 'verified' and s.grouping_state = 'approved' and sec.state = 'approved'
  $q$, p_medium, p_medium || '_id', p_ids);
$$;

select tests.eq('server filter returns only verified approved spans (295 published + the cross-medium anime span)',
  tests.rowcount(pg_temp.filter_sql('anime', (select ids from read_ids))), 296::bigint);
select tests.eq('server filter drops the default-inserted (singleton) series',
  tests.rowcount(pg_temp.filter_sql('anime', (select ids from read_ids)) || ' and 1=1 and sp.anime_id in (7116001, 7116002)'), 0::bigint);
select tests.eq('server filter drops the superseded section',
  tests.rowcount(pg_temp.filter_sql('anime', (select ids from read_ids)) || ' and sp.anime_id = 7116003'), 0::bigint);
select tests.eq('the cross-medium anime span is returned by the server and removed by the client',
  tests.rowcount(pg_temp.filter_sql('anime', (select ids from read_ids)) || ' and s.medium <> sp.medium'), 1::bigint);
select tests.eq('the manga read returns the manga span of the anime series (client drops it)',
  tests.rowcount(pg_temp.filter_sql('manga', '7116005') || ' and s.medium <> sp.medium'), 1::bigint);
select tests.eq('after the client medium check, exactly the 295 published spans remain',
  tests.rowcount(pg_temp.filter_sql('anime', (select ids from read_ids)) || ' and s.medium = sp.medium'), 295::bigint);

create temporary table membership_plan(plan jsonb);
grant all on membership_plan to public;
do $$
declare v_plan jsonb;
begin
  execute 'explain (analyze, format json) ' || pg_temp.filter_sql('anime', (select ids from read_ids)) into v_plan;
  insert into membership_plan values (v_plan);
end $$;
select tests.ok('the 300-id read uses series_entry_spans_anime_uq',
  (select plan::text like '%series_entry_spans_anime_uq%' from membership_plan));
select tests.ok('the 300-id read does not seq-scan series_entry_spans',
  (select not jsonb_path_exists(plan,
     '$.** ? (@."Node Type" == "Seq Scan" && @."Relation Name" == "series_entry_spans")') from membership_plan));

select tests.ok('FK names used by the embed hints exist',
  (select count(*) = 2 from pg_constraint
   where conrelid = 'public.series_entry_spans'::regclass and contype = 'f'
     and conname in ('series_entry_spans_series_id_fkey', 'series_entry_spans_section_id_fkey')));

-- Clients read only. The migration grants SELECT but revokes nothing, and Supabase's default privileges
-- give anon/authenticated table-level write grants, so RLS (a select-only policy, no write policy) is
-- what keeps clients out: assert behaviour as each role, not has_table_privilege.
select tests.ok('select is granted: ' || t,
  has_table_privilege('anon', 'public.' || t, 'select') and has_table_privilege('authenticated', 'public.' || t, 'select'))
from unnest(array['series_entry_spans', 'series', 'series_sections']) t;

select tests.as_anon();
select tests.eq('anon reads published spans', (select count(*) > 0 from public.series_entry_spans), true);
select tests.denied('anon cannot insert a series', $$insert into public.series(medium, title) values ('anime', 'x')$$);
select tests.denied('anon cannot insert a span',
  $$insert into public.series_entry_spans(series_id, medium, anime_id) values (md5('pub1')::uuid, 'anime', 7119999)$$);
select tests.as_user(tests.uid(1));
select tests.eq('authenticated reads sections', (select count(*) > 0 from public.series_sections), true);
select tests.denied('authenticated cannot insert a series', $$insert into public.series(medium, title) values ('anime', 'x')$$);
select tests.denied('authenticated cannot insert a section',
  $$insert into public.series_sections(series_id, kind, name, sort_order, provenance) values (md5('pub1')::uuid, 'season', 'x', 9, 'x')$$);
select tests.denied('authenticated cannot insert a span',
  $$insert into public.series_entry_spans(series_id, medium, anime_id) values (md5('pub1')::uuid, 'anime', 7119999)$$);
select tests.eq('authenticated update of a series touches no row',
  tests.affected($$update public.series set continuity = 'verified' where id = md5('default')::uuid$$), 0::bigint);
select tests.eq('authenticated delete of a span touches no row',
  tests.affected($$delete from public.series_entry_spans where anime_id = 7116001$$), 0::bigint);
select tests.reset();

rollback;
