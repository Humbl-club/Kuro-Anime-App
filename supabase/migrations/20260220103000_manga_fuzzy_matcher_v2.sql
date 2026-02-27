-- Manga fuzzy matcher v2: persistent verification memory, candidate prioritization,
-- scorecard metrics, and review auto-expiry housekeeping.

begin;

-- ---------------------------------------------------------------------------
-- 1) Mapping verification memory fields
-- ---------------------------------------------------------------------------
alter table if exists public.manga_source_links
  add column if not exists last_verified_at timestamptz;

alter table if exists public.manga_source_links
  add column if not exists next_verify_at timestamptz not null default now();

alter table if exists public.manga_source_links
  add column if not exists verify_status text not null default 'unverified'
    check (verify_status in ('unverified', 'ok', 'mismatch', 'not_found', 'rate_limited'));

alter table if exists public.manga_source_links
  add column if not exists verify_fail_count smallint not null default 0;

alter table if exists public.manga_source_links
  add column if not exists last_verify_reason text;

create index if not exists idx_manga_source_links_status_next_verify_at
  on public.manga_source_links(status, next_verify_at);

create index if not exists idx_manga_source_links_manga_provider_status_next_verify
  on public.manga_source_links(manga_id, provider, status, next_verify_at);

-- ---------------------------------------------------------------------------
-- 2) Candidate selector update (includes due verification priority class)
-- ---------------------------------------------------------------------------
create or replace function public.get_manga_chapter_enrich_candidates(
  p_limit integer default 20,
  p_force_manga_id integer default null
)
returns table (
  id integer,
  anilist_id integer,
  mal_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  title_synonyms text[],
  status text,
  chapters integer,
  last_synced_at timestamptz,
  chapter_row_count integer,
  priority_class integer
)
language sql
security definer
set search_path = public
as $$
  with chapter_counts as (
    select c.manga_id, count(*)::integer as chapter_row_count
    from public.chapters c
    group by c.manga_id
  ),
  active_mappings as (
    select
      msl.manga_id,
      min(msl.next_verify_at) as next_verify_at
    from public.manga_source_links msl
    where msl.provider = 'mangadex'
      and msl.status = 'active'
    group by msl.manga_id
  ),
  prioritized as (
    select
      m.id,
      m.anilist_id,
      m.mal_id,
      m.title_english,
      m.title_romaji,
      m.title_native,
      m.title_synonyms,
      m.status,
      m.chapters,
      m.last_synced_at,
      coalesce(cc.chapter_row_count, 0) as chapter_row_count,
      case
        when p_force_manga_id is not null and m.id = p_force_manga_id then 0
        when coalesce(cc.chapter_row_count, 0) = 0 then 1
        when m.status = 'RELEASING'
          and (m.last_synced_at is null or m.last_synced_at < now() - interval '24 hours') then 2
        when m.chapters is not null and coalesce(cc.chapter_row_count, 0) < m.chapters then 3
        when am.next_verify_at is not null and am.next_verify_at <= now() then 4
        else 99
      end as priority_class
    from public.manga m
    left join chapter_counts cc on cc.manga_id = m.id
    left join active_mappings am on am.manga_id = m.id
    where p_force_manga_id is null or m.id = p_force_manga_id
  )
  select
    p.id,
    p.anilist_id,
    p.mal_id,
    p.title_english,
    p.title_romaji,
    p.title_native,
    p.title_synonyms,
    p.status,
    p.chapters,
    p.last_synced_at,
    p.chapter_row_count,
    p.priority_class
  from prioritized p
  where p.priority_class < 99
  order by
    p.priority_class asc,
    coalesce(p.last_synced_at, to_timestamp(0)) asc,
    p.id asc
  limit greatest(1, least(coalesce(p_limit, 20), 200));
$$;

revoke all on function public.get_manga_chapter_enrich_candidates(integer, integer)
  from public, anon, authenticated;
grant execute on function public.get_manga_chapter_enrich_candidates(integer, integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3) Quality scorecard RPC for fuzzy matcher operations
-- ---------------------------------------------------------------------------
create or replace function public.get_manga_match_quality_metrics(
  p_hours integer default 24
)
returns table (
  processed bigint,
  auto_resolved bigint,
  auto_resolve_rate_pct numeric(7,3),
  unresolved bigint,
  wrong_map_proxy_count bigint,
  wrong_map_proxy_rate_pct numeric(7,3),
  fuzzy_auto_rate_pct numeric(7,3),
  verify_checked bigint,
  verify_deactivated bigint,
  pending_review_count bigint
)
language sql
security definer
set search_path = public
as $$
  with windowed as (
    select now() - make_interval(hours => greatest(1, coalesce(p_hours, 24))) as starts_after
  ),
  runs as (
    select
      coalesce(
        sum(case when coalesce(r.results->>'manga_processed', '') ~ '^[0-9]+$'
          then (r.results->>'manga_processed')::bigint else 0 end),
        0
      )::bigint as processed,
      coalesce(
        sum(case when coalesce(r.results->>'unresolved_mappings', '') ~ '^[0-9]+$'
          then (r.results->>'unresolved_mappings')::bigint else 0 end),
        0
      )::bigint as unresolved,
      coalesce(
        sum(case when coalesce(r.results->>'fuzzy_auto_mapped', '') ~ '^[0-9]+$'
          then (r.results->>'fuzzy_auto_mapped')::bigint else 0 end),
        0
      )::bigint as fuzzy_auto_mapped,
      coalesce(
        sum(case when coalesce(r.results->>'wrong_map_proxy_count', '') ~ '^[0-9]+$'
          then (r.results->>'wrong_map_proxy_count')::bigint else 0 end),
        0
      )::bigint as wrong_map_proxy_count,
      coalesce(
        sum(case when coalesce(r.results->>'verify_checked', '') ~ '^[0-9]+$'
          then (r.results->>'verify_checked')::bigint else 0 end),
        0
      )::bigint as verify_checked,
      coalesce(
        sum(case when coalesce(r.results->>'verify_deactivated', '') ~ '^[0-9]+$'
          then (r.results->>'verify_deactivated')::bigint else 0 end),
        0
      )::bigint as verify_deactivated
    from public.import_runs r
    cross join windowed w
    where r.media_type = 'MANGA'
      and r.run_type = 'chapter_enrich'
      and r.started_at >= w.starts_after
  ),
  pending as (
    select count(*)::bigint as pending_review_count
    from public.manga_source_link_review
    where status = 'pending'
  ),
  calc as (
    select
      runs.processed,
      greatest(runs.processed - runs.unresolved, 0)::bigint as auto_resolved,
      runs.unresolved,
      runs.fuzzy_auto_mapped,
      runs.wrong_map_proxy_count,
      runs.verify_checked,
      runs.verify_deactivated,
      pending.pending_review_count
    from runs
    cross join pending
  )
  select
    calc.processed,
    calc.auto_resolved,
    coalesce(round(100.0 * calc.auto_resolved / nullif(calc.processed, 0), 3), 0)::numeric(7,3) as auto_resolve_rate_pct,
    calc.unresolved,
    calc.wrong_map_proxy_count,
    coalesce(round(100.0 * calc.wrong_map_proxy_count / nullif(calc.processed, 0), 3), 0)::numeric(7,3) as wrong_map_proxy_rate_pct,
    coalesce(round(100.0 * calc.fuzzy_auto_mapped / nullif(calc.auto_resolved, 0), 3), 0)::numeric(7,3) as fuzzy_auto_rate_pct,
    calc.verify_checked,
    calc.verify_deactivated,
    calc.pending_review_count
  from calc;
$$;

revoke all on function public.get_manga_match_quality_metrics(integer)
  from public, anon, authenticated;
grant execute on function public.get_manga_match_quality_metrics(integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4) No-manual-review housekeeping: auto-expire stale review rows daily
-- ---------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'manga-source-review-auto-expire-daily';
exception
  when undefined_table then
    null;
end $$;

select cron.schedule(
  'manga-source-review-auto-expire-daily',
  '20 4 * * *',
  $$
    update public.manga_source_link_review
    set
      status = 'rejected',
      reason = 'auto_expired'
    where status = 'pending'
      and created_at < now() - interval '30 days';
  $$
);

commit;
