-- 2026-11-10 fix-forward for 20261109200100_search_titles_topn_v1 (applied 2026-11-10 09:40 UTC).
-- Owner approved deploying the backend latency plan 2026-11-10 ("do it all"); this corrects a
-- production regression found by the post-deployment timing (docs/plans/latency-deploy-2026-11-10/).
--
-- What production showed (read-only EXPLAIN ANALYZE, 2026-11-10):
-- * The old InitPlan body already used idx_title_search_title_norm_trgm in production (the full
--   scan seen on the local fixture was a fixture statistics effect, not production behaviour).
-- * A non-inlined SQL function is planned with p_query as an unknown parameter, so the 200100 body
--   recomputed normalize_title(p_query) for every rechecked row (~1,100 for 'naruto'): live calls
--   went from ~21 ms to ~32 ms ('naruto'), ~20 to ~26 ms ('attack on titan').
-- Fix: PL/pgSQL computes normalize_title(p_query) once and runs the query with RETURN QUERY EXECUTE
-- ... USING, so every call is planned with the normalized value known (the same pattern as
-- search_anime_page / search_manga_page) and the trigram index is chosen from real selectivity. Kept from
-- 200100: top N candidates before the anime / manga joins, and the title_search.id tie-breaker.
-- Measured on production with prepared statements: 'naruto' generic plan 14.9 ms / custom 14.2 ms
-- (old body 15.9 / 16.9, 200100 body 25.6 / 13.1).
-- Same signature, return type, invoker security, volatility and search_path; CREATE OR REPLACE
-- keeps the grants. The language changes from sql to plpgsql (allowed for OR REPLACE).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
set local search_path = public, extensions;

create or replace function public.search_titles(
  p_query text,
  p_media_type text default null,
  p_limit integer default 12
)
returns table (
  media_type text,
  media_id integer,
  variant_type text,
  title_raw text,
  score real,
  year integer,
  format text,
  cover_image_medium text
)
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  v_q text := public.normalize_title(p_query);
begin
  -- EXECUTE ... USING plans each call with the normalized value known (like search_*_page): a cached
  -- generic plan cannot see the value, and on skewed statistics it may choose a full scan.
  return query execute $q$
  with top_candidates as (
    select
      ts.id,
      ts.media_type,
      ts.media_id,
      ts.variant_type,
      ts.title_raw,
      ts.popularity,
      similarity(ts.title_norm, $1)::real as cand_score
    from public.title_search ts
    where ($2::text is null or ts.media_type = $2)
      and ts.title_norm % $1
    order by cand_score desc, ts.popularity desc nulls last, ts.id
    limit greatest(1, least($3, 50))
  )
  select
    t.media_type,
    t.media_id,
    t.variant_type,
    t.title_raw,
    t.cand_score,
    coalesce(a.start_date_year, m.start_date_year),
    coalesce(a.format, m.format),
    coalesce(a.cover_image_medium, m.cover_image_medium)
  from top_candidates t
  left join public.anime a
    on t.media_type = 'ANIME' and a.id = t.media_id
  left join public.manga m
    on t.media_type = 'MANGA' and m.id = t.media_id
  order by t.cand_score desc, t.popularity desc nulls last, t.id
  $q$ using v_q, p_media_type, p_limit;
end;
$$;

notify pgrst, 'reload schema';
commit;
