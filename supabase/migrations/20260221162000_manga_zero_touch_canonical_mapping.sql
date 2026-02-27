-- Zero-touch canonical manga mapping hardening:
-- - Alias memory table to keep one canonical mapping and suppress known losers.
-- - Retry/backoff metadata for unresolved review rows.
-- - Candidate selector update to include due unresolved retries.
-- - Chapter status RPC for rows-first UI gating.
-- - Nightly backlog sweep cron.

begin;

-- ---------------------------------------------------------------------------
-- 1) Alias memory table (accepted/rejected provider IDs per manga)
-- ---------------------------------------------------------------------------
create table if not exists public.manga_mapping_alias_memory (
  manga_id integer not null references public.manga(id) on delete cascade,
  provider text not null default 'mangadex' check (provider in ('mangadex')),
  provider_media_id text not null,
  decision text not null check (decision in ('accepted', 'rejected_collision', 'rejected_conflict')),
  reason text not null,
  created_at timestamptz not null default now(),
  primary key (manga_id, provider, provider_media_id)
);

create index if not exists idx_manga_mapping_alias_memory_lookup
  on public.manga_mapping_alias_memory(manga_id, provider, decision);

alter table public.manga_mapping_alias_memory enable row level security;
revoke all on table public.manga_mapping_alias_memory from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Retry/backoff + verification mismatch timestamp fields
-- ---------------------------------------------------------------------------
alter table if exists public.manga_source_link_review
  add column if not exists retry_count integer not null default 0;

alter table if exists public.manga_source_link_review
  add column if not exists next_retry_at timestamptz null;

alter table if exists public.manga_source_link_review
  add column if not exists auto_expired_at timestamptz null;

create index if not exists idx_manga_source_link_review_status_next_retry
  on public.manga_source_link_review(status, next_retry_at);

update public.manga_source_link_review
set
  retry_count = case when retry_count <= 0 then 1 else retry_count end,
  next_retry_at = coalesce(next_retry_at, created_at + interval '15 minutes')
where status = 'pending';

alter table if exists public.manga_source_links
  add column if not exists last_mismatch_at timestamptz null;

-- ---------------------------------------------------------------------------
-- 3) Candidate selector update (include due unresolved retries)
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
  review_due as (
    select
      r.manga_id,
      min(coalesce(r.next_retry_at, r.created_at)) as due_at
    from public.manga_source_link_review r
    where r.status = 'pending'
      and r.manga_id is not null
    group by r.manga_id
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
        when rd.due_at is not null and rd.due_at <= now() then 5
        else 99
      end as priority_class
    from public.manga m
    left join chapter_counts cc on cc.manga_id = m.id
    left join active_mappings am on am.manga_id = m.id
    left join review_due rd on rd.manga_id = m.id
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
-- 4) Chapter status RPC for rows-first UI gating
-- ---------------------------------------------------------------------------
create or replace function public.get_manga_chapter_status(
  p_manga_id integer
)
returns table (
  manga_id integer,
  chapter_rows integer,
  chapter_count_field integer,
  mapping_status text,
  last_sync_at timestamptz,
  next_retry_at timestamptz,
  last_reason text
)
language sql
security definer
set search_path = public
as $$
  with chapter_count as (
    select count(*)::integer as chapter_rows
    from public.chapters c
    where c.manga_id = p_manga_id
  ),
  active_mapping as (
    select min(msl.next_verify_at) as next_verify_at
    from public.manga_source_links msl
    where msl.manga_id = p_manga_id
      and msl.provider = 'mangadex'
      and msl.status = 'active'
  ),
  pending_review as (
    select
      min(coalesce(r.next_retry_at, r.created_at)) as next_retry_at,
      (
        array_agg(r.reason order by r.created_at desc nulls last)
      )[1] as last_reason
    from public.manga_source_link_review r
    where r.manga_id = p_manga_id
      and r.status = 'pending'
  )
  select
    m.id as manga_id,
    coalesce(cc.chapter_rows, 0) as chapter_rows,
    m.chapters as chapter_count_field,
    case
      when coalesce(cc.chapter_rows, 0) > 0 then 'ready'
      when am.next_verify_at is not null then 'syncing'
      when pr.next_retry_at is not null then 'unresolved'
      else 'no_source'
    end as mapping_status,
    m.last_synced_at as last_sync_at,
    pr.next_retry_at,
    pr.last_reason
  from public.manga m
  cross join chapter_count cc
  left join active_mapping am on true
  left join pending_review pr on true
  where m.id = p_manga_id;
$$;

revoke all on function public.get_manga_chapter_status(integer)
  from public;
grant execute on function public.get_manga_chapter_status(integer)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Review housekeeping update (capture auto_expired_at)
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
      reason = 'auto_expired',
      auto_expired_at = now()
    where status = 'pending'
      and created_at < now() - interval '30 days';
  $$
);

-- ---------------------------------------------------------------------------
-- 6) Nightly backlog sweep
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'manga-chapter-enrich-nightly-sweep') then
    perform cron.unschedule('manga-chapter-enrich-nightly-sweep');
  end if;
exception
  when undefined_table then
    null;
end $$;

select cron.schedule(
  'manga-chapter-enrich-nightly-sweep',
  '35 3 * * *',
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
        'limit', 200,
        'scheduleSafe', false,
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
