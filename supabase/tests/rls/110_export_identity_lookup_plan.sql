-- W2 export: plan check for the public catalogue identity lookup (CatalogStore+ExportIdentities):
--   select id,mal_id,title_english,title_romaji,title_native from <medium> where id in (<=500 ids>)
-- A plan check, not a red/green test: W2 changes no SQL. Disposable local fixture only, never hosted.
-- Each medium is checked as anon and as authenticated. A negative control (primary key dropped,
-- rolled back with the transaction) proves the positive check can fail.
-- @requires table public.anime
-- @requires table public.manga
\set ON_ERROR_STOP on
begin;
set local jit = off;

-- Avoid unrelated ingestion triggers only in this local test transaction. Never hosted.
set local session_replication_role = replica;
insert into public.anime(id, title_romaji, title_english)
select 9100000 + n, 'Plan check title ' || n, 'Plan check english ' || n
from generate_series(1, 22000) n;
insert into public.manga(id, title_romaji, title_english)
select 9100000 + n, 'Plan check title ' || n, 'Plan check english ' || n
from generate_series(1, 22000) n;
set local session_replication_role = origin;
analyze public.anime;
analyze public.manga;

-- Plans land in a temp table that every role may write (the lookup runs under the role).
create temporary table lookup_plans(medium text, role_name text, phase text, plan jsonb);
grant all on lookup_plans to public;

create or replace function pg_temp.capture_plan(p_medium text, p_role text, p_phase text)
returns void
language plpgsql
as $fn$
declare
  v_ids text;
  v_plan jsonb;
begin
  select string_agg((9100000 + n)::text, ',') into v_ids from generate_series(1, 500) n;
  execute format('set local role %I', p_role);
  execute format(
    'explain (analyze, format json) select id,mal_id,title_english,title_romaji,title_native from public.%I where id = any(array[%s])',
    p_medium, v_ids) into v_plan;
  reset role;
  insert into lookup_plans values (p_medium, p_role, p_phase, v_plan);
  raise notice 'PLAN % % % %', p_medium, p_role, p_phase, v_plan::text;
end
$fn$;

select pg_temp.capture_plan(m, r, 'indexed')
from unnest(array['anime', 'manga']) m
cross join unnest(array['anon', 'authenticated']) r;

select tests.ok('identity lookup uses the primary key (' || medium || ' as ' || role_name || ')',
  plan::text like '%' || medium || '_pkey%' and plan::text not like '%Seq Scan%')
from lookup_plans where phase = 'indexed' order by medium, role_name;

select tests.ok('lookup returns 500 rows (' || medium || ' as ' || role_name || ')',
  (plan -> 0 -> 'Plan' ->> 'Actual Rows')::numeric = 500)
from lookup_plans where phase = 'indexed' order by medium, role_name;

-- Negative control (F3.2 pair): without the primary key the same lookup must not name it.
alter table public.anime drop constraint anime_pkey cascade;
alter table public.manga drop constraint manga_pkey cascade;

select pg_temp.capture_plan(m, 'authenticated', 'no_pkey') from unnest(array['anime', 'manga']) m;

select tests.ok('without the primary key the ' || medium || ' plan no longer names ' || medium || '_pkey',
  plan::text not like '%' || medium || '_pkey%')
from lookup_plans where phase = 'no_pkey' order by medium;

rollback;
