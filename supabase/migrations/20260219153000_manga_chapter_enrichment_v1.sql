-- Manga Chapter Enrichment v1
-- Adds strict source mapping + review queue + candidate/metrics RPCs + 15-minute cron.

begin;

-- ---------------------------------------------------------------------------
-- 1) Provider mapping table (stable MangaDex mapping per manga)
-- ---------------------------------------------------------------------------
create table if not exists public.manga_source_links (
  manga_id integer not null references public.manga(id) on delete cascade,
  provider text not null check (provider in ('mangadex')),
  provider_media_id text not null,
  provider_url text not null,
  mapping_method text not null check (mapping_method in ('al_link', 'mal_link', 'title_strict')),
  confidence numeric(4, 3) not null check (confidence >= 0 and confidence <= 1),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, provider_media_id),
  unique (manga_id, provider)
);

create index if not exists idx_manga_source_links_manga_provider_status
  on public.manga_source_links(manga_id, provider, status);

do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    if not exists (select 1 from pg_trigger where tgname = 'manga_source_links_set_updated_at') then
      create trigger manga_source_links_set_updated_at
        before update on public.manga_source_links
        for each row execute function public.set_updated_at();
    end if;
  end if;
end $$;

alter table public.manga_source_links enable row level security;
revoke all on table public.manga_source_links from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Manual review queue for ambiguous/unresolved source mappings
-- ---------------------------------------------------------------------------
create table if not exists public.manga_source_link_review (
  id bigserial primary key,
  provider text not null check (provider in ('mangadex')),
  manga_id integer null references public.manga(id) on delete set null,
  query_title text,
  candidate_payload jsonb not null default '{}'::jsonb,
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_manga_source_link_review_status_created_at
  on public.manga_source_link_review(status, created_at desc);

create index if not exists idx_manga_source_link_review_provider_status
  on public.manga_source_link_review(provider, status);

create index if not exists idx_manga_source_link_review_manga_pending
  on public.manga_source_link_review(manga_id, status);

do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    if not exists (select 1 from pg_trigger where tgname = 'manga_source_link_review_set_updated_at') then
      create trigger manga_source_link_review_set_updated_at
        before update on public.manga_source_link_review
        for each row execute function public.set_updated_at();
    end if;
  end if;
end $$;

alter table public.manga_source_link_review enable row level security;
revoke all on table public.manga_source_link_review from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Candidate selector RPC (missing/dirty-first policy)
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
        else 99
      end as priority_class
    from public.manga m
    left join chapter_counts cc on cc.manga_id = m.id
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
-- 4) Metrics RPC for cron health + ops dashboards
-- ---------------------------------------------------------------------------
create or replace function public.get_manga_chapter_enrich_metrics(
  p_hours integer default 24
)
returns table (
  manga_chapters_null bigint,
  manga_zero_chapter_rows bigint,
  recent_runs bigint,
  success_runs bigint,
  error_runs bigint,
  skipped_runs bigint,
  fractional_skipped bigint,
  unresolved_pending bigint
)
language sql
security definer
set search_path = public
as $$
  with windowed as (
    select now() - make_interval(hours => greatest(1, coalesce(p_hours, 24))) as starts_after
  ),
  chapter_counts as (
    select c.manga_id, count(*)::bigint as chapter_row_count
    from public.chapters c
    group by c.manga_id
  ),
  counts as (
    select
      count(*) filter (where m.chapters is null)::bigint as manga_chapters_null,
      count(*) filter (where coalesce(cc.chapter_row_count, 0) = 0)::bigint as manga_zero_chapter_rows
    from public.manga m
    left join chapter_counts cc on cc.manga_id = m.id
  ),
  runs as (
    select
      count(*)::bigint as recent_runs,
      count(*) filter (where r.status = 'success')::bigint as success_runs,
      count(*) filter (where r.status = 'error')::bigint as error_runs,
      count(*) filter (where r.status = 'skipped')::bigint as skipped_runs,
      coalesce(
        sum(
          case
            when coalesce(r.results->>'fractional_skipped', '') ~ '^[0-9]+$'
              then (r.results->>'fractional_skipped')::bigint
            else 0
          end
        ),
        0
      )::bigint as fractional_skipped
    from public.import_runs r
    cross join windowed w
    where r.media_type = 'MANGA'
      and r.run_type = 'chapter_enrich'
      and r.started_at >= w.starts_after
  ),
  unresolved as (
    select count(*)::bigint as unresolved_pending
    from public.manga_source_link_review
    where status = 'pending'
  )
  select
    counts.manga_chapters_null,
    counts.manga_zero_chapter_rows,
    runs.recent_runs,
    runs.success_runs,
    runs.error_runs,
    runs.skipped_runs,
    runs.fractional_skipped,
    unresolved.unresolved_pending
  from counts
  cross join runs
  cross join unresolved;
$$;

revoke all on function public.get_manga_chapter_enrich_metrics(integer)
  from public, anon, authenticated;
grant execute on function public.get_manga_chapter_enrich_metrics(integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 5) 15-minute pg_cron schedule for chapter enrichment
--
-- NOTE:
-- - app.settings.import_secret should be configured at DB level so cron can
--   send x-import-secret.
-- - app.settings.supabase_anon_key can be set for portability; otherwise this
--   migration falls back to the current project's anon key.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'manga-chapter-enrich-15m') then
    perform cron.unschedule('manga-chapter-enrich-15m');
  end if;
exception
  when undefined_table then
    null;
end $$;

select cron.schedule(
  'manga-chapter-enrich-15m',
  '*/15 * * * *',
  $job$
    select net.http_post(
      url := coalesce(
        nullif(current_setting('app.settings.supabase_url', true), ''),
        'https://bkdifromsqxkndnllmdj.supabase.co'
      ) || '/functions/v1/manga-chapter-enrich',
      headers := jsonb_strip_nulls(
        jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || coalesce(
            nullif(current_setting('app.settings.supabase_anon_key', true), ''),
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
          ),
          'x-import-secret', nullif(current_setting('app.settings.import_secret', true), '')
        )
      ),
      body := jsonb_build_object(
        'limit', 20,
        'scheduleSafe', true,
        'timeBudgetMs', 45000,
        'languages', jsonb_build_array('en', 'de'),
        'includeFallbackAllLanguages', true,
        'forceMangaId', null,
        'lockTtlSeconds', 900
      )
    ) as request_id;
  $job$
);

commit;
