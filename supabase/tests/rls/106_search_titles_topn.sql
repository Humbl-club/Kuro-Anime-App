-- 106_search_titles_topn.sql
-- 20261109200100_search_titles_topn_v1.sql + fix-forward 20261110100000_search_titles_param_v1.sql
-- (both applied 2026-11-10): search_titles picks the top N title_search candidates before joining
-- anime / manga, breaks ties by title_search.id, and (PL/pgSQL) normalizes the query once.
-- Differential against the live pre-change body (read-only pg_get_functiondef 2026-11-09,
-- installed below as pg_temp.old_search_titles): same rows and scores; ordering compared with
-- tie groups treated as sets (the old order inside a tie was unspecified). Then the intended
-- change: tied rows at the limit boundary are the lowest ids, in id order, on every call.
-- @requires table public.title_search
-- @requires table public.anime
-- @requires table public.manga
-- @requires function public.normalize_title(text)
-- @requires function public.search_titles(text,text,integer)
\set ON_ERROR_STOP on
\o /dev/null
begin;
set local jit = off;
select tests.reset();

create function pg_temp.old_search_titles(p_query text, p_media_type text default null, p_limit integer default 12)
returns table (media_type text, media_id integer, variant_type text, title_raw text, score real, year integer, format text, cover_image_medium text)
language sql stable set search_path to 'public', 'extensions' as $$
  with q as (
    select public.normalize_title(p_query) as qn
  )
  select
    ts.media_type,
    ts.media_id,
    ts.variant_type,
    ts.title_raw,
    similarity(ts.title_norm, (select qn from q))::real as score,
    coalesce(a.start_date_year, m.start_date_year) as year,
    coalesce(a.format, m.format) as format,
    coalesce(a.cover_image_medium, m.cover_image_medium) as cover_image_medium
  from public.title_search ts
  cross join q
  left join public.anime a
    on ts.media_type = 'ANIME' and a.id = ts.media_id
  left join public.manga m
    on ts.media_type = 'MANGA' and m.id = ts.media_id
  where (p_media_type is null or ts.media_type = p_media_type)
    and ts.title_norm % (select qn from q)
  order by score desc, ts.popularity desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;

-- ---- 1. posture ----------------------------------------------------------------------
select tests.ok('search_titles: plpgsql, stable, invoker, search_path = public, extensions; query normalized once; top-N before joins; id tie-breaker',
  (select prolang = (select oid from pg_language where lanname = 'plpgsql') and provolatile = 's' and not prosecdef
          and proconfig @> array['search_path=public, extensions']
          and prosrc like '%v_q text := public.normalize_title(p_query);%'
          and prosrc like '%top_candidates%' and prosrc like '%order by cand_score desc, ts.popularity desc nulls last, ts.id%'
          and prosrc like '%return query execute%' and prosrc like '%using v_q, p_media_type, p_limit%'
          and prosrc like '%ts.title_norm \% $1%' and prosrc not like '%\% public.normalize_title(p_query)%'
          and prosrc not like '%select qn from q%'
   from pg_proc where oid = 'public.search_titles(text,text,integer)'::regprocedure));
select tests.ok('anon and authenticated keep EXECUTE on search_titles',
  has_function_privilege('anon', 'public.search_titles(text,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.search_titles(text,text,integer)', 'execute'));

-- ---- 2. rows (production-sized: 72k title variants, 22k titles per medium) ------------------
set local session_replication_role = replica;
insert into public.anime (id, title_romaji, format, status, popularity, genres, is_adult, start_date_year, cover_image_medium)
select 1060000 + n, 'Anime ' || n, case when n % 3 = 0 then 'MOVIE' else 'TV' end, 'FINISHED', n % 500, array['Action'], false, 1990 + n % 30,
       'https://img.invalid/a' || n || '.jpg'
from generate_series(1, 22000) n;
insert into public.manga (id, title_romaji, format, status, popularity, genres, is_adult, start_date_year, cover_image_medium)
select 1060000 + n, 'Manga ' || n, 'MANGA', 'FINISHED', n % 500, array['Drama'], false, 1990 + n % 30, 'https://img.invalid/m' || n || '.jpg'
from generate_series(1, 22000) n;
set local session_replication_role = origin;
-- Title variants: a few distinctive titles, many near-duplicates (large candidate sets), NULL
-- popularity, and exact ties (same title_norm and popularity) to exercise the tie-breaker.
insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, popularity)
select case when n % 2 = 0 then 'ANIME' else 'MANGA' end, 1060000 + (n % 22000) + 1,
       case n % 3 when 0 then 'english' when 1 then 'romaji' else 'synonym' end,
       t, public.normalize_title(t), case when n % 17 = 0 then null else n % 300 end
from (select n, case
        when n % 101 = 0 then 'Naruto Shippuden ' || (n % 7)
        when n % 103 = 0 then 'Attack on Titan Season ' || (n % 5)
        when n % 5 = 0 then 'Love Live ' || n
        else 'Generic story ' || n end as t
      from generate_series(1, 72000) n) s;
-- exact ties: five identical rows (same norm, same popularity)
insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, popularity)
select 'ANIME', 1060000 + n, 'alias', 'Kurotie', 'kurotie', 42 from generate_series(1, 5) n;
analyze public.title_search;

-- ---- 3. differential: same rows/scores; order equal up to tie groups ----------------------
create temporary table titles_results (name text, passed boolean);
do $diff$
declare q text; mt text; lim int; old jsonb; new jsonb; old_sorted jsonb; new_sorted jsonb; n_old int; ref jsonb;
begin
  foreach q in array array['naruto', 'naruto shipuden', 'attack on titan', 'love live', 'generic story 12', 'kurotie', 'xyzzyq', '', 'AOT', 'Shingeki'] loop
    foreach mt in array array[null, 'ANIME', 'MANGA'] loop
      foreach lim in array array[6, 12, 50] loop
        select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('o', o) order by o), '[]') into old
          from pg_temp.old_search_titles(q, mt, lim) with ordinality as x(media_type, media_id, variant_type, title_raw, score, year, format, cover_image_medium, o);
        select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('o', o) order by o), '[]') into new
          from public.search_titles(q, mt, lim) with ordinality as x(media_type, media_id, variant_type, title_raw, score, year, format, cover_image_medium, o);
        n_old := jsonb_array_length(old);
        -- Compare full rows; inside equal (score) groups compare as sets. A tie group that straddles
        -- the limit may legitimately differ in WHICH tied rows were returned (old: arbitrary), so
        -- such a straddling group is compared by size only.
        select coalesce(jsonb_agg(e - 'o' order by (e->>'score')::real desc, (e - 'o')::text), '[]') into old_sorted
          from jsonb_array_elements(old) e
          where n_old < lim or (e->>'score')::real > (select min((x->>'score')::real) from jsonb_array_elements(old) x);
        select coalesce(jsonb_agg(e - 'o' order by (e->>'score')::real desc, (e - 'o')::text), '[]') into new_sorted
          from jsonb_array_elements(new) e
          where n_old < lim or (e->>'score')::real > (select min((x->>'score')::real) from jsonb_array_elements(new) x);
        -- Exact expected order, written independently: score, then popularity (nulls last), then id.
        select coalesce(jsonb_agg(jsonb_build_object('media_type', ts.media_type, 'media_id', ts.media_id, 'variant_type', ts.variant_type,
                                                     'title_raw', ts.title_raw)
                                  order by similarity(ts.title_norm, public.normalize_title(q)) desc, ts.popularity desc nulls last, ts.id), '[]')
          into ref
          from (select * from public.title_search ts0
                where (mt is null or ts0.media_type = mt) and ts0.title_norm % public.normalize_title(q)
                order by similarity(ts0.title_norm, public.normalize_title(q)) desc, ts0.popularity desc nulls last, ts0.id
                limit greatest(1, least(lim, 50))) ts;
        insert into titles_results values (format('exact order q=%L mt=%s lim=%s', q, coalesce(mt, 'any'), lim),
          ref = (select coalesce(jsonb_agg(jsonb_build_object('media_type', e->>'media_type', 'media_id', (e->>'media_id')::int,
                                                              'variant_type', e->>'variant_type', 'title_raw', e->>'title_raw') order by (e->>'o')::int), '[]')
                 from jsonb_array_elements(new) e));
        insert into titles_results values (format('q=%L mt=%s lim=%s', q, coalesce(mt, 'any'), lim),
          jsonb_array_length(new) = n_old
          and old_sorted = new_sorted
          -- scores are non-increasing in the new order
          and not exists (select 1 from jsonb_array_elements(new) a, jsonb_array_elements(new) b
                           where (a->>'o')::int < (b->>'o')::int and (a->>'score')::real < (b->>'score')::real));
      end loop;
    end loop;
  end loop;
end;
$diff$;
do $report$ declare r record; begin
  for r in select name from titles_results where not passed loop raise notice 'TITLES CHECK FAILED: %', r.name; end loop;
end $report$;
select tests.eq('every search_titles differential case matches (tie groups as sets)', (select count(*) from titles_results where not passed), 0::bigint);
select tests.eq('search_titles differential cases executed', (select count(*) from titles_results), 180::bigint);
select tests.ok('the differential covers large candidate sets (a limited page is full) and empty results',
  (select count(*) from public.search_titles('generic story 12', null, 50)) = 50
  and (select count(*) from public.search_titles('xyzzyq', null, 50)) = 0);

-- ---- 4. intended change: ties are broken by title_search.id, stably ---------------------------
select tests.eq('limit 2 over five exact ties returns the two lowest title_search ids, in id order',
  (select array_agg(media_id order by o) from public.search_titles('kurotie', 'ANIME', 2) with ordinality x(media_type, media_id, variant_type, title_raw, score, year, format, cover_image_medium, o)),
  (select array_agg(media_id order by id) from (select id, media_id from public.title_search where title_norm = 'kurotie' order by id limit 2) s));
select tests.ok('repeated calls return the same rows in the same order',
  (select bool_and(r = (select jsonb_agg(to_jsonb(x)) from public.search_titles('love live', null, 12) x))
     from (select (select jsonb_agg(to_jsonb(x)) from public.search_titles('love live', null, 12) x) r from generate_series(1, 5)) s));
select tests.ok('cards still carry year, format and cover from the joined medium',
  (select bool_and(year is not null and format is not null and cover_image_medium is not null) from public.search_titles('naruto shippuden', null, 12)));

-- ---- 5. access path, observed on the real function calls -----------------------------------
-- Per-transaction table statistics (pg_stat_xact_user_tables) count the scans each call makes on
-- title_search. EXECUTE ... USING plans the call with the normalized value known, so a selective
-- term ('kurotie', 5 rows) reads the trigram index; the former InitPlan form hides the value and,
-- on this fixture's statistics, scans the whole table (control, proves the counter discriminates).
-- Planner-dependent by nature: for broad terms a full scan can be the right plan. Production
-- timings for the access path are in docs/plans/latency-deploy-2026-11-10/.
create temporary table titles_scans (form text, seq bigint, idx bigint);
do $s$
declare s0 bigint; i0 bigint; s1 bigint; i1 bigint; n int;
begin
  select seq_scan, coalesce(idx_scan, 0) into s0, i0 from pg_stat_xact_user_tables where relid = 'public.title_search'::regclass;
  select count(*) into n from public.search_titles('kurotie', null, 6);
  select seq_scan, coalesce(idx_scan, 0) into s1, i1 from pg_stat_xact_user_tables where relid = 'public.title_search'::regclass;
  insert into titles_scans values ('direct', s1 - s0, i1 - i0);
  select count(*) into n from pg_temp.old_search_titles('kurotie', null, 6);
  select seq_scan, coalesce(idx_scan, 0) into s0, i0 from pg_stat_xact_user_tables where relid = 'public.title_search'::regclass;
  insert into titles_scans values ('initplan', s0 - s1, i0 - i1);
end;
$s$;
select tests.ok('search_titles reads title_search through the trigram index (no sequential scan)',
  (select seq = 0 and idx >= 1 from titles_scans where form = 'direct'));
select tests.ok('control: the former InitPlan body scans title_search sequentially',
  (select seq >= 1 from titles_scans where form = 'initplan'));
rollback;
