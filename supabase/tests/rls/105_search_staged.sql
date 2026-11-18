-- 105_search_staged.sql
-- Prepared 20261109200000_search_staged_v1.sql (NOT deployed): search_anime_page /
-- search_manga_page run a strong stage (exact/prefix/word/contains/full-text, rank >= 320) and
-- the trigram stage (rank exactly 250) only when the page is still short; a blank query keeps its
-- single popularity-ordered pass. Differential against the frozen pre-load bodies in
-- fixtures/102_load_baseline.sql (pg_temp.old_search_*), plus the page-boundary case the staging
-- must not break: 35 strong + 50 fuzzy rows, page size 30 -> page 2 = last 5 strong then fuzzy
-- only, no repeats, and a cursor that starts inside the fuzzy region. Disposable fixture only.
-- @requires table public.anime
-- @requires table public.manga
-- @requires function public.search_anime_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)
-- @requires function public.search_manga_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean)
\set ON_ERROR_STOP on
\o /dev/null
begin;
set local jit = off;
\ir ../fixtures/102_load_baseline.sql
select tests.reset();

-- ---- 1. posture ----------------------------------------------------------------------
select tests.ok('both Search functions are staged: blank pass, strong stage, rank-250 trigram stage',
  (select bool_and(prosrc like '%$blank$%' and prosrc like '%$strong$%' and prosrc like '%$fuzzy$%'
                   and prosrc like '%rank = 250::double precision%')
   from pg_proc where oid in (
     'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
     'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'::regprocedure)));
select tests.ok('definer, plpgsql, search_path, jit off and similarity_threshold exactly 0.35 (20261109123758 kept)',
  (select bool_and(prosecdef and proconfig @> array['search_path=public, extensions','jit=off','pg_trgm.similarity_threshold=0.35']
                   and not (proconfig @> array['pg_trgm.similarity_threshold=0.3']))
   from pg_proc where oid in (
     'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
     'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'::regprocedure)));
select tests.ok('anon and authenticated keep EXECUTE on both Search functions',
  has_function_privilege('anon', 'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and has_function_privilege('anon', 'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)', 'execute'));

-- ---- 2. rows: 35 strong + 50 fuzzy per medium, plus filler ------------------------------
-- Strong: 'Kuroshiro Saga n' (prefix, 500). Fuzzy: 'Kuroshir n' (no substring/word/full-text
-- match, trigram similarity >= 0.35). Fuzzy rows are MORE popular than strong rows, so only the
-- rank (never popularity) can put the strong rows first. Scores and years vary (90 / 70; 2005 /
-- this year / 2024) so every filter flag has matching strong AND fuzzy rows.
set local session_replication_role = replica;
insert into public.anime (id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, episodes, season_year, start_date_year)
select 1050000 + n, 'Kuroshiro Saga ' || n, null, 'TV', case when n % 2 = 0 then 'RELEASING' else 'FINISHED' end,
       1000 + n, n, case when n % 3 = 0 then 90 else 70 end, array['Action'], false, 12,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end from generate_series(1, 35) n
union all
select 1050100 + n, 'Kuroshir ' || n, null, 'TV', case when n % 2 = 0 then 'RELEASING' else 'FINISHED' end,
       5000 + n, n, case when n % 3 = 0 then 90 else 70 end, array['Action'], false, 12,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end from generate_series(1, 50) n
union all
select 1051000 + n, 'Filler story ' || n, 'Plain title ' || n, 'TV', 'FINISHED', n % 900, n % 50, 60, array['Drama'], false, 12, 2000 + n % 20, 2000 + n % 20
from generate_series(1, 3000) n;
insert into public.manga (id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, chapters, start_date_year)
select 1050000 + n, 'Kuroshiro Saga ' || n, null, 'MANGA', 'FINISHED', 1000 + n, n, case when n % 3 = 0 then 90 else 70 end, array['Action'], false, 40,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end from generate_series(1, 35) n
union all
select 1050100 + n, 'Kuroshir ' || n, null, 'MANGA', 'FINISHED', 5000 + n, n, case when n % 3 = 0 then 90 else 70 end, array['Action'], false, 40,
       case n % 3 when 0 then 2005 when 1 then extract(year from now())::int else 2024 end from generate_series(1, 50) n
union all
select 1051000 + n, 'Filler story ' || n, 'Plain title ' || n, 'MANGA', 'FINISHED', n % 900, n % 50, 60, array['Drama'], false, 40, 2000 + n % 20
from generate_series(1, 3000) n;
set local session_replication_role = origin;
analyze public.anime;
analyze public.manga;

create temporary table staged_results (name text, passed boolean);
do $boundary$
declare
  med text; p1 jsonb; p2 jsonb; p3 jsonb; p4 jsonb; o1 jsonb; o2 jsonb; o3 jsonb; c jsonb;
  self_strong bigint; self_fuzzy bigint; all_ids int[];
begin
  foreach med in array array['anime','manga'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'', p_limit=>30) x', med) into p1;
    c := p1 -> -1;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'', p_limit=>30, p_cursor_rank=>$1, p_cursor_popularity=>$2, p_cursor_id=>$3) x', med)
      into p2 using (c->>'rank')::float8, (c->>'popularity')::int, (c->>'id')::int;
    c := p2 -> -1;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'', p_limit=>30, p_cursor_rank=>$1, p_cursor_popularity=>$2, p_cursor_id=>$3) x', med)
      into p3 using (c->>'rank')::float8, (c->>'popularity')::int, (c->>'id')::int;
    c := p3 -> -1;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'', p_limit=>30, p_cursor_rank=>$1, p_cursor_popularity=>$2, p_cursor_id=>$3) x', med)
      into p4 using (c->>'rank')::float8, (c->>'popularity')::int, (c->>'id')::int;

    insert into staged_results values ('page 1 '||med||' = 30 strong rows',
      jsonb_array_length(p1) = 30 and (select bool_and((e->>'rank')::float8 >= 320) from jsonb_array_elements(p1) e));
    insert into staged_results values ('page 2 '||med||' = last 5 strong, then 25 fuzzy only',
      jsonb_array_length(p2) = 30
      and (select bool_and((e->>'rank')::float8 >= 320) from jsonb_array_elements(p2) with ordinality t(e, o) where o <= 5)
      and (select bool_and((e->>'rank')::float8 = 250) from jsonb_array_elements(p2) with ordinality t(e, o) where o > 5));
    insert into staged_results values ('page 3 '||med||' = 25 fuzzy (cursor starts in the fuzzy region), page 4 empty',
      jsonb_array_length(p3) = 25 and (select bool_and((e->>'rank')::float8 = 250) from jsonb_array_elements(p3) e)
      and jsonb_array_length(p4) = 0);
    select array_agg((e->>'id')::int) into all_ids
      from (select e from jsonb_array_elements(p1) e union all select e from jsonb_array_elements(p2) e
            union all select e from jsonb_array_elements(p3) e) s;
    insert into staged_results values ('pages 1-3 '||med||' cover all 85 rows with no repeats',
      cardinality(all_ids) = 85 and (select count(distinct x) from unnest(all_ids) x) = 85);

    -- Same pages from the old single-pass body, with the old body's own cursors.
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>''kuroshiro'', p_limit=>30) x', med) into o1;
    c := o1 -> -1;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>''kuroshiro'', p_limit=>30, p_cursor_rank=>$1, p_cursor_popularity=>$2, p_cursor_id=>$3) x', med)
      into o2 using (c->>'rank')::float8, (c->>'popularity')::int, (c->>'id')::int;
    c := o2 -> -1;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>''kuroshiro'', p_limit=>30, p_cursor_rank=>$1, p_cursor_popularity=>$2, p_cursor_id=>$3) x', med)
      into o3 using (c->>'rank')::float8, (c->>'popularity')::int, (c->>'id')::int;
    insert into staged_results values ('pages 1-3 '||med||' are identical to the old single-pass body', p1 = o1 and p2 = o2 and p3 = o3);
    -- Fixture self-check (old single-pass ranking, paged; one page is capped at 50 rows):
    -- exactly 35 strong and 50 fuzzy rows exist, so the boundary case is not vacuous.
    select count(*) filter (where (e->>'rank')::float8 >= 320), count(*) filter (where (e->>'rank')::float8 = 250)
      into self_strong, self_fuzzy
      from (select e from jsonb_array_elements(o1) e union all select e from jsonb_array_elements(o2) e
            union all select e from jsonb_array_elements(o3) e) s;
    insert into staged_results values ('fixture self-check '||med||' 35 strong / 50 fuzzy', self_strong = 35 and self_fuzzy = 50);
  end loop;
end;
$boundary$;

-- ---- 3. filters with blank and non-blank queries match the old body ---------------------
do $filters$
declare med text; flag text; q text; old jsonb; new jsonb;
begin
  foreach med in array array['anime','manga'] loop
    foreach q in array array['', 'kuroshiro', 'kuroshir'] loop
      foreach flag in array array['p_trending','p_new_season','p_classics','p_hidden_gems'] loop
        execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>$1,%I=>true,p_limit=>30) x', med, flag) into old using q;
        execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,%I=>true,p_limit=>30) x', med, flag) into new using q;
        insert into staged_results values ('filter '||med||' '||flag||' query '''||q||''' (non-empty)', old = new and jsonb_array_length(new) > 0);
      end loop;
    end loop;
  end loop;
  -- anime-only filters (airing, season)
  foreach q in array array['', 'kuroshiro'] loop
    execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_anime_page(p_query=>$1,p_airing_only=>true,p_limit=>30) x' into old using q;
    execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_anime_page(p_query=>$1,p_airing_only=>true,p_limit=>30) x' into new using q;
    insert into staged_results values ('filter anime airing query '''||q||'''', old = new and jsonb_array_length(new) > 0);
    execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_anime_page(p_query=>$1,p_season_year=>2024,p_limit=>30) x' into old using q;
    execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_anime_page(p_query=>$1,p_season_year=>2024,p_limit=>30) x' into new using q;
    insert into staged_results values ('filter anime season_year query '''||q||'''', old = new and jsonb_array_length(new) > 0);
  end loop;
  -- an explicit cursor inside the fuzzy region (the strong stage is skipped)
  execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_anime_page(p_query=>$1,p_limit=>10,p_cursor_rank=>250,p_cursor_popularity=>5040,p_cursor_id=>1050140) x' into old using 'kuroshiro';
  execute 'select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_anime_page(p_query=>$1,p_limit=>10,p_cursor_rank=>250,p_cursor_popularity=>5040,p_cursor_id=>1050140) x' into new using 'kuroshiro';
  insert into staged_results values ('explicit fuzzy-region cursor matches the old body', old = new and jsonb_array_length(new) = 10);
end;
$filters$;

-- ---- 3b. edge parameters across the stage boundary match the old body --------------------
do $edges$
declare med text; lim int; old jsonb; new jsonb; q text; cr float8; cp int; ci int; i int;
  cursors float8[] := array[500, 500, 250, null, 400];
  pops int[] := array[null, 1020, null, 1020, 1000];
  ids int[] := array[1050020, null, 1050140, 1050020, 0];
begin
  foreach med in array array['anime','manga'] loop
    foreach lim in array array[null, 0, -5, 1, 34, 36, 51, 200] loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>''kuroshiro'',p_limit=>$1) x', med) into old using lim;
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'',p_limit=>$1) x', med) into new using lim;
      insert into staged_results values ('limit '||med||' '||coalesce(lim::text,'null'), old = new and jsonb_array_length(new) > 0);
    end loop;
    for i in 1..array_length(cursors, 1) loop
      cr := cursors[i]; cp := pops[i]; ci := ids[i];
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>''kuroshiro'',p_limit=>30,p_cursor_rank=>$1,p_cursor_popularity=>$2,p_cursor_id=>$3) x', med) into old using cr, cp, ci;
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>''kuroshiro'',p_limit=>30,p_cursor_rank=>$1,p_cursor_popularity=>$2,p_cursor_id=>$3) x', med) into new using cr, cp, ci;
      insert into staged_results values (format('cursor %s (%s,%s,%s)', med, cr, cp, ci), old = new);
    end loop;
    -- wildcards and short queries (1-4 chars never reach the trigram stage)
    foreach q in array array['%', '_', 'kuro_hir', 'kuroshir%', 'kur', 'k', 'KUROSHIRO', '  kuroshiro  '] loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>$1,p_limit=>50) x', med) into old using q;
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,p_limit=>50) x', med) into new using q;
      insert into staged_results values ('query '||med||' '||quote_literal(q), old = new);
    end loop;
  end loop;
end;
$edges$;
do $report$ declare r record; begin
  for r in select name from staged_results where not passed loop raise notice 'STAGED CHECK FAILED: %', r.name; end loop;
end $report$;
select tests.eq('every staged Search check passes', (select count(*) from staged_results where not passed), 0::bigint);
select tests.eq('staged Search checks executed', (select count(*) from staged_results), 83::bigint);

-- ---- 4. plans: blank query uses the popularity index; strong stage never runs trigram % ------
create temporary table staged_plans (medium text, stage text, plan jsonb);
do $plans$
declare med text; src text; q text; plan jsonb; i integer; stage text; term text;
begin
  foreach med in array array['anime','manga'] loop
    select prosrc into src from pg_proc where proname = 'search_' || med || '_page' and pronamespace = 'public'::regnamespace;
    foreach stage in array array['blank','strong','fuzzy'] loop
      q := split_part(src, '$' || stage || '$', 2);
      for i in reverse 13..3 loop
        q := replace(q, '$' || i::text, case when i between 6 and 10 and not (med = 'manga' and i = 10) then 'false'
                                             when i = 13 or (med = 'manga' and i = 10) then '30' else 'null' end);
      end loop;
      term := case when stage = 'blank' then '' when stage = 'strong' then 'kuroshiro' else 'kuroshrio' end;
      q := replace(replace(q, '$2', '30'), '$1', quote_literal(term));
      execute 'explain (format json) ' || q into plan;
      insert into staged_plans values (med, stage, plan);
    end loop;
  end loop;
end;
$plans$;
select tests.ok('blank-query pass reads idx_<medium>_load_popular_v1 in order (no Sort, no trigram scan)',
  (select count(*) = 2 from staged_plans where stage = 'blank'
     and plan::text like '%"Index Name": "idx_' || medium || '_load_popular_v1"%'
     and plan::text not like '%"Node Type": "Sort"%'));
-- (The rank CASE in the output list still names similarity(); it is never reached for strong
-- rows. What matters is that no scan condition or filter uses the trigram operator.)
select tests.ok('strong stage: no scan condition or filter uses the trigram % operator or similarity()',
  (select count(distinct medium) = 2 from staged_plans where stage = 'strong')
  and not exists (
    select 1 from staged_plans sp, jsonb_path_query(sp.plan, 'strict $.**') v
    where sp.stage = 'strong' and jsonb_typeof(v) = 'object'
      and (coalesce(v ->> 'Filter', '') || coalesce(v ->> 'Index Cond', '') || coalesce(v ->> 'Recheck Cond', '')) ~ '(similarity\(| % )'));
select tests.ok('control: the same scan in the fuzzy stage does use the trigram operator (the check above can fail)',
  (select count(distinct sp.medium) = 2 from staged_plans sp, jsonb_path_query(sp.plan, 'strict $.**') v
    where sp.stage = 'fuzzy' and jsonb_typeof(v) = 'object'
      and (coalesce(v ->> 'Filter', '') || coalesce(v ->> 'Index Cond', '') || coalesce(v ->> 'Recheck Cond', '')) ~ ' % '));
\o
select medium, stage, plan from staged_plans;
\o /dev/null
rollback;
