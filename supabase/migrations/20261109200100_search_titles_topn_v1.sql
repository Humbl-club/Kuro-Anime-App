-- Prepared 2026-11-09 (docs/plans/2026-11-09-backend-latency-plan.md step 1b).
-- Owner approved deployment to production 2026-11-10 ("do it all").
--
-- search_titles (Concierge parse / recommend seed lookup):
-- 1. The trigram filter compares against normalize_title(p_query) directly instead of an InitPlan
--    `(select qn from q)`. With the InitPlan the planner cannot use idx_title_search_title_norm_trgm
--    and scans all of title_search (72,560 rows live) on every call: on the local fixture a
--    no-match lookup took ~57 ms (seq scan) vs ~1.7 ms (bitmap index scan); a distinctive title
--    ~58 ms vs ~4-6 ms. Trade-off: a query whose trigrams match most of the table (synthetic
--    'story' over 57k matching rows) is ~25% slower through the index. normalize_title is
--    IMMUTABLE, so the value is the same as before.
-- 2. Choose the top N candidates first, then join anime / manga only for those N rows. The joins
--    are on primary keys and neither filter nor multiply rows, so the returned set is unchanged.
-- One intended change: ties after `score desc, popularity desc nulls last` were unordered (and at
-- the limit boundary, which tied rows were returned was arbitrary); they are now broken by
-- title_search.id ascending, so repeated calls return the same rows in the same order.
-- Same signature, return type, language (sql), invoker security and search_path as the live
-- definition (read-only pg_get_functiondef 2026-11-09), so CREATE OR REPLACE keeps the grants.
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
language sql
stable
set search_path = public, extensions
as $$
  with top_candidates as (
    select
      ts.id,
      ts.media_type,
      ts.media_id,
      ts.variant_type,
      ts.title_raw,
      ts.popularity,
      similarity(ts.title_norm, public.normalize_title(p_query))::real as score
    from public.title_search ts
    where (p_media_type is null or ts.media_type = p_media_type)
      and ts.title_norm % public.normalize_title(p_query)
    order by score desc, ts.popularity desc nulls last, ts.id
    limit greatest(1, least(p_limit, 50))
  )
  select
    t.media_type,
    t.media_id,
    t.variant_type,
    t.title_raw,
    t.score,
    coalesce(a.start_date_year, m.start_date_year) as year,
    coalesce(a.format, m.format) as format,
    coalesce(a.cover_image_medium, m.cover_image_medium) as cover_image_medium
  from top_candidates t
  left join public.anime a
    on t.media_type = 'ANIME' and a.id = t.media_id
  left join public.manga m
    on t.media_type = 'MANGA' and m.id = t.media_id
  order by t.score desc, t.popularity desc nulls last, t.id;
$$;

notify pgrst, 'reload schema';
commit;
