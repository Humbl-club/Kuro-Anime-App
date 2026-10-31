-- DRAFT / NOT APPLIED. Requires the specific reviewed production-apply approval.
-- Only the two pinned prepared migrations; global Home activation excluded.
-- One transaction: any failed guard/DDL/history write rolls back the complete delta.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
SELECT pg_advisory_xact_lock(hashtextextended('kuro.series.home.migration.20261007',0));
LOCK TABLE public.anime_user_lists, public.manga_user_lists IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE kuro_home_apply_snapshot ON COMMIT DROP AS
SELECT 'anime' AS medium, md5(coalesce(string_agg((to_jsonb(l) - ARRAY['server_revision','lifecycle_id','unit_id','progress_label','repeat_count','score_raw','score_scale','started_raw','finished_raw','volumes_progress','entry_private','source_custom_lists','source_hidden','source_list_options'])::text,E'\n' ORDER BY id),'')) AS digest FROM public.anime_user_lists l
UNION ALL
SELECT 'manga',md5(coalesce(string_agg((to_jsonb(l) - ARRAY['server_revision','lifecycle_id','unit_id','progress_label','repeat_count','score_raw','score_scale','started_raw','finished_raw','volumes_progress','entry_private','source_custom_lists','source_hidden','source_list_options'])::text,E'\n' ORDER BY id),'')) FROM public.manga_user_lists l;
DO $kuro_preflight$
DECLARE relation_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261007040000','20261007130000')) THEN
    RAISE EXCEPTION 'Candidate migration already recorded: inspect instead of replaying';
  END IF;
  FOREACH relation_name IN ARRAY ARRAY['list_entry_tombstones','mutation_receipts','series','series_sections','series_entry_spans','provider_entry_refs','mapping_revisions','mapping_revision_spans','user_series_intent','catalogue_units','artwork_materials','detail_copy','theme_links','adaptation_coverage','release_events','home_publications','library_import_jobs','library_import_baselines','library_import_items','series_enrichment_jobs'] LOOP
    IF to_regclass('public.' || relation_name) IS NOT NULL THEN
      RAISE EXCEPTION 'Unexpected existing foundation table: %', relation_name;
    END IF;
  END LOOP;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public._account_write_guard(text)'::regprocedure)
      IS DISTINCT FROM '371d495002a7e36cbe3c286d14a078e3' THEN
    RAISE EXCEPTION 'Live deletion helper changed since reviewed preflight';
  END IF;
  IF to_regprocedure('public._import_apply_outcome(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Missing compatible import outcome helper';
  END IF;
END;
$kuro_preflight$;

-- Series / Home foundation (prepared, NOT deployed).
-- Additive identity, revision fence, bounded Home/detail/Collection reads,
-- import jobs and progress receipts. Existing anime/manga ids and list rows stay.
-- Rollback: see docs/handoffs/2026-10-07-home-series-evidence/rollback.md.
-- No cron is scheduled here.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- List revision fence. Legacy integer progress stays the compatibility
-- projection. Fractional labels live in progress_label and are not rounded
-- into progress. Every insert/update/delete advances the fence in this
-- trigger, including direct PostgREST writes.
-- ---------------------------------------------------------------------------

alter table public.anime_user_lists
  add column if not exists server_revision bigint not null default 1,
  add column if not exists lifecycle_id uuid not null default gen_random_uuid(),
  add column if not exists unit_id uuid,
  add column if not exists progress_label text,
  add column if not exists repeat_count integer not null default 0,
  add column if not exists score_raw numeric,
  add column if not exists score_scale text,
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
  add column if not exists entry_private boolean not null default false,
  add column if not exists source_custom_lists jsonb not null default '[]'::jsonb,
  add column if not exists source_hidden boolean not null default false,
  add column if not exists source_list_options text;

alter table public.manga_user_lists
  add column if not exists server_revision bigint not null default 1,
  add column if not exists lifecycle_id uuid not null default gen_random_uuid(),
  add column if not exists unit_id uuid,
  add column if not exists progress_label text,
  add column if not exists repeat_count integer not null default 0,
  add column if not exists score_raw numeric,
  add column if not exists score_scale text,
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
  add column if not exists volumes_progress integer,
  add column if not exists entry_private boolean not null default false,
  add column if not exists source_custom_lists jsonb not null default '[]'::jsonb,
  add column if not exists source_hidden boolean not null default false,
  add column if not exists source_list_options text;

create table if not exists public.list_entry_tombstones (
  user_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null,
  lifecycle_id uuid not null,
  server_revision bigint not null,
  removed_at timestamptz not null default now(),
  primary key (user_id, medium, media_id, lifecycle_id)
);

create index if not exists idx_list_entry_tombstones_lookup
  on public.list_entry_tombstones (user_id, medium, media_id);

alter table public.list_entry_tombstones enable row level security;
revoke all on table public.list_entry_tombstones from public, anon, authenticated;

create index if not exists idx_anime_user_lists_home_active
  on public.anime_user_lists (user_id, updated_at desc, anime_id desc)
  where list_type in ('WATCHING', 'PLANNING');

create index if not exists idx_manga_user_lists_home_active
  on public.manga_user_lists (user_id, updated_at desc, manga_id desc)
  where list_type in ('READING', 'PLANNING');

-- All authenticated list statements and RPC writers share one account admission lock.
-- It is transaction-scoped (not a network lock), independent across accounts, and is
-- acquired BEFORE row locks so missing-row imports and deletion cannot cross.
create or replace function public.list_account_write_lock()
returns trigger language plpgsql security invoker set search_path=public,extensions as $$
begin
 if auth.uid() is not null then perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0)); end if;
 return null;
end; $$;
revoke all on function public.list_account_write_lock() from public;
grant execute on function public.list_account_write_lock() to authenticated,service_role;
drop trigger if exists list_account_write_lock on public.anime_user_lists;
create trigger list_account_write_lock before insert or update or delete on public.anime_user_lists
for each statement execute function public.list_account_write_lock();
drop trigger if exists list_account_write_lock on public.manga_user_lists;
create trigger list_account_write_lock before insert or update or delete on public.manga_user_lists
for each statement execute function public.list_account_write_lock();

create or replace function public.list_entry_revision_fence()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_medium text;
  v_media_id integer;
begin
  v_medium := case when tg_table_name = 'anime_user_lists' then 'anime' else 'manga' end;

  if tg_op = 'DELETE' then
    if tg_table_name = 'anime_user_lists' then
      v_media_id := old.anime_id;
    else
      v_media_id := old.manga_id;
    end if;
    insert into public.list_entry_tombstones
      (user_id, medium, media_id, lifecycle_id, server_revision, removed_at)
    values
      (old.user_id, v_medium, v_media_id, old.lifecycle_id, old.server_revision + 1, now())
    on conflict (user_id, medium, media_id, lifecycle_id)
    do update set server_revision = excluded.server_revision, removed_at = excluded.removed_at;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.lifecycle_id is null then
      new.lifecycle_id := gen_random_uuid();
    end if;
    if new.server_revision is null or new.server_revision < 1 then
      new.server_revision := 1;
    end if;
    return new;
  end if;

  -- UPDATE: database-owned revision. lifecycle_id is immutable.
  new.server_revision := old.server_revision + 1;
  new.lifecycle_id := old.lifecycle_id;
  return new;
end;
$$;

drop trigger if exists list_entry_revision_fence on public.anime_user_lists;
create trigger list_entry_revision_fence
  before insert or update or delete on public.anime_user_lists
  for each row execute function public.list_entry_revision_fence();

drop trigger if exists list_entry_revision_fence on public.manga_user_lists;
create trigger list_entry_revision_fence
  before insert or update or delete on public.manga_user_lists
  for each row execute function public.list_entry_revision_fence();

revoke all on function public.list_entry_revision_fence() from public;
grant execute on function public.list_entry_revision_fence() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Receipts. Replay of the same mutation id is not a second write.
-- ---------------------------------------------------------------------------

create table if not exists public.mutation_receipts (
  user_id text not null,
  mutation_id uuid not null,
  request_hash text not null,
  outcome text not null,
  medium text not null,
  media_id integer not null,
  server_revision bigint,
  position integer,
  created_at timestamptz not null default now(),
  primary key (user_id, mutation_id)
);

create index if not exists idx_mutation_receipts_created
  on public.mutation_receipts (created_at);

alter table public.mutation_receipts enable row level security;
revoke all on table public.mutation_receipts from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Continuity identity. A graph edge is not membership. Source rows stay.
-- ---------------------------------------------------------------------------

create table if not exists public.series (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  continuity text not null default 'singleton' check (continuity in ('singleton', 'verified', 'disputed')),
  title text not null,
  grouping_state text not null default 'approved' check (grouping_state in ('proposed', 'approved', 'superseded')),
  mapping_revision bigint not null default 1,
  artwork_policy text not null default 'resume_entry',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.series_sections (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  kind text not null check (kind in ('season', 'film', 'extra', 'edition')),
  ordinal integer,
  name text not null,
  sort_order integer not null,
  provenance text not null,
  state text not null default 'approved' check (state in ('proposed', 'approved', 'superseded')),
  unique (series_id, sort_order)
);

create table if not exists public.series_entry_spans (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  section_id uuid references public.series_sections (id),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  source_range_start text,
  source_range_end text,
  display_label text,
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

create unique index if not exists series_entry_spans_anime_uq
  on public.series_entry_spans (anime_id) where anime_id is not null;
create unique index if not exists series_entry_spans_manga_uq
  on public.series_entry_spans (manga_id) where manga_id is not null;
create index if not exists series_entry_spans_series
  on public.series_entry_spans (series_id);

create table if not exists public.provider_entry_refs (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  external_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  unresolved boolean not null default false,
  unique (provider, external_id, medium)
);

create table if not exists public.mapping_revisions (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  state text not null check (state in ('proposed', 'approved', 'superseded')),
  source text not null,
  rule_revision text not null,
  reviewer text,
  created_at timestamptz not null default now()
);

create table if not exists public.mapping_revision_spans (
  revision_id uuid not null references public.mapping_revisions (id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_kind text not null,
  section_ordinal integer,
  section_name text not null,
  sort_order integer not null,
  source_range_start text,
  source_range_end text,
  display_label text
);

create index if not exists mapping_revision_spans_revision
  on public.mapping_revision_spans (revision_id);

create table if not exists public.user_series_intent (
  user_id text not null,
  series_id uuid not null references public.series (id),
  saved boolean not null default false,
  followed boolean not null default false,
  resume_medium text,
  resume_media_id integer,
  primary key (user_id, series_id)
);

create table if not exists public.catalogue_units (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  section_id uuid references public.series_sections (id),
  label text not null,
  order_key numeric not null,
  edition_key text not null default '',
  available boolean not null default false,
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

alter table public.catalogue_units
  add column if not exists title text,
  add column if not exists synopsis text,
  add column if not exists image_url text,
  add column if not exists source_provenance text;

create unique index if not exists catalogue_units_anime_uq
  on public.catalogue_units (anime_id, edition_key, order_key) where anime_id is not null;
create unique index if not exists catalogue_units_manga_uq
  on public.catalogue_units (manga_id, edition_key, order_key) where manga_id is not null;

create table if not exists public.artwork_materials (
  image_digest text primary key,
  image_url text not null,
  content_revision text not null,
  extraction_version text not null,
  base_color text not null,
  deep_color text not null,
  wash_color text not null,
  edge_color text not null,
  ink_color text not null,
  contrast text not null
);

alter table public.artwork_materials add column if not exists is_current boolean not null default true;
create unique index if not exists artwork_materials_current_image_uq
  on public.artwork_materials(image_url) where is_current;

create table if not exists public.detail_copy (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_id uuid references public.series_sections (id),
  locale text not null default 'en',
  premise text,
  hook text,
  synopsis text,
  provenance text not null,
  review_state text not null default 'unreviewed',
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

create table if not exists public.theme_links (
  id uuid primary key default gen_random_uuid(),
  anime_id integer not null references public.anime (id),
  section_id uuid references public.series_sections (id),
  role text not null check (role in ('op', 'ed', 'insert')),
  sequence_order integer not null default 1,
  song_title text,
  artist text,
  external_url text,
  match_state text not null check (match_state in ('verified', 'search', 'unmatched')),
  evidence text
);

create table if not exists public.adaptation_coverage (
  id uuid primary key default gen_random_uuid(),
  anime_id integer references public.anime (id),
  section_id uuid references public.series_sections (id),
  source_manga_id integer references public.manga (id),
  source_kind text not null check (source_kind in ('manga', 'novel', 'other')),
  mapping_state text not null check (mapping_state in ('exact', 'partial', 'reordered', 'original_ending', 'unknown')),
  starts_at text,
  ends_at text,
  read_next text,
  evidence text,
  revision bigint not null default 1
);

create index if not exists detail_copy_anime_lookup on public.detail_copy(anime_id, locale, section_id) where anime_id is not null;
create index if not exists detail_copy_manga_lookup on public.detail_copy(manga_id, locale, section_id) where manga_id is not null;
create index if not exists theme_links_entry_section on public.theme_links(anime_id, section_id, sequence_order);
create index if not exists coverage_anime_section on public.adaptation_coverage(anime_id, section_id, revision desc);
create index if not exists coverage_manga_revision on public.adaptation_coverage(source_manga_id, revision desc);

create table if not exists public.release_events (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_id uuid references public.series_sections (id),
  kind text not null,
  precision text not null check (precision in ('instant', 'day', 'month', 'quarter', 'year', 'unknown')),
  source_local_date text,
  source_zone text,
  utc_instant timestamptz,
  locale text,
  territory text,
  status text not null check (status in ('scheduled', 'released', 'delayed', 'cancelled', 'withdrawn', 'announced')),
  evidence text,
  freshness timestamptz,
  revision bigint not null default 1,
  check (
    (medium = 'anime' and anime_id is not null)
    or (medium = 'manga' and manga_id is not null)
  )
);

create index if not exists idx_release_events_anime_time
  on public.release_events (anime_id, utc_instant)
  where anime_id is not null and utc_instant is not null;
create index if not exists idx_release_events_manga
  on public.release_events (manga_id, status)
  where manga_id is not null;

create table if not exists public.home_publications (
  user_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  revision bigint not null default 0,
  primary key (user_id, medium)
);

create table if not exists public.library_import_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  provider text not null check (provider in ('anilist', 'myanimelist')),
  source_kind text not null check (source_kind in ('account', 'export')),
  medium_filter text not null check (medium_filter in ('anime', 'manga', 'both')),
  merge_policy text not null default 'merge' check (merge_policy = 'merge'),
  idempotency_key text not null,
  payload_hash text not null,
  state text not null check (state in ('queued', 'running', 'ready', 'ready_with_issues', 'cancelled', 'failed')),
  discovered_total integer,
  counters jsonb not null default '{}'::jsonb,
  home_revision bigint not null default 0,
  sanitized_error text,
  retry_after timestamptz,
  anime_checkpoint jsonb not null default '{}'::jsonb,
  manga_checkpoint jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists idx_library_import_jobs_owner
  on public.library_import_jobs (user_id, state);

-- One active action per account/provider. Both-medium actions overlap either stream.
create unique index if not exists library_import_jobs_active_uq
  on public.library_import_jobs(user_id, provider) where state in ('queued', 'running');

create table if not exists public.library_import_baselines (
  job_id uuid not null references public.library_import_jobs(id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null,
  lifecycle_id uuid not null,
  server_revision bigint not null,
  primary key(job_id, medium, media_id)
);
alter table public.library_import_baselines enable row level security;
revoke all on public.library_import_baselines from public, anon, authenticated;

create table if not exists public.library_import_items (
  job_id uuid not null references public.library_import_jobs (id) on delete cascade,
  provider text not null,
  external_id text not null,
  medium text not null,
  disposition text not null,
  request_hash text,
  detail text,
  primary key (job_id, provider, external_id, medium)
);

alter table public.series enable row level security;
alter table public.series_sections enable row level security;
alter table public.series_entry_spans enable row level security;
alter table public.provider_entry_refs enable row level security;
alter table public.mapping_revisions enable row level security;
alter table public.mapping_revision_spans enable row level security;
alter table public.user_series_intent enable row level security;
alter table public.catalogue_units enable row level security;
alter table public.artwork_materials enable row level security;
alter table public.detail_copy enable row level security;
alter table public.theme_links enable row level security;
alter table public.adaptation_coverage enable row level security;
alter table public.release_events enable row level security;
alter table public.home_publications enable row level security;
alter table public.library_import_jobs enable row level security;
alter table public.library_import_items enable row level security;

drop policy if exists series_public_read on public.series;
create policy series_public_read on public.series for select to anon, authenticated using (true);
drop policy if exists series_sections_public_read on public.series_sections;
create policy series_sections_public_read on public.series_sections for select to anon, authenticated using (true);
drop policy if exists series_spans_public_read on public.series_entry_spans;
create policy series_spans_public_read on public.series_entry_spans for select to anon, authenticated using (true);
drop policy if exists provider_refs_public_read on public.provider_entry_refs;
create policy provider_refs_public_read on public.provider_entry_refs for select to anon, authenticated using (true);
drop policy if exists mapping_revisions_public_read on public.mapping_revisions;
create policy mapping_revisions_public_read on public.mapping_revisions for select to anon, authenticated using (true);
drop policy if exists mapping_spans_public_read on public.mapping_revision_spans;
create policy mapping_spans_public_read on public.mapping_revision_spans for select to anon, authenticated using (true);
drop policy if exists units_public_read on public.catalogue_units;
create policy units_public_read on public.catalogue_units for select to anon, authenticated using (true);
drop policy if exists materials_public_read on public.artwork_materials;
create policy materials_public_read on public.artwork_materials for select to anon, authenticated using (true);
drop policy if exists detail_copy_public_read on public.detail_copy;
create policy detail_copy_public_read on public.detail_copy for select to anon, authenticated using (true);
drop policy if exists themes_public_read on public.theme_links;
create policy themes_public_read on public.theme_links for select to anon, authenticated using (true);
drop policy if exists coverage_public_read on public.adaptation_coverage;
create policy coverage_public_read on public.adaptation_coverage for select to anon, authenticated using (true);
drop policy if exists releases_public_read on public.release_events;
create policy releases_public_read on public.release_events for select to anon, authenticated using (true);

drop policy if exists user_series_intent_own on public.user_series_intent;
create policy user_series_intent_own on public.user_series_intent
  for all to authenticated
  using (user_id = (select auth.uid())::text)
  with check (user_id = (select auth.uid())::text);

drop policy if exists home_publications_own on public.home_publications;
create policy home_publications_own on public.home_publications
  for select to authenticated
  using (user_id = (select auth.uid())::text);

drop policy if exists library_import_jobs_own_select on public.library_import_jobs;
create policy library_import_jobs_own_select on public.library_import_jobs
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists library_import_items_own_select on public.library_import_items;
create policy library_import_items_own_select on public.library_import_items
  for select to authenticated
  using (
    exists (
      select 1 from public.library_import_jobs j
      where j.id = library_import_items.job_id and j.user_id = (select auth.uid())
    )
  );

grant select on public.series, public.series_sections, public.series_entry_spans,
  public.provider_entry_refs, public.mapping_revisions, public.mapping_revision_spans,
  public.catalogue_units, public.artwork_materials, public.detail_copy, public.theme_links,
  public.adaptation_coverage, public.release_events
  to anon, authenticated;

grant select, insert, update, delete on public.user_series_intent to authenticated;
grant select on public.home_publications, public.library_import_jobs, public.library_import_items to authenticated;
revoke insert, update, delete on public.home_publications, public.library_import_jobs, public.library_import_items from authenticated, anon;

do $$
begin
  if to_regclass('public.title_comments') is not null
     and not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'title_comments' and column_name = 'spoiler_scope'
     ) then
    alter table public.title_comments
      add column spoiler_scope text not null default 'none'
      check (spoiler_scope in ('none', 'story', 'ending'));
  end if;
  if to_regclass('public.feature_flags') is not null then
    insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
    values
      ('series_foundation_v1', false, 0, '{}', 'Bounded series Home/detail/Collection contracts and progress receipts'),
      ('series_home_native_v1', false, 0, '{}', 'Native Home and Anime/Manga detail hierarchy')
    on conflict (flag_name) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Progress mutations. Field-specific. Same key + same hash replays the receipt.
-- Same key + different hash is rejected. A removed lifecycle is not recreated.
--
-- `_apply_progress_mutations_for_user` is the one writer: authenticated RPCs
-- pass auth.uid()::text; service-role import apply/undo pass the already-checked
-- session user. It is NOT granted to authenticated.
-- ---------------------------------------------------------------------------

create or replace function public._apply_progress_mutations_for_user(
  p_user text,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user text := p_user;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_mutation uuid;
  v_medium text;
  v_media_id integer;
  v_lifecycle uuid;
  v_unit uuid;
  v_base bigint;
  v_position integer;
  v_label text;
  v_status text;
  v_hash text;
  v_canonical text;
  v_receipt public.mutation_receipts%rowtype;
  v_revision bigint;
  v_lifecycle_row uuid;
  v_progress integer;
  v_notes text;
  v_rating integer;
  v_list_type text;
  v_found boolean;
  v_outcome text;
  v_tombstone boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if v_user is null or btrim(v_user) = '' then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if jsonb_array_length(p_mutations) > 50 then
    raise exception 'BATCH_TOO_LARGE';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_mutations) as t(value)
    order by t.value->>'medium', (t.value->>'media_id'), t.value->>'mutation_id'
  loop
    begin
      v_mutation := (v_item->>'mutation_id')::uuid;
      v_medium := v_item->>'medium';
      v_media_id := (v_item->>'media_id')::integer;
      v_lifecycle := (v_item->>'lifecycle_id')::uuid;
      v_base := (v_item->>'base_revision')::bigint;
      v_position := (v_item->>'position')::integer;
      v_label := v_item->>'position_label';
      v_status := v_item->>'status';
      if v_item->>'unit_id' is null or v_item->>'unit_id' = '' then
        v_unit := null;
      else
        v_unit := (v_item->>'unit_id')::uuid;
      end if;
    exception when others then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_item->>'mutation_id', 'outcome', 'invalid_target'
      ));
      continue;
    end;

    if v_mutation is null or v_media_id is null or v_lifecycle is null
       or v_medium is null or v_medium not in ('anime', 'manga') or v_base is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is not null and v_position < 0 then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is null and v_status is null and v_label is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_status is not null and v_status not in ('WATCHING', 'READING', 'PLANNING', 'COMPLETED', 'DROPPED', 'PAUSED') then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    v_found := false;
    if v_medium = 'anime' then
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id
      for update;
      v_found := found;
    else
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id
      for update;
      v_found := found;
    end if;

    v_canonical := jsonb_build_object(
      'medium', v_medium, 'media_id', v_media_id, 'lifecycle_id', v_lifecycle,
      'base_revision', v_base, 'unit_id', v_unit, 'position', v_item->'position',
      'position_label', v_item->'position_label', 'status', v_item->'status',
      'has_position',v_item ? 'position','has_unit_id',v_item ? 'unit_id',
      'has_position_label',v_item ? 'position_label','has_status',v_item ? 'status'
    )::text;
    v_hash := encode(digest(v_canonical, 'sha256'), 'hex');

    select * into v_receipt
    from public.mutation_receipts
    where user_id = v_user and mutation_id = v_mutation;

    if v_receipt.mutation_id is not null then
      v_outcome := case when v_receipt.request_hash <> v_hash then 'rejected_payload'
        when v_receipt.outcome in ('applied','already_applied') then 'already_applied' else v_receipt.outcome end;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', v_outcome,
        'server_revision', v_receipt.server_revision,
        'position', v_receipt.position
      ));
      continue;
    end if;

    select exists (
      select 1 from public.list_entry_tombstones t
      where t.user_id = v_user and t.medium = v_medium and t.media_id = v_media_id
        and t.lifecycle_id = v_lifecycle
    ) into v_tombstone;

    if v_tombstone or (v_found and v_lifecycle_row is distinct from v_lifecycle) then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'removed_entry'
      ));
      continue;
    end if;

    if not v_found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    if v_revision is distinct from v_base then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', 'conflict',
        'server_revision', v_revision,
        'position', v_progress,
        'notes', v_notes,
        'rating', v_rating,
        'status', v_list_type
      ));
      continue;
    end if;

    if v_unit is not null and not exists (
      select 1 from public.catalogue_units u where u.id = v_unit and u.medium = v_medium
        and ((v_medium = 'anime' and u.anime_id = v_media_id)
          or (v_medium = 'manga' and u.manga_id = v_media_id))
    ) then
      v_results := v_results || jsonb_build_array(jsonb_build_object('mutation_id', v_mutation, 'outcome', 'invalid_target'));
      continue;
    end if;
    -- Missing position is retained only after hashing/replay lookup of the immutable body.
    v_position := coalesce(v_position, v_progress, 0);

    if v_medium = 'anime' then
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.anime_user_lists
          set progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      else
        update public.anime_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id;
    else
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.manga_user_lists
          set progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      else
        update public.manga_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id;
    end if;

    insert into public.mutation_receipts
      (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
    values
      (v_user, v_mutation, v_hash, 'applied', v_medium, v_media_id, v_revision, v_progress);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'mutation_id', v_mutation,
      'outcome', 'applied',
      'server_revision', v_revision,
      'position', v_progress
    ));
  end loop;

  return jsonb_build_object('items', v_results);
end;
$$;

create or replace function public.apply_progress_mutations_v1(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  return public._apply_progress_mutations_for_user(v_uid::text, p_mutations);
end;
$$;

-- Service-role / import-session helper: take the current server_revision under the
-- row lock, write one receipt, apply progress and/or status. Notes and rating stay
-- outside this helper (direct writes that still advance server_revision).
create or replace function public._fence_set_progress_status(
  p_user text,
  p_medium text,
  p_media_id integer,
  p_mutation_id uuid,
  p_progress integer,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lifecycle uuid;
  v_revision bigint;
  v_cur_progress integer;
  v_cur_status text;
  v_position integer;
  v_status text;
  v_result jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if p_user is null or p_medium is null or p_media_id is null or p_mutation_id is null then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_progress is null and p_status is null then
    raise exception 'INVALID_PAYLOAD';
  end if;

  if p_medium = 'anime' then
    select lifecycle_id, server_revision, progress, list_type
      into v_lifecycle, v_revision, v_cur_progress, v_cur_status
    from public.anime_user_lists
    where user_id = p_user and anime_id = p_media_id
    for update;
  else
    select lifecycle_id, server_revision, progress, list_type
      into v_lifecycle, v_revision, v_cur_progress, v_cur_status
    from public.manga_user_lists
    where user_id = p_user and manga_id = p_media_id
    for update;
  end if;
  if v_lifecycle is null then
    raise exception 'INVALID_TARGET';
  end if;

  v_position := coalesce(p_progress, v_cur_progress, 0);
  v_status := coalesce(p_status, v_cur_status);

  v_result := public._apply_progress_mutations_for_user(
    p_user,
    jsonb_build_array(jsonb_build_object(
      'mutation_id', p_mutation_id,
      'medium', p_medium,
      'media_id', p_media_id,
      'lifecycle_id', v_lifecycle,
      'base_revision', v_revision,
      'position', v_position,
      'status', v_status
    ))
  );
  return v_result -> 'items' -> 0;
end;
$$;

create or replace function public._import_mutation_id(
  p_scope text,
  p_session uuid,
  p_type text,
  p_media_id integer
)
returns uuid
language sql
immutable
set search_path = public, extensions
as $$
  select (
    substr(h, 1, 8) || '-' ||
    substr(h, 9, 4) || '-' ||
    '5' || substr(h, 13, 3) || '-' ||
    'a' || substr(h, 17, 3) || '-' ||
    substr(h, 21, 12)
  )::uuid
  from (
    select md5(coalesce(p_scope, '') || ':' || coalesce(p_session::text, '') || ':'
      || coalesce(p_type, '') || ':' || coalesce(p_media_id::text, '')) as h
  ) s;
$$;

revoke all on function public._apply_progress_mutations_for_user(text, jsonb) from public, anon, authenticated;
revoke all on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) from public, anon, authenticated;
revoke all on function public._import_mutation_id(text, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.apply_progress_mutations_v1(jsonb) from public;
grant execute on function public.apply_progress_mutations_v1(jsonb) to authenticated, service_role;
-- service_role keeps EXECUTE on the internal helpers (SECURITY DEFINER callers).
grant execute on function public._apply_progress_mutations_for_user(text, jsonb) to service_role;
grant execute on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) to service_role;
grant execute on function public._import_mutation_id(text, uuid, text, integer) to service_role;

-- ---------------------------------------------------------------------------
-- Removal mutations. Same key + same hash replays the receipt. A stale base
-- revision conflicts. The delete trigger writes the lifecycle tombstone.
-- ---------------------------------------------------------------------------

create or replace function public.apply_remove_mutations_v1(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_mutation uuid;
  v_medium text;
  v_media_id integer;
  v_lifecycle uuid;
  v_base bigint;
  v_hash text;
  v_canonical text;
  v_receipt public.mutation_receipts%rowtype;
  v_revision bigint;
  v_lifecycle_row uuid;
  v_progress integer;
  v_notes text;
  v_rating integer;
  v_list_type text;
  v_found boolean;
  v_outcome text;
  v_tombstone boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if jsonb_array_length(p_mutations) > 50 then
    raise exception 'BATCH_TOO_LARGE';
  end if;
  v_user := v_uid::text;

  for v_item in
    select value
    from jsonb_array_elements(p_mutations) as t(value)
    order by t.value->>'medium', (t.value->>'media_id'), t.value->>'mutation_id'
  loop
    begin
      v_mutation := (v_item->>'mutation_id')::uuid;
      v_medium := v_item->>'medium';
      v_media_id := (v_item->>'media_id')::integer;
      v_lifecycle := (v_item->>'lifecycle_id')::uuid;
      v_base := (v_item->>'base_revision')::bigint;
    exception when others then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_item->>'mutation_id', 'outcome', 'invalid_target'
      ));
      continue;
    end;

    if v_medium not in ('anime', 'manga') or v_lifecycle is null or v_base is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    v_canonical := 'remove|' || v_medium || '|' || v_media_id::text || '|' || v_lifecycle::text;
    v_hash := encode(digest(v_canonical, 'sha256'), 'hex');

    select * into v_receipt
    from public.mutation_receipts
    where user_id = v_user and mutation_id = v_mutation;

    if v_receipt.mutation_id is not null then
      v_outcome := case when v_receipt.request_hash <> v_hash then 'rejected_payload'
        when v_receipt.outcome in ('applied','already_applied') then 'already_applied' else v_receipt.outcome end;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', v_outcome,
        'server_revision', v_receipt.server_revision
      ));
      continue;
    end if;

    select exists (
      select 1 from public.list_entry_tombstones t
      where t.user_id = v_user and t.medium = v_medium and t.media_id = v_media_id
        and t.lifecycle_id = v_lifecycle
    ) into v_tombstone;

    v_found := false;
    if v_medium = 'anime' then
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id
      for update;
      v_found := found;
    else
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id
      for update;
      v_found := found;
    end if;

    if v_tombstone and not v_found then
      insert into public.mutation_receipts
        (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
      values
        (v_user, v_mutation, v_hash, 'already_applied', v_medium, v_media_id, coalesce(v_revision, v_base), null);
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'already_applied'
      ));
      continue;
    end if;

    if v_found and v_lifecycle_row is distinct from v_lifecycle then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'removed_entry'
      ));
      continue;
    end if;

    if not v_found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'already_applied'
      ));
      continue;
    end if;

    if v_revision is distinct from v_base then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', 'conflict',
        'server_revision', v_revision,
        'position', v_progress,
        'notes', v_notes,
        'rating', v_rating,
        'status', v_list_type
      ));
      continue;
    end if;

    if v_medium = 'anime' then
      delete from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id;
    else
      delete from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id;
    end if;

    insert into public.mutation_receipts
      (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
    values
      (v_user, v_mutation, v_hash, 'applied', v_medium, v_media_id, v_revision + 1, null);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'mutation_id', v_mutation,
      'outcome', 'applied',
      'server_revision', v_revision + 1
    ));
  end loop;

  return jsonb_build_object('items', v_results);
end;
$$;

revoke all on function public.apply_remove_mutations_v1(jsonb) from public;
grant execute on function public.apply_remove_mutations_v1(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Atomic mapping publication. A failed revision does not delete the last
-- approved spans: validation runs before the replacement, and a raise
-- rolls the replacement back with the statement.
-- ---------------------------------------------------------------------------

create or replace function public.publish_mapping_revision(p_revision uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_series uuid;
  v_state text;
  v_bad integer;
  v_role text := auth.role();
begin
  if v_role in ('authenticated', 'anon') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select series_id, state into v_series, v_state
  from public.mapping_revisions
  where id = p_revision
  for update;

  if v_series is null then
    raise exception 'REVISION_NOT_FOUND';
  end if;
  -- Different proposed revisions for the same continuity share its publication
  -- lock; metadata validation and replacement must see the same current map.
  perform 1 from public.series where id=v_series for update;
  if v_state <> 'proposed' then
    raise exception 'REVISION_NOT_PROPOSED';
  end if;

  select count(*) into v_bad
  from public.mapping_revision_spans s
  where s.revision_id = p_revision
    and (
      (s.medium = 'anime' and (s.anime_id is null or not exists (select 1 from public.anime a where a.id = s.anime_id)))
      or (s.medium = 'manga' and (s.manga_id is null or not exists (select 1 from public.manga m where m.id = s.manga_id)))
      or s.medium not in ('anime', 'manga')
    );
  if v_bad > 0 then
    raise exception 'UNRESOLVED_TARGET';
  end if;

  -- A split cour may have multiple source entries in one logical section. Their
  -- section description must agree before publication touches the last good map.
  if exists (
    select 1 from public.mapping_revision_spans s where s.revision_id=p_revision
    group by s.sort_order
    having count(distinct jsonb_build_array(s.section_kind,s.section_ordinal,s.section_name))>1
  ) then raise exception 'INCONSISTENT_SECTION'; end if;
  if not exists(select 1 from public.mapping_revision_spans where revision_id=p_revision)
    then raise exception 'UNRESOLVED_TARGET'; end if;

  if exists (
    select 1 from public.series_sections old
    where old.series_id = v_series and old.state = 'approved'
      and not exists (select 1 from public.mapping_revision_spans proposed where proposed.revision_id = p_revision
        and proposed.sort_order = old.sort_order and proposed.section_kind = old.kind
        and proposed.section_ordinal is not distinct from old.ordinal)
      and (exists (select 1 from public.catalogue_units where section_id = old.id)
        or exists (select 1 from public.detail_copy where section_id = old.id)
        or exists (select 1 from public.theme_links where section_id = old.id)
        or exists (select 1 from public.adaptation_coverage where section_id = old.id)
        or exists (select 1 from public.release_events where section_id = old.id))
  ) then raise exception 'SECTION_RECONCILIATION_REQUIRED'; end if;

  -- A section with attached data cannot silently be rebound to different catalogue entries.
  if exists (
    select 1 from public.series_sections old
    where old.series_id=v_series and old.state='approved'
      and (exists (select 1 from public.catalogue_units where section_id = old.id)
        or exists (select 1 from public.detail_copy where section_id = old.id)
        or exists (select 1 from public.theme_links where section_id = old.id)
        or exists (select 1 from public.adaptation_coverage where section_id = old.id)
        or exists (select 1 from public.release_events where section_id = old.id))
      and exists (
        (select sp.medium,sp.anime_id,sp.manga_id,sp.source_range_start,sp.source_range_end
         from public.series_entry_spans sp where sp.section_id=old.id
         except select p.medium,p.anime_id,p.manga_id,p.source_range_start,p.source_range_end
         from public.mapping_revision_spans p where p.revision_id=p_revision and p.sort_order=old.sort_order)
        union all
        (select p.medium,p.anime_id,p.manga_id,p.source_range_start,p.source_range_end
         from public.mapping_revision_spans p where p.revision_id=p_revision and p.sort_order=old.sort_order
         except select sp.medium,sp.anime_id,sp.manga_id,sp.source_range_start,sp.source_range_end
         from public.series_entry_spans sp where sp.section_id=old.id)
      )
  ) then raise exception 'SECTION_RECONCILIATION_REQUIRED'; end if;

  delete from public.series_entry_spans where series_id = v_series;
  update public.series_sections set state = 'superseded' where series_id = v_series;
  insert into public.series_sections (series_id, kind, ordinal, name, sort_order, provenance, state)
  select distinct v_series, s.section_kind, s.section_ordinal, s.section_name, s.sort_order, 'mapping_revision', 'approved'
  from public.mapping_revision_spans s where s.revision_id = p_revision order by s.sort_order
  on conflict (series_id, sort_order) do update set
    kind = excluded.kind, ordinal = excluded.ordinal, name = excluded.name,
    provenance = excluded.provenance, state = 'approved';

  insert into public.series_entry_spans
    (series_id, section_id, medium, anime_id, manga_id, source_range_start, source_range_end, display_label)
  select v_series, sec.id, s.medium, s.anime_id, s.manga_id, s.source_range_start, s.source_range_end, s.display_label
  from public.mapping_revision_spans s
  join public.series_sections sec
    on sec.series_id = v_series and sec.sort_order = s.sort_order
  where s.revision_id = p_revision;

  update public.mapping_revisions
    set state = 'superseded'
  where series_id = v_series and state = 'approved' and id <> p_revision;

  update public.mapping_revisions
    set state = 'approved'
  where id = p_revision;

  update public.series
    set mapping_revision = mapping_revision + 1,
        continuity = 'verified',
        grouping_state = 'approved',
        updated_at = now()
  where id = v_series;
end;
$$;

revoke all on function public.publish_mapping_revision(uuid) from public;
grant execute on function public.publish_mapping_revision(uuid) to service_role;

-- Names and rank checks go through these helpers. club_members select is
-- own-row after the membership lifecycle migration, so an invoker join cannot
-- see the other member. The helper still requires a current shared club at
-- the requested rank and does not return private-rank identities.
create or replace function public.shares_club_at_least(p_other uuid, p_level text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.club_members me
    join public.club_members them
      on them.club_id = me.club_id and them.user_id = p_other
    join public.clubs cl on cl.id = me.club_id and cl.is_archived = false
    where me.user_id = auth.uid()
      and p_other is not null
      and p_other <> auth.uid()
      and least(public.sharing_level_rank(coalesce(me.sharing_level, cl.sharing_level)), public.sharing_level_rank(cl.sharing_level),
               public.sharing_level_rank(coalesce(them.sharing_level, cl.sharing_level)))
          >= public.sharing_level_rank(p_level)
  );
$$;

create or replace function public.club_peer_display_name(p_other uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_name text;
begin
  if not public.shares_club_at_least(p_other, 'status') then
    return null;
  end if;
  select nullif(trim(coalesce(p.display_name, '')), '') into v_name
  from public.profiles p
  where p.id = p_other;
  return v_name;
end;
$$;

revoke all on function public.shares_club_at_least(uuid, text) from public;
revoke all on function public.club_peer_display_name(uuid) from public;
grant execute on function public.shares_club_at_least(uuid, text) to authenticated, service_role;
grant execute on function public.club_peer_display_name(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Home bundle. One indexed read of the caller's list, then primary-key
-- catalogue lookups. Club text is a rank-filtered slice, not a public feed.
-- ---------------------------------------------------------------------------

-- Approved continuity is presentation identity; all child tracking rows remain intact.
create or replace view public.anime_home_resume_v1 with (security_invoker = true) as
select distinct on (coalesce(sp.series_id::text, 'entry:' || l.anime_id::text)) l.*
from public.anime_user_lists l
left join lateral (select sp.series_id from public.series_entry_spans sp
  join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.anime_id=l.anime_id limit 1) sp on true
left join public.user_series_intent intent on intent.series_id = sp.series_id and intent.user_id = l.user_id
where l.user_id = auth.uid()::text and l.list_type in ('WATCHING', 'PLANNING')
order by coalesce(sp.series_id::text, 'entry:' || l.anime_id::text),
         case when intent.resume_medium = 'anime' and intent.resume_media_id = l.anime_id then 0 else 1 end,
         case when l.list_type = 'WATCHING' then 0 else 1 end, l.updated_at desc, l.anime_id desc;
revoke all on public.anime_home_resume_v1 from public, anon;
grant select on public.anime_home_resume_v1 to authenticated;

-- Approved continuity is presentation identity; all child tracking rows remain intact.
create or replace view public.manga_home_resume_v1 with (security_invoker = true) as
select distinct on (coalesce(sp.series_id::text, 'entry:' || l.manga_id::text)) l.*
from public.manga_user_lists l
left join lateral (select sp.series_id from public.series_entry_spans sp
  join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.manga_id=l.manga_id limit 1) sp on true
left join public.user_series_intent intent on intent.series_id = sp.series_id and intent.user_id = l.user_id
where l.user_id = auth.uid()::text and l.list_type in ('READING', 'PLANNING')
order by coalesce(sp.series_id::text, 'entry:' || l.manga_id::text),
         case when intent.resume_medium = 'manga' and intent.resume_media_id = l.manga_id then 0 else 1 end,
         case when l.list_type = 'READING' then 0 else 1 end, l.updated_at desc, l.manga_id desc;
revoke all on public.manga_home_resume_v1 from public, anon;
grant select on public.manga_home_resume_v1 to authenticated;

create or replace function public.home_bundle_v1(
  p_medium text,
  p_locale text default 'en',
  p_window_days integer default 7,
  p_active_limit integer default 12,
  p_event_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_limit integer;
  v_events integer;
  v_window integer;
  v_cursor_at timestamptz;
  v_cursor_id integer;
  v_active jsonb;
  v_upcoming jsonb;
  v_pending jsonb;
  v_club jsonb := '[]'::jsonb;
  v_club_state text := 'none';
  v_club_label text := 'Your clubs';
  v_publication bigint := 0;
  v_next text;
  v_event_page jsonb;
  v_pending_page jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  v_user := v_uid::text;
  v_limit := least(50, greatest(1, coalesce(p_active_limit, 12)));
  v_events := least(50, greatest(1, coalesce(p_event_limit, 20)));
  v_window := least(90, greatest(1, coalesce(p_window_days, 7)));

  if p_cursor is not null and p_cursor <> '' then
    begin
      v_cursor_at := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::integer;
    exception when others then
      raise exception 'INVALID_CURSOR';
    end;
  end if;

  if p_medium = 'anime' then
    with resume_page as materialized (
      select l.* from public.anime_home_resume_v1 l
      where l.user_id=v_user and (v_cursor_at is null or l.updated_at<v_cursor_at
        or (l.updated_at=v_cursor_at and l.anime_id<v_cursor_id))
      order by l.updated_at desc,l.anime_id desc limit v_limit+1
    ), page as (
      select l.anime_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id,
             coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled') as title,
             a.banner_image, a.cover_image_large, a.format, a.episodes, a.status as catalogue_status,
             sp.series_id, sec.ordinal as section_ordinal, sec.kind as section_kind, sec.name as section_name,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from resume_page l
      join public.anime a on a.id = l.anime_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
        join public.series_sections ss on ss.id=sp.section_id and ss.state='approved'
        where sp.anime_id=l.anime_id order by ss.sort_order,sp.id limit 1) sp on true
      left join public.series_sections sec on sec.id = sp.section_id
      left join public.artwork_materials mat on mat.image_url = coalesce(a.banner_image, a.cover_image_large) and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('WATCHING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.anime_id < v_cursor_id)
        )
      order by l.updated_at desc, l.anime_id desc
      limit v_limit + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'banner_image', banner_image,
      'cover_image', cover_image_large,
      'format', format,
      'episodes', episodes,
      'catalogue_status', catalogue_status,
      'series_id', series_id,
      'section_ordinal', section_ordinal,
      'section_kind', section_kind,
      'section_name', section_name,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb)
    , (select case when count(*)>v_limit then
         (select updated_at::text||'|'||media_id::text from page order by updated_at desc,media_id desc offset v_limit-1 limit 1)
         else null end from page)
    into v_active,v_next
    from (
      select * from page
      order by updated_at desc, media_id desc
      limit v_limit
    ) p;


  else
    with page as (
      select l.manga_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id, l.volumes_progress,
             coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled') as title,
             m.cover_image_large, m.format, m.chapters, m.volumes, m.status as catalogue_status,
             sp.series_id,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from public.manga_home_resume_v1 l
      join public.manga m on m.id = l.manga_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
        where sp.manga_id=l.manga_id order by sp.id limit 1) sp on true
      left join public.artwork_materials mat on mat.image_url = m.cover_image_large and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('READING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id)
        )
      order by l.updated_at desc, l.manga_id desc
      limit v_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'volumes_progress', volumes_progress,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'cover_image', cover_image_large,
      'format', format,
      'chapters', chapters,
      'volumes', volumes,
      'catalogue_status', catalogue_status,
      'series_id', series_id,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb)
    into v_active
    from page;

    v_next := null;
    if (
      select count(*) from (
        select 1 from public.manga_home_resume_v1 l
        where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
          and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
        limit v_limit + 1
      ) s
    ) > v_limit then
      select l.updated_at::text || '|' || l.manga_id::text into v_next
      from public.manga_home_resume_v1 l
      where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
        and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
      order by l.updated_at desc, l.manga_id desc
      offset v_limit - 1
      limit 1;
    end if;


  end if;

  v_pending_page := public.home_pending_page_v1(p_medium,v_events,null);
  v_pending := v_pending_page->'items';

  begin
    with eligible as (
      select c.id, c.media_id, c.media_type, c.spoiler_scope, c.created_at,
             case when c.spoiler_scope = 'none' then c.text else null end as body,
             public.club_peer_display_name(c.user_id) as display_name
      from public.title_comments c
      where c.user_id <> v_uid
        and public.shares_club_at_least(c.user_id, 'status')
        and (
          (p_medium = 'anime' and c.media_type = 'ANIME')
          or (p_medium = 'manga' and c.media_type = 'MANGA')
        )
        and exists (
          select 1 from public.anime_user_lists al
          where p_medium = 'anime' and al.user_id = v_user and al.anime_id = c.media_id
          union all
          select 1 from public.manga_user_lists ml
          where p_medium = 'manga' and ml.user_id = v_user and ml.manga_id = c.media_id
        )
      order by c.created_at desc
      limit 6
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'comment_id', id,
      'media_id', media_id,
      'media_type', media_type,
      'spoiler_scope', spoiler_scope,
      'text', body,
      'display_name', display_name,
      'created_at', created_at
    ) order by created_at desc), '[]'::jsonb)
    into v_club
    from eligible;

    if jsonb_array_length(coalesce(v_club, '[]'::jsonb)) = 0 then
      v_club_state := 'none';
      v_club := '[]'::jsonb;
    else
      v_club_state := 'ok';
      v_club_label := 'Your clubs';
    end if;
  exception when others then
    v_club := '[]'::jsonb;
    v_club_state := 'error';
    v_club_label := 'Your clubs';
  end;

  select revision into v_publication
  from public.home_publications
  where user_id = v_user and medium = p_medium;
  v_publication := coalesce(v_publication, 0);

  v_event_page := public.home_events_page_v1(p_medium,v_window,v_events,null);
  v_upcoming := v_event_page->'items';
  return jsonb_build_object(
    'medium', p_medium,
    'locale', coalesce(p_locale, 'en'),
    'window_days', v_window,
    'as_of', now(),
    'home_revision', v_publication,
    'active', coalesce(v_active, '[]'::jsonb),
    'upcoming', coalesce(v_upcoming, '[]'::jsonb),
    'upcoming_total', v_event_page->'total', 'events_cursor', v_event_page->>'next_cursor',
    'pending', v_pending,
    'pending_total',v_pending_page->'total','pending_cursor',v_pending_page->>'next_cursor',
    'schedule_state', case
      when p_medium = 'manga' and jsonb_array_length(coalesce(v_upcoming, '[]'::jsonb)) = 0
        then 'no_verified_schedule'
      else 'ok'
    end,
    'next_cursor', v_next,
    'club', jsonb_build_object('state', v_club_state, 'label', v_club_label, 'items', coalesce(v_club, '[]'::jsonb))
  );
end;
$$;

revoke all on function public.home_bundle_v1(text, text, integer, integer, integer, text) from public;
grant execute on function public.home_bundle_v1(text, text, integer, integer, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Detail bundle. Selected section only. Missing copy stays null.
-- ---------------------------------------------------------------------------

create or replace function public.series_detail_bundle_v1(
  p_medium text,
  p_media_id integer,
  p_section_id uuid default null,
  p_locale text default 'en'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_header jsonb;
  v_sections jsonb;
  v_units jsonb;
  v_copy jsonb;
  v_user jsonb;
  v_themes jsonb;
  v_coverage jsonb;
  v_cast jsonb;
  v_series uuid;
  v_material jsonb;
  v_principals jsonb;
  v_guides jsonb;
  v_units_next jsonb;
  v_default_section uuid;
  v_edition text;
  v_editions jsonb;
  v_editions_next text;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') or p_media_id is null then
    raise exception 'INVALID_TARGET';
  end if;

  select sp.series_id,sec.id into v_series,v_default_section from public.series_entry_spans sp
  join public.series sr on sr.id = sp.series_id and sr.grouping_state = 'approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where (p_medium = 'anime' and sp.anime_id = p_media_id) or (p_medium = 'manga' and sp.manga_id = p_media_id);
  if p_medium='anime' and p_section_id is null then p_section_id:=v_default_section;end if;
  if p_section_id is not null then
    if p_medium <> 'anime' or v_series is null or not exists (
      select 1 from public.series_sections sec where sec.id = p_section_id and sec.series_id = v_series and sec.state = 'approved'
    ) then raise exception 'INVALID_SECTION'; end if;
    if not exists(select 1 from public.series_entry_spans sp where sp.section_id=p_section_id and sp.anime_id=p_media_id) then
      select sp.anime_id into p_media_id from public.series_entry_spans sp
      where sp.section_id=p_section_id and sp.series_id=v_series and sp.medium='anime'
      order by sp.source_range_start nulls first,sp.anime_id limit 1;
    end if;
    if p_media_id is null then raise exception 'INVALID_SECTION'; end if;
  end if;

  -- An edition is an authoritative catalogue-unit source key, never a synthetic
  -- manga "part". Prefer the tracked exact unit's edition; otherwise use the first
  -- available key. Every initial/subsequent unit page stays within that edition.
  select u.edition_key into v_edition from public.catalogue_units u
  where u.id=case when p_medium='anime' then
    (select unit_id from public.anime_user_lists where user_id=v_uid::text and anime_id=p_media_id)
    else (select unit_id from public.manga_user_lists where user_id=v_uid::text and manga_id=p_media_id) end
    and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
    and (p_section_id is null or u.section_id=p_section_id or u.section_id is null);
  if v_edition is null then
    select u.edition_key into v_edition from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
    order by u.edition_key,u.order_key,u.id limit 1;
  end if;
  select coalesce(jsonb_agg(edition_key order by edition_key),'[]'::jsonb) into v_editions
  from (select distinct u.edition_key from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
    order by u.edition_key limit 51) keys;
  if jsonb_array_length(v_editions)>50 then
    v_editions_next:=v_editions->>49; v_editions:=v_editions-50;
  end if;

  if p_medium = 'anime' then
    -- v_series was resolved through approved continuity above.
    select jsonb_build_object(
      'media_id', a.id,
      'title', coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled'),
      'banner_image', a.banner_image,
      'cover_image', a.cover_image_large,
      'format', a.format,
      'catalogue_status', a.status,
      'episodes', a.episodes,
      'description', coalesce(nullif(a.synopsis_enhanced,''),a.description_normalized,a.description),
      'copy_source',case when nullif(a.synopsis_enhanced,'') is not null then 'catalogue_enrichment' else 'catalogue_source' end,
      'artwork_scope', case when a.banner_image is null then 'cover_fallback' else 'banner' end
    ) into v_header
    from public.anime a where a.id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', u.id, 'label', u.label, 'order_key', u.order_key::text, 'available', u.available, 'edition_key', u.edition_key, 'title', u.title, 'synopsis', u.synopsis, 'image_url', u.image_url
    ) order by u.order_key,u.id), '[]'::jsonb)
    into v_units
    from (
      select id, label, order_key, available, edition_key, title, synopsis, image_url
      from public.catalogue_units
      where anime_id = p_media_id
        and (p_section_id is null or section_id = p_section_id or section_id is null)
        and edition_key=v_edition
      order by order_key,id
      limit 20
    ) u;

    select coalesce(jsonb_agg(jsonb_build_object(
      'role', t.role, 'song_title', t.song_title, 'artist', t.artist,
      'external_url', t.external_url, 'match_state', t.match_state
    ) order by t.sequence_order), '[]'::jsonb)
    into v_themes
    from (
      select role, song_title, artist, external_url, match_state, sequence_order
      from public.theme_links
      where anime_id = p_media_id
        and (p_section_id is null or section_id = p_section_id or section_id is null)
      order by sequence_order
      limit 20
    ) t;

    select jsonb_build_object(
      'server_revision', l.server_revision,
      'lifecycle_id', l.lifecycle_id,
      'progress', l.progress,
      'progress_label', l.progress_label,
      'list_type', l.list_type,
      'rating', l.rating,
      'notes', l.notes,
      'unit_id', l.unit_id
    ) into v_user
    from public.anime_user_lists l
    where l.user_id = v_uid::text and l.anime_id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name_full, 'role', ac.role, 'image_url', c.image_large, 'description', c.description
    )), '[]'::jsonb)
    into v_cast
    from (
      select character_id, role
      from public.anime_characters
      where anime_id = p_media_id
      order by case when role = 'MAIN' then 0 else 1 end, id
      limit 12
    ) ac
    join public.characters c on c.id = ac.character_id;
  else
    -- v_series was resolved through approved continuity above.
    select jsonb_build_object(
      'media_id', m.id,
      'title', coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled'),
      'cover_image', m.cover_image_large,
      'format', m.format,
      'catalogue_status', m.status,
      'chapters', m.chapters,
      'volumes', m.volumes,
      'description', coalesce(nullif(m.synopsis_enhanced,''),m.description_normalized,m.description),
      'copy_source',case when nullif(m.synopsis_enhanced,'') is not null then 'catalogue_enrichment' else 'catalogue_source' end,
      'artwork_scope', 'cover'
    ) into v_header
    from public.manga m where m.id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', u.id, 'label', u.label, 'order_key', u.order_key::text, 'available', u.available, 'edition_key', u.edition_key, 'title', u.title, 'synopsis', u.synopsis, 'image_url', u.image_url
    ) order by u.order_key,u.id), '[]'::jsonb)
    into v_units
    from (
      select id, label, order_key, available, edition_key, title, synopsis, image_url
      from public.catalogue_units
      where manga_id = p_media_id
        and edition_key=v_edition
      order by order_key,id
      limit 20
    ) u;

    v_themes := '[]'::jsonb;

    select jsonb_build_object(
      'server_revision', l.server_revision,
      'lifecycle_id', l.lifecycle_id,
      'progress', l.progress,
      'progress_label', l.progress_label,
      'volumes_progress', l.volumes_progress,
      'list_type', l.list_type,
      'rating', l.rating,
      'notes', l.notes,
      'unit_id', l.unit_id
    ) into v_user
    from public.manga_user_lists l
    where l.user_id = v_uid::text and l.manga_id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name_full, 'role', mc.role, 'image_url', c.image_large, 'description', c.description
    )), '[]'::jsonb)
    into v_cast
    from (
      select character_id, role
      from public.manga_characters
      where manga_id = p_media_id
      order by case when role = 'MAIN' then 0 else 1 end, id
      limit 12
    ) mc
    join public.characters c on c.id = mc.character_id;
  end if;

  if v_header is null then
    raise exception 'INVALID_TARGET';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'kind', s.kind, 'ordinal', s.ordinal, 'name', s.name, 'sort_order', s.sort_order,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('media_id',a.id,'title',coalesce(a.title_english,a.title_romaji,a.title_native),
      'banner_image',a.banner_image,'cover_image',a.cover_image_large,'episodes',a.episodes) order by sp.source_range_start nulls first,a.id),'[]'::jsonb)
      from public.series_entry_spans sp join public.anime a on a.id=sp.anime_id where sp.section_id=s.id)
  ) order by s.sort_order), '[]'::jsonb)
  into v_sections
  from public.series_sections s
  where s.series_id = v_series and s.state = 'approved';

  select jsonb_build_object(
    'premise', d.premise, 'hook', d.hook, 'synopsis', d.synopsis,
    'provenance', d.provenance, 'review_state', d.review_state,
    'story_state', case when d.premise is null and d.hook is null then 'missing' else 'present' end
  ) into v_copy
  from public.detail_copy d
  where d.locale = coalesce(p_locale, 'en')
    and ((p_medium = 'anime' and d.anime_id = p_media_id) or (p_medium = 'manga' and d.manga_id = p_media_id))
    and (p_section_id is null or d.section_id = p_section_id or d.section_id is null)
  order by case when d.section_id = p_section_id then 0 else 1 end,
    case when d.review_state='approved' then 0 when d.provenance<>'catalogue_bridge_v1' then 1 else 2 end,
    d.provenance, d.id
  limit 1;

  if v_copy is null then
    v_copy := jsonb_build_object('story_state', case when v_header->>'description' is null then 'missing' else 'source' end, 'premise', null, 'hook', null, 'synopsis', v_header->>'description', 'provenance', v_header->>'copy_source');
  end if;

  select jsonb_build_object(
    'source_kind', c.source_kind,
    'mapping_state', c.mapping_state,
    'starts_at', c.starts_at,
    'ends_at', c.ends_at,
    'read_next', c.read_next,
    'source_manga_id', c.source_manga_id,
    'evidence', c.evidence
  ) into v_coverage
  from public.adaptation_coverage c
  where ((p_medium = 'anime' and c.anime_id = p_media_id)
     or (p_medium = 'manga' and c.source_manga_id = p_media_id))
    and (p_medium = 'manga' or p_section_id is null or c.section_id = p_section_id or c.section_id is null)
  order by c.revision desc
  limit 1;

  select jsonb_build_object('image_digest', image_digest, 'base', base_color, 'deep', deep_color,
      'wash', wash_color, 'edge', edge_color, 'ink', ink_color)
  into v_material from public.artwork_materials
  where image_url=coalesce(v_header->>'banner_image',v_header->>'cover_image') and is_current;

  if p_medium='anime' then
    select coalesce(jsonb_agg(row_data order by priority, entity_id),'[]'::jsonb) into v_principals from (
      select jsonb_build_object('id',st.id,'kind','studio','name',st.name,'role','Animation studio') row_data, 0 priority, st.id entity_id
      from public.anime_studios j join public.studios st on st.id=j.studio_id where j.anime_id=p_media_id
      union all
      select jsonb_build_object('id',st.id,'kind','staff','name',st.name_full,'role',j.role,'image_url',st.image_large,'description',st.description),
        case when j.role ilike '%director%' then 1 else 2 end, st.id
      from public.anime_staff j join public.staff st on st.id=j.staff_id where j.anime_id=p_media_id
        and (j.role ilike '%director%' or j.role ilike '%original creator%' or j.role ilike '%series composition%')
      order by priority,entity_id limit 8
    ) credits;
  else
    select coalesce(jsonb_agg(row_data order by entity_id),'[]'::jsonb) into v_principals from (
      select jsonb_build_object('id',au.id,'kind','author','name',au.name_full,'role',j.role,'image_url',au.image_large,'description',au.description) row_data, au.id entity_id
      from public.manga_authors j join public.authors au on au.id=j.author_id where j.manga_id=p_media_id order by au.id limit 8
    ) credits;
  end if;

  select coalesce(jsonb_agg(row_data order by sort_order,anime_id),'[]'::jsonb) into v_guides from (
    select jsonb_build_object('anime_id',c.anime_id,'section_id',c.section_id,'season',sec.name,
      'source_kind',c.source_kind,'mapping_state',c.mapping_state,'starts_at',c.starts_at,'ends_at',c.ends_at,
      'read_next',c.read_next,'source_manga_id',c.source_manga_id,'evidence',c.evidence) row_data,
      c.anime_id,coalesce(sec.sort_order,0) sort_order
    from (select distinct on (anime_id,section_id) * from public.adaptation_coverage
      where source_manga_id=p_media_id order by anime_id,section_id,revision desc,id desc) c
    left join public.series_sections sec on sec.id=c.section_id
    where p_medium='manga' and c.source_manga_id=p_media_id and c.mapping_state in ('exact','partial')
      and (sec.id is null or sec.state='approved')
    order by sort_order,c.anime_id limit 50
  ) guides;

  -- Return the exact last visible unit only when a further page exists.
  if jsonb_array_length(v_units)>0 and exists(
    select 1 from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_medium='manga' or p_section_id is null or u.section_id=p_section_id or u.section_id is null)
      and u.edition_key=v_edition
      and (u.order_key,u.id)>((v_units->-1->>'order_key')::numeric,(v_units->-1->>'id')::uuid)
  ) then
    v_units_next:=jsonb_build_object('order',v_units->-1->'order_key','id',v_units->-1->'id');
  end if;

  return jsonb_build_object(
    'medium', p_medium,
    'media_id', p_media_id,
    'series_id', v_series,
    'section_id', p_section_id,
    'header', v_header,
    'sections', coalesce(v_sections, '[]'::jsonb),
    'units', coalesce(v_units, '[]'::jsonb),
    'units_next',v_units_next,
    'edition',v_edition,'editions',v_editions,'editions_next',v_editions_next,
    'units_state', case when jsonb_array_length(coalesce(v_units, '[]'::jsonb)) = 0 then 'not_in_catalogue' else 'ok' end,
    'copy', v_copy,
    'themes', coalesce(v_themes, '[]'::jsonb),
    'coverage', v_coverage,
    'cast', coalesce(v_cast, '[]'::jsonb),
    'principals', v_principals, 'material', v_material, 'adaptations', v_guides,
    'user', v_user
  );
end;
$$;

revoke all on function public.series_detail_bundle_v1(text, integer, uuid, text) from public;
grant execute on function public.series_detail_bundle_v1(text, integer, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Collection page grouped by approved series before the keyset limit.
-- An entry with no series is its own group. Child progress is inside the group.
-- ---------------------------------------------------------------------------

create or replace function public.collection_series_page_v1(
  p_medium text,
  p_status text default null,
  p_query text default null,
  p_limit integer default 30,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_limit integer;
  v_query text;
  v_cursor_at timestamptz;
  v_cursor_key text;
  v_rows jsonb;
  v_next text;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  v_user := v_uid::text;
  v_limit := least(50, greatest(1, coalesce(p_limit, 30)));
  v_query := left(replace(replace(coalesce(p_query, ''), '%', ''), '_', ''), 80);

  if p_cursor is not null and p_cursor <> '' then
    begin
      v_cursor_at := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_key := split_part(p_cursor, '|', 2);
    exception when others then
      raise exception 'INVALID_CURSOR';
    end;
  end if;

  if p_medium = 'anime' then
    with rows as (
      select
        coalesce(sp.series_id::text, 'entry:anime:' || l.anime_id::text) as group_key,
        l.updated_at,
        l.anime_id as media_id,
        l.list_type,
        l.progress,
        l.server_revision,
        l.lifecycle_id,
        coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled') as title,
        a.title_synonyms
      from public.anime_user_lists l
      join public.anime a on a.id = l.anime_id
      left join lateral (select sp.* from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved' where sp.anime_id=l.anime_id order by sp.id limit 1) sp on true
      where l.user_id = v_user
        and (p_status is null or l.list_type = p_status)
        and (
          v_query = ''
          or a.title_english ilike '%' || v_query || '%'
          or a.title_romaji ilike '%' || v_query || '%'
          or a.title_native ilike '%' || v_query || '%'
          or exists (select 1 from unnest(coalesce(a.title_synonyms, array[]::text[])) syn where syn ilike '%' || v_query || '%')
        )
    ), grouped as (
      select group_key, max(updated_at) as updated_at, count(*) as child_count
      from rows
      group by group_key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'group_key', group_key, 'updated_at', updated_at, 'child_count', child_count,
      'children_next',case when child_count>50 then (select min(r.media_id) from (select media_id from rows where rows.group_key=page.group_key order by media_id desc limit 50)r) end,
      'children', (select coalesce(jsonb_agg(jsonb_build_object('media_id',r.media_id,'list_type',r.list_type,'progress',r.progress,
        'server_revision',r.server_revision,'lifecycle_id',r.lifecycle_id,'title',r.title) order by r.media_id desc),'[]'::jsonb)
        from (select * from rows where rows.group_key=page.group_key order by media_id desc limit 50) r)
    ) order by updated_at desc, group_key desc), '[]'::jsonb)
    into v_rows
    from (
      select * from grouped g
      where v_cursor_at is null
         or g.updated_at < v_cursor_at
         or (g.updated_at = v_cursor_at and g.group_key < v_cursor_key)
      order by g.updated_at desc, g.group_key desc
      limit v_limit
    ) page;
  else
    with rows as (
      select
        coalesce(sp.series_id::text, 'entry:manga:' || l.manga_id::text) as group_key,
        l.updated_at,
        l.manga_id as media_id,
        l.list_type,
        l.progress,
        l.server_revision,
        l.lifecycle_id,
        coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled') as title
      from public.manga_user_lists l
      join public.manga m on m.id = l.manga_id
      left join lateral (select sp.* from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved' where sp.manga_id=l.manga_id order by sp.id limit 1) sp on true
      where l.user_id = v_user
        and (p_status is null or l.list_type = p_status)
        and (
          v_query = ''
          or m.title_english ilike '%' || v_query || '%'
          or m.title_romaji ilike '%' || v_query || '%'
          or m.title_native ilike '%' || v_query || '%'
        )
    ), grouped as (
      select group_key, max(updated_at) as updated_at, count(*) as child_count
      from rows
      group by group_key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'group_key', group_key, 'updated_at', updated_at, 'child_count', child_count,
      'children_next',case when child_count>50 then (select min(r.media_id) from (select media_id from rows where rows.group_key=page.group_key order by media_id desc limit 50)r) end,
      'children', (select coalesce(jsonb_agg(jsonb_build_object('media_id',r.media_id,'list_type',r.list_type,'progress',r.progress,
        'server_revision',r.server_revision,'lifecycle_id',r.lifecycle_id,'title',r.title) order by r.media_id desc),'[]'::jsonb)
        from (select * from rows where rows.group_key=page.group_key order by media_id desc limit 50) r)
    ) order by updated_at desc, group_key desc), '[]'::jsonb)
    into v_rows
    from (
      select * from grouped g
      where v_cursor_at is null
         or g.updated_at < v_cursor_at
         or (g.updated_at = v_cursor_at and g.group_key < v_cursor_key)
      order by g.updated_at desc, g.group_key desc
      limit v_limit
    ) page;
  end if;

  if jsonb_array_length(coalesce(v_rows, '[]'::jsonb)) = v_limit then
    v_next := (v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'updated_at')
      || '|' || (v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'group_key');
  end if;

  return jsonb_build_object(
    'medium', p_medium,
    'groups', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', v_next
  );
end;
$$;

revoke all on function public.collection_series_page_v1(text, text, text, integer, text) from public;
grant execute on function public.collection_series_page_v1(text, text, text, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Import jobs. Merge only. Account API for MAL is not claimed here.
-- ---------------------------------------------------------------------------

create or replace function public.start_library_import_v1(
  p_provider text,
  p_source_kind text,
  p_medium_filter text,
  p_idempotency_key text,
  p_payload_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_provider not in ('anilist', 'myanimelist')
     or p_source_kind not in ('account', 'export')
     or p_medium_filter not in ('anime', 'manga', 'both')
     or p_idempotency_key is null or length(p_idempotency_key) < 8
     or p_payload_hash is null or length(p_payload_hash) < 8 then
    raise exception 'INVALID_PAYLOAD';
  end if;
  -- OAuth/PKCE is qualified by the connector. Account and file sources enter the
  -- same owner-scoped structured job; neither endpoint stores provider tokens.

  select * into v_job
  from public.library_import_jobs
  where user_id = v_uid and idempotency_key = p_idempotency_key;

  if v_job.id is not null then
    if v_job.payload_hash <> p_payload_hash or v_job.provider <> p_provider or v_job.source_kind <> p_source_kind or v_job.medium_filter <> p_medium_filter then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', true, 'home_revision', v_job.home_revision);
  end if;

  if exists (
    select 1 from public.library_import_jobs
    where user_id = v_uid and provider = p_provider 
      and state in ('queued', 'running')
  ) then
    raise exception 'IMPORT_ALREADY_ACTIVE';
  end if;

  insert into public.library_import_jobs
    (user_id, provider, source_kind, medium_filter, idempotency_key, payload_hash, state)
  values
    (v_uid, p_provider, p_source_kind, p_medium_filter, p_idempotency_key, p_payload_hash, 'running')
  returning * into v_job;

  insert into public.library_import_baselines(job_id, medium, media_id, lifecycle_id, server_revision)
  select v_job.id, 'anime', anime_id, lifecycle_id, server_revision from public.anime_user_lists
    where user_id = v_uid::text and p_medium_filter in ('anime', 'both')
  union all
  select v_job.id, 'manga', manga_id, lifecycle_id, server_revision from public.manga_user_lists
    where user_id = v_uid::text and p_medium_filter in ('manga', 'both');

  return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', false, 'home_revision', 0);
end;
$$;

create or replace function public.apply_import_chunk_v1(p_job_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_item jsonb;
  v_medium text;
  v_external text;
  v_media_id integer;
  v_status text;
  v_progress integer;
  v_notes text;
  v_added integer := 0;
  v_updated_count integer := 0;
  v_conflict integer := 0;
  v_unmatched integer := 0;
  v_unchanged integer := 0;
  v_list_type text;
  v_updated timestamptz;
  v_local_progress integer;
  v_local_notes text;
  v_baseline public.library_import_baselines%rowtype;
  v_current_revision bigint;
  v_current_lifecycle uuid;
  v_request_hash text;
  v_prior_hash text;
  v_prior_disposition text;
  v_disposition text;
  v_written integer;
  v_ref_found boolean;
  v_unavailable jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'INVALID_PAYLOAD';
  end if;

  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.state not in ('queued', 'running', 'ready', 'ready_with_issues') then raise exception 'JOB_NOT_RUNNING'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_medium := lower(v_item->>'medium');
    v_external := v_item->>'external_id';
    if v_medium not in ('anime', 'manga') or v_external is null or v_external !~ '^[0-9]{1,10}$'
       or (v_job.medium_filter <> 'both' and v_medium <> v_job.medium_filter) then raise exception 'INVALID_ITEM'; end if;
    if length(coalesce(v_item->>'source_list_options',''))>16384 then raise exception 'OPTIONS_TOO_LARGE'; end if;
    v_unavailable:='[]'::jsonb;
    if nullif(v_item->>'source_list_options','') is not null then
      begin
        v_unavailable:=coalesce((v_item->>'source_list_options')::jsonb->'unavailable_fields','[]'::jsonb);
        if jsonb_typeof(v_unavailable)<>'array' then raise exception 'INVALID_SOURCE_OPTIONS'; end if;
      exception when others then raise exception 'INVALID_SOURCE_OPTIONS'; end;
    end if;
    if v_item->>'normalized_rating' is not null and (v_item->>'normalized_rating')::integer not between 1 and 10 then raise exception 'INVALID_RATING'; end if;
    v_request_hash := encode(digest(v_item::text, 'sha256'), 'hex');
    select request_hash, disposition into v_prior_hash, v_prior_disposition from public.library_import_items
      where job_id = v_job.id and provider = v_job.provider and external_id = v_external and medium = v_medium;
    if found then
      if v_prior_hash is distinct from v_request_hash then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
      continue; -- A terminal item's write and count are committed together; replay changes neither.
    end if;
    if v_job.state in ('ready', 'ready_with_issues') then raise exception 'JOB_ALREADY_FINISHED'; end if;
    v_media_id := null;
    select case when unresolved then null when v_medium='anime' then anime_id else manga_id end
      into v_media_id from public.provider_entry_refs
      where provider=v_job.provider and medium=v_medium and external_id=v_external;
    v_ref_found := found;
    if not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'anilist' then
      select min(a.id) into v_media_id from public.anime a
      where a.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'anilist' then
      select min(m.id) into v_media_id from public.manga m
      where m.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'myanimelist' then
      select min(a.id) into v_media_id from public.anime a where a.mal_id = v_external::integer having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'myanimelist' then
      select min(m.id) into v_media_id from public.manga m where m.mal_id = v_external::integer having count(*)=1;
    end if;

    if v_media_id is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash, detail)
      values (v_job.id, v_job.provider, coalesce(v_external, ''), coalesce(v_medium, ''), 'unmatched', v_request_hash, 'catalogue id not found')
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'unmatched';
      continue;
    end if;

    v_status := lower(coalesce(v_item->>'status', ''));
    v_list_type := case v_status
      when 'watching' then 'WATCHING'
      when 'current' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      when 'reading' then 'READING'
      when 'completed' then 'COMPLETED'
      when 'planning' then 'PLANNING'
      when 'plan to watch' then 'PLANNING'
      when 'plan to read' then 'PLANNING'
      when 'dropped' then 'DROPPED'
      when 'paused' then 'PAUSED'
      when 'on-hold' then 'PAUSED'
      when 'on hold' then 'PAUSED'
      when 'repeating' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      else null
    end;
    v_progress := coalesce((v_item->>'progress')::integer, 0);
    v_notes := v_item->>'notes';
    if coalesce(v_item->>'score_raw', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (v_item->>'score_raw')::numeric = 0 then
      v_item := v_item || jsonb_build_object('score_raw', null);
    end if;

    if v_medium = 'anime' then
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.anime_user_lists where user_id = v_uid::text and anime_id = v_media_id
      for update;
    else
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.manga_user_lists where user_id = v_uid::text and manga_id = v_media_id
      for update;
    end if;

    select * into v_baseline from public.library_import_baselines
      where job_id = v_job.id and medium = v_medium and media_id = v_media_id;
    if (v_baseline.media_id is not null and (v_current_revision is distinct from v_baseline.server_revision
          or v_current_lifecycle is distinct from v_baseline.lifecycle_id))
       or (v_baseline.media_id is null and v_current_lifecycle is not null)
       or exists (select 1 from public.list_entry_tombstones where user_id = v_uid::text and medium = v_medium
          and media_id = v_media_id and removed_at >= v_job.created_at) then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
      values (v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash)
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'conflict';
      continue;
    end if;

    if v_list_type is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash, detail)
      values(v_job.id, v_job.provider, v_external, v_medium, 'unmatched', v_request_hash, 'unsupported status');
      continue;
    end if;

    if v_medium = 'anime' then
      insert into public.anime_user_lists
        (user_id, anime_id, list_type, progress, notes, score_raw, score_scale, repeat_count, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0), v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, anime_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.anime_user_lists.progress end,
        notes = coalesce(excluded.notes, public.anime_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.anime_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.anime_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.anime_user_lists.repeat_count end,
        started_raw = coalesce(excluded.started_raw, public.anime_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.anime_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.anime_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.anime_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.anime_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.anime_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.anime_user_lists.rating)
      where public.anime_user_lists.server_revision = v_baseline.server_revision
        and public.anime_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    else
      insert into public.manga_user_lists
        (user_id, manga_id, list_type, progress, notes, score_raw, score_scale, repeat_count, volumes_progress, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0),
        nullif(v_item->>'volumes_progress', '')::integer,
        v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, manga_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.manga_user_lists.progress end,
        notes = coalesce(excluded.notes, public.manga_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.manga_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.manga_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.manga_user_lists.repeat_count end,
        volumes_progress = coalesce(excluded.volumes_progress, public.manga_user_lists.volumes_progress),
        started_raw = coalesce(excluded.started_raw, public.manga_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.manga_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.manga_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.manga_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.manga_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.manga_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.manga_user_lists.rating)
      where public.manga_user_lists.server_revision = v_baseline.server_revision
        and public.manga_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    end if;

    get diagnostics v_written = row_count;
    if v_written = 0 then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash)
      values(v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash);
      continue;
    end if;
    if v_updated is null then
      v_disposition := 'added';
      v_added := v_added + 1;
    else
      v_disposition := 'updated';
      v_updated_count := v_updated_count + 1;
    end if;

    insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
    values (v_job.id, v_job.provider, v_external, v_medium, v_disposition, v_request_hash)
    on conflict (job_id, provider, external_id, medium) do update set disposition = 'applied';

    insert into public.provider_entry_refs (provider, external_id, medium, anime_id, manga_id, unresolved)
    values (
      v_job.provider, v_external, v_medium,
      case when v_medium = 'anime' then v_media_id else null end,
      case when v_medium = 'manga' then v_media_id else null end,
      false
    )
    on conflict (provider, external_id, medium) do nothing;
  end loop;

  update public.library_import_jobs
    set counters = coalesce(counters, '{}'::jsonb) || jsonb_build_object(
          'added', coalesce((counters->>'added')::integer, 0) + v_added,
          'updated', coalesce((counters->>'updated')::integer, 0) + v_updated_count,
          'conflict', coalesce((counters->>'conflict')::integer, 0) + v_conflict,
          'unmatched', coalesce((counters->>'unmatched')::integer, 0) + v_unmatched,
          'unchanged', coalesce((counters->>'unchanged')::integer, 0) + v_unchanged
        ),
        updated_at = now()
  where id = v_job.id;

  if v_added + v_updated_count > 0 then
    insert into public.home_publications(user_id, medium, revision)
    select v_uid::text, medium, 1 from (select distinct lower(value->>'medium') medium from jsonb_array_elements(p_items)) media
    on conflict(user_id, medium) do update set revision = public.home_publications.revision + 1;
    update public.library_import_jobs j set home_revision = p.revision from public.home_publications p
      where j.id = v_job.id and p.user_id = v_uid::text and p.medium = case when v_job.medium_filter = 'both' then 'anime' else v_job.medium_filter end;
  end if;

  return jsonb_build_object(
    'applied', v_added + v_updated_count,
    'added', v_added,
    'updated', v_updated_count,
    'conflict', v_conflict,
    'unmatched', v_unmatched,
    'unchanged', v_unchanged
  );
end;
$$;

create or replace function public.finish_library_import_v1(p_job_id uuid, p_exhausted boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_state text;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.state not in ('queued','running','ready','ready_with_issues') then
    raise exception 'JOB_NOT_RUNNING';
  end if;
  if v_job.state in ('ready','ready_with_issues') then
    return public.import_job_status_v1(p_job_id);
  end if;
  if not coalesce(p_exhausted, false) then
    v_state := 'running';
  elsif coalesce((v_job.counters->>'unmatched')::integer, 0) > 0
     or coalesce((v_job.counters->>'conflict')::integer, 0) > 0 then
    v_state := 'ready_with_issues';
  else
    v_state := 'ready';
  end if;
  update public.library_import_jobs set state = v_state, updated_at = now() where id = v_job.id;
  return jsonb_build_object('state', v_state, 'home_revision', v_job.home_revision, 'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)), 'counters', v_job.counters);
end;
$$;

create or replace function public.import_job_status_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return jsonb_build_object(
    'job_id', v_job.id,
    'state', v_job.state,
    'provider', v_job.provider,
    'source_kind', v_job.source_kind,
    'counters', v_job.counters,
    'discovered_total', v_job.discovered_total,
    'home_revision', v_job.home_revision,
    'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)),
    'sanitized_error', v_job.sanitized_error,
    'retry_after', v_job.retry_after
  );
end;
$$;

revoke all on function public.start_library_import_v1(text, text, text, text, text) from public;
revoke all on function public.apply_import_chunk_v1(uuid, jsonb) from public;
revoke all on function public.finish_library_import_v1(uuid, boolean) from public;
revoke all on function public.import_job_status_v1(uuid) from public;
grant execute on function public.start_library_import_v1(text, text, text, text, text) to authenticated;
grant execute on function public.apply_import_chunk_v1(uuid, jsonb) to authenticated;
grant execute on function public.finish_library_import_v1(uuid, boolean) to authenticated;
grant execute on function public.import_job_status_v1(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Concierge apply / undo: progress and status go through the receipt fence.
-- Notes and rating stay direct writes. Session idempotency is unchanged.
-- Replaces public.apply_import_session / undo_import_session from
-- 20261005130000 without editing that applied migration.
-- ---------------------------------------------------------------------------

create or replace function public.apply_import_session(
  p_user_id uuid,
  p_session_id uuid,
  p_idempotency_key text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;     -- list tables keep the legacy TEXT user_id (auth.uid()::text)
  v_session_id uuid;
  v_existing uuid;
  v_item jsonb;
  v_ord integer;
  v_type text;
  v_media_id integer;
  v_action text;
  v_table text;
  v_idcol text;
  v_expected jsonb;
  v_values jsonb;
  v_journal jsonb;
  v_cur jsonb;
  v_written jsonb;
  v_prev jsonb;
  v_after jsonb;
  v_outcome text;
  v_error text;
  v_applied integer := 0;
  v_locked bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
  if p_user_id is null then
    raise exception 'apply_import_session: p_user_id is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'apply_import_session: p_items must be an array of 1..100 planned items' using errcode = '22023';
  end if;
  if p_idempotency_key is not null and char_length(p_idempotency_key) not between 1 and 128 then
    raise exception 'apply_import_session: p_idempotency_key must be 1..128 characters' using errcode = '22023';
  end if;

  -- Replay: the same user action (key) never applies twice.
  if p_idempotency_key is not null then
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if found then
      return public._import_apply_outcome(v_existing, true);
    end if;
  end if;

  v_session_id := coalesce(p_session_id, gen_random_uuid());
  begin
    insert into public.import_sessions (id, user_id, status, source, idempotency_key)
    values (v_session_id, p_user_id, 'draft', 'chat', p_idempotency_key);
  exception when unique_violation then
    -- A concurrent call with the same key committed first (this insert waited on it).
    if p_idempotency_key is null then
      raise;
    end if;
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    return public._import_apply_outcome(v_existing, true);
  end;

  -- Import origin for the taste_capture triggers, for exactly this transaction.
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, v_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  -- Lock order (see header, review R2): every existing target row of the batch,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first
  -- write (the first write takes the user's recompute-queue row through taste_capture).
  -- Malformed identities are not cast here; the item loop rejects them.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'ANIME' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'MANGA' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item, v_ord in
    select e.value, e.ordinality::integer
    from jsonb_array_elements(p_items) with ordinality as e(value, ordinality)
    order by e.ordinality
  loop
    v_type := v_item ->> 'media_type';
    v_action := v_item ->> 'import_action';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or jsonb_typeof(v_item -> 'media_id') is distinct from 'number'
       or (case when (v_item ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                then (v_item ->> 'media_id')::bigint > 2147483647 else true end)
       or v_action is null or v_action not in ('add', 'update', 'skip') then
      raise exception 'apply_import_session: item % is not a planned item (media_type/media_id/import_action)', v_ord
        using errcode = '22023';
    end if;
    v_media_id := (v_item ->> 'media_id')::integer;
    v_table := case v_type when 'ANIME' then 'anime_user_lists' else 'manga_user_lists' end;
    v_idcol := case v_type when 'ANIME' then 'anime_id' else 'manga_id' end;
    v_expected := case when jsonb_typeof(v_item -> 'expected') = 'object' then v_item -> 'expected' end;
    -- Descriptive journal fields are type-checked, never cast blindly: a malformed value is
    -- replaced by its default instead of aborting the Apply.
    v_journal := case when jsonb_typeof(v_item -> 'journal') = 'object' then v_item -> 'journal' else '{}'::jsonb end;
    v_cur := null; v_written := null; v_prev := null; v_after := null; v_outcome := null; v_error := null;

    if v_action = 'skip' then
      v_outcome := 'skipped';
    else
      -- Current row under a row lock (concurrent writers of this row wait for us).
      if v_type = 'ANIME' then
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.anime_user_lists l
        where l.user_id = v_uid and l.anime_id = v_media_id
        for update;
      else
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.manga_user_lists l
        where l.user_id = v_uid and l.manga_id = v_media_id
        for update;
      end if;

      -- Compare-and-set on the state the client reviewed.
      if v_expected is not null then
        if v_cur is null then
          v_outcome := 'conflict';
          v_error := 'Entry no longer exists (deleted since parse)';
        elsif exists (select 1 from jsonb_each(v_expected) e where (v_cur -> e.key) is distinct from e.value) then
          v_outcome := 'conflict';
          v_error := 'State changed since parse — review and retry';
        end if;
      end if;

      if v_outcome is null then
        begin
          if v_cur is null then
            v_values := coalesce(v_item -> 'insert_values', '{}'::jsonb);
            if v_type = 'ANIME' then
              insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, anime_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            else
              insert into public.manga_user_lists (user_id, manga_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, manga_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            end if;
            if v_written is null then
              -- The row was inserted by another transaction after our read: retry the whole Apply.
              raise exception 'apply_import_session: % % was written concurrently', v_type, v_media_id
                using errcode = '40001';
            end if;
            v_after := v_written;          -- an insert journals the whole tracked row
          else
            v_values := coalesce(v_item -> 'update_values', '{}'::jsonb);
            -- Progress/status go through the series receipt fence. Notes/rating stay
            -- direct writes and still advance server_revision via their triggers.
            if v_values ? 'progress' or v_values ? 'list_type' then
              perform public._fence_set_progress_status(
                v_uid,
                case v_type when 'ANIME' then 'anime' else 'manga' end,
                v_media_id,
                public._import_mutation_id('apply', v_session_id, v_type, v_media_id),
                case when v_values ? 'progress' then (v_values ->> 'progress')::integer end,
                case when v_values ? 'list_type' then v_values ->> 'list_type' end
              );
            end if;
            if v_values ? 'rating' or v_values ? 'notes' then
              if v_type = 'ANIME' then
                update public.anime_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.anime_id = v_media_id;
              else
                update public.manga_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.manga_id = v_media_id;
              end if;
            end if;
            if v_type = 'ANIME' then
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict)
                into v_written
              from public.anime_user_lists l
              where l.user_id = v_uid and l.anime_id = v_media_id;
            else
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict)
                into v_written
              from public.manga_user_lists l
              where l.user_id = v_uid and l.manga_id = v_media_id;
            end if;
            -- an update journals only the fields it wrote, as stored
            select coalesce(jsonb_object_agg(k.key, v_written -> k.key), '{}'::jsonb)
              into v_after
            from jsonb_object_keys(v_values) as k(key)
            where k.key in ('list_type', 'progress', 'rating', 'notes');
            v_prev := v_cur;
          end if;
          v_outcome := 'applied';
          v_applied := v_applied + 1;
        exception when integrity_constraint_violation or data_exception then
          -- This item's data was rejected by the table: item error, batch continues.
          -- A fixed message per SQLSTATE (never schema or constraint names).
          v_outcome := 'error';
          v_error := case when sqlstate = '23503' then 'Unknown title' else 'Value rejected' end;
          v_written := null; v_after := null; v_prev := null;
        end;
      end if;
    end if;

    -- Journal row: REQUIRED (any error here aborts the whole Apply).
    insert into public.import_session_items (
      session_id, raw, parsed, candidates, chosen, action, confidence, state, import_action, error,
      previous_values, after_values
    ) values (
      v_session_id,
      left(case when jsonb_typeof(v_journal -> 'raw') = 'string' then v_journal ->> 'raw'
                else v_type || ':' || v_media_id end, 500),
      case when jsonb_typeof(v_journal -> 'parsed') = 'object' then v_journal -> 'parsed' else '{}'::jsonb end,
      case when jsonb_typeof(v_journal -> 'candidates') = 'array' then v_journal -> 'candidates' else '[]'::jsonb end,
      jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id),
      jsonb_build_object(
        'ordinal', v_ord,
        'outcome', v_outcome,
        'table', case when v_action <> 'skip' then v_table end,
        'key', case when v_action <> 'skip' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) end,
        'before', v_cur,
        -- legacy-compatible upsert image (read by the pre-transaction undo during a mixed deploy)
        'after', case when v_outcome = 'applied' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) || v_after end
      ),
      case when jsonb_typeof(v_journal -> 'confidence') = 'number' then (v_journal ->> 'confidence')::real else 0 end,
      case v_outcome when 'applied' then 'applied' when 'skipped' then 'skipped' else 'error' end,
      v_action,
      v_error,
      case when v_outcome = 'applied' then v_prev end,
      case when v_outcome = 'applied' then v_after end
    );
  end loop;

  -- Session transition: REQUIRED.
  update public.import_sessions
     set status = case when v_applied > 0 then 'applied' else 'failed' end
   where id = v_session_id and status = 'draft';
  if not found then
    raise exception 'apply_import_session: session % could not be finalized', v_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = v_session_id;

  return public._import_apply_outcome(v_session_id, false);
end;
$$;

create or replace function public.undo_import_session(p_user_id uuid, p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;
  v_session record;
  v_latest uuid;
  v_item record;
  v_type text;
  v_media_id integer;
  v_ident jsonb;
  v_after jsonb;
  v_before jsonb;
  v_cur jsonb;
  v_changed text[];
  v_revert text[];
  v_unrestorable text[];
  v_reverted jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_locked bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
  if p_user_id is null or p_session_id is null then
    raise exception 'undo_import_session: p_user_id and p_session_id are required' using errcode = '22023';
  end if;

  select s.id, s.user_id, s.status, s.created_at into v_session
  from public.import_sessions s
  where s.id = p_session_id
  for update;
  -- Another user's session is reported exactly like a missing one.
  if not found or v_session.user_id is distinct from p_user_id then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_session.status = 'cancelled' then
    return jsonb_build_object('result', 'already_undone', 'session_id', p_session_id,
                              'reverted', '[]'::jsonb, 'skipped', '[]'::jsonb, 'warnings', '[]'::jsonb);
  end if;
  if v_session.status <> 'applied'
     or not exists (select 1 from public.import_session_items i where i.session_id = p_session_id and i.state = 'applied') then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- Revert writes are import-origin for the taste_capture triggers (same as Apply).
  -- Also serialises with an in-flight Apply of this user (same context row).
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, p_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  select s.id into v_latest
  from public.import_sessions s
  where s.user_id = p_user_id and s.status = 'applied'
  order by s.created_at desc, s.id desc
  limit 1;
  if v_latest is distinct from p_session_id then
    delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;
    return jsonb_build_object('result', 'not_latest');
  end if;

  -- Lock order (see header, review R2): every existing row this Undo may write,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first write.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'ANIME')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'MANGA')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item in
    select i.id, i.chosen, i.import_action, i.previous_values, i.after_values, i.action
    from public.import_session_items i
    where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
    -- DESCENDING ordinal (review A1): a chain on one title (add then update) unwinds last
    -- write first. Results are prepended, so the response lists items in request order.
    order by case when coalesce(i.action ->> 'ordinal', '') ~ '^[0-9]{1,9}$' then (i.action ->> 'ordinal')::integer else 0 end desc,
             i.created_at desc, i.id desc
  loop
    v_type := v_item.chosen ->> 'mediaType';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or (case when coalesce(v_item.chosen ->> 'mediaId', '') ~ '^[1-9][0-9]{0,9}$'
                then (v_item.chosen ->> 'mediaId')::bigint > 2147483647 else true end) then
      v_warnings := jsonb_build_array(jsonb_build_object('id', v_item.id, 'reason', 'invalid_journal_identity')) || v_warnings;
      continue;
    end if;
    v_media_id := (v_item.chosen ->> 'mediaId')::integer;
    v_ident := jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id);

    -- After image: after_values; journals written before 20261005130000 carry it in action.after.
    select jsonb_object_agg(e.key, e.value) into v_after
    from jsonb_each(case
                      when jsonb_typeof(v_item.after_values) = 'object' then v_item.after_values
                      when jsonb_typeof(v_item.action -> 'after') = 'object' then v_item.action -> 'after'
                      else '{}'::jsonb
                    end) e
    where e.key in ('list_type', 'progress', 'rating', 'notes', 'verdict');
    if v_after is null then
      v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'no_after_image'))) || v_warnings;
      continue;
    end if;
    -- Before image: null means the import created the row.
    v_before := case
                  when jsonb_typeof(v_item.previous_values) = 'object' then v_item.previous_values
                  when jsonb_typeof(v_item.action -> 'before') = 'object' then v_item.action -> 'before'
                end;

    v_cur := null;
    if v_type = 'ANIME' then
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.anime_user_lists l
      where l.user_id = v_uid and l.anime_id = v_media_id
      for update;
    else
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.manga_user_lists l
      where l.user_id = v_uid and l.manga_id = v_media_id
      for update;
    end if;

    if v_cur is null then
      -- Deleted after the import: stays deleted.
      v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'deleted_since_import'))) || v_skipped;
      continue;
    end if;

    select coalesce(array_agg(e.key order by e.key), '{}') into v_changed
    from jsonb_each(v_after) e
    where (v_cur -> e.key) is distinct from e.value;

    if v_before is null then
      -- The import created the row: delete it only when nothing was changed since.
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
        continue;
      end if;
      if v_type = 'ANIME' then
        delete from public.anime_user_lists where user_id = v_uid and anime_id = v_media_id;
      else
        delete from public.manga_user_lists where user_id = v_uid and manga_id = v_media_id;
      end if;
      v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'deleted'))) || v_reverted;
    else
      -- The import changed an existing row: revert each written field still equal to
      -- the after image. The journaled before value is type-checked, never cast blindly:
      -- list_type a string, progress a non-negative integer (a NOT NULL column is never
      -- restored to null), rating null or 1..10, notes null or a string. A field whose
      -- before value is not restorable keeps its value and is reported in warnings.
      select coalesce(array_agg(e.key order by e.key) filter (where r.ok), '{}'),
             coalesce(array_agg(e.key order by e.key) filter (where not r.ok), '{}')
        into v_revert, v_unrestorable
      from jsonb_each(v_after) e
      cross join lateral (
        select coalesce(case e.key
          when 'list_type' then jsonb_typeof(v_before -> 'list_type') = 'string'
          when 'progress'  then jsonb_typeof(v_before -> 'progress') = 'number'
                                and (v_before ->> 'progress') ~ '^[0-9]{1,9}$'
          when 'rating'    then coalesce(jsonb_typeof(v_before -> 'rating'), 'null') = 'null'
                                or (jsonb_typeof(v_before -> 'rating') = 'number'
                                    and (v_before ->> 'rating') ~ '^([1-9]|10)$')
          when 'notes'     then coalesce(jsonb_typeof(v_before -> 'notes'), 'null') in ('null', 'string')
        end, false) as ok
      ) r
      where e.key in ('list_type', 'progress', 'rating', 'notes')
        and (v_cur -> e.key) is not distinct from e.value;
      if cardinality(v_unrestorable) > 0 then
        v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'unrestorable_before_value',
                                                                   'fields', to_jsonb(v_unrestorable)))) || v_warnings;
      end if;
      if cardinality(v_revert) > 0 then
        if 'progress' = any(v_revert) or 'list_type' = any(v_revert) then
          perform public._fence_set_progress_status(
            v_uid,
            case v_type when 'ANIME' then 'anime' else 'manga' end,
            v_media_id,
            public._import_mutation_id('undo', p_session_id, v_type, v_media_id),
            case when 'progress' = any(v_revert) then (v_before ->> 'progress')::integer end,
            case when 'list_type' = any(v_revert) then v_before ->> 'list_type' end
          );
        end if;
        if 'rating' = any(v_revert) or 'notes' = any(v_revert) then
          if v_type = 'ANIME' then
            update public.anime_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.anime_id = v_media_id;
          else
            update public.manga_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.manga_id = v_media_id;
          end if;
        end if;
        v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'restored', 'fields', to_jsonb(v_revert)))) || v_reverted;
      end if;
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
      end if;
      if cardinality(v_revert) = 0 then
        continue;
      end if;
    end if;

    update public.import_session_items set reverted_at = now() where id = v_item.id;
  end loop;

  update public.import_sessions set status = 'cancelled' where id = p_session_id and status = 'applied';
  if not found then
    raise exception 'undo_import_session: session % changed during undo', p_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;

  return jsonb_build_object('result', 'undone', 'session_id', p_session_id,
                            'reverted', v_reverted, 'skipped', v_skipped, 'warnings', v_warnings);
end;
$$;


revoke all on function public.apply_import_session(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.undo_import_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public.apply_import_session(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.undo_import_session(uuid, uuid) to service_role;

-- Private import flags are enforced by the established social readers too.
CREATE OR REPLACE FUNCTION public.friend_activity_page_v1(
  p_media_type text, p_media_id integer, p_after_comment_at timestamptz default null,
  p_after_comment_id uuid default null, p_after_friend uuid default null
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid             uuid := auth.uid();
  _friend_uuids    uuid[];
  _detail_uuids    uuid[];
  _friends_json    jsonb;
  _comments_json   jsonb;
  _comment_next jsonb;
  _friend_next text;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('friends_tracking', '[]'::jsonb, 'comments', '[]'::jsonb);
  END IF;

  if p_media_type not in ('ANIME','MANGA') then raise exception 'INVALID_MEDIUM'; end if;
  if (p_after_comment_at is null) <> (p_after_comment_id is null) then raise exception 'INVALID_CURSOR'; end if;

  -- Friend visibility map: per friend, the MAX effective sharing rank across
  -- all shared non-archived clubs. Effective rank mirrors fetch_club_bundle:
  -- least of club sharing_level rank and the subject member's own downgrade
  -- (member sharing_level can only lower exposure; NULL inherits club level).
  -- eff_rank 0 everywhere -> not visible at all; >= 1 -> status-level;
  -- >= 2 -> progress/rating detail.
  WITH friend_visibility AS (
    SELECT
      cm2.user_id AS friend_id,
      MAX(
        least(public.sharing_level_rank(c.sharing_level),
          public.sharing_level_rank(coalesce(cm1.sharing_level,c.sharing_level)),
          public.sharing_level_rank(coalesce(cm2.sharing_level,c.sharing_level)))
      ) AS eff_rank
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
  )
  SELECT
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 1), '{}'::uuid[]),
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 2), '{}'::uuid[])
  INTO _friend_uuids, _detail_uuids;

  -- Friends tracking this title (from user lists)
  -- NOTE: anime_user_lists/manga_user_lists have TEXT user_id, so cast uuid::text
  WITH friends_tracking AS (
    SELECT
      f_uid AS user_id,
      p.display_name,
      ul.status,
      ul.progress,
      ul.rating,
      ul.updated_at::text AS updated_at
    FROM unnest(_friend_uuids) AS f_uid
    JOIN profiles p ON p.id = f_uid
    INNER JOIN (
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM anime_user_lists
      WHERE not entry_private AND anime_id = p_media_id AND 'ANIME' = p_media_type
      UNION ALL
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM manga_user_lists
      WHERE not entry_private AND manga_id = p_media_id AND 'MANGA' = p_media_type
    ) ul ON ul.user_id = f_uid::text
    where p_after_friend is null or f_uid>p_after_friend
    order by f_uid limit 51
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', ft.user_id,
      'display_name', ft.display_name,
      'status', ft.status,
      -- eff_rank 1 = status only: keep columns but NULL the detail fields
      'progress', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.progress ELSE NULL END,
      'rating', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.rating ELSE NULL END,
      'updated_at', ft.updated_at
    )
   order by ft.user_id), '[]'::jsonb)
  INTO _friends_json
  FROM friends_tracking ft;

  if jsonb_array_length(_friends_json)>50 then
    _friend_next:=_friends_json->49->>'user_id'; _friends_json:=_friends_json-50;
  end if;

  -- Comments from self + visible friends, with reaction counts
  WITH visible_comments AS (
    SELECT tc.*
    FROM title_comments tc
    WHERE tc.media_type = p_media_type
      AND tc.media_id = p_media_id
      AND (tc.user_id = _uid OR tc.user_id = ANY(_friend_uuids))
      AND (p_after_comment_at is null or (tc.created_at,tc.id)<(p_after_comment_at,p_after_comment_id))
    order by tc.created_at desc,tc.id desc limit 21
  ),
  comment_agg AS (
    SELECT
      vc.id,
      vc.user_id,
      p.display_name,
      vc.text,
      vc.spoiler_scope,
      vc.created_at::text AS created_at,
      vc.updated_at::text AS updated_at,
      (vc.user_id = _uid) AS is_own,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'up' THEN 1 ELSE 0 END), 0)::int AS up_count,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'down' THEN 1 ELSE 0 END), 0)::int AS down_count,
      (SELECT cr2.reaction_type FROM title_comment_reactions cr2
       WHERE cr2.comment_id = vc.id AND cr2.user_id = _uid
       LIMIT 1) AS my_reaction
    FROM visible_comments vc
    JOIN profiles p ON p.id = vc.user_id
    LEFT JOIN title_comment_reactions cr ON cr.comment_id = vc.id
    GROUP BY vc.id, vc.user_id, p.display_name, vc.text, vc.spoiler_scope, vc.created_at, vc.updated_at
    ORDER BY vc.created_at DESC,vc.id DESC
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ca.id,
      'user_id', ca.user_id,
      'display_name', ca.display_name,
      'text', ca.text,
      'spoiler_scope', ca.spoiler_scope,
      'created_at', ca.created_at,
      'updated_at', ca.updated_at,
      'is_own', ca.is_own,
      'up_count', ca.up_count,
      'down_count', ca.down_count,
      'my_reaction', ca.my_reaction
    )
   order by ca.created_at desc,ca.id desc), '[]'::jsonb)
  INTO _comments_json
  FROM comment_agg ca;

  if jsonb_array_length(_comments_json)>20 then
    _comment_next:=jsonb_build_object('at',_comments_json->19->>'created_at','id',_comments_json->19->>'id');
    _comments_json:=_comments_json-20;
  end if;
  RETURN jsonb_build_object(
    'own_comment',(select jsonb_build_object('id',tc.id,'user_id',tc.user_id,'display_name',p.display_name,
      'text',tc.text,'spoiler_scope',tc.spoiler_scope,'created_at',tc.created_at,'updated_at',tc.updated_at,
      'is_own',true,
      'up_count',(select count(*) from public.title_comment_reactions cr where cr.comment_id=tc.id and cr.reaction_type='up'),
      'down_count',(select count(*) from public.title_comment_reactions cr where cr.comment_id=tc.id and cr.reaction_type='down'),
      'my_reaction',null)
      from public.title_comments tc join public.profiles p on p.id=tc.user_id
      where tc.user_id=_uid and tc.media_type=p_media_type and tc.media_id=p_media_id),
    'comments_next',_comment_next,'friends_next',_friend_next,
    'friends_tracking', _friends_json,
    'comments', _comments_json
  );
END;
$$;

revoke all on function public.friend_activity_page_v1(text,integer,timestamptz,uuid,uuid) from public,anon,service_role;
grant execute on function public.friend_activity_page_v1(text,integer,timestamptz,uuid,uuid) to authenticated;
create or replace function public.fetch_friend_activity_for_title(p_media_type text,p_media_id integer)
returns jsonb language sql stable security invoker set search_path=public,extensions as $$
 select public.friend_activity_page_v1(p_media_type,p_media_id,null,null,null);
$$;

CREATE OR REPLACE FUNCTION public.count_friends_tracking(p_items text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid        uuid := auth.uid();
  _items_json jsonb := p_items::jsonb;
  _result     jsonb;
BEGIN
  IF _uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  if jsonb_typeof(_items_json) <> 'array' or jsonb_array_length(_items_json)>100 then raise exception 'INVALID_ITEMS'; end if;

  -- Only friends whose MAX effective sharing rank across shared non-archived
  -- clubs is >= 1 count toward indicators (private club or self-downgrade
  -- to 'private' in every shared club -> invisible). Same eff-rank rule as
  -- fetch_club_bundle / fetch_friend_activity_for_title.
  WITH friend_ids AS (
    SELECT cm2.user_id
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
    HAVING MAX(least(public.sharing_level_rank(c.sharing_level),
      public.sharing_level_rank(coalesce(cm1.sharing_level,c.sharing_level)),
      public.sharing_level_rank(coalesce(cm2.sharing_level,c.sharing_level)))
    ) >= 1
  ),
  items AS (
    SELECT
      (elem->>'media_type')::text AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(_items_json) AS elem
  ),
  counts AS (
    SELECT
      i.media_type,
      i.media_id,
      COUNT(DISTINCT ul.user_id)::int AS count
    FROM items i
    JOIN (
      SELECT user_id, 'ANIME'::text AS media_type, anime_id AS media_id FROM anime_user_lists WHERE not entry_private
      UNION ALL
      SELECT user_id, 'MANGA'::text AS media_type, manga_id AS media_id FROM manga_user_lists WHERE not entry_private
    ) ul ON ul.media_type = i.media_type AND ul.media_id = i.media_id
    WHERE ul.user_id::uuid IN (SELECT user_id FROM friend_ids)
    GROUP BY i.media_type, i.media_id
    HAVING COUNT(DISTINCT ul.user_id) > 0
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'media_type', c.media_type,
      'media_id', c.media_id,
      'count', c.count
    )
  ), '[]'::jsonb)
  INTO _result
  FROM counts c;

  RETURN _result;
END;
$$;

create or replace function public.upsert_title_comment_scoped_v1(
  p_media_type text, p_media_id integer, p_text text, p_spoiler_scope text
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_result jsonb; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_spoiler_scope not in ('none','story','ending') or p_spoiler_scope is null then raise exception 'INVALID_SPOILER_SCOPE'; end if;
  -- Keep the existing title validation, rate limit and single-comment contract.
  v_result := public.upsert_title_comment(p_media_type,p_media_id,p_text);
  update public.title_comments set spoiler_scope=p_spoiler_scope
  where user_id=v_uid and media_type=p_media_type and media_id=p_media_id;
  return v_result;
end; $$;
revoke all on function public.upsert_title_comment_scoped_v1(text,integer,text,text) from public, anon;
grant execute on function public.upsert_title_comment_scoped_v1(text,integer,text,text) to authenticated;

-- Independent, deterministic unit paging; opening a page never writes tracking.
create or replace function public.series_units_page_v1(
 p_medium text, p_media_id integer, p_section_id uuid default null,
 p_edition_key text default null, p_after_order numeric default null, p_after_id uuid default null, p_limit integer default 20
) returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare v_rows jsonb; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20))); v_next jsonb; v_edition text:=p_edition_key;
begin
 if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if (p_after_order is null) <> (p_after_id is null) then raise exception 'INVALID_CURSOR'; end if;
 if p_section_id is not null and not exists(select 1 from public.series_entry_spans sp join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
   where sp.section_id=p_section_id and ((p_medium='anime' and sp.anime_id=p_media_id) or (p_medium='manga' and sp.manga_id=p_media_id))) then raise exception 'INVALID_SECTION'; end if;
 if v_edition is null then
  select u.edition_key into v_edition from public.catalogue_units u
   where u.medium=p_medium and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
    and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
   order by u.edition_key,u.order_key,u.id limit 1;
 end if;
 select coalesce(jsonb_agg(row_data order by order_key,id),'[]'::jsonb) into v_rows from (
   select jsonb_build_object('id',u.id,'label',u.label,'order_key',u.order_key::text,'available',u.available,
       'edition_key',u.edition_key,'title',u.title,'synopsis',u.synopsis,'image_url',u.image_url) row_data,u.order_key,u.id
   from public.catalogue_units u where u.medium=p_medium
     and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
     and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
     and u.edition_key=v_edition
     and (p_after_order is null or (u.order_key,u.id)>(p_after_order,p_after_id))
   order by u.order_key,u.id limit v_limit+1
 ) page;
 if jsonb_array_length(v_rows)>v_limit then
   v_next:=jsonb_build_object('order',v_rows->(v_limit-1)->'order_key','id',v_rows->(v_limit-1)->'id');
   v_rows:=v_rows-(v_limit);
 end if;
 return jsonb_build_object('items',v_rows,'next',v_next,'edition',v_edition);
end; $$;
revoke all on function public.series_units_page_v1(text,integer,uuid,text,numeric,uuid,integer) from public,anon;
grant execute on function public.series_units_page_v1(text,integer,uuid,text,numeric,uuid,integer) to authenticated;

-- Bounded source-edition keys with an independent exact-string cursor. No whole
-- catalogue aggregation, fictional volumes, or collapsing translated editions.
create or replace function public.series_editions_page_v1(p_medium text,p_media_id integer,
 p_section_id uuid default null,p_after_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare items jsonb; cursor text; cap integer:=least(50,greatest(1,coalesce(p_limit,50)));
begin
 if auth.uid() is null then raise exception 'UNAUTHENTICATED';end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM';end if;
 if length(coalesce(p_after_key,''))>1024 then raise exception 'INVALID_CURSOR';end if;
 if p_section_id is not null and not exists(select 1 from public.series_entry_spans sp
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.section_id=p_section_id and ((p_medium='anime' and sp.anime_id=p_media_id) or (p_medium='manga' and sp.manga_id=p_media_id)))
 then raise exception 'INVALID_SECTION';end if;
 select coalesce(jsonb_agg(edition_key order by edition_key),'[]'::jsonb) into items from (
  select distinct u.edition_key from public.catalogue_units u where u.medium=p_medium
   and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
   and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
   and (p_after_key is null or u.edition_key>p_after_key)
  order by u.edition_key limit cap+1) keys;
 if jsonb_array_length(items)>cap then cursor:=items->>(cap-1);items:=items-cap;end if;
 return jsonb_build_object('items',items,'next',cursor);
end; $$;
revoke all on function public.series_editions_page_v1(text,integer,uuid,text,integer) from public,anon;
grant execute on function public.series_editions_page_v1(text,integer,uuid,text,integer) to authenticated;

-- R11: independent release keyset. Counts apply to the selected user's tracked/saved/followed
-- titles. Day precision is a source day, never fabricated UTC midnight. Unknown dates stay pending.
create or replace function public.home_events_page_v1(p_medium text,p_window_days integer default 7,
 p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare
 v_uid text:=auth.uid()::text; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20)));
 v_after text; v_id text; v_page jsonb; v_total bigint; v_next text;
begin
 if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if length(coalesce(p_cursor,''))>1024 then raise exception 'INVALID_CURSOR'; end if;
 if p_cursor is not null then
   begin v_after:=p_cursor::jsonb->>'sort'; v_id:=p_cursor::jsonb->>'id';
     if v_after is null or v_id is null then raise exception 'INVALID_CURSOR'; end if;
   exception when others then raise exception 'INVALID_CURSOR'; end;
 end if;
 with tracked as materialized (
   select anime_id as id from public.anime_user_lists where p_medium='anime' and user_id=v_uid and list_type in ('WATCHING','PLANNING')
   union select manga_id from public.manga_user_lists where p_medium='manga' and user_id=v_uid and list_type in ('READING','PLANNING')
   union select case when p_medium='anime' then sp.anime_id else sp.manga_id end
     from public.user_series_intent i join public.series sr on sr.id=i.series_id and sr.grouping_state='approved'
     join public.series_entry_spans sp on sp.series_id=i.series_id and sp.medium=p_medium
     where i.user_id=v_uid and (i.saved or i.followed)
 ), events as materialized (
   select r.id::text as event_id,coalesce(r.anime_id,r.manga_id) as media_id,r.utc_instant as at,
     r.precision,r.source_local_date,r.source_zone,r.kind as unit_label,r.status,
     case when r.precision='instant' then to_char(r.utc_instant at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')
          else r.source_local_date||'T' end as sort_key
   from public.release_events r join tracked t on t.id=coalesce(r.anime_id,r.manga_id)
   where r.medium=p_medium and r.status in ('scheduled','announced') and (
     (r.precision='instant' and r.utc_instant>=now() and r.utc_instant<now()+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7)))))
     or (r.precision='day' and r.source_local_date>=to_char(now() at time zone 'UTC','YYYY-MM-DD')
       and r.source_local_date<to_char((now() at time zone 'UTC')+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7)))),'YYYY-MM-DD'))
   )
   union all
   select 'next:anime:'||a.id||':'||coalesce(a.next_episode_number::text,'')||':'||a.next_airing_at::text,
     a.id,a.next_airing_at,'instant',null,null,
     case when a.next_episode_number is null then 'Episode' else 'Episode '||a.next_episode_number end,'scheduled',
     to_char(a.next_airing_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')
   from public.anime a join tracked t on t.id=a.id
   where p_medium='anime' and a.next_airing_at>=now() and a.next_airing_at<now()+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7))))
     and not exists(select 1 from public.release_events r where r.anime_id=a.id and r.status in ('scheduled','announced') and r.utc_instant=a.next_airing_at)
 ), page as materialized (
   select * from events where v_after is null or (sort_key,event_id)>(v_after,v_id)
   order by sort_key,event_id limit v_limit+1
 ), visible as (
   select p.*,coalesce(a.title_english,a.title_romaji,a.title_native,m.title_english,m.title_romaji,m.title_native,'Untitled') as title,
    coalesce(a.cover_image_large,m.cover_image_large) as cover_image
   from (select * from page order by sort_key,event_id limit v_limit) p
   left join public.anime a on p_medium='anime' and a.id=p.media_id
   left join public.manga m on p_medium='manga' and m.id=p.media_id
 )
 select coalesce(jsonb_agg(to_jsonb(visible)-'sort_key' order by sort_key,event_id),'[]'::jsonb),
   (select count(*) from events),
   (select case when count(*)>v_limit then (select jsonb_build_object('sort',sort_key,'id',event_id)::text
      from page order by sort_key,event_id offset v_limit-1 limit 1) else null end from page)
 into v_page,v_total,v_next from visible;
 return jsonb_build_object('items',v_page,'total',v_total,'next_cursor',v_next);
end; $$;
revoke all on function public.home_events_page_v1(text,integer,integer,text) from public,anon;
grant execute on function public.home_events_page_v1(text,integer,integer,text) to authenticated;

-- Undated announcements have an independent UUID keyset; they never acquire a
-- fabricated midnight merely for display or sorting.
create or replace function public.home_pending_page_v1(p_medium text,p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare
 v_uid text:=auth.uid()::text; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20)));
 v_after uuid; v_items jsonb; v_total bigint; v_next text;
begin
 if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium is null or p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if p_cursor is not null then
   begin v_after:=p_cursor::uuid; exception when others then raise exception 'INVALID_CURSOR'; end;
 end if;
 with tracked as materialized (
   select anime_id as id from public.anime_user_lists where p_medium='anime' and user_id=v_uid
   union select manga_id from public.manga_user_lists where p_medium='manga' and user_id=v_uid
   union select case when p_medium='anime' then sp.anime_id else sp.manga_id end
     from public.user_series_intent i join public.series sr on sr.id=i.series_id and sr.grouping_state='approved'
     join public.series_entry_spans sp on sp.series_id=i.series_id and sp.medium=p_medium
     where i.user_id=v_uid and (i.saved or i.followed)
 ), eligible as materialized (
   select e.* from public.release_events e join tracked t on t.id=coalesce(e.anime_id,e.manga_id)
   where e.medium=p_medium and e.precision='unknown' and e.status='announced'
 ), page as materialized (
   select * from eligible where v_after is null or id>v_after order by id limit v_limit+1
 ), visible as (
   select e.id,e.medium,coalesce(e.anime_id,e.manga_id) media_id,e.status,e.precision,
     e.source_local_date,e.source_zone,e.kind unit_label,
     coalesce(a.title_english,a.title_romaji,a.title_native,m.title_english,m.title_romaji,m.title_native,'Untitled') title,
     coalesce(a.cover_image_large,m.cover_image_large) cover_image
   from (select * from page order by id limit v_limit)e
   left join public.anime a on p_medium='anime' and a.id=e.anime_id
   left join public.manga m on p_medium='manga' and m.id=e.manga_id
 )
 select coalesce(jsonb_agg((to_jsonb(visible)-'id')||jsonb_build_object('event_id',id) order by id),'[]'::jsonb),
   (select count(*) from eligible),
   (select case when count(*)>v_limit then (select id::text from page order by id offset v_limit-1 limit 1) end from page)
 into v_items,v_total,v_next from visible;
 return jsonb_build_object('items',v_items,'total',v_total,'next_cursor',v_next);
end; $$;
revoke all on function public.home_pending_page_v1(text,integer,text) from public,anon;
grant execute on function public.home_pending_page_v1(text,integer,text) to authenticated;

-- R14: additive legacy catalogue bridge. Existing source rows retain their own identity;
-- no invented episode/chapter totals, chapter dates, editions or continuation boundaries.
alter table public.release_events add column if not exists source_identity text;
create unique index if not exists release_events_source_identity on public.release_events(source_identity) where source_identity is not null;
create index if not exists catalogue_units_source on public.catalogue_units(source_provenance);
create or replace function public._bridge_legacy_unit_v1(p_medium text,p_source_id integer,p_media_id integer,
 p_number integer,p_title text,p_synopsis text,p_image text,p_day date,p_instant timestamptz,p_removed boolean default false)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid; v_source text:='legacy:'||p_medium||':'||p_source_id||':'||p_media_id||':'||p_number; v_available boolean;
begin
 if p_medium not in ('anime','manga') or p_number<0 then raise exception 'INVALID_SOURCE_UNIT'; end if;
 v_available:=not p_removed and case when p_instant is not null then p_instant<=now()
   when p_day is not null then p_day<(now() at time zone 'UTC')::date else false end;
 if p_medium='anime' then
   insert into public.catalogue_units(medium,anime_id,label,order_key,edition_key,available,title,synopsis,image_url,source_provenance)
   values ('anime',p_media_id,p_number::text,p_number,'legacy_catalogue',v_available,p_title,p_synopsis,p_image,v_source)
   on conflict (anime_id,edition_key,order_key) where anime_id is not null do update set
     available=excluded.available,title=excluded.title,synopsis=excluded.synopsis,image_url=excluded.image_url
     where catalogue_units.source_provenance=excluded.source_provenance returning id into v_id;
 else
   insert into public.catalogue_units(medium,manga_id,label,order_key,edition_key,available,title,synopsis,image_url,source_provenance)
   values ('manga',p_media_id,p_number::text,p_number,'legacy_catalogue',v_available,p_title,p_synopsis,p_image,v_source)
   on conflict (manga_id,edition_key,order_key) where manga_id is not null do update set
     available=excluded.available,title=excluded.title,synopsis=excluded.synopsis,image_url=excluded.image_url
     where catalogue_units.source_provenance=excluded.source_provenance returning id into v_id;
 end if;
 if v_id is null then return; end if; -- another verified source owns this unit; do not overwrite it.
 if p_day is not null or p_instant is not null or p_removed then
   insert into public.release_events(medium,anime_id,manga_id,kind,precision,source_local_date,utc_instant,status,evidence,freshness,source_identity)
   values(p_medium,case when p_medium='anime' then p_media_id end,case when p_medium='manga' then p_media_id end,
     case when p_medium='anime' then 'Episode ' else 'Chapter ' end||p_number,
     case when p_instant is not null then 'instant' when p_day is not null then 'day' else 'unknown' end,
     p_day::text,p_instant,case when p_removed then 'withdrawn' when v_available then 'released' else 'scheduled' end,
     v_source,now(),v_source)
   on conflict(source_identity) where source_identity is not null do update set
     precision=excluded.precision,source_local_date=excluded.source_local_date,utc_instant=excluded.utc_instant,
     status=excluded.status,evidence=excluded.evidence,freshness=excluded.freshness,revision=release_events.revision+1;
 end if;
end; $$;
revoke all on function public._bridge_legacy_unit_v1(text,integer,integer,integer,text,text,text,date,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public._bridge_legacy_unit_v1(text,integer,integer,integer,text,text,text,date,timestamptz,boolean) to service_role;

create or replace function public.legacy_unit_bridge_trigger_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if TG_TABLE_NAME='episodes' then
   if TG_OP='DELETE' then
     perform public._bridge_legacy_unit_v1('anime',old.id,old.anime_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.air_date,old.air_at,true);
   else
     if TG_OP='UPDATE' and (old.anime_id,old.number) is distinct from (new.anime_id,new.number) then
       perform public._bridge_legacy_unit_v1('anime',old.id,old.anime_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.air_date,old.air_at,true);
     end if;
     perform public._bridge_legacy_unit_v1('anime',new.id,new.anime_id,new.number,coalesce(new.title,new.title_romaji),new.description,new.thumbnail,new.air_date,new.air_at,false);
   end if;
 else
   if TG_OP='DELETE' then
     perform public._bridge_legacy_unit_v1('manga',old.id,old.manga_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.release_date,old.release_at,true);
   else
     if TG_OP='UPDATE' and (old.manga_id,old.number) is distinct from (new.manga_id,new.number) then
       perform public._bridge_legacy_unit_v1('manga',old.id,old.manga_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.release_date,old.release_at,true);
     end if;
     perform public._bridge_legacy_unit_v1('manga',new.id,new.manga_id,new.number,coalesce(new.title,new.title_romaji),new.description,new.thumbnail,new.release_date,new.release_at,false);
   end if;
 end if;
 return null;
end; $$;
revoke all on function public.legacy_unit_bridge_trigger_v1() from public,anon,authenticated;
drop trigger if exists series_bridge_episodes on public.episodes;
create trigger series_bridge_episodes after insert or update or delete on public.episodes for each row execute function public.legacy_unit_bridge_trigger_v1();
drop trigger if exists series_bridge_chapters on public.chapters;
create trigger series_bridge_chapters after insert or update or delete on public.chapters for each row execute function public.legacy_unit_bridge_trigger_v1();

-- Existing data backfill is a resumable SERVICE job: <=250 PK rows per call. Never a Home call.
create or replace function public.backfill_legacy_series_units_v1(p_medium text,p_after_id integer default 0,p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r record; n integer:=0; last_id integer:=coalesce(p_after_id,0); cap integer:=least(250,greatest(1,coalesce(p_limit,250)));
begin
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if p_medium='anime' then
   for r in select * from public.episodes where id>last_id order by id limit cap loop
     perform public._bridge_legacy_unit_v1('anime',r.id,r.anime_id,r.number,coalesce(r.title,r.title_romaji),r.description,r.thumbnail,r.air_date,r.air_at,false);
     n:=n+1; last_id:=r.id;
   end loop;
 else
   for r in select * from public.chapters where id>last_id order by id limit cap loop
     perform public._bridge_legacy_unit_v1('manga',r.id,r.manga_id,r.number,coalesce(r.title,r.title_romaji),r.description,r.thumbnail,r.release_date,r.release_at,false);
     n:=n+1; last_id:=r.id;
   end loop;
 end if;
 return jsonb_build_object('processed',n,'after_id',last_id,'has_more',n=cap);
end; $$;
revoke all on function public.backfill_legacy_series_units_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function public.backfill_legacy_series_units_v1(text,integer,integer) to service_role;


-- Imported PRIVATE entries never contribute to club aggregates or named rows.
create or replace function public.fetch_club_bundle(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _members jsonb;
  _rails jsonb;
  _polls jsonb;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Explicit caller authorization: this function reads every member's rows.
  IF NOT public.is_club_member(p_club_id) THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT cm.role, cm.sharing_level, cm.joined_at
  INTO _my_membership
  FROM public.club_members cm
  WHERE cm.club_id = p_club_id AND cm.user_id = _uid;

  IF _my_membership IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  INTO _club
  FROM public.clubs c
  WHERE c.id = p_club_id;

  IF _club IS NULL THEN
    RAISE EXCEPTION 'CLUB_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  _my_effective_level := CASE
    WHEN _my_membership.sharing_level IS NULL THEN _club.sharing_level
    WHEN public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      THEN _my_membership.sharing_level
    ELSE _club.sharing_level
  END;

  _club_sharing_rank := least(public.sharing_level_rank(_club.sharing_level),public.sharing_level_rank(_my_effective_level));

  -- current members only
  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = p_club_id;

  -- MEMBERS: private club or fewer than 3 members -> only the caller
  IF _club_sharing_rank = 0 OR _member_count < 3 THEN
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id AND cm.user_id = _uid
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  END IF;

  _members := COALESCE(_members, '[]'::jsonb);

  -- RAILS + ITEMS with media join + per-item aggregates + reactions
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'title', r.title,
      'description', r.description,
      'is_locked', r.is_locked,
      'sort_order', r.sort_order,
      'created_by', r.created_by,
      'items', COALESCE(r.items, '[]'::jsonb)
    ) ORDER BY r.sort_order, r.id
  ), '[]'::jsonb)
  INTO _rails
  FROM (
    SELECT
      cr.id, cr.title, cr.description, cr.is_locked, cr.sort_order, cr.created_by,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', enriched.item_id,
            'media_type', enriched.media_type,
            'media_id', enriched.media_id,
            'sort_order', enriched.sort_order,
            'note', enriched.note,
            'added_by', enriched.added_by,
            'title_display', enriched.title_display,
            'cover_image_medium', enriched.cover_image_medium,
            'average_score', enriched.average_score,
            'year', enriched.year,
            'format', enriched.format,
            'episode_count', enriched.episode_count,
            'chapter_count', enriched.chapter_count,
            'my_status', enriched.my_status,
            'my_progress', enriched.my_progress,
            'my_rating', enriched.my_rating,
            'member_status_counts', enriched.member_status_counts,
            'member_statuses', enriched.member_statuses,
            'reactions', enriched.reactions,
            'my_reactions', enriched.my_reactions
          ) ORDER BY enriched.sort_order, enriched.item_id
        )
        FROM (
          SELECT
            cri.id AS item_id,
            cri.media_type,
            cri.media_id,
            cri.sort_order,
            cri.note,
            cri.added_by,
            COALESCE(
              CASE WHEN cri.media_type = 'ANIME' THEN COALESCE(a.title_english, a.title_romaji)
                   WHEN cri.media_type = 'MANGA' THEN COALESCE(m.title_english, m.title_romaji)
              END, 'Unknown'
            ) AS title_display,
            CASE WHEN cri.media_type = 'ANIME' THEN a.cover_image_medium
                 WHEN cri.media_type = 'MANGA' THEN m.cover_image_medium
            END AS cover_image_medium,
            CASE WHEN cri.media_type = 'ANIME' THEN a.average_score
                 WHEN cri.media_type = 'MANGA' THEN m.average_score
            END AS average_score,
            CASE WHEN cri.media_type = 'ANIME' THEN a.season_year
                 WHEN cri.media_type = 'MANGA' THEN m.start_date_year
            END AS year,
            CASE WHEN cri.media_type = 'ANIME' THEN a.format
                 WHEN cri.media_type = 'MANGA' THEN m.format
            END AS format,
            CASE WHEN cri.media_type = 'ANIME' THEN a.episodes ELSE NULL END AS episode_count,
            CASE WHEN cri.media_type = 'MANGA' THEN m.chapters ELSE NULL END AS chapter_count,
            -- Caller's own status/progress/rating
            COALESCE(my_aul.list_type, my_mul.list_type) AS my_status,
            COALESCE(my_aul.progress, my_mul.progress) AS my_progress,
            COALESCE(my_aul.rating, my_mul.rating) AS my_rating,
            -- Aggregate status counts across CURRENT club members
            CASE
              -- Fewer than 3 members: no cross-member aggregate at all (H1 "only own data";
              -- a count over one other member would identify that person).
              WHEN _member_count < 3 THEN NULL
              WHEN _club_sharing_rank = 0 THEN
                -- private club (>= 3 members, so >= 2 others): anonymous count of the OTHER
                -- members who track the item; every member's effective level is private here,
                -- which docs/clubs-spec.md defines as "anonymous contribution to counts"
                jsonb_build_object('_tracking_count', (
                  SELECT count(*)
                  FROM public.club_members cm2
                  WHERE cm2.club_id = p_club_id
                    AND cm2.user_id != _uid
                    AND (
                      CASE WHEN cri.media_type = 'ANIME' THEN
                        EXISTS (SELECT 1 FROM public.anime_user_lists aul2
                                WHERE not aul2.entry_private AND aul2.user_id = cm2.user_id::text AND aul2.anime_id = cri.media_id)
                      WHEN cri.media_type = 'MANGA' THEN
                        EXISTS (SELECT 1 FROM public.manga_user_lists mul2
                                WHERE not mul2.entry_private AND mul2.user_id = cm2.user_id::text AND mul2.manga_id = cri.media_id)
                      END
                    )
                ))
              ELSE
                (
                  SELECT COALESCE(jsonb_object_agg(sa.list_type, sa.cnt), '{}'::jsonb)
                  FROM (
                    SELECT ul.list_type, count(*) AS cnt
                    FROM public.club_members cm3
                    JOIN LATERAL (
                      SELECT CASE
                        WHEN cm3.sharing_level IS NULL THEN _club_sharing_rank
                        WHEN public.sharing_level_rank(cm3.sharing_level) < _club_sharing_rank
                          THEN public.sharing_level_rank(cm3.sharing_level)
                        ELSE _club_sharing_rank
                      END AS eff_rank
                    ) eff ON true
                    LEFT JOIN LATERAL (
                      SELECT aul3.list_type FROM public.anime_user_lists aul3
                      WHERE cri.media_type = 'ANIME' AND not aul3.entry_private AND aul3.user_id = cm3.user_id::text AND aul3.anime_id = cri.media_id
                      UNION ALL
                      SELECT mul3.list_type FROM public.manga_user_lists mul3
                      WHERE cri.media_type = 'MANGA' AND not mul3.entry_private AND mul3.user_id = cm3.user_id::text AND mul3.manga_id = cri.media_id
                    ) ul ON true
                    WHERE cm3.club_id = p_club_id AND eff.eff_rank >= 1 AND ul.list_type IS NOT NULL
                    GROUP BY ul.list_type
                  ) sa
                )
            END AS member_status_counts,
            -- Per-member status: effective rank >= 1; progress only at effective rank >= 2
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN NULL
              ELSE (
                SELECT jsonb_agg(jsonb_build_object(
                  'user_id', ms.user_id,
                  'display_name', ms.display_name,
                  'status', ms.list_type,
                  'progress', CASE WHEN ms.eff_rank >= 2 THEN ms.progress ELSE NULL END,
                  'updated_at', ms.updated_at
                ) ORDER BY ms.updated_at DESC NULLS LAST, ms.user_id)
                FROM (
                  SELECT cm4.user_id, nullif(trim(coalesce(p4.display_name, '')), '') AS display_name,
                         ul4.list_type, ul4.progress, ul4.updated_at, eff4.eff_rank
                  FROM public.club_members cm4
                  LEFT JOIN public.profiles p4 ON p4.id = cm4.user_id
                  JOIN LATERAL (
                    SELECT CASE
                      WHEN cm4.sharing_level IS NULL THEN _club_sharing_rank
                      WHEN public.sharing_level_rank(cm4.sharing_level) < _club_sharing_rank
                        THEN public.sharing_level_rank(cm4.sharing_level)
                      ELSE _club_sharing_rank
                    END AS eff_rank
                  ) eff4 ON true
                  LEFT JOIN LATERAL (
                    SELECT aul4.list_type, aul4.progress, aul4.updated_at FROM public.anime_user_lists aul4
                    WHERE cri.media_type = 'ANIME' AND not aul4.entry_private AND aul4.user_id = cm4.user_id::text AND aul4.anime_id = cri.media_id
                    UNION ALL
                    SELECT mul4.list_type, mul4.progress, mul4.updated_at FROM public.manga_user_lists mul4
                    WHERE cri.media_type = 'MANGA' AND not mul4.entry_private AND mul4.user_id = cm4.user_id::text AND mul4.manga_id = cri.media_id
                  ) ul4 ON true
                  WHERE cm4.club_id = p_club_id AND eff4.eff_rank >= 1 AND ul4.list_type IS NOT NULL
                ) ms
              )
            END AS member_statuses,
            -- Reactions of CURRENT members: anonymous aggregate counts {fire: 3, heart: 1}
            (
              SELECT COALESCE(jsonb_object_agg(rc.emoji, rc.cnt), '{}'::jsonb)
              FROM (
                SELECT r2.emoji, count(*) AS cnt
                FROM public.club_rail_item_reactions r2
                JOIN public.club_members rm ON rm.club_id = p_club_id AND rm.user_id = r2.user_id
                WHERE r2.rail_item_id = cri.id
                GROUP BY r2.emoji
              ) rc
            ) AS reactions,
            -- My reactions: ["fire", "heart"]
            (
              SELECT COALESCE(jsonb_agg(r3.emoji), '[]'::jsonb)
              FROM public.club_rail_item_reactions r3
              WHERE r3.rail_item_id = cri.id AND r3.user_id = _uid
            ) AS my_reactions
          FROM public.club_rail_items cri
          LEFT JOIN public.anime a ON cri.media_type = 'ANIME' AND a.id = cri.media_id
          LEFT JOIN public.manga m ON cri.media_type = 'MANGA' AND m.id = cri.media_id
          LEFT JOIN public.anime_user_lists my_aul
            ON cri.media_type = 'ANIME' AND my_aul.user_id = _uid::text AND my_aul.anime_id = cri.media_id
          LEFT JOIN public.manga_user_lists my_mul
            ON cri.media_type = 'MANGA' AND my_mul.user_id = _uid::text AND my_mul.manga_id = cri.media_id
          WHERE cri.rail_id = cr.id
          ORDER BY cri.sort_order, cri.id
          LIMIT 50
        ) enriched
      ) AS items
    FROM public.club_rails cr
    WHERE cr.club_id = p_club_id
  ) r;

  -- POLLS + OPTIONS + VOTE COUNTS (current members' votes)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'question', p.question,
      'is_closed', p.is_closed,
      'closes_at', p.closes_at,
      'created_by', p.created_by,
      'created_at', p.created_at,
      'options', COALESCE(p.options, '[]'::jsonb),
      'my_vote_option_id', p.my_vote_option_id
    ) ORDER BY p.is_closed ASC, p.created_at DESC, p.id DESC
  ), '[]'::jsonb)
  INTO _polls
  FROM (
    SELECT
      cp.id, cp.question, cp.is_closed, cp.closes_at, cp.created_by, cp.created_at,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', option_rows.id,
            'label', option_rows.label,
            'media_type', option_rows.media_type,
            'media_id', option_rows.media_id,
            'sort_order', option_rows.sort_order,
            'vote_count', option_rows.vote_count
          ) ORDER BY option_rows.sort_order, option_rows.id
        )
        FROM (
          SELECT
            cpo.id,
            cpo.label,
            cpo.media_type,
            cpo.media_id,
            cpo.sort_order,
            COALESCE(vc.vote_count, 0)::int AS vote_count
          FROM public.club_poll_options cpo
          LEFT JOIN (
            SELECT cv.option_id, count(*) AS vote_count
            FROM public.club_votes cv
            JOIN public.club_members vm ON vm.club_id = p_club_id AND vm.user_id = cv.user_id
            WHERE cv.poll_id = cp.id
            GROUP BY cv.option_id
          ) vc ON vc.option_id = cpo.id
          WHERE cpo.poll_id = cp.id
        ) option_rows
      ) AS options,
      (
        SELECT cv2.option_id
        FROM public.club_votes cv2
        WHERE cv2.poll_id = cp.id AND cv2.user_id = _uid
        LIMIT 1
      ) AS my_vote_option_id
    FROM public.club_polls cp
    WHERE cp.club_id = p_club_id
    ORDER BY cp.is_closed ASC, cp.created_at DESC, cp.id DESC
    LIMIT 20
  ) p;

  RETURN jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      'invite_code', CASE WHEN _my_membership.role IN ('owner', 'admin') THEN _club.invite_code ELSE NULL END,
      'created_at', _club.created_at
    ),
    'members', _members,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', _rails,
    'polls', _polls,
    'member_count', _member_count
  );
END;
$function$;

create or replace function public.list_unit_owner_guard_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if new.unit_id is not null and not exists(select 1 from public.catalogue_units u
   where u.id=new.unit_id and ((TG_TABLE_NAME='anime_user_lists' and u.medium='anime' and u.anime_id=(to_jsonb(new)->>'anime_id')::integer)
     or (TG_TABLE_NAME='manga_user_lists' and u.medium='manga' and u.manga_id=(to_jsonb(new)->>'manga_id')::integer))) then
   raise exception 'INVALID_UNIT_OWNER';
 end if;
 return new;
end; $$;
revoke all on function public.list_unit_owner_guard_v1() from public,anon,authenticated;
drop trigger if exists series_unit_owner on public.anime_user_lists;
create trigger series_unit_owner before insert or update of unit_id,anime_id on public.anime_user_lists for each row execute function public.list_unit_owner_guard_v1();
drop trigger if exists series_unit_owner on public.manga_user_lists;
create trigger series_unit_owner before insert or update of unit_id,manga_id on public.manga_user_lists for each row execute function public.list_unit_owner_guard_v1();

-- A large approved continuity cannot hide its 51st tracked child. Group metadata is bounded;
-- children page independently by immutable internal ID with the SAME status/query scope.
create or replace function public.collection_series_children_v1(p_medium text,p_group_key text,
 p_status text default null,p_query text default null,p_after_id integer default null,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare v_user text:=auth.uid()::text; cap integer:=least(50,greatest(1,coalesce(p_limit,50))); q text:=left(replace(replace(coalesce(p_query,''),'%',''),'_',''),80); result jsonb; next_id integer;
begin
 if v_user is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') or length(p_group_key)>128 then raise exception 'INVALID_TARGET'; end if;
 with entries as (
  select l.anime_id media_id,l.list_type,l.progress,l.server_revision,l.lifecycle_id,
    coalesce(a.title_english,a.title_romaji,a.title_native,'Untitled') title,
    coalesce(sp.series_id::text,'entry:anime:'||l.anime_id) group_key
  from public.anime_user_lists l join public.anime a on a.id=l.anime_id
  left join lateral (select sp.series_id from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
    where sp.anime_id=l.anime_id order by sp.id limit 1)sp on true
  where p_medium='anime' and l.user_id=v_user and (p_status is null or l.list_type=p_status)
    and (q='' or coalesce(a.title_english,'') ilike '%'||q||'%' or coalesce(a.title_romaji,'') ilike '%'||q||'%'
      or coalesce(a.title_native,'') ilike '%'||q||'%' or exists(select 1 from unnest(coalesce(a.title_synonyms,array[]::text[]))syn where syn ilike '%'||q||'%'))
  union all
  select l.manga_id,l.list_type,l.progress,l.server_revision,l.lifecycle_id,coalesce(m.title_english,m.title_romaji,m.title_native,'Untitled'),
    coalesce(sp.series_id::text,'entry:manga:'||l.manga_id)
  from public.manga_user_lists l join public.manga m on m.id=l.manga_id
  left join lateral (select sp.series_id from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
    where sp.manga_id=l.manga_id order by sp.id limit 1)sp on true
  where p_medium='manga' and l.user_id=v_user and (p_status is null or l.list_type=p_status)
    and (q='' or coalesce(m.title_english,'') ilike '%'||q||'%' or coalesce(m.title_romaji,'') ilike '%'||q||'%' or coalesce(m.title_native,'') ilike '%'||q||'%')
 ), page as materialized (select * from entries where group_key=p_group_key and (p_after_id is null or media_id<p_after_id) order by media_id desc limit cap+1)
 select coalesce(jsonb_agg(to_jsonb(p)-'group_key' order by media_id desc),'[]'::jsonb),
   (select case when count(*)>cap then (select media_id from page order by media_id desc offset cap-1 limit 1) end from page)
 into result,next_id from (select * from page order by media_id desc limit cap)p;
 return jsonb_build_object('children',result,'next',next_id);
end; $$;
revoke all on function public.collection_series_children_v1(text,text,text,text,integer,integer) from public,anon;
grant execute on function public.collection_series_children_v1(text,text,text,text,integer,integer) to authenticated;

-- Every remaining viewer receives its OWN metadata signal when a peer is removed/downgraded.
-- This enables immediate Home/title-cache revocation without subscribing to raw member rows.
create or replace function public.club_disclosure_signal_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
declare cid uuid; member record;
begin
 if TG_TABLE_NAME='clubs' then cid:=new.id; else cid:=coalesce(new.club_id,old.club_id); end if;
 for member in select user_id from public.club_members where club_id=cid loop
   insert into public.club_membership_signals as signal(user_id,club_id,state,revision,changed_at)
   values(member.user_id,cid,'member',1,now()) on conflict(user_id,club_id) do update set
     state='member',revision=signal.revision+1,changed_at=now();
 end loop;
 return null;
end; $$;
revoke all on function public.club_disclosure_signal_v1() from public,anon,authenticated;
drop trigger if exists series_club_disclosure on public.club_members;
create trigger series_club_disclosure after insert or update of sharing_level or delete on public.club_members
 for each row execute function public.club_disclosure_signal_v1();
drop trigger if exists series_club_disclosure on public.clubs;
create trigger series_club_disclosure after update of sharing_level,is_archived on public.clubs
 for each row execute function public.club_disclosure_signal_v1();

-- Direct RLS and the reaction writer use the SAME disclosure rule as the paged reader.
create or replace function public.shares_club_with(p_other_user_id uuid)
returns boolean language sql stable security definer set search_path=public,extensions as $$
 select exists(select 1 from public.club_members viewer
  join public.club_members subject on subject.club_id=viewer.club_id
  join public.clubs c on c.id=viewer.club_id
  where viewer.user_id=auth.uid() and subject.user_id=p_other_user_id
   and viewer.user_id<>subject.user_id and not c.is_archived
   and least(public.sharing_level_rank(coalesce(viewer.sharing_level,c.sharing_level)),public.sharing_level_rank(coalesce(subject.sharing_level,c.sharing_level)),
     public.sharing_level_rank(c.sharing_level))>=1);
$$;

create or replace function public.list_disclosure_signal_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if new.entry_private is not distinct from old.entry_private then return null; end if;
 insert into public.club_membership_signals as signal(user_id,club_id,state,revision,changed_at)
 select distinct viewer.user_id,viewer.club_id,'member',1,now()
 from public.club_members subject join public.club_members viewer on viewer.club_id=subject.club_id
 where subject.user_id::text=new.user_id
 on conflict(user_id,club_id) do update set state='member',revision=signal.revision+1,changed_at=now();
 return null;
end; $$;
revoke all on function public.list_disclosure_signal_v1() from public,anon,authenticated;
drop trigger if exists series_list_disclosure on public.anime_user_lists;
create trigger series_list_disclosure after update of entry_private on public.anime_user_lists
 for each row execute function public.list_disclosure_signal_v1();
drop trigger if exists series_list_disclosure on public.manga_user_lists;
create trigger series_list_disclosure after update of entry_private on public.manga_user_lists
 for each row execute function public.list_disclosure_signal_v1();

-- The existing catalogue ingestion owns its source rows. This bridge turns changes into
-- bounded, leased enrichment jobs; no synchronous artwork/API work in a user request.
create table if not exists public.series_enrichment_jobs (
 medium text not null check(medium in ('anime','manga')), media_id integer not null,
 source_revision text not null, payload jsonb not null,
 due_at timestamptz not null default now(), lease_token uuid, lease_until timestamptz,
 attempts integer not null default 0, last_error text, last_success_at timestamptz,
 primary key(medium,media_id)
);
alter table public.series_enrichment_jobs enable row level security;
revoke all on public.series_enrichment_jobs from anon,authenticated;
grant all on public.series_enrichment_jobs to service_role;
create index if not exists series_enrichment_due on public.series_enrichment_jobs(due_at,medium,media_id);
alter table public.detail_copy add column if not exists source_revision text;
alter table public.detail_copy add column if not exists freshness timestamptz;
create unique index if not exists detail_copy_bridge_anime on public.detail_copy(anime_id,locale)
 where provenance='catalogue_bridge_v1' and section_id is null and anime_id is not null;
create unique index if not exists detail_copy_bridge_manga on public.detail_copy(manga_id,locale)
 where provenance='catalogue_bridge_v1' and section_id is null and manga_id is not null;
alter table public.theme_links add column if not exists source_identity text;
alter table public.theme_links add column if not exists freshness timestamptz;
create unique index if not exists theme_links_source_identity on public.theme_links(source_identity)
 where source_identity is not null;

create or replace function public._queue_series_enrichment_v1(p_medium text,p_row jsonb)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare snapshot jsonb; revision text;
begin
 snapshot:=jsonb_build_object('medium',p_medium,'media_id',(p_row->>'id')::integer,
  'anilist_id',p_row->'anilist_id','mal_id',p_row->'mal_id','description',p_row->'description',
  'image_url',case when p_medium='anime' then coalesce(p_row->>'banner_image',p_row->>'cover_image_large')
    else p_row->>'cover_image_large' end);
 revision:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
 insert into public.series_enrichment_jobs as job(medium,media_id,source_revision,payload)
 values(p_medium,(p_row->>'id')::integer,revision,snapshot)
 on conflict(medium,media_id) do update set source_revision=excluded.source_revision,payload=excluded.payload,
  due_at=now(),lease_token=null,lease_until=null,attempts=0,last_error=null
 where job.source_revision<>excluded.source_revision;
end; $$;
revoke all on function public._queue_series_enrichment_v1(text,jsonb) from public,anon,authenticated;

create or replace function public.catalogue_series_enrichment_trigger_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 perform public._queue_series_enrichment_v1(TG_TABLE_NAME,to_jsonb(new)); return null;
end; $$;
revoke all on function public.catalogue_series_enrichment_trigger_v1() from public,anon,authenticated;
drop trigger if exists series_enrichment_source on public.anime;
create trigger series_enrichment_source after insert or update of description,banner_image,cover_image_large,anilist_id,mal_id
 on public.anime for each row execute function public.catalogue_series_enrichment_trigger_v1();
drop trigger if exists series_enrichment_source on public.manga;
create trigger series_enrichment_source after insert or update of description,cover_image_large,anilist_id,mal_id
 on public.manga for each row execute function public.catalogue_series_enrichment_trigger_v1();

-- Catalogue deletion must not leave a perpetually due orphan consuming worker
-- claims. Stale-revision completions still preserve a newer existing job.
create or replace function public.catalogue_series_enrichment_delete_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 delete from public.series_enrichment_jobs where medium=TG_TABLE_NAME and media_id=old.id;
 return null;
end; $$;
revoke all on function public.catalogue_series_enrichment_delete_v1() from public,anon,authenticated;
drop trigger if exists series_enrichment_delete on public.anime;
create trigger series_enrichment_delete after delete on public.anime
 for each row execute function public.catalogue_series_enrichment_delete_v1();
drop trigger if exists series_enrichment_delete on public.manga;
create trigger series_enrichment_delete after delete on public.manga
 for each row execute function public.catalogue_series_enrichment_delete_v1();

create or replace function public.backfill_series_enrichment_v1(p_medium text,p_after_id integer default 0,p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r record; last_id integer:=coalesce(p_after_id,0); n integer:=0; cap integer:=least(250,greatest(1,coalesce(p_limit,250)));
begin
 if p_medium='anime' then
  -- A backfill snapshot must not overtake a newer catalogue-triggered job.
  -- SHARE (not KEY SHARE) blocks non-key description/artwork updates until this
  -- bounded source-row -> job transaction completes, and rechecks waited rows.
  for r in select * from public.anime where id>last_id order by id limit cap for share loop
   perform public._queue_series_enrichment_v1('anime',to_jsonb(r));last_id:=r.id;n:=n+1;end loop;
 elsif p_medium='manga' then
  for r in select * from public.manga where id>last_id order by id limit cap for share loop
   perform public._queue_series_enrichment_v1('manga',to_jsonb(r));last_id:=r.id;n:=n+1;end loop;
 else raise exception 'INVALID_MEDIUM'; end if;
 return jsonb_build_object('processed',n,'after_id',last_id,'has_more',n=cap);
end; $$;
revoke all on function public.backfill_series_enrichment_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function public.backfill_series_enrichment_v1(text,integer,integer) to service_role;

create or replace function public.claim_series_enrichment_v1(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare jobs jsonb;
begin
 with candidates as (select medium,media_id from public.series_enrichment_jobs
  where due_at<=now() and (lease_until is null or lease_until<=now())
  order by due_at,medium,media_id limit least(20,greatest(1,coalesce(p_limit,10))) for update skip locked),
 claimed as (update public.series_enrichment_jobs j set lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes'
  from candidates c where (j.medium,j.media_id)=(c.medium,c.media_id) returning j.*)
 select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into jobs from claimed;
 return jobs;
end; $$;
revoke all on function public.claim_series_enrichment_v1(integer) from public,anon,authenticated;
grant execute on function public.claim_series_enrichment_v1(integer) to service_role;

-- Last-good data is updated only by the current source revision AND current claim.
-- A failed or superseded extraction cannot clear curated copy, theme links or palettes.
create or replace function public.finish_series_enrichment_v1(p_medium text,p_media_id integer,p_source_revision text,
 p_lease_token uuid,p_copy jsonb default null,p_material jsonb default null,p_themes jsonb default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare job public.series_enrichment_jobs%rowtype; theme jsonb; source text;
begin
 -- Catalogue writers/deletion take the catalogue row before their job trigger.
 -- Match that order before touching a job, including theme_links FK admission,
 -- so concurrent catalogue deletion cannot create a catalogue/job deadlock.
 if p_medium='anime' then perform 1 from public.anime where id=p_media_id for key share;
 elsif p_medium='manga' then perform 1 from public.manga where id=p_media_id for key share;
 else return jsonb_build_object('outcome','superseded');end if;
 if not found then return jsonb_build_object('outcome','superseded');end if;
 select * into job from public.series_enrichment_jobs where medium=p_medium and media_id=p_media_id for update;
 if not found or p_lease_token is null or p_source_revision is null
  or job.source_revision<>p_source_revision or job.lease_token is distinct from p_lease_token
  or job.lease_until is null or job.lease_until<=now()
 then return jsonb_build_object('outcome','superseded');end if;
 if p_error is not null then
  update public.series_enrichment_jobs set attempts=attempts+1,last_error=left(p_error,120),lease_token=null,lease_until=null,
   due_at=now()+make_interval(secs=>least(86400,60*power(2,least(attempts,10)))::integer) where medium=p_medium and media_id=p_media_id;
  return jsonb_build_object('outcome','retry');
 end if;
 if nullif(p_copy->>'synopsis','') is not null then
  if p_medium='anime' then
   insert into public.detail_copy(medium,anime_id,locale,premise,synopsis,provenance,review_state,source_revision,freshness)
   values('anime',p_media_id,'en',left(p_copy->>'premise',240),p_copy->>'synopsis','catalogue_bridge_v1','source',p_source_revision,now())
   on conflict(anime_id,locale) where provenance='catalogue_bridge_v1' and section_id is null and anime_id is not null
   do update set premise=excluded.premise,synopsis=excluded.synopsis,source_revision=excluded.source_revision,freshness=now();
  else
   insert into public.detail_copy(medium,manga_id,locale,premise,synopsis,provenance,review_state,source_revision,freshness)
   values('manga',p_media_id,'en',left(p_copy->>'premise',240),p_copy->>'synopsis','catalogue_bridge_v1','source',p_source_revision,now())
   on conflict(manga_id,locale) where provenance='catalogue_bridge_v1' and section_id is null and manga_id is not null
   do update set premise=excluded.premise,synopsis=excluded.synopsis,source_revision=excluded.source_revision,freshness=now();
  end if;
 end if;
 if p_material is not null then
  if p_material->>'image_url' is distinct from job.payload->>'image_url'
   or coalesce(p_material->>'digest','') !~ '^[0-9a-f]{64}$'
   or coalesce(p_material->>'base','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'deep','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'wash','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'edge','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'ink','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'contrast','') !~ '^[0-9]+(\.[0-9]+)?$'
  then raise exception 'INVALID_MATERIAL';end if;
  if (p_material->>'contrast')::numeric<7 then raise exception 'INVALID_MATERIAL';end if;
  -- Different catalogue jobs can share an artwork URL. Serialize the current-image
  -- flip independently of their job-row locks; the partial unique index remains
  -- the last backstop. Digest includes URL AND bytes in the worker, so identical
  -- content at two provider URLs has two identities without cross-URL mutation.
  perform pg_advisory_xact_lock(hashtextextended('series-artwork:'||(p_material->>'image_url'),0));
  if exists(select 1 from public.artwork_materials where image_digest=p_material->>'digest'
    and image_url is distinct from p_material->>'image_url') then raise exception 'INVALID_MATERIAL_IDENTITY';end if;
  update public.artwork_materials set is_current=false where image_url=p_material->>'image_url';
  insert into public.artwork_materials(image_digest,image_url,content_revision,extraction_version,base_color,deep_color,wash_color,edge_color,ink_color,contrast,is_current)
  values(p_material->>'digest',p_material->>'image_url',p_source_revision,'art-hue-v1',p_material->>'base',p_material->>'deep',
   p_material->>'wash',p_material->>'edge',p_material->>'ink',p_material->>'contrast',true)
  on conflict(image_digest) do update set is_current=true,content_revision=excluded.content_revision,
   extraction_version=excluded.extraction_version,base_color=excluded.base_color,deep_color=excluded.deep_color,
   wash_color=excluded.wash_color,edge_color=excluded.edge_color,ink_color=excluded.ink_color,contrast=excluded.contrast;
 end if;
 if p_medium='anime' and p_themes is not null then
  if jsonb_typeof(p_themes)<>'array' or jsonb_array_length(p_themes)>30 then raise exception 'INVALID_THEMES';end if;
  -- NULL means unknown/provider failure: retain last good. A known exact-ID set,
  -- including [], supersedes only this producer's rows, never curated links.
  delete from public.theme_links t where t.anime_id=p_media_id
   and t.source_identity like 'animethemes:'||p_media_id||':%'
   and not exists(select 1 from jsonb_array_elements(p_themes) incoming
     where t.source_identity='animethemes:'||p_media_id||':'||(incoming->>'source_id'));
  for theme in select * from jsonb_array_elements(p_themes) loop
   source:='animethemes:'||p_media_id||':'||(theme->>'source_id');
   if nullif(theme->>'source_id','') is null or theme->>'role' not in ('op','ed') then raise exception 'INVALID_THEME';end if;
   insert into public.theme_links(anime_id,role,sequence_order,song_title,artist,match_state,evidence,source_identity,freshness)
   values(p_media_id,theme->>'role',coalesce((theme->>'sequence_order')::integer,1),theme->>'song_title',theme->>'artist',
    'search','Exact external ID: '||coalesce(job.payload->>'anilist_id','')||' / '||coalesce(job.payload->>'mal_id',''),source,now())
   on conflict(source_identity) where source_identity is not null do update set song_title=excluded.song_title,
    artist=excluded.artist,sequence_order=excluded.sequence_order,role=excluded.role,
    match_state='search',external_url=null,evidence=excluded.evidence,freshness=now();
  end loop;
 end if;
 update public.series_enrichment_jobs set lease_token=null,lease_until=null,attempts=0,last_error=null,
  last_success_at=now(),due_at=now()+interval '7 days' where medium=p_medium and media_id=p_media_id;
 return jsonb_build_object('outcome','applied');
end; $$;
revoke all on function public.finish_series_enrichment_v1(text,integer,text,uuid,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_series_enrichment_v1(text,integer,text,uuid,jsonb,jsonb,jsonb,text) to service_role;

-- Forward lifecycle repair for the integrated series foundation. Prepared only.
-- Auth foreign keys validate existing ownership; orphaned data aborts this migration
-- for explicit review rather than being silently purged or rewritten.
ALTER TABLE public.library_import_jobs
    ADD CONSTRAINT library_import_jobs_auth_owner
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'user_series_intent', 'home_publications', 'mutation_receipts', 'list_entry_tombstones'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN account_user_id uuid GENERATED ALWAYS AS (user_id::uuid) STORED', relation_name);
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (account_user_id) REFERENCES auth.users(id) ON DELETE CASCADE',
            relation_name, relation_name || '_auth_owner');
        EXECUTE format('CREATE INDEX %I ON public.%I(account_user_id)',
            relation_name || '_auth_owner_idx', relation_name);
    END LOOP;
END;
$$;

CREATE FUNCTION public.series_account_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE owner_text text := to_jsonb(NEW)->>'user_id'; owner_id uuid;
BEGIN
    BEGIN
        owner_id := owner_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END;
    IF owner_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END IF;
    -- Reuse the existing deletion lock and committed barrier. Old JWT validity
    -- cannot admit writes while account deletion is in progress.
    PERFORM public._account_write_guard(owner_id::text);
    -- Hold the live owner until this transaction ends. GoTrue deletion either
    -- waits and cascades this write, or finishes first and this write is refused.
    PERFORM 1 FROM auth.users WHERE id = owner_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ACCOUNT_DELETION_IN_PROGRESS' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.series_account_write_guard() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'library_import_jobs', 'user_series_intent', 'mutation_receipts'
    ] LOOP
        EXECUTE format('CREATE TRIGGER series_account_write_guard BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.series_account_write_guard()', relation_name);
    END LOOP;
END;
$$;
-- Tombstones and Home publications have no client write grants. Internal list
-- deletion may write them after the deletion barrier; guarding that cleanup
-- would prevent deletion itself. Their validated auth FK still prevents orphan
-- creation and cascades the internal cleanup records with the deleted account.

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES
('20261007040000','series_home_foundation_v1',ARRAY[$kuro_foundation_history$-- Series / Home foundation (prepared, NOT deployed).
-- Additive identity, revision fence, bounded Home/detail/Collection reads,
-- import jobs and progress receipts. Existing anime/manga ids and list rows stay.
-- Rollback: see docs/handoffs/2026-10-07-home-series-evidence/rollback.md.
-- No cron is scheduled here.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- List revision fence. Legacy integer progress stays the compatibility
-- projection. Fractional labels live in progress_label and are not rounded
-- into progress. Every insert/update/delete advances the fence in this
-- trigger, including direct PostgREST writes.
-- ---------------------------------------------------------------------------

alter table public.anime_user_lists
  add column if not exists server_revision bigint not null default 1,
  add column if not exists lifecycle_id uuid not null default gen_random_uuid(),
  add column if not exists unit_id uuid,
  add column if not exists progress_label text,
  add column if not exists repeat_count integer not null default 0,
  add column if not exists score_raw numeric,
  add column if not exists score_scale text,
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
  add column if not exists entry_private boolean not null default false,
  add column if not exists source_custom_lists jsonb not null default '[]'::jsonb,
  add column if not exists source_hidden boolean not null default false,
  add column if not exists source_list_options text;

alter table public.manga_user_lists
  add column if not exists server_revision bigint not null default 1,
  add column if not exists lifecycle_id uuid not null default gen_random_uuid(),
  add column if not exists unit_id uuid,
  add column if not exists progress_label text,
  add column if not exists repeat_count integer not null default 0,
  add column if not exists score_raw numeric,
  add column if not exists score_scale text,
  add column if not exists started_raw text,
  add column if not exists finished_raw text,
  add column if not exists volumes_progress integer,
  add column if not exists entry_private boolean not null default false,
  add column if not exists source_custom_lists jsonb not null default '[]'::jsonb,
  add column if not exists source_hidden boolean not null default false,
  add column if not exists source_list_options text;

create table if not exists public.list_entry_tombstones (
  user_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null,
  lifecycle_id uuid not null,
  server_revision bigint not null,
  removed_at timestamptz not null default now(),
  primary key (user_id, medium, media_id, lifecycle_id)
);

create index if not exists idx_list_entry_tombstones_lookup
  on public.list_entry_tombstones (user_id, medium, media_id);

alter table public.list_entry_tombstones enable row level security;
revoke all on table public.list_entry_tombstones from public, anon, authenticated;

create index if not exists idx_anime_user_lists_home_active
  on public.anime_user_lists (user_id, updated_at desc, anime_id desc)
  where list_type in ('WATCHING', 'PLANNING');

create index if not exists idx_manga_user_lists_home_active
  on public.manga_user_lists (user_id, updated_at desc, manga_id desc)
  where list_type in ('READING', 'PLANNING');

-- All authenticated list statements and RPC writers share one account admission lock.
-- It is transaction-scoped (not a network lock), independent across accounts, and is
-- acquired BEFORE row locks so missing-row imports and deletion cannot cross.
create or replace function public.list_account_write_lock()
returns trigger language plpgsql security invoker set search_path=public,extensions as $$
begin
 if auth.uid() is not null then perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0)); end if;
 return null;
end; $$;
revoke all on function public.list_account_write_lock() from public;
grant execute on function public.list_account_write_lock() to authenticated,service_role;
drop trigger if exists list_account_write_lock on public.anime_user_lists;
create trigger list_account_write_lock before insert or update or delete on public.anime_user_lists
for each statement execute function public.list_account_write_lock();
drop trigger if exists list_account_write_lock on public.manga_user_lists;
create trigger list_account_write_lock before insert or update or delete on public.manga_user_lists
for each statement execute function public.list_account_write_lock();

create or replace function public.list_entry_revision_fence()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_medium text;
  v_media_id integer;
begin
  v_medium := case when tg_table_name = 'anime_user_lists' then 'anime' else 'manga' end;

  if tg_op = 'DELETE' then
    if tg_table_name = 'anime_user_lists' then
      v_media_id := old.anime_id;
    else
      v_media_id := old.manga_id;
    end if;
    insert into public.list_entry_tombstones
      (user_id, medium, media_id, lifecycle_id, server_revision, removed_at)
    values
      (old.user_id, v_medium, v_media_id, old.lifecycle_id, old.server_revision + 1, now())
    on conflict (user_id, medium, media_id, lifecycle_id)
    do update set server_revision = excluded.server_revision, removed_at = excluded.removed_at;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.lifecycle_id is null then
      new.lifecycle_id := gen_random_uuid();
    end if;
    if new.server_revision is null or new.server_revision < 1 then
      new.server_revision := 1;
    end if;
    return new;
  end if;

  -- UPDATE: database-owned revision. lifecycle_id is immutable.
  new.server_revision := old.server_revision + 1;
  new.lifecycle_id := old.lifecycle_id;
  return new;
end;
$$;

drop trigger if exists list_entry_revision_fence on public.anime_user_lists;
create trigger list_entry_revision_fence
  before insert or update or delete on public.anime_user_lists
  for each row execute function public.list_entry_revision_fence();

drop trigger if exists list_entry_revision_fence on public.manga_user_lists;
create trigger list_entry_revision_fence
  before insert or update or delete on public.manga_user_lists
  for each row execute function public.list_entry_revision_fence();

revoke all on function public.list_entry_revision_fence() from public;
grant execute on function public.list_entry_revision_fence() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Receipts. Replay of the same mutation id is not a second write.
-- ---------------------------------------------------------------------------

create table if not exists public.mutation_receipts (
  user_id text not null,
  mutation_id uuid not null,
  request_hash text not null,
  outcome text not null,
  medium text not null,
  media_id integer not null,
  server_revision bigint,
  position integer,
  created_at timestamptz not null default now(),
  primary key (user_id, mutation_id)
);

create index if not exists idx_mutation_receipts_created
  on public.mutation_receipts (created_at);

alter table public.mutation_receipts enable row level security;
revoke all on table public.mutation_receipts from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Continuity identity. A graph edge is not membership. Source rows stay.
-- ---------------------------------------------------------------------------

create table if not exists public.series (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  continuity text not null default 'singleton' check (continuity in ('singleton', 'verified', 'disputed')),
  title text not null,
  grouping_state text not null default 'approved' check (grouping_state in ('proposed', 'approved', 'superseded')),
  mapping_revision bigint not null default 1,
  artwork_policy text not null default 'resume_entry',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.series_sections (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  kind text not null check (kind in ('season', 'film', 'extra', 'edition')),
  ordinal integer,
  name text not null,
  sort_order integer not null,
  provenance text not null,
  state text not null default 'approved' check (state in ('proposed', 'approved', 'superseded')),
  unique (series_id, sort_order)
);

create table if not exists public.series_entry_spans (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  section_id uuid references public.series_sections (id),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  source_range_start text,
  source_range_end text,
  display_label text,
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

create unique index if not exists series_entry_spans_anime_uq
  on public.series_entry_spans (anime_id) where anime_id is not null;
create unique index if not exists series_entry_spans_manga_uq
  on public.series_entry_spans (manga_id) where manga_id is not null;
create index if not exists series_entry_spans_series
  on public.series_entry_spans (series_id);

create table if not exists public.provider_entry_refs (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  external_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  unresolved boolean not null default false,
  unique (provider, external_id, medium)
);

create table if not exists public.mapping_revisions (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series (id),
  state text not null check (state in ('proposed', 'approved', 'superseded')),
  source text not null,
  rule_revision text not null,
  reviewer text,
  created_at timestamptz not null default now()
);

create table if not exists public.mapping_revision_spans (
  revision_id uuid not null references public.mapping_revisions (id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_kind text not null,
  section_ordinal integer,
  section_name text not null,
  sort_order integer not null,
  source_range_start text,
  source_range_end text,
  display_label text
);

create index if not exists mapping_revision_spans_revision
  on public.mapping_revision_spans (revision_id);

create table if not exists public.user_series_intent (
  user_id text not null,
  series_id uuid not null references public.series (id),
  saved boolean not null default false,
  followed boolean not null default false,
  resume_medium text,
  resume_media_id integer,
  primary key (user_id, series_id)
);

create table if not exists public.catalogue_units (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer references public.anime (id),
  manga_id integer references public.manga (id),
  section_id uuid references public.series_sections (id),
  label text not null,
  order_key numeric not null,
  edition_key text not null default '',
  available boolean not null default false,
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

alter table public.catalogue_units
  add column if not exists title text,
  add column if not exists synopsis text,
  add column if not exists image_url text,
  add column if not exists source_provenance text;

create unique index if not exists catalogue_units_anime_uq
  on public.catalogue_units (anime_id, edition_key, order_key) where anime_id is not null;
create unique index if not exists catalogue_units_manga_uq
  on public.catalogue_units (manga_id, edition_key, order_key) where manga_id is not null;

create table if not exists public.artwork_materials (
  image_digest text primary key,
  image_url text not null,
  content_revision text not null,
  extraction_version text not null,
  base_color text not null,
  deep_color text not null,
  wash_color text not null,
  edge_color text not null,
  ink_color text not null,
  contrast text not null
);

alter table public.artwork_materials add column if not exists is_current boolean not null default true;
create unique index if not exists artwork_materials_current_image_uq
  on public.artwork_materials(image_url) where is_current;

create table if not exists public.detail_copy (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_id uuid references public.series_sections (id),
  locale text not null default 'en',
  premise text,
  hook text,
  synopsis text,
  provenance text not null,
  review_state text not null default 'unreviewed',
  check (
    (medium = 'anime' and anime_id is not null and manga_id is null)
    or (medium = 'manga' and manga_id is not null and anime_id is null)
  )
);

create table if not exists public.theme_links (
  id uuid primary key default gen_random_uuid(),
  anime_id integer not null references public.anime (id),
  section_id uuid references public.series_sections (id),
  role text not null check (role in ('op', 'ed', 'insert')),
  sequence_order integer not null default 1,
  song_title text,
  artist text,
  external_url text,
  match_state text not null check (match_state in ('verified', 'search', 'unmatched')),
  evidence text
);

create table if not exists public.adaptation_coverage (
  id uuid primary key default gen_random_uuid(),
  anime_id integer references public.anime (id),
  section_id uuid references public.series_sections (id),
  source_manga_id integer references public.manga (id),
  source_kind text not null check (source_kind in ('manga', 'novel', 'other')),
  mapping_state text not null check (mapping_state in ('exact', 'partial', 'reordered', 'original_ending', 'unknown')),
  starts_at text,
  ends_at text,
  read_next text,
  evidence text,
  revision bigint not null default 1
);

create index if not exists detail_copy_anime_lookup on public.detail_copy(anime_id, locale, section_id) where anime_id is not null;
create index if not exists detail_copy_manga_lookup on public.detail_copy(manga_id, locale, section_id) where manga_id is not null;
create index if not exists theme_links_entry_section on public.theme_links(anime_id, section_id, sequence_order);
create index if not exists coverage_anime_section on public.adaptation_coverage(anime_id, section_id, revision desc);
create index if not exists coverage_manga_revision on public.adaptation_coverage(source_manga_id, revision desc);

create table if not exists public.release_events (
  id uuid primary key default gen_random_uuid(),
  medium text not null check (medium in ('anime', 'manga')),
  anime_id integer,
  manga_id integer,
  section_id uuid references public.series_sections (id),
  kind text not null,
  precision text not null check (precision in ('instant', 'day', 'month', 'quarter', 'year', 'unknown')),
  source_local_date text,
  source_zone text,
  utc_instant timestamptz,
  locale text,
  territory text,
  status text not null check (status in ('scheduled', 'released', 'delayed', 'cancelled', 'withdrawn', 'announced')),
  evidence text,
  freshness timestamptz,
  revision bigint not null default 1,
  check (
    (medium = 'anime' and anime_id is not null)
    or (medium = 'manga' and manga_id is not null)
  )
);

create index if not exists idx_release_events_anime_time
  on public.release_events (anime_id, utc_instant)
  where anime_id is not null and utc_instant is not null;
create index if not exists idx_release_events_manga
  on public.release_events (manga_id, status)
  where manga_id is not null;

create table if not exists public.home_publications (
  user_id text not null,
  medium text not null check (medium in ('anime', 'manga')),
  revision bigint not null default 0,
  primary key (user_id, medium)
);

create table if not exists public.library_import_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  provider text not null check (provider in ('anilist', 'myanimelist')),
  source_kind text not null check (source_kind in ('account', 'export')),
  medium_filter text not null check (medium_filter in ('anime', 'manga', 'both')),
  merge_policy text not null default 'merge' check (merge_policy = 'merge'),
  idempotency_key text not null,
  payload_hash text not null,
  state text not null check (state in ('queued', 'running', 'ready', 'ready_with_issues', 'cancelled', 'failed')),
  discovered_total integer,
  counters jsonb not null default '{}'::jsonb,
  home_revision bigint not null default 0,
  sanitized_error text,
  retry_after timestamptz,
  anime_checkpoint jsonb not null default '{}'::jsonb,
  manga_checkpoint jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists idx_library_import_jobs_owner
  on public.library_import_jobs (user_id, state);

-- One active action per account/provider. Both-medium actions overlap either stream.
create unique index if not exists library_import_jobs_active_uq
  on public.library_import_jobs(user_id, provider) where state in ('queued', 'running');

create table if not exists public.library_import_baselines (
  job_id uuid not null references public.library_import_jobs(id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null,
  lifecycle_id uuid not null,
  server_revision bigint not null,
  primary key(job_id, medium, media_id)
);
alter table public.library_import_baselines enable row level security;
revoke all on public.library_import_baselines from public, anon, authenticated;

create table if not exists public.library_import_items (
  job_id uuid not null references public.library_import_jobs (id) on delete cascade,
  provider text not null,
  external_id text not null,
  medium text not null,
  disposition text not null,
  request_hash text,
  detail text,
  primary key (job_id, provider, external_id, medium)
);

alter table public.series enable row level security;
alter table public.series_sections enable row level security;
alter table public.series_entry_spans enable row level security;
alter table public.provider_entry_refs enable row level security;
alter table public.mapping_revisions enable row level security;
alter table public.mapping_revision_spans enable row level security;
alter table public.user_series_intent enable row level security;
alter table public.catalogue_units enable row level security;
alter table public.artwork_materials enable row level security;
alter table public.detail_copy enable row level security;
alter table public.theme_links enable row level security;
alter table public.adaptation_coverage enable row level security;
alter table public.release_events enable row level security;
alter table public.home_publications enable row level security;
alter table public.library_import_jobs enable row level security;
alter table public.library_import_items enable row level security;

drop policy if exists series_public_read on public.series;
create policy series_public_read on public.series for select to anon, authenticated using (true);
drop policy if exists series_sections_public_read on public.series_sections;
create policy series_sections_public_read on public.series_sections for select to anon, authenticated using (true);
drop policy if exists series_spans_public_read on public.series_entry_spans;
create policy series_spans_public_read on public.series_entry_spans for select to anon, authenticated using (true);
drop policy if exists provider_refs_public_read on public.provider_entry_refs;
create policy provider_refs_public_read on public.provider_entry_refs for select to anon, authenticated using (true);
drop policy if exists mapping_revisions_public_read on public.mapping_revisions;
create policy mapping_revisions_public_read on public.mapping_revisions for select to anon, authenticated using (true);
drop policy if exists mapping_spans_public_read on public.mapping_revision_spans;
create policy mapping_spans_public_read on public.mapping_revision_spans for select to anon, authenticated using (true);
drop policy if exists units_public_read on public.catalogue_units;
create policy units_public_read on public.catalogue_units for select to anon, authenticated using (true);
drop policy if exists materials_public_read on public.artwork_materials;
create policy materials_public_read on public.artwork_materials for select to anon, authenticated using (true);
drop policy if exists detail_copy_public_read on public.detail_copy;
create policy detail_copy_public_read on public.detail_copy for select to anon, authenticated using (true);
drop policy if exists themes_public_read on public.theme_links;
create policy themes_public_read on public.theme_links for select to anon, authenticated using (true);
drop policy if exists coverage_public_read on public.adaptation_coverage;
create policy coverage_public_read on public.adaptation_coverage for select to anon, authenticated using (true);
drop policy if exists releases_public_read on public.release_events;
create policy releases_public_read on public.release_events for select to anon, authenticated using (true);

drop policy if exists user_series_intent_own on public.user_series_intent;
create policy user_series_intent_own on public.user_series_intent
  for all to authenticated
  using (user_id = (select auth.uid())::text)
  with check (user_id = (select auth.uid())::text);

drop policy if exists home_publications_own on public.home_publications;
create policy home_publications_own on public.home_publications
  for select to authenticated
  using (user_id = (select auth.uid())::text);

drop policy if exists library_import_jobs_own_select on public.library_import_jobs;
create policy library_import_jobs_own_select on public.library_import_jobs
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists library_import_items_own_select on public.library_import_items;
create policy library_import_items_own_select on public.library_import_items
  for select to authenticated
  using (
    exists (
      select 1 from public.library_import_jobs j
      where j.id = library_import_items.job_id and j.user_id = (select auth.uid())
    )
  );

grant select on public.series, public.series_sections, public.series_entry_spans,
  public.provider_entry_refs, public.mapping_revisions, public.mapping_revision_spans,
  public.catalogue_units, public.artwork_materials, public.detail_copy, public.theme_links,
  public.adaptation_coverage, public.release_events
  to anon, authenticated;

grant select, insert, update, delete on public.user_series_intent to authenticated;
grant select on public.home_publications, public.library_import_jobs, public.library_import_items to authenticated;
revoke insert, update, delete on public.home_publications, public.library_import_jobs, public.library_import_items from authenticated, anon;

do $$
begin
  if to_regclass('public.title_comments') is not null
     and not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'title_comments' and column_name = 'spoiler_scope'
     ) then
    alter table public.title_comments
      add column spoiler_scope text not null default 'none'
      check (spoiler_scope in ('none', 'story', 'ending'));
  end if;
  if to_regclass('public.feature_flags') is not null then
    insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
    values
      ('series_foundation_v1', false, 0, '{}', 'Bounded series Home/detail/Collection contracts and progress receipts'),
      ('series_home_native_v1', false, 0, '{}', 'Native Home and Anime/Manga detail hierarchy')
    on conflict (flag_name) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Progress mutations. Field-specific. Same key + same hash replays the receipt.
-- Same key + different hash is rejected. A removed lifecycle is not recreated.
--
-- `_apply_progress_mutations_for_user` is the one writer: authenticated RPCs
-- pass auth.uid()::text; service-role import apply/undo pass the already-checked
-- session user. It is NOT granted to authenticated.
-- ---------------------------------------------------------------------------

create or replace function public._apply_progress_mutations_for_user(
  p_user text,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user text := p_user;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_mutation uuid;
  v_medium text;
  v_media_id integer;
  v_lifecycle uuid;
  v_unit uuid;
  v_base bigint;
  v_position integer;
  v_label text;
  v_status text;
  v_hash text;
  v_canonical text;
  v_receipt public.mutation_receipts%rowtype;
  v_revision bigint;
  v_lifecycle_row uuid;
  v_progress integer;
  v_notes text;
  v_rating integer;
  v_list_type text;
  v_found boolean;
  v_outcome text;
  v_tombstone boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if v_user is null or btrim(v_user) = '' then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if jsonb_array_length(p_mutations) > 50 then
    raise exception 'BATCH_TOO_LARGE';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_mutations) as t(value)
    order by t.value->>'medium', (t.value->>'media_id'), t.value->>'mutation_id'
  loop
    begin
      v_mutation := (v_item->>'mutation_id')::uuid;
      v_medium := v_item->>'medium';
      v_media_id := (v_item->>'media_id')::integer;
      v_lifecycle := (v_item->>'lifecycle_id')::uuid;
      v_base := (v_item->>'base_revision')::bigint;
      v_position := (v_item->>'position')::integer;
      v_label := v_item->>'position_label';
      v_status := v_item->>'status';
      if v_item->>'unit_id' is null or v_item->>'unit_id' = '' then
        v_unit := null;
      else
        v_unit := (v_item->>'unit_id')::uuid;
      end if;
    exception when others then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_item->>'mutation_id', 'outcome', 'invalid_target'
      ));
      continue;
    end;

    if v_mutation is null or v_media_id is null or v_lifecycle is null
       or v_medium is null or v_medium not in ('anime', 'manga') or v_base is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is not null and v_position < 0 then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is null and v_status is null and v_label is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_status is not null and v_status not in ('WATCHING', 'READING', 'PLANNING', 'COMPLETED', 'DROPPED', 'PAUSED') then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    v_found := false;
    if v_medium = 'anime' then
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id
      for update;
      v_found := found;
    else
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id
      for update;
      v_found := found;
    end if;

    v_canonical := jsonb_build_object(
      'medium', v_medium, 'media_id', v_media_id, 'lifecycle_id', v_lifecycle,
      'base_revision', v_base, 'unit_id', v_unit, 'position', v_item->'position',
      'position_label', v_item->'position_label', 'status', v_item->'status',
      'has_position',v_item ? 'position','has_unit_id',v_item ? 'unit_id',
      'has_position_label',v_item ? 'position_label','has_status',v_item ? 'status'
    )::text;
    v_hash := encode(digest(v_canonical, 'sha256'), 'hex');

    select * into v_receipt
    from public.mutation_receipts
    where user_id = v_user and mutation_id = v_mutation;

    if v_receipt.mutation_id is not null then
      v_outcome := case when v_receipt.request_hash <> v_hash then 'rejected_payload'
        when v_receipt.outcome in ('applied','already_applied') then 'already_applied' else v_receipt.outcome end;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', v_outcome,
        'server_revision', v_receipt.server_revision,
        'position', v_receipt.position
      ));
      continue;
    end if;

    select exists (
      select 1 from public.list_entry_tombstones t
      where t.user_id = v_user and t.medium = v_medium and t.media_id = v_media_id
        and t.lifecycle_id = v_lifecycle
    ) into v_tombstone;

    if v_tombstone or (v_found and v_lifecycle_row is distinct from v_lifecycle) then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'removed_entry'
      ));
      continue;
    end if;

    if not v_found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    if v_revision is distinct from v_base then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', 'conflict',
        'server_revision', v_revision,
        'position', v_progress,
        'notes', v_notes,
        'rating', v_rating,
        'status', v_list_type
      ));
      continue;
    end if;

    if v_unit is not null and not exists (
      select 1 from public.catalogue_units u where u.id = v_unit and u.medium = v_medium
        and ((v_medium = 'anime' and u.anime_id = v_media_id)
          or (v_medium = 'manga' and u.manga_id = v_media_id))
    ) then
      v_results := v_results || jsonb_build_array(jsonb_build_object('mutation_id', v_mutation, 'outcome', 'invalid_target'));
      continue;
    end if;
    -- Missing position is retained only after hashing/replay lookup of the immutable body.
    v_position := coalesce(v_position, v_progress, 0);

    if v_medium = 'anime' then
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.anime_user_lists
          set progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      else
        update public.anime_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id;
    else
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.manga_user_lists
          set progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      else
        update public.manga_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id;
    end if;

    insert into public.mutation_receipts
      (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
    values
      (v_user, v_mutation, v_hash, 'applied', v_medium, v_media_id, v_revision, v_progress);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'mutation_id', v_mutation,
      'outcome', 'applied',
      'server_revision', v_revision,
      'position', v_progress
    ));
  end loop;

  return jsonb_build_object('items', v_results);
end;
$$;

create or replace function public.apply_progress_mutations_v1(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  return public._apply_progress_mutations_for_user(v_uid::text, p_mutations);
end;
$$;

-- Service-role / import-session helper: take the current server_revision under the
-- row lock, write one receipt, apply progress and/or status. Notes and rating stay
-- outside this helper (direct writes that still advance server_revision).
create or replace function public._fence_set_progress_status(
  p_user text,
  p_medium text,
  p_media_id integer,
  p_mutation_id uuid,
  p_progress integer,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lifecycle uuid;
  v_revision bigint;
  v_cur_progress integer;
  v_cur_status text;
  v_position integer;
  v_status text;
  v_result jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if p_user is null or p_medium is null or p_media_id is null or p_mutation_id is null then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_progress is null and p_status is null then
    raise exception 'INVALID_PAYLOAD';
  end if;

  if p_medium = 'anime' then
    select lifecycle_id, server_revision, progress, list_type
      into v_lifecycle, v_revision, v_cur_progress, v_cur_status
    from public.anime_user_lists
    where user_id = p_user and anime_id = p_media_id
    for update;
  else
    select lifecycle_id, server_revision, progress, list_type
      into v_lifecycle, v_revision, v_cur_progress, v_cur_status
    from public.manga_user_lists
    where user_id = p_user and manga_id = p_media_id
    for update;
  end if;
  if v_lifecycle is null then
    raise exception 'INVALID_TARGET';
  end if;

  v_position := coalesce(p_progress, v_cur_progress, 0);
  v_status := coalesce(p_status, v_cur_status);

  v_result := public._apply_progress_mutations_for_user(
    p_user,
    jsonb_build_array(jsonb_build_object(
      'mutation_id', p_mutation_id,
      'medium', p_medium,
      'media_id', p_media_id,
      'lifecycle_id', v_lifecycle,
      'base_revision', v_revision,
      'position', v_position,
      'status', v_status
    ))
  );
  return v_result -> 'items' -> 0;
end;
$$;

create or replace function public._import_mutation_id(
  p_scope text,
  p_session uuid,
  p_type text,
  p_media_id integer
)
returns uuid
language sql
immutable
set search_path = public, extensions
as $$
  select (
    substr(h, 1, 8) || '-' ||
    substr(h, 9, 4) || '-' ||
    '5' || substr(h, 13, 3) || '-' ||
    'a' || substr(h, 17, 3) || '-' ||
    substr(h, 21, 12)
  )::uuid
  from (
    select md5(coalesce(p_scope, '') || ':' || coalesce(p_session::text, '') || ':'
      || coalesce(p_type, '') || ':' || coalesce(p_media_id::text, '')) as h
  ) s;
$$;

revoke all on function public._apply_progress_mutations_for_user(text, jsonb) from public, anon, authenticated;
revoke all on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) from public, anon, authenticated;
revoke all on function public._import_mutation_id(text, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.apply_progress_mutations_v1(jsonb) from public;
grant execute on function public.apply_progress_mutations_v1(jsonb) to authenticated, service_role;
-- service_role keeps EXECUTE on the internal helpers (SECURITY DEFINER callers).
grant execute on function public._apply_progress_mutations_for_user(text, jsonb) to service_role;
grant execute on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) to service_role;
grant execute on function public._import_mutation_id(text, uuid, text, integer) to service_role;

-- ---------------------------------------------------------------------------
-- Removal mutations. Same key + same hash replays the receipt. A stale base
-- revision conflicts. The delete trigger writes the lifecycle tombstone.
-- ---------------------------------------------------------------------------

create or replace function public.apply_remove_mutations_v1(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_mutation uuid;
  v_medium text;
  v_media_id integer;
  v_lifecycle uuid;
  v_base bigint;
  v_hash text;
  v_canonical text;
  v_receipt public.mutation_receipts%rowtype;
  v_revision bigint;
  v_lifecycle_row uuid;
  v_progress integer;
  v_notes text;
  v_rating integer;
  v_list_type text;
  v_found boolean;
  v_outcome text;
  v_tombstone boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if jsonb_array_length(p_mutations) > 50 then
    raise exception 'BATCH_TOO_LARGE';
  end if;
  v_user := v_uid::text;

  for v_item in
    select value
    from jsonb_array_elements(p_mutations) as t(value)
    order by t.value->>'medium', (t.value->>'media_id'), t.value->>'mutation_id'
  loop
    begin
      v_mutation := (v_item->>'mutation_id')::uuid;
      v_medium := v_item->>'medium';
      v_media_id := (v_item->>'media_id')::integer;
      v_lifecycle := (v_item->>'lifecycle_id')::uuid;
      v_base := (v_item->>'base_revision')::bigint;
    exception when others then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_item->>'mutation_id', 'outcome', 'invalid_target'
      ));
      continue;
    end;

    if v_medium not in ('anime', 'manga') or v_lifecycle is null or v_base is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    v_canonical := 'remove|' || v_medium || '|' || v_media_id::text || '|' || v_lifecycle::text;
    v_hash := encode(digest(v_canonical, 'sha256'), 'hex');

    select * into v_receipt
    from public.mutation_receipts
    where user_id = v_user and mutation_id = v_mutation;

    if v_receipt.mutation_id is not null then
      v_outcome := case when v_receipt.request_hash <> v_hash then 'rejected_payload'
        when v_receipt.outcome in ('applied','already_applied') then 'already_applied' else v_receipt.outcome end;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', v_outcome,
        'server_revision', v_receipt.server_revision
      ));
      continue;
    end if;

    select exists (
      select 1 from public.list_entry_tombstones t
      where t.user_id = v_user and t.medium = v_medium and t.media_id = v_media_id
        and t.lifecycle_id = v_lifecycle
    ) into v_tombstone;

    v_found := false;
    if v_medium = 'anime' then
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id
      for update;
      v_found := found;
    else
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id
      for update;
      v_found := found;
    end if;

    if v_tombstone and not v_found then
      insert into public.mutation_receipts
        (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
      values
        (v_user, v_mutation, v_hash, 'already_applied', v_medium, v_media_id, coalesce(v_revision, v_base), null);
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'already_applied'
      ));
      continue;
    end if;

    if v_found and v_lifecycle_row is distinct from v_lifecycle then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'removed_entry'
      ));
      continue;
    end if;

    if not v_found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'already_applied'
      ));
      continue;
    end if;

    if v_revision is distinct from v_base then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', 'conflict',
        'server_revision', v_revision,
        'position', v_progress,
        'notes', v_notes,
        'rating', v_rating,
        'status', v_list_type
      ));
      continue;
    end if;

    if v_medium = 'anime' then
      delete from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id;
    else
      delete from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id;
    end if;

    insert into public.mutation_receipts
      (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
    values
      (v_user, v_mutation, v_hash, 'applied', v_medium, v_media_id, v_revision + 1, null);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'mutation_id', v_mutation,
      'outcome', 'applied',
      'server_revision', v_revision + 1
    ));
  end loop;

  return jsonb_build_object('items', v_results);
end;
$$;

revoke all on function public.apply_remove_mutations_v1(jsonb) from public;
grant execute on function public.apply_remove_mutations_v1(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Atomic mapping publication. A failed revision does not delete the last
-- approved spans: validation runs before the replacement, and a raise
-- rolls the replacement back with the statement.
-- ---------------------------------------------------------------------------

create or replace function public.publish_mapping_revision(p_revision uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_series uuid;
  v_state text;
  v_bad integer;
  v_role text := auth.role();
begin
  if v_role in ('authenticated', 'anon') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select series_id, state into v_series, v_state
  from public.mapping_revisions
  where id = p_revision
  for update;

  if v_series is null then
    raise exception 'REVISION_NOT_FOUND';
  end if;
  -- Different proposed revisions for the same continuity share its publication
  -- lock; metadata validation and replacement must see the same current map.
  perform 1 from public.series where id=v_series for update;
  if v_state <> 'proposed' then
    raise exception 'REVISION_NOT_PROPOSED';
  end if;

  select count(*) into v_bad
  from public.mapping_revision_spans s
  where s.revision_id = p_revision
    and (
      (s.medium = 'anime' and (s.anime_id is null or not exists (select 1 from public.anime a where a.id = s.anime_id)))
      or (s.medium = 'manga' and (s.manga_id is null or not exists (select 1 from public.manga m where m.id = s.manga_id)))
      or s.medium not in ('anime', 'manga')
    );
  if v_bad > 0 then
    raise exception 'UNRESOLVED_TARGET';
  end if;

  -- A split cour may have multiple source entries in one logical section. Their
  -- section description must agree before publication touches the last good map.
  if exists (
    select 1 from public.mapping_revision_spans s where s.revision_id=p_revision
    group by s.sort_order
    having count(distinct jsonb_build_array(s.section_kind,s.section_ordinal,s.section_name))>1
  ) then raise exception 'INCONSISTENT_SECTION'; end if;
  if not exists(select 1 from public.mapping_revision_spans where revision_id=p_revision)
    then raise exception 'UNRESOLVED_TARGET'; end if;

  if exists (
    select 1 from public.series_sections old
    where old.series_id = v_series and old.state = 'approved'
      and not exists (select 1 from public.mapping_revision_spans proposed where proposed.revision_id = p_revision
        and proposed.sort_order = old.sort_order and proposed.section_kind = old.kind
        and proposed.section_ordinal is not distinct from old.ordinal)
      and (exists (select 1 from public.catalogue_units where section_id = old.id)
        or exists (select 1 from public.detail_copy where section_id = old.id)
        or exists (select 1 from public.theme_links where section_id = old.id)
        or exists (select 1 from public.adaptation_coverage where section_id = old.id)
        or exists (select 1 from public.release_events where section_id = old.id))
  ) then raise exception 'SECTION_RECONCILIATION_REQUIRED'; end if;

  -- A section with attached data cannot silently be rebound to different catalogue entries.
  if exists (
    select 1 from public.series_sections old
    where old.series_id=v_series and old.state='approved'
      and (exists (select 1 from public.catalogue_units where section_id = old.id)
        or exists (select 1 from public.detail_copy where section_id = old.id)
        or exists (select 1 from public.theme_links where section_id = old.id)
        or exists (select 1 from public.adaptation_coverage where section_id = old.id)
        or exists (select 1 from public.release_events where section_id = old.id))
      and exists (
        (select sp.medium,sp.anime_id,sp.manga_id,sp.source_range_start,sp.source_range_end
         from public.series_entry_spans sp where sp.section_id=old.id
         except select p.medium,p.anime_id,p.manga_id,p.source_range_start,p.source_range_end
         from public.mapping_revision_spans p where p.revision_id=p_revision and p.sort_order=old.sort_order)
        union all
        (select p.medium,p.anime_id,p.manga_id,p.source_range_start,p.source_range_end
         from public.mapping_revision_spans p where p.revision_id=p_revision and p.sort_order=old.sort_order
         except select sp.medium,sp.anime_id,sp.manga_id,sp.source_range_start,sp.source_range_end
         from public.series_entry_spans sp where sp.section_id=old.id)
      )
  ) then raise exception 'SECTION_RECONCILIATION_REQUIRED'; end if;

  delete from public.series_entry_spans where series_id = v_series;
  update public.series_sections set state = 'superseded' where series_id = v_series;
  insert into public.series_sections (series_id, kind, ordinal, name, sort_order, provenance, state)
  select distinct v_series, s.section_kind, s.section_ordinal, s.section_name, s.sort_order, 'mapping_revision', 'approved'
  from public.mapping_revision_spans s where s.revision_id = p_revision order by s.sort_order
  on conflict (series_id, sort_order) do update set
    kind = excluded.kind, ordinal = excluded.ordinal, name = excluded.name,
    provenance = excluded.provenance, state = 'approved';

  insert into public.series_entry_spans
    (series_id, section_id, medium, anime_id, manga_id, source_range_start, source_range_end, display_label)
  select v_series, sec.id, s.medium, s.anime_id, s.manga_id, s.source_range_start, s.source_range_end, s.display_label
  from public.mapping_revision_spans s
  join public.series_sections sec
    on sec.series_id = v_series and sec.sort_order = s.sort_order
  where s.revision_id = p_revision;

  update public.mapping_revisions
    set state = 'superseded'
  where series_id = v_series and state = 'approved' and id <> p_revision;

  update public.mapping_revisions
    set state = 'approved'
  where id = p_revision;

  update public.series
    set mapping_revision = mapping_revision + 1,
        continuity = 'verified',
        grouping_state = 'approved',
        updated_at = now()
  where id = v_series;
end;
$$;

revoke all on function public.publish_mapping_revision(uuid) from public;
grant execute on function public.publish_mapping_revision(uuid) to service_role;

-- Names and rank checks go through these helpers. club_members select is
-- own-row after the membership lifecycle migration, so an invoker join cannot
-- see the other member. The helper still requires a current shared club at
-- the requested rank and does not return private-rank identities.
create or replace function public.shares_club_at_least(p_other uuid, p_level text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.club_members me
    join public.club_members them
      on them.club_id = me.club_id and them.user_id = p_other
    join public.clubs cl on cl.id = me.club_id and cl.is_archived = false
    where me.user_id = auth.uid()
      and p_other is not null
      and p_other <> auth.uid()
      and least(public.sharing_level_rank(coalesce(me.sharing_level, cl.sharing_level)), public.sharing_level_rank(cl.sharing_level),
               public.sharing_level_rank(coalesce(them.sharing_level, cl.sharing_level)))
          >= public.sharing_level_rank(p_level)
  );
$$;

create or replace function public.club_peer_display_name(p_other uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_name text;
begin
  if not public.shares_club_at_least(p_other, 'status') then
    return null;
  end if;
  select nullif(trim(coalesce(p.display_name, '')), '') into v_name
  from public.profiles p
  where p.id = p_other;
  return v_name;
end;
$$;

revoke all on function public.shares_club_at_least(uuid, text) from public;
revoke all on function public.club_peer_display_name(uuid) from public;
grant execute on function public.shares_club_at_least(uuid, text) to authenticated, service_role;
grant execute on function public.club_peer_display_name(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Home bundle. One indexed read of the caller's list, then primary-key
-- catalogue lookups. Club text is a rank-filtered slice, not a public feed.
-- ---------------------------------------------------------------------------

-- Approved continuity is presentation identity; all child tracking rows remain intact.
create or replace view public.anime_home_resume_v1 with (security_invoker = true) as
select distinct on (coalesce(sp.series_id::text, 'entry:' || l.anime_id::text)) l.*
from public.anime_user_lists l
left join lateral (select sp.series_id from public.series_entry_spans sp
  join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.anime_id=l.anime_id limit 1) sp on true
left join public.user_series_intent intent on intent.series_id = sp.series_id and intent.user_id = l.user_id
where l.user_id = auth.uid()::text and l.list_type in ('WATCHING', 'PLANNING')
order by coalesce(sp.series_id::text, 'entry:' || l.anime_id::text),
         case when intent.resume_medium = 'anime' and intent.resume_media_id = l.anime_id then 0 else 1 end,
         case when l.list_type = 'WATCHING' then 0 else 1 end, l.updated_at desc, l.anime_id desc;
revoke all on public.anime_home_resume_v1 from public, anon;
grant select on public.anime_home_resume_v1 to authenticated;

-- Approved continuity is presentation identity; all child tracking rows remain intact.
create or replace view public.manga_home_resume_v1 with (security_invoker = true) as
select distinct on (coalesce(sp.series_id::text, 'entry:' || l.manga_id::text)) l.*
from public.manga_user_lists l
left join lateral (select sp.series_id from public.series_entry_spans sp
  join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.manga_id=l.manga_id limit 1) sp on true
left join public.user_series_intent intent on intent.series_id = sp.series_id and intent.user_id = l.user_id
where l.user_id = auth.uid()::text and l.list_type in ('READING', 'PLANNING')
order by coalesce(sp.series_id::text, 'entry:' || l.manga_id::text),
         case when intent.resume_medium = 'manga' and intent.resume_media_id = l.manga_id then 0 else 1 end,
         case when l.list_type = 'READING' then 0 else 1 end, l.updated_at desc, l.manga_id desc;
revoke all on public.manga_home_resume_v1 from public, anon;
grant select on public.manga_home_resume_v1 to authenticated;

create or replace function public.home_bundle_v1(
  p_medium text,
  p_locale text default 'en',
  p_window_days integer default 7,
  p_active_limit integer default 12,
  p_event_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_limit integer;
  v_events integer;
  v_window integer;
  v_cursor_at timestamptz;
  v_cursor_id integer;
  v_active jsonb;
  v_upcoming jsonb;
  v_pending jsonb;
  v_club jsonb := '[]'::jsonb;
  v_club_state text := 'none';
  v_club_label text := 'Your clubs';
  v_publication bigint := 0;
  v_next text;
  v_event_page jsonb;
  v_pending_page jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  v_user := v_uid::text;
  v_limit := least(50, greatest(1, coalesce(p_active_limit, 12)));
  v_events := least(50, greatest(1, coalesce(p_event_limit, 20)));
  v_window := least(90, greatest(1, coalesce(p_window_days, 7)));

  if p_cursor is not null and p_cursor <> '' then
    begin
      v_cursor_at := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::integer;
    exception when others then
      raise exception 'INVALID_CURSOR';
    end;
  end if;

  if p_medium = 'anime' then
    with resume_page as materialized (
      select l.* from public.anime_home_resume_v1 l
      where l.user_id=v_user and (v_cursor_at is null or l.updated_at<v_cursor_at
        or (l.updated_at=v_cursor_at and l.anime_id<v_cursor_id))
      order by l.updated_at desc,l.anime_id desc limit v_limit+1
    ), page as (
      select l.anime_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id,
             coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled') as title,
             a.banner_image, a.cover_image_large, a.format, a.episodes, a.status as catalogue_status,
             sp.series_id, sec.ordinal as section_ordinal, sec.kind as section_kind, sec.name as section_name,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from resume_page l
      join public.anime a on a.id = l.anime_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
        join public.series_sections ss on ss.id=sp.section_id and ss.state='approved'
        where sp.anime_id=l.anime_id order by ss.sort_order,sp.id limit 1) sp on true
      left join public.series_sections sec on sec.id = sp.section_id
      left join public.artwork_materials mat on mat.image_url = coalesce(a.banner_image, a.cover_image_large) and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('WATCHING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.anime_id < v_cursor_id)
        )
      order by l.updated_at desc, l.anime_id desc
      limit v_limit + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'banner_image', banner_image,
      'cover_image', cover_image_large,
      'format', format,
      'episodes', episodes,
      'catalogue_status', catalogue_status,
      'series_id', series_id,
      'section_ordinal', section_ordinal,
      'section_kind', section_kind,
      'section_name', section_name,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb)
    , (select case when count(*)>v_limit then
         (select updated_at::text||'|'||media_id::text from page order by updated_at desc,media_id desc offset v_limit-1 limit 1)
         else null end from page)
    into v_active,v_next
    from (
      select * from page
      order by updated_at desc, media_id desc
      limit v_limit
    ) p;


  else
    with page as (
      select l.manga_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id, l.volumes_progress,
             coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled') as title,
             m.cover_image_large, m.format, m.chapters, m.volumes, m.status as catalogue_status,
             sp.series_id,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from public.manga_home_resume_v1 l
      join public.manga m on m.id = l.manga_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
        where sp.manga_id=l.manga_id order by sp.id limit 1) sp on true
      left join public.artwork_materials mat on mat.image_url = m.cover_image_large and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('READING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id)
        )
      order by l.updated_at desc, l.manga_id desc
      limit v_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'volumes_progress', volumes_progress,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'cover_image', cover_image_large,
      'format', format,
      'chapters', chapters,
      'volumes', volumes,
      'catalogue_status', catalogue_status,
      'series_id', series_id,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb)
    into v_active
    from page;

    v_next := null;
    if (
      select count(*) from (
        select 1 from public.manga_home_resume_v1 l
        where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
          and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
        limit v_limit + 1
      ) s
    ) > v_limit then
      select l.updated_at::text || '|' || l.manga_id::text into v_next
      from public.manga_home_resume_v1 l
      where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
        and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
      order by l.updated_at desc, l.manga_id desc
      offset v_limit - 1
      limit 1;
    end if;


  end if;

  v_pending_page := public.home_pending_page_v1(p_medium,v_events,null);
  v_pending := v_pending_page->'items';

  begin
    with eligible as (
      select c.id, c.media_id, c.media_type, c.spoiler_scope, c.created_at,
             case when c.spoiler_scope = 'none' then c.text else null end as body,
             public.club_peer_display_name(c.user_id) as display_name
      from public.title_comments c
      where c.user_id <> v_uid
        and public.shares_club_at_least(c.user_id, 'status')
        and (
          (p_medium = 'anime' and c.media_type = 'ANIME')
          or (p_medium = 'manga' and c.media_type = 'MANGA')
        )
        and exists (
          select 1 from public.anime_user_lists al
          where p_medium = 'anime' and al.user_id = v_user and al.anime_id = c.media_id
          union all
          select 1 from public.manga_user_lists ml
          where p_medium = 'manga' and ml.user_id = v_user and ml.manga_id = c.media_id
        )
      order by c.created_at desc
      limit 6
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'comment_id', id,
      'media_id', media_id,
      'media_type', media_type,
      'spoiler_scope', spoiler_scope,
      'text', body,
      'display_name', display_name,
      'created_at', created_at
    ) order by created_at desc), '[]'::jsonb)
    into v_club
    from eligible;

    if jsonb_array_length(coalesce(v_club, '[]'::jsonb)) = 0 then
      v_club_state := 'none';
      v_club := '[]'::jsonb;
    else
      v_club_state := 'ok';
      v_club_label := 'Your clubs';
    end if;
  exception when others then
    v_club := '[]'::jsonb;
    v_club_state := 'error';
    v_club_label := 'Your clubs';
  end;

  select revision into v_publication
  from public.home_publications
  where user_id = v_user and medium = p_medium;
  v_publication := coalesce(v_publication, 0);

  v_event_page := public.home_events_page_v1(p_medium,v_window,v_events,null);
  v_upcoming := v_event_page->'items';
  return jsonb_build_object(
    'medium', p_medium,
    'locale', coalesce(p_locale, 'en'),
    'window_days', v_window,
    'as_of', now(),
    'home_revision', v_publication,
    'active', coalesce(v_active, '[]'::jsonb),
    'upcoming', coalesce(v_upcoming, '[]'::jsonb),
    'upcoming_total', v_event_page->'total', 'events_cursor', v_event_page->>'next_cursor',
    'pending', v_pending,
    'pending_total',v_pending_page->'total','pending_cursor',v_pending_page->>'next_cursor',
    'schedule_state', case
      when p_medium = 'manga' and jsonb_array_length(coalesce(v_upcoming, '[]'::jsonb)) = 0
        then 'no_verified_schedule'
      else 'ok'
    end,
    'next_cursor', v_next,
    'club', jsonb_build_object('state', v_club_state, 'label', v_club_label, 'items', coalesce(v_club, '[]'::jsonb))
  );
end;
$$;

revoke all on function public.home_bundle_v1(text, text, integer, integer, integer, text) from public;
grant execute on function public.home_bundle_v1(text, text, integer, integer, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Detail bundle. Selected section only. Missing copy stays null.
-- ---------------------------------------------------------------------------

create or replace function public.series_detail_bundle_v1(
  p_medium text,
  p_media_id integer,
  p_section_id uuid default null,
  p_locale text default 'en'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_header jsonb;
  v_sections jsonb;
  v_units jsonb;
  v_copy jsonb;
  v_user jsonb;
  v_themes jsonb;
  v_coverage jsonb;
  v_cast jsonb;
  v_series uuid;
  v_material jsonb;
  v_principals jsonb;
  v_guides jsonb;
  v_units_next jsonb;
  v_default_section uuid;
  v_edition text;
  v_editions jsonb;
  v_editions_next text;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') or p_media_id is null then
    raise exception 'INVALID_TARGET';
  end if;

  select sp.series_id,sec.id into v_series,v_default_section from public.series_entry_spans sp
  join public.series sr on sr.id = sp.series_id and sr.grouping_state = 'approved'
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where (p_medium = 'anime' and sp.anime_id = p_media_id) or (p_medium = 'manga' and sp.manga_id = p_media_id);
  if p_medium='anime' and p_section_id is null then p_section_id:=v_default_section;end if;
  if p_section_id is not null then
    if p_medium <> 'anime' or v_series is null or not exists (
      select 1 from public.series_sections sec where sec.id = p_section_id and sec.series_id = v_series and sec.state = 'approved'
    ) then raise exception 'INVALID_SECTION'; end if;
    if not exists(select 1 from public.series_entry_spans sp where sp.section_id=p_section_id and sp.anime_id=p_media_id) then
      select sp.anime_id into p_media_id from public.series_entry_spans sp
      where sp.section_id=p_section_id and sp.series_id=v_series and sp.medium='anime'
      order by sp.source_range_start nulls first,sp.anime_id limit 1;
    end if;
    if p_media_id is null then raise exception 'INVALID_SECTION'; end if;
  end if;

  -- An edition is an authoritative catalogue-unit source key, never a synthetic
  -- manga "part". Prefer the tracked exact unit's edition; otherwise use the first
  -- available key. Every initial/subsequent unit page stays within that edition.
  select u.edition_key into v_edition from public.catalogue_units u
  where u.id=case when p_medium='anime' then
    (select unit_id from public.anime_user_lists where user_id=v_uid::text and anime_id=p_media_id)
    else (select unit_id from public.manga_user_lists where user_id=v_uid::text and manga_id=p_media_id) end
    and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
    and (p_section_id is null or u.section_id=p_section_id or u.section_id is null);
  if v_edition is null then
    select u.edition_key into v_edition from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
    order by u.edition_key,u.order_key,u.id limit 1;
  end if;
  select coalesce(jsonb_agg(edition_key order by edition_key),'[]'::jsonb) into v_editions
  from (select distinct u.edition_key from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
    order by u.edition_key limit 51) keys;
  if jsonb_array_length(v_editions)>50 then
    v_editions_next:=v_editions->>49; v_editions:=v_editions-50;
  end if;

  if p_medium = 'anime' then
    -- v_series was resolved through approved continuity above.
    select jsonb_build_object(
      'media_id', a.id,
      'title', coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled'),
      'banner_image', a.banner_image,
      'cover_image', a.cover_image_large,
      'format', a.format,
      'catalogue_status', a.status,
      'episodes', a.episodes,
      'description', coalesce(nullif(a.synopsis_enhanced,''),a.description_normalized,a.description),
      'copy_source',case when nullif(a.synopsis_enhanced,'') is not null then 'catalogue_enrichment' else 'catalogue_source' end,
      'artwork_scope', case when a.banner_image is null then 'cover_fallback' else 'banner' end
    ) into v_header
    from public.anime a where a.id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', u.id, 'label', u.label, 'order_key', u.order_key::text, 'available', u.available, 'edition_key', u.edition_key, 'title', u.title, 'synopsis', u.synopsis, 'image_url', u.image_url
    ) order by u.order_key,u.id), '[]'::jsonb)
    into v_units
    from (
      select id, label, order_key, available, edition_key, title, synopsis, image_url
      from public.catalogue_units
      where anime_id = p_media_id
        and (p_section_id is null or section_id = p_section_id or section_id is null)
        and edition_key=v_edition
      order by order_key,id
      limit 20
    ) u;

    select coalesce(jsonb_agg(jsonb_build_object(
      'role', t.role, 'song_title', t.song_title, 'artist', t.artist,
      'external_url', t.external_url, 'match_state', t.match_state
    ) order by t.sequence_order), '[]'::jsonb)
    into v_themes
    from (
      select role, song_title, artist, external_url, match_state, sequence_order
      from public.theme_links
      where anime_id = p_media_id
        and (p_section_id is null or section_id = p_section_id or section_id is null)
      order by sequence_order
      limit 20
    ) t;

    select jsonb_build_object(
      'server_revision', l.server_revision,
      'lifecycle_id', l.lifecycle_id,
      'progress', l.progress,
      'progress_label', l.progress_label,
      'list_type', l.list_type,
      'rating', l.rating,
      'notes', l.notes,
      'unit_id', l.unit_id
    ) into v_user
    from public.anime_user_lists l
    where l.user_id = v_uid::text and l.anime_id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name_full, 'role', ac.role, 'image_url', c.image_large, 'description', c.description
    )), '[]'::jsonb)
    into v_cast
    from (
      select character_id, role
      from public.anime_characters
      where anime_id = p_media_id
      order by case when role = 'MAIN' then 0 else 1 end, id
      limit 12
    ) ac
    join public.characters c on c.id = ac.character_id;
  else
    -- v_series was resolved through approved continuity above.
    select jsonb_build_object(
      'media_id', m.id,
      'title', coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled'),
      'cover_image', m.cover_image_large,
      'format', m.format,
      'catalogue_status', m.status,
      'chapters', m.chapters,
      'volumes', m.volumes,
      'description', coalesce(nullif(m.synopsis_enhanced,''),m.description_normalized,m.description),
      'copy_source',case when nullif(m.synopsis_enhanced,'') is not null then 'catalogue_enrichment' else 'catalogue_source' end,
      'artwork_scope', 'cover'
    ) into v_header
    from public.manga m where m.id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', u.id, 'label', u.label, 'order_key', u.order_key::text, 'available', u.available, 'edition_key', u.edition_key, 'title', u.title, 'synopsis', u.synopsis, 'image_url', u.image_url
    ) order by u.order_key,u.id), '[]'::jsonb)
    into v_units
    from (
      select id, label, order_key, available, edition_key, title, synopsis, image_url
      from public.catalogue_units
      where manga_id = p_media_id
        and edition_key=v_edition
      order by order_key,id
      limit 20
    ) u;

    v_themes := '[]'::jsonb;

    select jsonb_build_object(
      'server_revision', l.server_revision,
      'lifecycle_id', l.lifecycle_id,
      'progress', l.progress,
      'progress_label', l.progress_label,
      'volumes_progress', l.volumes_progress,
      'list_type', l.list_type,
      'rating', l.rating,
      'notes', l.notes,
      'unit_id', l.unit_id
    ) into v_user
    from public.manga_user_lists l
    where l.user_id = v_uid::text and l.manga_id = p_media_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name_full, 'role', mc.role, 'image_url', c.image_large, 'description', c.description
    )), '[]'::jsonb)
    into v_cast
    from (
      select character_id, role
      from public.manga_characters
      where manga_id = p_media_id
      order by case when role = 'MAIN' then 0 else 1 end, id
      limit 12
    ) mc
    join public.characters c on c.id = mc.character_id;
  end if;

  if v_header is null then
    raise exception 'INVALID_TARGET';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'kind', s.kind, 'ordinal', s.ordinal, 'name', s.name, 'sort_order', s.sort_order,
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('media_id',a.id,'title',coalesce(a.title_english,a.title_romaji,a.title_native),
      'banner_image',a.banner_image,'cover_image',a.cover_image_large,'episodes',a.episodes) order by sp.source_range_start nulls first,a.id),'[]'::jsonb)
      from public.series_entry_spans sp join public.anime a on a.id=sp.anime_id where sp.section_id=s.id)
  ) order by s.sort_order), '[]'::jsonb)
  into v_sections
  from public.series_sections s
  where s.series_id = v_series and s.state = 'approved';

  select jsonb_build_object(
    'premise', d.premise, 'hook', d.hook, 'synopsis', d.synopsis,
    'provenance', d.provenance, 'review_state', d.review_state,
    'story_state', case when d.premise is null and d.hook is null then 'missing' else 'present' end
  ) into v_copy
  from public.detail_copy d
  where d.locale = coalesce(p_locale, 'en')
    and ((p_medium = 'anime' and d.anime_id = p_media_id) or (p_medium = 'manga' and d.manga_id = p_media_id))
    and (p_section_id is null or d.section_id = p_section_id or d.section_id is null)
  order by case when d.section_id = p_section_id then 0 else 1 end,
    case when d.review_state='approved' then 0 when d.provenance<>'catalogue_bridge_v1' then 1 else 2 end,
    d.provenance, d.id
  limit 1;

  if v_copy is null then
    v_copy := jsonb_build_object('story_state', case when v_header->>'description' is null then 'missing' else 'source' end, 'premise', null, 'hook', null, 'synopsis', v_header->>'description', 'provenance', v_header->>'copy_source');
  end if;

  select jsonb_build_object(
    'source_kind', c.source_kind,
    'mapping_state', c.mapping_state,
    'starts_at', c.starts_at,
    'ends_at', c.ends_at,
    'read_next', c.read_next,
    'source_manga_id', c.source_manga_id,
    'evidence', c.evidence
  ) into v_coverage
  from public.adaptation_coverage c
  where ((p_medium = 'anime' and c.anime_id = p_media_id)
     or (p_medium = 'manga' and c.source_manga_id = p_media_id))
    and (p_medium = 'manga' or p_section_id is null or c.section_id = p_section_id or c.section_id is null)
  order by c.revision desc
  limit 1;

  select jsonb_build_object('image_digest', image_digest, 'base', base_color, 'deep', deep_color,
      'wash', wash_color, 'edge', edge_color, 'ink', ink_color)
  into v_material from public.artwork_materials
  where image_url=coalesce(v_header->>'banner_image',v_header->>'cover_image') and is_current;

  if p_medium='anime' then
    select coalesce(jsonb_agg(row_data order by priority, entity_id),'[]'::jsonb) into v_principals from (
      select jsonb_build_object('id',st.id,'kind','studio','name',st.name,'role','Animation studio') row_data, 0 priority, st.id entity_id
      from public.anime_studios j join public.studios st on st.id=j.studio_id where j.anime_id=p_media_id
      union all
      select jsonb_build_object('id',st.id,'kind','staff','name',st.name_full,'role',j.role,'image_url',st.image_large,'description',st.description),
        case when j.role ilike '%director%' then 1 else 2 end, st.id
      from public.anime_staff j join public.staff st on st.id=j.staff_id where j.anime_id=p_media_id
        and (j.role ilike '%director%' or j.role ilike '%original creator%' or j.role ilike '%series composition%')
      order by priority,entity_id limit 8
    ) credits;
  else
    select coalesce(jsonb_agg(row_data order by entity_id),'[]'::jsonb) into v_principals from (
      select jsonb_build_object('id',au.id,'kind','author','name',au.name_full,'role',j.role,'image_url',au.image_large,'description',au.description) row_data, au.id entity_id
      from public.manga_authors j join public.authors au on au.id=j.author_id where j.manga_id=p_media_id order by au.id limit 8
    ) credits;
  end if;

  select coalesce(jsonb_agg(row_data order by sort_order,anime_id),'[]'::jsonb) into v_guides from (
    select jsonb_build_object('anime_id',c.anime_id,'section_id',c.section_id,'season',sec.name,
      'source_kind',c.source_kind,'mapping_state',c.mapping_state,'starts_at',c.starts_at,'ends_at',c.ends_at,
      'read_next',c.read_next,'source_manga_id',c.source_manga_id,'evidence',c.evidence) row_data,
      c.anime_id,coalesce(sec.sort_order,0) sort_order
    from (select distinct on (anime_id,section_id) * from public.adaptation_coverage
      where source_manga_id=p_media_id order by anime_id,section_id,revision desc,id desc) c
    left join public.series_sections sec on sec.id=c.section_id
    where p_medium='manga' and c.source_manga_id=p_media_id and c.mapping_state in ('exact','partial')
      and (sec.id is null or sec.state='approved')
    order by sort_order,c.anime_id limit 50
  ) guides;

  -- Return the exact last visible unit only when a further page exists.
  if jsonb_array_length(v_units)>0 and exists(
    select 1 from public.catalogue_units u
    where ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
      and (p_medium='manga' or p_section_id is null or u.section_id=p_section_id or u.section_id is null)
      and u.edition_key=v_edition
      and (u.order_key,u.id)>((v_units->-1->>'order_key')::numeric,(v_units->-1->>'id')::uuid)
  ) then
    v_units_next:=jsonb_build_object('order',v_units->-1->'order_key','id',v_units->-1->'id');
  end if;

  return jsonb_build_object(
    'medium', p_medium,
    'media_id', p_media_id,
    'series_id', v_series,
    'section_id', p_section_id,
    'header', v_header,
    'sections', coalesce(v_sections, '[]'::jsonb),
    'units', coalesce(v_units, '[]'::jsonb),
    'units_next',v_units_next,
    'edition',v_edition,'editions',v_editions,'editions_next',v_editions_next,
    'units_state', case when jsonb_array_length(coalesce(v_units, '[]'::jsonb)) = 0 then 'not_in_catalogue' else 'ok' end,
    'copy', v_copy,
    'themes', coalesce(v_themes, '[]'::jsonb),
    'coverage', v_coverage,
    'cast', coalesce(v_cast, '[]'::jsonb),
    'principals', v_principals, 'material', v_material, 'adaptations', v_guides,
    'user', v_user
  );
end;
$$;

revoke all on function public.series_detail_bundle_v1(text, integer, uuid, text) from public;
grant execute on function public.series_detail_bundle_v1(text, integer, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Collection page grouped by approved series before the keyset limit.
-- An entry with no series is its own group. Child progress is inside the group.
-- ---------------------------------------------------------------------------

create or replace function public.collection_series_page_v1(
  p_medium text,
  p_status text default null,
  p_query text default null,
  p_limit integer default 30,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_limit integer;
  v_query text;
  v_cursor_at timestamptz;
  v_cursor_key text;
  v_rows jsonb;
  v_next text;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  v_user := v_uid::text;
  v_limit := least(50, greatest(1, coalesce(p_limit, 30)));
  v_query := left(replace(replace(coalesce(p_query, ''), '%', ''), '_', ''), 80);

  if p_cursor is not null and p_cursor <> '' then
    begin
      v_cursor_at := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_key := split_part(p_cursor, '|', 2);
    exception when others then
      raise exception 'INVALID_CURSOR';
    end;
  end if;

  if p_medium = 'anime' then
    with rows as (
      select
        coalesce(sp.series_id::text, 'entry:anime:' || l.anime_id::text) as group_key,
        l.updated_at,
        l.anime_id as media_id,
        l.list_type,
        l.progress,
        l.server_revision,
        l.lifecycle_id,
        coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled') as title,
        a.title_synonyms
      from public.anime_user_lists l
      join public.anime a on a.id = l.anime_id
      left join lateral (select sp.* from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved' where sp.anime_id=l.anime_id order by sp.id limit 1) sp on true
      where l.user_id = v_user
        and (p_status is null or l.list_type = p_status)
        and (
          v_query = ''
          or a.title_english ilike '%' || v_query || '%'
          or a.title_romaji ilike '%' || v_query || '%'
          or a.title_native ilike '%' || v_query || '%'
          or exists (select 1 from unnest(coalesce(a.title_synonyms, array[]::text[])) syn where syn ilike '%' || v_query || '%')
        )
    ), grouped as (
      select group_key, max(updated_at) as updated_at, count(*) as child_count
      from rows
      group by group_key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'group_key', group_key, 'updated_at', updated_at, 'child_count', child_count,
      'children_next',case when child_count>50 then (select min(r.media_id) from (select media_id from rows where rows.group_key=page.group_key order by media_id desc limit 50)r) end,
      'children', (select coalesce(jsonb_agg(jsonb_build_object('media_id',r.media_id,'list_type',r.list_type,'progress',r.progress,
        'server_revision',r.server_revision,'lifecycle_id',r.lifecycle_id,'title',r.title) order by r.media_id desc),'[]'::jsonb)
        from (select * from rows where rows.group_key=page.group_key order by media_id desc limit 50) r)
    ) order by updated_at desc, group_key desc), '[]'::jsonb)
    into v_rows
    from (
      select * from grouped g
      where v_cursor_at is null
         or g.updated_at < v_cursor_at
         or (g.updated_at = v_cursor_at and g.group_key < v_cursor_key)
      order by g.updated_at desc, g.group_key desc
      limit v_limit
    ) page;
  else
    with rows as (
      select
        coalesce(sp.series_id::text, 'entry:manga:' || l.manga_id::text) as group_key,
        l.updated_at,
        l.manga_id as media_id,
        l.list_type,
        l.progress,
        l.server_revision,
        l.lifecycle_id,
        coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled') as title
      from public.manga_user_lists l
      join public.manga m on m.id = l.manga_id
      left join lateral (select sp.* from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved' where sp.manga_id=l.manga_id order by sp.id limit 1) sp on true
      where l.user_id = v_user
        and (p_status is null or l.list_type = p_status)
        and (
          v_query = ''
          or m.title_english ilike '%' || v_query || '%'
          or m.title_romaji ilike '%' || v_query || '%'
          or m.title_native ilike '%' || v_query || '%'
        )
    ), grouped as (
      select group_key, max(updated_at) as updated_at, count(*) as child_count
      from rows
      group by group_key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'group_key', group_key, 'updated_at', updated_at, 'child_count', child_count,
      'children_next',case when child_count>50 then (select min(r.media_id) from (select media_id from rows where rows.group_key=page.group_key order by media_id desc limit 50)r) end,
      'children', (select coalesce(jsonb_agg(jsonb_build_object('media_id',r.media_id,'list_type',r.list_type,'progress',r.progress,
        'server_revision',r.server_revision,'lifecycle_id',r.lifecycle_id,'title',r.title) order by r.media_id desc),'[]'::jsonb)
        from (select * from rows where rows.group_key=page.group_key order by media_id desc limit 50) r)
    ) order by updated_at desc, group_key desc), '[]'::jsonb)
    into v_rows
    from (
      select * from grouped g
      where v_cursor_at is null
         or g.updated_at < v_cursor_at
         or (g.updated_at = v_cursor_at and g.group_key < v_cursor_key)
      order by g.updated_at desc, g.group_key desc
      limit v_limit
    ) page;
  end if;

  if jsonb_array_length(coalesce(v_rows, '[]'::jsonb)) = v_limit then
    v_next := (v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'updated_at')
      || '|' || (v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'group_key');
  end if;

  return jsonb_build_object(
    'medium', p_medium,
    'groups', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', v_next
  );
end;
$$;

revoke all on function public.collection_series_page_v1(text, text, text, integer, text) from public;
grant execute on function public.collection_series_page_v1(text, text, text, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Import jobs. Merge only. Account API for MAL is not claimed here.
-- ---------------------------------------------------------------------------

create or replace function public.start_library_import_v1(
  p_provider text,
  p_source_kind text,
  p_medium_filter text,
  p_idempotency_key text,
  p_payload_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_provider not in ('anilist', 'myanimelist')
     or p_source_kind not in ('account', 'export')
     or p_medium_filter not in ('anime', 'manga', 'both')
     or p_idempotency_key is null or length(p_idempotency_key) < 8
     or p_payload_hash is null or length(p_payload_hash) < 8 then
    raise exception 'INVALID_PAYLOAD';
  end if;
  -- OAuth/PKCE is qualified by the connector. Account and file sources enter the
  -- same owner-scoped structured job; neither endpoint stores provider tokens.

  select * into v_job
  from public.library_import_jobs
  where user_id = v_uid and idempotency_key = p_idempotency_key;

  if v_job.id is not null then
    if v_job.payload_hash <> p_payload_hash or v_job.provider <> p_provider or v_job.source_kind <> p_source_kind or v_job.medium_filter <> p_medium_filter then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', true, 'home_revision', v_job.home_revision);
  end if;

  if exists (
    select 1 from public.library_import_jobs
    where user_id = v_uid and provider = p_provider 
      and state in ('queued', 'running')
  ) then
    raise exception 'IMPORT_ALREADY_ACTIVE';
  end if;

  insert into public.library_import_jobs
    (user_id, provider, source_kind, medium_filter, idempotency_key, payload_hash, state)
  values
    (v_uid, p_provider, p_source_kind, p_medium_filter, p_idempotency_key, p_payload_hash, 'running')
  returning * into v_job;

  insert into public.library_import_baselines(job_id, medium, media_id, lifecycle_id, server_revision)
  select v_job.id, 'anime', anime_id, lifecycle_id, server_revision from public.anime_user_lists
    where user_id = v_uid::text and p_medium_filter in ('anime', 'both')
  union all
  select v_job.id, 'manga', manga_id, lifecycle_id, server_revision from public.manga_user_lists
    where user_id = v_uid::text and p_medium_filter in ('manga', 'both');

  return jsonb_build_object('job_id', v_job.id, 'state', v_job.state, 'resumed', false, 'home_revision', 0);
end;
$$;

create or replace function public.apply_import_chunk_v1(p_job_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_item jsonb;
  v_medium text;
  v_external text;
  v_media_id integer;
  v_status text;
  v_progress integer;
  v_notes text;
  v_added integer := 0;
  v_updated_count integer := 0;
  v_conflict integer := 0;
  v_unmatched integer := 0;
  v_unchanged integer := 0;
  v_list_type text;
  v_updated timestamptz;
  v_local_progress integer;
  v_local_notes text;
  v_baseline public.library_import_baselines%rowtype;
  v_current_revision bigint;
  v_current_lifecycle uuid;
  v_request_hash text;
  v_prior_hash text;
  v_prior_disposition text;
  v_disposition text;
  v_written integer;
  v_ref_found boolean;
  v_unavailable jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'INVALID_PAYLOAD';
  end if;

  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.state not in ('queued', 'running', 'ready', 'ready_with_issues') then raise exception 'JOB_NOT_RUNNING'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_medium := lower(v_item->>'medium');
    v_external := v_item->>'external_id';
    if v_medium not in ('anime', 'manga') or v_external is null or v_external !~ '^[0-9]{1,10}$'
       or (v_job.medium_filter <> 'both' and v_medium <> v_job.medium_filter) then raise exception 'INVALID_ITEM'; end if;
    if length(coalesce(v_item->>'source_list_options',''))>16384 then raise exception 'OPTIONS_TOO_LARGE'; end if;
    v_unavailable:='[]'::jsonb;
    if nullif(v_item->>'source_list_options','') is not null then
      begin
        v_unavailable:=coalesce((v_item->>'source_list_options')::jsonb->'unavailable_fields','[]'::jsonb);
        if jsonb_typeof(v_unavailable)<>'array' then raise exception 'INVALID_SOURCE_OPTIONS'; end if;
      exception when others then raise exception 'INVALID_SOURCE_OPTIONS'; end;
    end if;
    if v_item->>'normalized_rating' is not null and (v_item->>'normalized_rating')::integer not between 1 and 10 then raise exception 'INVALID_RATING'; end if;
    v_request_hash := encode(digest(v_item::text, 'sha256'), 'hex');
    select request_hash, disposition into v_prior_hash, v_prior_disposition from public.library_import_items
      where job_id = v_job.id and provider = v_job.provider and external_id = v_external and medium = v_medium;
    if found then
      if v_prior_hash is distinct from v_request_hash then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
      continue; -- A terminal item's write and count are committed together; replay changes neither.
    end if;
    if v_job.state in ('ready', 'ready_with_issues') then raise exception 'JOB_ALREADY_FINISHED'; end if;
    v_media_id := null;
    select case when unresolved then null when v_medium='anime' then anime_id else manga_id end
      into v_media_id from public.provider_entry_refs
      where provider=v_job.provider and medium=v_medium and external_id=v_external;
    v_ref_found := found;
    if not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'anilist' then
      select min(a.id) into v_media_id from public.anime a
      where a.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'anilist' then
      select min(m.id) into v_media_id from public.manga m
      where m.anilist_id = v_external::integer
      having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'anime' and v_job.provider = 'myanimelist' then
      select min(a.id) into v_media_id from public.anime a where a.mal_id = v_external::integer having count(*)=1;
    elsif not v_ref_found and v_external ~ '^[0-9]+$' and v_medium = 'manga' and v_job.provider = 'myanimelist' then
      select min(m.id) into v_media_id from public.manga m where m.mal_id = v_external::integer having count(*)=1;
    end if;

    if v_media_id is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash, detail)
      values (v_job.id, v_job.provider, coalesce(v_external, ''), coalesce(v_medium, ''), 'unmatched', v_request_hash, 'catalogue id not found')
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'unmatched';
      continue;
    end if;

    v_status := lower(coalesce(v_item->>'status', ''));
    v_list_type := case v_status
      when 'watching' then 'WATCHING'
      when 'current' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      when 'reading' then 'READING'
      when 'completed' then 'COMPLETED'
      when 'planning' then 'PLANNING'
      when 'plan to watch' then 'PLANNING'
      when 'plan to read' then 'PLANNING'
      when 'dropped' then 'DROPPED'
      when 'paused' then 'PAUSED'
      when 'on-hold' then 'PAUSED'
      when 'on hold' then 'PAUSED'
      when 'repeating' then case when v_medium = 'manga' then 'READING' else 'WATCHING' end
      else null
    end;
    v_progress := coalesce((v_item->>'progress')::integer, 0);
    v_notes := v_item->>'notes';
    if coalesce(v_item->>'score_raw', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (v_item->>'score_raw')::numeric = 0 then
      v_item := v_item || jsonb_build_object('score_raw', null);
    end if;

    if v_medium = 'anime' then
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.anime_user_lists where user_id = v_uid::text and anime_id = v_media_id
      for update;
    else
      select updated_at, progress, notes, server_revision, lifecycle_id into v_updated, v_local_progress, v_local_notes, v_current_revision, v_current_lifecycle
      from public.manga_user_lists where user_id = v_uid::text and manga_id = v_media_id
      for update;
    end if;

    select * into v_baseline from public.library_import_baselines
      where job_id = v_job.id and medium = v_medium and media_id = v_media_id;
    if (v_baseline.media_id is not null and (v_current_revision is distinct from v_baseline.server_revision
          or v_current_lifecycle is distinct from v_baseline.lifecycle_id))
       or (v_baseline.media_id is null and v_current_lifecycle is not null)
       or exists (select 1 from public.list_entry_tombstones where user_id = v_uid::text and medium = v_medium
          and media_id = v_media_id and removed_at >= v_job.created_at) then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
      values (v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash)
      on conflict (job_id, provider, external_id, medium) do update set disposition = 'conflict';
      continue;
    end if;

    if v_list_type is null then
      v_unmatched := v_unmatched + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash, detail)
      values(v_job.id, v_job.provider, v_external, v_medium, 'unmatched', v_request_hash, 'unsupported status');
      continue;
    end if;

    if v_medium = 'anime' then
      insert into public.anime_user_lists
        (user_id, anime_id, list_type, progress, notes, score_raw, score_scale, repeat_count, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0), v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, anime_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.anime_user_lists.progress end,
        notes = coalesce(excluded.notes, public.anime_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.anime_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.anime_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.anime_user_lists.repeat_count end,
        started_raw = coalesce(excluded.started_raw, public.anime_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.anime_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.anime_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.anime_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.anime_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.anime_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.anime_user_lists.rating)
      where public.anime_user_lists.server_revision = v_baseline.server_revision
        and public.anime_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    else
      insert into public.manga_user_lists
        (user_id, manga_id, list_type, progress, notes, score_raw, score_scale, repeat_count, volumes_progress, started_raw, finished_raw, entry_private, source_custom_lists, source_hidden, source_list_options, rating)
      values (
        v_uid::text, v_media_id, v_list_type, v_progress, v_notes,
        nullif(v_item->>'score_raw', '')::numeric, v_item->>'score_scale',
        coalesce((v_item->>'repeat_count')::integer, 0),
        nullif(v_item->>'volumes_progress', '')::integer,
        v_item->>'started_raw', v_item->>'finished_raw', coalesce((v_item->>'private')::boolean, false),
        coalesce(v_item->'custom_lists', '[]'::jsonb), coalesce((v_item->>'hidden_from_status_lists')::boolean, false), v_item->>'source_list_options',coalesce((v_item->>'normalized_rating')::integer,case when v_item->>'score_scale'='POINT_10' and nullif(v_item->>'score_raw','')::numeric between 1 and 10 then round((v_item->>'score_raw')::numeric)::integer end)
      )
      on conflict (user_id, manga_id) do update set
        list_type = excluded.list_type,
        progress = case when v_item ? 'progress' and not(v_unavailable ? 'progress') then excluded.progress else public.manga_user_lists.progress end,
        notes = coalesce(excluded.notes, public.manga_user_lists.notes),
        score_raw = coalesce(excluded.score_raw, public.manga_user_lists.score_raw),
        score_scale = coalesce(excluded.score_scale, public.manga_user_lists.score_scale),
        repeat_count = case when v_item ? 'repeat_count' and not(v_unavailable ? 'repeat_count') then excluded.repeat_count else public.manga_user_lists.repeat_count end,
        volumes_progress = coalesce(excluded.volumes_progress, public.manga_user_lists.volumes_progress),
        started_raw = coalesce(excluded.started_raw, public.manga_user_lists.started_raw),
        finished_raw = coalesce(excluded.finished_raw, public.manga_user_lists.finished_raw),
        entry_private = case when v_item ? 'private' and not(v_unavailable ? 'private') then excluded.entry_private else public.manga_user_lists.entry_private end,
        source_custom_lists = case when v_item ? 'custom_lists' and not(v_unavailable ? 'custom_lists') then excluded.source_custom_lists else public.manga_user_lists.source_custom_lists end,
        source_hidden = case when v_item ? 'hidden_from_status_lists' and not(v_unavailable ? 'hidden_from_status_lists') then excluded.source_hidden else public.manga_user_lists.source_hidden end,
        source_list_options = coalesce(excluded.source_list_options, public.manga_user_lists.source_list_options),
        rating = coalesce(excluded.rating,public.manga_user_lists.rating)
      where public.manga_user_lists.server_revision = v_baseline.server_revision
        and public.manga_user_lists.lifecycle_id = v_baseline.lifecycle_id;
    end if;

    get diagnostics v_written = row_count;
    if v_written = 0 then
      v_conflict := v_conflict + 1;
      insert into public.library_import_items(job_id, provider, external_id, medium, disposition, request_hash)
      values(v_job.id, v_job.provider, v_external, v_medium, 'conflict', v_request_hash);
      continue;
    end if;
    if v_updated is null then
      v_disposition := 'added';
      v_added := v_added + 1;
    else
      v_disposition := 'updated';
      v_updated_count := v_updated_count + 1;
    end if;

    insert into public.library_import_items (job_id, provider, external_id, medium, disposition, request_hash)
    values (v_job.id, v_job.provider, v_external, v_medium, v_disposition, v_request_hash)
    on conflict (job_id, provider, external_id, medium) do update set disposition = 'applied';

    insert into public.provider_entry_refs (provider, external_id, medium, anime_id, manga_id, unresolved)
    values (
      v_job.provider, v_external, v_medium,
      case when v_medium = 'anime' then v_media_id else null end,
      case when v_medium = 'manga' then v_media_id else null end,
      false
    )
    on conflict (provider, external_id, medium) do nothing;
  end loop;

  update public.library_import_jobs
    set counters = coalesce(counters, '{}'::jsonb) || jsonb_build_object(
          'added', coalesce((counters->>'added')::integer, 0) + v_added,
          'updated', coalesce((counters->>'updated')::integer, 0) + v_updated_count,
          'conflict', coalesce((counters->>'conflict')::integer, 0) + v_conflict,
          'unmatched', coalesce((counters->>'unmatched')::integer, 0) + v_unmatched,
          'unchanged', coalesce((counters->>'unchanged')::integer, 0) + v_unchanged
        ),
        updated_at = now()
  where id = v_job.id;

  if v_added + v_updated_count > 0 then
    insert into public.home_publications(user_id, medium, revision)
    select v_uid::text, medium, 1 from (select distinct lower(value->>'medium') medium from jsonb_array_elements(p_items)) media
    on conflict(user_id, medium) do update set revision = public.home_publications.revision + 1;
    update public.library_import_jobs j set home_revision = p.revision from public.home_publications p
      where j.id = v_job.id and p.user_id = v_uid::text and p.medium = case when v_job.medium_filter = 'both' then 'anime' else v_job.medium_filter end;
  end if;

  return jsonb_build_object(
    'applied', v_added + v_updated_count,
    'added', v_added,
    'updated', v_updated_count,
    'conflict', v_conflict,
    'unmatched', v_unmatched,
    'unchanged', v_unchanged
  );
end;
$$;

create or replace function public.finish_library_import_v1(p_job_id uuid, p_exhausted boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
  v_state text;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||auth.uid()::text,0));
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid for update;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_job.state not in ('queued','running','ready','ready_with_issues') then
    raise exception 'JOB_NOT_RUNNING';
  end if;
  if v_job.state in ('ready','ready_with_issues') then
    return public.import_job_status_v1(p_job_id);
  end if;
  if not coalesce(p_exhausted, false) then
    v_state := 'running';
  elsif coalesce((v_job.counters->>'unmatched')::integer, 0) > 0
     or coalesce((v_job.counters->>'conflict')::integer, 0) > 0 then
    v_state := 'ready_with_issues';
  else
    v_state := 'ready';
  end if;
  update public.library_import_jobs set state = v_state, updated_at = now() where id = v_job.id;
  return jsonb_build_object('state', v_state, 'home_revision', v_job.home_revision, 'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)), 'counters', v_job.counters);
end;
$$;

create or replace function public.import_job_status_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_job public.library_import_jobs%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  select * into v_job from public.library_import_jobs where id = p_job_id and user_id = v_uid;
  if v_job.id is null then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return jsonb_build_object(
    'job_id', v_job.id,
    'state', v_job.state,
    'provider', v_job.provider,
    'source_kind', v_job.source_kind,
    'counters', v_job.counters,
    'discovered_total', v_job.discovered_total,
    'home_revision', v_job.home_revision,
    'home_revisions', jsonb_build_object('anime',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='anime'),0),'manga',coalesce((select revision from public.home_publications where user_id=v_uid::text and medium='manga'),0)),
    'sanitized_error', v_job.sanitized_error,
    'retry_after', v_job.retry_after
  );
end;
$$;

revoke all on function public.start_library_import_v1(text, text, text, text, text) from public;
revoke all on function public.apply_import_chunk_v1(uuid, jsonb) from public;
revoke all on function public.finish_library_import_v1(uuid, boolean) from public;
revoke all on function public.import_job_status_v1(uuid) from public;
grant execute on function public.start_library_import_v1(text, text, text, text, text) to authenticated;
grant execute on function public.apply_import_chunk_v1(uuid, jsonb) to authenticated;
grant execute on function public.finish_library_import_v1(uuid, boolean) to authenticated;
grant execute on function public.import_job_status_v1(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Concierge apply / undo: progress and status go through the receipt fence.
-- Notes and rating stay direct writes. Session idempotency is unchanged.
-- Replaces public.apply_import_session / undo_import_session from
-- 20261005130000 without editing that applied migration.
-- ---------------------------------------------------------------------------

create or replace function public.apply_import_session(
  p_user_id uuid,
  p_session_id uuid,
  p_idempotency_key text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;     -- list tables keep the legacy TEXT user_id (auth.uid()::text)
  v_session_id uuid;
  v_existing uuid;
  v_item jsonb;
  v_ord integer;
  v_type text;
  v_media_id integer;
  v_action text;
  v_table text;
  v_idcol text;
  v_expected jsonb;
  v_values jsonb;
  v_journal jsonb;
  v_cur jsonb;
  v_written jsonb;
  v_prev jsonb;
  v_after jsonb;
  v_outcome text;
  v_error text;
  v_applied integer := 0;
  v_locked bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
  if p_user_id is null then
    raise exception 'apply_import_session: p_user_id is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'apply_import_session: p_items must be an array of 1..100 planned items' using errcode = '22023';
  end if;
  if p_idempotency_key is not null and char_length(p_idempotency_key) not between 1 and 128 then
    raise exception 'apply_import_session: p_idempotency_key must be 1..128 characters' using errcode = '22023';
  end if;

  -- Replay: the same user action (key) never applies twice.
  if p_idempotency_key is not null then
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if found then
      return public._import_apply_outcome(v_existing, true);
    end if;
  end if;

  v_session_id := coalesce(p_session_id, gen_random_uuid());
  begin
    insert into public.import_sessions (id, user_id, status, source, idempotency_key)
    values (v_session_id, p_user_id, 'draft', 'chat', p_idempotency_key);
  exception when unique_violation then
    -- A concurrent call with the same key committed first (this insert waited on it).
    if p_idempotency_key is null then
      raise;
    end if;
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    return public._import_apply_outcome(v_existing, true);
  end;

  -- Import origin for the taste_capture triggers, for exactly this transaction.
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, v_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  -- Lock order (see header, review R2): every existing target row of the batch,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first
  -- write (the first write takes the user's recompute-queue row through taste_capture).
  -- Malformed identities are not cast here; the item loop rejects them.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'ANIME' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'MANGA' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item, v_ord in
    select e.value, e.ordinality::integer
    from jsonb_array_elements(p_items) with ordinality as e(value, ordinality)
    order by e.ordinality
  loop
    v_type := v_item ->> 'media_type';
    v_action := v_item ->> 'import_action';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or jsonb_typeof(v_item -> 'media_id') is distinct from 'number'
       or (case when (v_item ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                then (v_item ->> 'media_id')::bigint > 2147483647 else true end)
       or v_action is null or v_action not in ('add', 'update', 'skip') then
      raise exception 'apply_import_session: item % is not a planned item (media_type/media_id/import_action)', v_ord
        using errcode = '22023';
    end if;
    v_media_id := (v_item ->> 'media_id')::integer;
    v_table := case v_type when 'ANIME' then 'anime_user_lists' else 'manga_user_lists' end;
    v_idcol := case v_type when 'ANIME' then 'anime_id' else 'manga_id' end;
    v_expected := case when jsonb_typeof(v_item -> 'expected') = 'object' then v_item -> 'expected' end;
    -- Descriptive journal fields are type-checked, never cast blindly: a malformed value is
    -- replaced by its default instead of aborting the Apply.
    v_journal := case when jsonb_typeof(v_item -> 'journal') = 'object' then v_item -> 'journal' else '{}'::jsonb end;
    v_cur := null; v_written := null; v_prev := null; v_after := null; v_outcome := null; v_error := null;

    if v_action = 'skip' then
      v_outcome := 'skipped';
    else
      -- Current row under a row lock (concurrent writers of this row wait for us).
      if v_type = 'ANIME' then
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.anime_user_lists l
        where l.user_id = v_uid and l.anime_id = v_media_id
        for update;
      else
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.manga_user_lists l
        where l.user_id = v_uid and l.manga_id = v_media_id
        for update;
      end if;

      -- Compare-and-set on the state the client reviewed.
      if v_expected is not null then
        if v_cur is null then
          v_outcome := 'conflict';
          v_error := 'Entry no longer exists (deleted since parse)';
        elsif exists (select 1 from jsonb_each(v_expected) e where (v_cur -> e.key) is distinct from e.value) then
          v_outcome := 'conflict';
          v_error := 'State changed since parse — review and retry';
        end if;
      end if;

      if v_outcome is null then
        begin
          if v_cur is null then
            v_values := coalesce(v_item -> 'insert_values', '{}'::jsonb);
            if v_type = 'ANIME' then
              insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, anime_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            else
              insert into public.manga_user_lists (user_id, manga_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, manga_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            end if;
            if v_written is null then
              -- The row was inserted by another transaction after our read: retry the whole Apply.
              raise exception 'apply_import_session: % % was written concurrently', v_type, v_media_id
                using errcode = '40001';
            end if;
            v_after := v_written;          -- an insert journals the whole tracked row
          else
            v_values := coalesce(v_item -> 'update_values', '{}'::jsonb);
            -- Progress/status go through the series receipt fence. Notes/rating stay
            -- direct writes and still advance server_revision via their triggers.
            if v_values ? 'progress' or v_values ? 'list_type' then
              perform public._fence_set_progress_status(
                v_uid,
                case v_type when 'ANIME' then 'anime' else 'manga' end,
                v_media_id,
                public._import_mutation_id('apply', v_session_id, v_type, v_media_id),
                case when v_values ? 'progress' then (v_values ->> 'progress')::integer end,
                case when v_values ? 'list_type' then v_values ->> 'list_type' end
              );
            end if;
            if v_values ? 'rating' or v_values ? 'notes' then
              if v_type = 'ANIME' then
                update public.anime_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.anime_id = v_media_id;
              else
                update public.manga_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.manga_id = v_media_id;
              end if;
            end if;
            if v_type = 'ANIME' then
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict)
                into v_written
              from public.anime_user_lists l
              where l.user_id = v_uid and l.anime_id = v_media_id;
            else
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict)
                into v_written
              from public.manga_user_lists l
              where l.user_id = v_uid and l.manga_id = v_media_id;
            end if;
            -- an update journals only the fields it wrote, as stored
            select coalesce(jsonb_object_agg(k.key, v_written -> k.key), '{}'::jsonb)
              into v_after
            from jsonb_object_keys(v_values) as k(key)
            where k.key in ('list_type', 'progress', 'rating', 'notes');
            v_prev := v_cur;
          end if;
          v_outcome := 'applied';
          v_applied := v_applied + 1;
        exception when integrity_constraint_violation or data_exception then
          -- This item's data was rejected by the table: item error, batch continues.
          -- A fixed message per SQLSTATE (never schema or constraint names).
          v_outcome := 'error';
          v_error := case when sqlstate = '23503' then 'Unknown title' else 'Value rejected' end;
          v_written := null; v_after := null; v_prev := null;
        end;
      end if;
    end if;

    -- Journal row: REQUIRED (any error here aborts the whole Apply).
    insert into public.import_session_items (
      session_id, raw, parsed, candidates, chosen, action, confidence, state, import_action, error,
      previous_values, after_values
    ) values (
      v_session_id,
      left(case when jsonb_typeof(v_journal -> 'raw') = 'string' then v_journal ->> 'raw'
                else v_type || ':' || v_media_id end, 500),
      case when jsonb_typeof(v_journal -> 'parsed') = 'object' then v_journal -> 'parsed' else '{}'::jsonb end,
      case when jsonb_typeof(v_journal -> 'candidates') = 'array' then v_journal -> 'candidates' else '[]'::jsonb end,
      jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id),
      jsonb_build_object(
        'ordinal', v_ord,
        'outcome', v_outcome,
        'table', case when v_action <> 'skip' then v_table end,
        'key', case when v_action <> 'skip' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) end,
        'before', v_cur,
        -- legacy-compatible upsert image (read by the pre-transaction undo during a mixed deploy)
        'after', case when v_outcome = 'applied' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) || v_after end
      ),
      case when jsonb_typeof(v_journal -> 'confidence') = 'number' then (v_journal ->> 'confidence')::real else 0 end,
      case v_outcome when 'applied' then 'applied' when 'skipped' then 'skipped' else 'error' end,
      v_action,
      v_error,
      case when v_outcome = 'applied' then v_prev end,
      case when v_outcome = 'applied' then v_after end
    );
  end loop;

  -- Session transition: REQUIRED.
  update public.import_sessions
     set status = case when v_applied > 0 then 'applied' else 'failed' end
   where id = v_session_id and status = 'draft';
  if not found then
    raise exception 'apply_import_session: session % could not be finalized', v_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = v_session_id;

  return public._import_apply_outcome(v_session_id, false);
end;
$$;

create or replace function public.undo_import_session(p_user_id uuid, p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;
  v_session record;
  v_latest uuid;
  v_item record;
  v_type text;
  v_media_id integer;
  v_ident jsonb;
  v_after jsonb;
  v_before jsonb;
  v_cur jsonb;
  v_changed text[];
  v_revert text[];
  v_unrestorable text[];
  v_reverted jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_locked bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
  if p_user_id is null or p_session_id is null then
    raise exception 'undo_import_session: p_user_id and p_session_id are required' using errcode = '22023';
  end if;

  select s.id, s.user_id, s.status, s.created_at into v_session
  from public.import_sessions s
  where s.id = p_session_id
  for update;
  -- Another user's session is reported exactly like a missing one.
  if not found or v_session.user_id is distinct from p_user_id then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_session.status = 'cancelled' then
    return jsonb_build_object('result', 'already_undone', 'session_id', p_session_id,
                              'reverted', '[]'::jsonb, 'skipped', '[]'::jsonb, 'warnings', '[]'::jsonb);
  end if;
  if v_session.status <> 'applied'
     or not exists (select 1 from public.import_session_items i where i.session_id = p_session_id and i.state = 'applied') then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- Revert writes are import-origin for the taste_capture triggers (same as Apply).
  -- Also serialises with an in-flight Apply of this user (same context row).
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, p_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  select s.id into v_latest
  from public.import_sessions s
  where s.user_id = p_user_id and s.status = 'applied'
  order by s.created_at desc, s.id desc
  limit 1;
  if v_latest is distinct from p_session_id then
    delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;
    return jsonb_build_object('result', 'not_latest');
  end if;

  -- Lock order (see header, review R2): every existing row this Undo may write,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first write.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'ANIME')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'MANGA')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item in
    select i.id, i.chosen, i.import_action, i.previous_values, i.after_values, i.action
    from public.import_session_items i
    where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
    -- DESCENDING ordinal (review A1): a chain on one title (add then update) unwinds last
    -- write first. Results are prepended, so the response lists items in request order.
    order by case when coalesce(i.action ->> 'ordinal', '') ~ '^[0-9]{1,9}$' then (i.action ->> 'ordinal')::integer else 0 end desc,
             i.created_at desc, i.id desc
  loop
    v_type := v_item.chosen ->> 'mediaType';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or (case when coalesce(v_item.chosen ->> 'mediaId', '') ~ '^[1-9][0-9]{0,9}$'
                then (v_item.chosen ->> 'mediaId')::bigint > 2147483647 else true end) then
      v_warnings := jsonb_build_array(jsonb_build_object('id', v_item.id, 'reason', 'invalid_journal_identity')) || v_warnings;
      continue;
    end if;
    v_media_id := (v_item.chosen ->> 'mediaId')::integer;
    v_ident := jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id);

    -- After image: after_values; journals written before 20261005130000 carry it in action.after.
    select jsonb_object_agg(e.key, e.value) into v_after
    from jsonb_each(case
                      when jsonb_typeof(v_item.after_values) = 'object' then v_item.after_values
                      when jsonb_typeof(v_item.action -> 'after') = 'object' then v_item.action -> 'after'
                      else '{}'::jsonb
                    end) e
    where e.key in ('list_type', 'progress', 'rating', 'notes', 'verdict');
    if v_after is null then
      v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'no_after_image'))) || v_warnings;
      continue;
    end if;
    -- Before image: null means the import created the row.
    v_before := case
                  when jsonb_typeof(v_item.previous_values) = 'object' then v_item.previous_values
                  when jsonb_typeof(v_item.action -> 'before') = 'object' then v_item.action -> 'before'
                end;

    v_cur := null;
    if v_type = 'ANIME' then
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.anime_user_lists l
      where l.user_id = v_uid and l.anime_id = v_media_id
      for update;
    else
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.manga_user_lists l
      where l.user_id = v_uid and l.manga_id = v_media_id
      for update;
    end if;

    if v_cur is null then
      -- Deleted after the import: stays deleted.
      v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'deleted_since_import'))) || v_skipped;
      continue;
    end if;

    select coalesce(array_agg(e.key order by e.key), '{}') into v_changed
    from jsonb_each(v_after) e
    where (v_cur -> e.key) is distinct from e.value;

    if v_before is null then
      -- The import created the row: delete it only when nothing was changed since.
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
        continue;
      end if;
      if v_type = 'ANIME' then
        delete from public.anime_user_lists where user_id = v_uid and anime_id = v_media_id;
      else
        delete from public.manga_user_lists where user_id = v_uid and manga_id = v_media_id;
      end if;
      v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'deleted'))) || v_reverted;
    else
      -- The import changed an existing row: revert each written field still equal to
      -- the after image. The journaled before value is type-checked, never cast blindly:
      -- list_type a string, progress a non-negative integer (a NOT NULL column is never
      -- restored to null), rating null or 1..10, notes null or a string. A field whose
      -- before value is not restorable keeps its value and is reported in warnings.
      select coalesce(array_agg(e.key order by e.key) filter (where r.ok), '{}'),
             coalesce(array_agg(e.key order by e.key) filter (where not r.ok), '{}')
        into v_revert, v_unrestorable
      from jsonb_each(v_after) e
      cross join lateral (
        select coalesce(case e.key
          when 'list_type' then jsonb_typeof(v_before -> 'list_type') = 'string'
          when 'progress'  then jsonb_typeof(v_before -> 'progress') = 'number'
                                and (v_before ->> 'progress') ~ '^[0-9]{1,9}$'
          when 'rating'    then coalesce(jsonb_typeof(v_before -> 'rating'), 'null') = 'null'
                                or (jsonb_typeof(v_before -> 'rating') = 'number'
                                    and (v_before ->> 'rating') ~ '^([1-9]|10)$')
          when 'notes'     then coalesce(jsonb_typeof(v_before -> 'notes'), 'null') in ('null', 'string')
        end, false) as ok
      ) r
      where e.key in ('list_type', 'progress', 'rating', 'notes')
        and (v_cur -> e.key) is not distinct from e.value;
      if cardinality(v_unrestorable) > 0 then
        v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'unrestorable_before_value',
                                                                   'fields', to_jsonb(v_unrestorable)))) || v_warnings;
      end if;
      if cardinality(v_revert) > 0 then
        if 'progress' = any(v_revert) or 'list_type' = any(v_revert) then
          perform public._fence_set_progress_status(
            v_uid,
            case v_type when 'ANIME' then 'anime' else 'manga' end,
            v_media_id,
            public._import_mutation_id('undo', p_session_id, v_type, v_media_id),
            case when 'progress' = any(v_revert) then (v_before ->> 'progress')::integer end,
            case when 'list_type' = any(v_revert) then v_before ->> 'list_type' end
          );
        end if;
        if 'rating' = any(v_revert) or 'notes' = any(v_revert) then
          if v_type = 'ANIME' then
            update public.anime_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.anime_id = v_media_id;
          else
            update public.manga_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.manga_id = v_media_id;
          end if;
        end if;
        v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'restored', 'fields', to_jsonb(v_revert)))) || v_reverted;
      end if;
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
      end if;
      if cardinality(v_revert) = 0 then
        continue;
      end if;
    end if;

    update public.import_session_items set reverted_at = now() where id = v_item.id;
  end loop;

  update public.import_sessions set status = 'cancelled' where id = p_session_id and status = 'applied';
  if not found then
    raise exception 'undo_import_session: session % changed during undo', p_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;

  return jsonb_build_object('result', 'undone', 'session_id', p_session_id,
                            'reverted', v_reverted, 'skipped', v_skipped, 'warnings', v_warnings);
end;
$$;


revoke all on function public.apply_import_session(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.undo_import_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public.apply_import_session(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.undo_import_session(uuid, uuid) to service_role;

-- Private import flags are enforced by the established social readers too.
CREATE OR REPLACE FUNCTION public.friend_activity_page_v1(
  p_media_type text, p_media_id integer, p_after_comment_at timestamptz default null,
  p_after_comment_id uuid default null, p_after_friend uuid default null
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid             uuid := auth.uid();
  _friend_uuids    uuid[];
  _detail_uuids    uuid[];
  _friends_json    jsonb;
  _comments_json   jsonb;
  _comment_next jsonb;
  _friend_next text;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('friends_tracking', '[]'::jsonb, 'comments', '[]'::jsonb);
  END IF;

  if p_media_type not in ('ANIME','MANGA') then raise exception 'INVALID_MEDIUM'; end if;
  if (p_after_comment_at is null) <> (p_after_comment_id is null) then raise exception 'INVALID_CURSOR'; end if;

  -- Friend visibility map: per friend, the MAX effective sharing rank across
  -- all shared non-archived clubs. Effective rank mirrors fetch_club_bundle:
  -- least of club sharing_level rank and the subject member's own downgrade
  -- (member sharing_level can only lower exposure; NULL inherits club level).
  -- eff_rank 0 everywhere -> not visible at all; >= 1 -> status-level;
  -- >= 2 -> progress/rating detail.
  WITH friend_visibility AS (
    SELECT
      cm2.user_id AS friend_id,
      MAX(
        least(public.sharing_level_rank(c.sharing_level),
          public.sharing_level_rank(coalesce(cm1.sharing_level,c.sharing_level)),
          public.sharing_level_rank(coalesce(cm2.sharing_level,c.sharing_level)))
      ) AS eff_rank
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
  )
  SELECT
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 1), '{}'::uuid[]),
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 2), '{}'::uuid[])
  INTO _friend_uuids, _detail_uuids;

  -- Friends tracking this title (from user lists)
  -- NOTE: anime_user_lists/manga_user_lists have TEXT user_id, so cast uuid::text
  WITH friends_tracking AS (
    SELECT
      f_uid AS user_id,
      p.display_name,
      ul.status,
      ul.progress,
      ul.rating,
      ul.updated_at::text AS updated_at
    FROM unnest(_friend_uuids) AS f_uid
    JOIN profiles p ON p.id = f_uid
    INNER JOIN (
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM anime_user_lists
      WHERE not entry_private AND anime_id = p_media_id AND 'ANIME' = p_media_type
      UNION ALL
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM manga_user_lists
      WHERE not entry_private AND manga_id = p_media_id AND 'MANGA' = p_media_type
    ) ul ON ul.user_id = f_uid::text
    where p_after_friend is null or f_uid>p_after_friend
    order by f_uid limit 51
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', ft.user_id,
      'display_name', ft.display_name,
      'status', ft.status,
      -- eff_rank 1 = status only: keep columns but NULL the detail fields
      'progress', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.progress ELSE NULL END,
      'rating', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.rating ELSE NULL END,
      'updated_at', ft.updated_at
    )
   order by ft.user_id), '[]'::jsonb)
  INTO _friends_json
  FROM friends_tracking ft;

  if jsonb_array_length(_friends_json)>50 then
    _friend_next:=_friends_json->49->>'user_id'; _friends_json:=_friends_json-50;
  end if;

  -- Comments from self + visible friends, with reaction counts
  WITH visible_comments AS (
    SELECT tc.*
    FROM title_comments tc
    WHERE tc.media_type = p_media_type
      AND tc.media_id = p_media_id
      AND (tc.user_id = _uid OR tc.user_id = ANY(_friend_uuids))
      AND (p_after_comment_at is null or (tc.created_at,tc.id)<(p_after_comment_at,p_after_comment_id))
    order by tc.created_at desc,tc.id desc limit 21
  ),
  comment_agg AS (
    SELECT
      vc.id,
      vc.user_id,
      p.display_name,
      vc.text,
      vc.spoiler_scope,
      vc.created_at::text AS created_at,
      vc.updated_at::text AS updated_at,
      (vc.user_id = _uid) AS is_own,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'up' THEN 1 ELSE 0 END), 0)::int AS up_count,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'down' THEN 1 ELSE 0 END), 0)::int AS down_count,
      (SELECT cr2.reaction_type FROM title_comment_reactions cr2
       WHERE cr2.comment_id = vc.id AND cr2.user_id = _uid
       LIMIT 1) AS my_reaction
    FROM visible_comments vc
    JOIN profiles p ON p.id = vc.user_id
    LEFT JOIN title_comment_reactions cr ON cr.comment_id = vc.id
    GROUP BY vc.id, vc.user_id, p.display_name, vc.text, vc.spoiler_scope, vc.created_at, vc.updated_at
    ORDER BY vc.created_at DESC,vc.id DESC
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ca.id,
      'user_id', ca.user_id,
      'display_name', ca.display_name,
      'text', ca.text,
      'spoiler_scope', ca.spoiler_scope,
      'created_at', ca.created_at,
      'updated_at', ca.updated_at,
      'is_own', ca.is_own,
      'up_count', ca.up_count,
      'down_count', ca.down_count,
      'my_reaction', ca.my_reaction
    )
   order by ca.created_at desc,ca.id desc), '[]'::jsonb)
  INTO _comments_json
  FROM comment_agg ca;

  if jsonb_array_length(_comments_json)>20 then
    _comment_next:=jsonb_build_object('at',_comments_json->19->>'created_at','id',_comments_json->19->>'id');
    _comments_json:=_comments_json-20;
  end if;
  RETURN jsonb_build_object(
    'own_comment',(select jsonb_build_object('id',tc.id,'user_id',tc.user_id,'display_name',p.display_name,
      'text',tc.text,'spoiler_scope',tc.spoiler_scope,'created_at',tc.created_at,'updated_at',tc.updated_at,
      'is_own',true,
      'up_count',(select count(*) from public.title_comment_reactions cr where cr.comment_id=tc.id and cr.reaction_type='up'),
      'down_count',(select count(*) from public.title_comment_reactions cr where cr.comment_id=tc.id and cr.reaction_type='down'),
      'my_reaction',null)
      from public.title_comments tc join public.profiles p on p.id=tc.user_id
      where tc.user_id=_uid and tc.media_type=p_media_type and tc.media_id=p_media_id),
    'comments_next',_comment_next,'friends_next',_friend_next,
    'friends_tracking', _friends_json,
    'comments', _comments_json
  );
END;
$$;

revoke all on function public.friend_activity_page_v1(text,integer,timestamptz,uuid,uuid) from public,anon,service_role;
grant execute on function public.friend_activity_page_v1(text,integer,timestamptz,uuid,uuid) to authenticated;
create or replace function public.fetch_friend_activity_for_title(p_media_type text,p_media_id integer)
returns jsonb language sql stable security invoker set search_path=public,extensions as $$
 select public.friend_activity_page_v1(p_media_type,p_media_id,null,null,null);
$$;

CREATE OR REPLACE FUNCTION public.count_friends_tracking(p_items text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid        uuid := auth.uid();
  _items_json jsonb := p_items::jsonb;
  _result     jsonb;
BEGIN
  IF _uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  if jsonb_typeof(_items_json) <> 'array' or jsonb_array_length(_items_json)>100 then raise exception 'INVALID_ITEMS'; end if;

  -- Only friends whose MAX effective sharing rank across shared non-archived
  -- clubs is >= 1 count toward indicators (private club or self-downgrade
  -- to 'private' in every shared club -> invisible). Same eff-rank rule as
  -- fetch_club_bundle / fetch_friend_activity_for_title.
  WITH friend_ids AS (
    SELECT cm2.user_id
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
    HAVING MAX(least(public.sharing_level_rank(c.sharing_level),
      public.sharing_level_rank(coalesce(cm1.sharing_level,c.sharing_level)),
      public.sharing_level_rank(coalesce(cm2.sharing_level,c.sharing_level)))
    ) >= 1
  ),
  items AS (
    SELECT
      (elem->>'media_type')::text AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(_items_json) AS elem
  ),
  counts AS (
    SELECT
      i.media_type,
      i.media_id,
      COUNT(DISTINCT ul.user_id)::int AS count
    FROM items i
    JOIN (
      SELECT user_id, 'ANIME'::text AS media_type, anime_id AS media_id FROM anime_user_lists WHERE not entry_private
      UNION ALL
      SELECT user_id, 'MANGA'::text AS media_type, manga_id AS media_id FROM manga_user_lists WHERE not entry_private
    ) ul ON ul.media_type = i.media_type AND ul.media_id = i.media_id
    WHERE ul.user_id::uuid IN (SELECT user_id FROM friend_ids)
    GROUP BY i.media_type, i.media_id
    HAVING COUNT(DISTINCT ul.user_id) > 0
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'media_type', c.media_type,
      'media_id', c.media_id,
      'count', c.count
    )
  ), '[]'::jsonb)
  INTO _result
  FROM counts c;

  RETURN _result;
END;
$$;

create or replace function public.upsert_title_comment_scoped_v1(
  p_media_type text, p_media_id integer, p_text text, p_spoiler_scope text
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_result jsonb; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_spoiler_scope not in ('none','story','ending') or p_spoiler_scope is null then raise exception 'INVALID_SPOILER_SCOPE'; end if;
  -- Keep the existing title validation, rate limit and single-comment contract.
  v_result := public.upsert_title_comment(p_media_type,p_media_id,p_text);
  update public.title_comments set spoiler_scope=p_spoiler_scope
  where user_id=v_uid and media_type=p_media_type and media_id=p_media_id;
  return v_result;
end; $$;
revoke all on function public.upsert_title_comment_scoped_v1(text,integer,text,text) from public, anon;
grant execute on function public.upsert_title_comment_scoped_v1(text,integer,text,text) to authenticated;

-- Independent, deterministic unit paging; opening a page never writes tracking.
create or replace function public.series_units_page_v1(
 p_medium text, p_media_id integer, p_section_id uuid default null,
 p_edition_key text default null, p_after_order numeric default null, p_after_id uuid default null, p_limit integer default 20
) returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare v_rows jsonb; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20))); v_next jsonb; v_edition text:=p_edition_key;
begin
 if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if (p_after_order is null) <> (p_after_id is null) then raise exception 'INVALID_CURSOR'; end if;
 if p_section_id is not null and not exists(select 1 from public.series_entry_spans sp join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
   where sp.section_id=p_section_id and ((p_medium='anime' and sp.anime_id=p_media_id) or (p_medium='manga' and sp.manga_id=p_media_id))) then raise exception 'INVALID_SECTION'; end if;
 if v_edition is null then
  select u.edition_key into v_edition from public.catalogue_units u
   where u.medium=p_medium and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
    and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
   order by u.edition_key,u.order_key,u.id limit 1;
 end if;
 select coalesce(jsonb_agg(row_data order by order_key,id),'[]'::jsonb) into v_rows from (
   select jsonb_build_object('id',u.id,'label',u.label,'order_key',u.order_key::text,'available',u.available,
       'edition_key',u.edition_key,'title',u.title,'synopsis',u.synopsis,'image_url',u.image_url) row_data,u.order_key,u.id
   from public.catalogue_units u where u.medium=p_medium
     and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
     and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
     and u.edition_key=v_edition
     and (p_after_order is null or (u.order_key,u.id)>(p_after_order,p_after_id))
   order by u.order_key,u.id limit v_limit+1
 ) page;
 if jsonb_array_length(v_rows)>v_limit then
   v_next:=jsonb_build_object('order',v_rows->(v_limit-1)->'order_key','id',v_rows->(v_limit-1)->'id');
   v_rows:=v_rows-(v_limit);
 end if;
 return jsonb_build_object('items',v_rows,'next',v_next,'edition',v_edition);
end; $$;
revoke all on function public.series_units_page_v1(text,integer,uuid,text,numeric,uuid,integer) from public,anon;
grant execute on function public.series_units_page_v1(text,integer,uuid,text,numeric,uuid,integer) to authenticated;

-- Bounded source-edition keys with an independent exact-string cursor. No whole
-- catalogue aggregation, fictional volumes, or collapsing translated editions.
create or replace function public.series_editions_page_v1(p_medium text,p_media_id integer,
 p_section_id uuid default null,p_after_key text default null,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare items jsonb; cursor text; cap integer:=least(50,greatest(1,coalesce(p_limit,50)));
begin
 if auth.uid() is null then raise exception 'UNAUTHENTICATED';end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM';end if;
 if length(coalesce(p_after_key,''))>1024 then raise exception 'INVALID_CURSOR';end if;
 if p_section_id is not null and not exists(select 1 from public.series_entry_spans sp
  join public.series_sections sec on sec.id=sp.section_id and sec.state='approved'
  where sp.section_id=p_section_id and ((p_medium='anime' and sp.anime_id=p_media_id) or (p_medium='manga' and sp.manga_id=p_media_id)))
 then raise exception 'INVALID_SECTION';end if;
 select coalesce(jsonb_agg(edition_key order by edition_key),'[]'::jsonb) into items from (
  select distinct u.edition_key from public.catalogue_units u where u.medium=p_medium
   and ((p_medium='anime' and u.anime_id=p_media_id) or (p_medium='manga' and u.manga_id=p_media_id))
   and (p_section_id is null or u.section_id=p_section_id or u.section_id is null)
   and (p_after_key is null or u.edition_key>p_after_key)
  order by u.edition_key limit cap+1) keys;
 if jsonb_array_length(items)>cap then cursor:=items->>(cap-1);items:=items-cap;end if;
 return jsonb_build_object('items',items,'next',cursor);
end; $$;
revoke all on function public.series_editions_page_v1(text,integer,uuid,text,integer) from public,anon;
grant execute on function public.series_editions_page_v1(text,integer,uuid,text,integer) to authenticated;

-- R11: independent release keyset. Counts apply to the selected user's tracked/saved/followed
-- titles. Day precision is a source day, never fabricated UTC midnight. Unknown dates stay pending.
create or replace function public.home_events_page_v1(p_medium text,p_window_days integer default 7,
 p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare
 v_uid text:=auth.uid()::text; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20)));
 v_after text; v_id text; v_page jsonb; v_total bigint; v_next text;
begin
 if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if length(coalesce(p_cursor,''))>1024 then raise exception 'INVALID_CURSOR'; end if;
 if p_cursor is not null then
   begin v_after:=p_cursor::jsonb->>'sort'; v_id:=p_cursor::jsonb->>'id';
     if v_after is null or v_id is null then raise exception 'INVALID_CURSOR'; end if;
   exception when others then raise exception 'INVALID_CURSOR'; end;
 end if;
 with tracked as materialized (
   select anime_id as id from public.anime_user_lists where p_medium='anime' and user_id=v_uid and list_type in ('WATCHING','PLANNING')
   union select manga_id from public.manga_user_lists where p_medium='manga' and user_id=v_uid and list_type in ('READING','PLANNING')
   union select case when p_medium='anime' then sp.anime_id else sp.manga_id end
     from public.user_series_intent i join public.series sr on sr.id=i.series_id and sr.grouping_state='approved'
     join public.series_entry_spans sp on sp.series_id=i.series_id and sp.medium=p_medium
     where i.user_id=v_uid and (i.saved or i.followed)
 ), events as materialized (
   select r.id::text as event_id,coalesce(r.anime_id,r.manga_id) as media_id,r.utc_instant as at,
     r.precision,r.source_local_date,r.source_zone,r.kind as unit_label,r.status,
     case when r.precision='instant' then to_char(r.utc_instant at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')
          else r.source_local_date||'T' end as sort_key
   from public.release_events r join tracked t on t.id=coalesce(r.anime_id,r.manga_id)
   where r.medium=p_medium and r.status in ('scheduled','announced') and (
     (r.precision='instant' and r.utc_instant>=now() and r.utc_instant<now()+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7)))))
     or (r.precision='day' and r.source_local_date>=to_char(now() at time zone 'UTC','YYYY-MM-DD')
       and r.source_local_date<to_char((now() at time zone 'UTC')+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7)))),'YYYY-MM-DD'))
   )
   union all
   select 'next:anime:'||a.id||':'||coalesce(a.next_episode_number::text,'')||':'||a.next_airing_at::text,
     a.id,a.next_airing_at,'instant',null,null,
     case when a.next_episode_number is null then 'Episode' else 'Episode '||a.next_episode_number end,'scheduled',
     to_char(a.next_airing_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')
   from public.anime a join tracked t on t.id=a.id
   where p_medium='anime' and a.next_airing_at>=now() and a.next_airing_at<now()+make_interval(days=>least(90,greatest(1,coalesce(p_window_days,7))))
     and not exists(select 1 from public.release_events r where r.anime_id=a.id and r.status in ('scheduled','announced') and r.utc_instant=a.next_airing_at)
 ), page as materialized (
   select * from events where v_after is null or (sort_key,event_id)>(v_after,v_id)
   order by sort_key,event_id limit v_limit+1
 ), visible as (
   select p.*,coalesce(a.title_english,a.title_romaji,a.title_native,m.title_english,m.title_romaji,m.title_native,'Untitled') as title,
    coalesce(a.cover_image_large,m.cover_image_large) as cover_image
   from (select * from page order by sort_key,event_id limit v_limit) p
   left join public.anime a on p_medium='anime' and a.id=p.media_id
   left join public.manga m on p_medium='manga' and m.id=p.media_id
 )
 select coalesce(jsonb_agg(to_jsonb(visible)-'sort_key' order by sort_key,event_id),'[]'::jsonb),
   (select count(*) from events),
   (select case when count(*)>v_limit then (select jsonb_build_object('sort',sort_key,'id',event_id)::text
      from page order by sort_key,event_id offset v_limit-1 limit 1) else null end from page)
 into v_page,v_total,v_next from visible;
 return jsonb_build_object('items',v_page,'total',v_total,'next_cursor',v_next);
end; $$;
revoke all on function public.home_events_page_v1(text,integer,integer,text) from public,anon;
grant execute on function public.home_events_page_v1(text,integer,integer,text) to authenticated;

-- Undated announcements have an independent UUID keyset; they never acquire a
-- fabricated midnight merely for display or sorting.
create or replace function public.home_pending_page_v1(p_medium text,p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare
 v_uid text:=auth.uid()::text; v_limit integer:=least(50,greatest(1,coalesce(p_limit,20)));
 v_after uuid; v_items jsonb; v_total bigint; v_next text;
begin
 if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium is null or p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if p_cursor is not null then
   begin v_after:=p_cursor::uuid; exception when others then raise exception 'INVALID_CURSOR'; end;
 end if;
 with tracked as materialized (
   select anime_id as id from public.anime_user_lists where p_medium='anime' and user_id=v_uid
   union select manga_id from public.manga_user_lists where p_medium='manga' and user_id=v_uid
   union select case when p_medium='anime' then sp.anime_id else sp.manga_id end
     from public.user_series_intent i join public.series sr on sr.id=i.series_id and sr.grouping_state='approved'
     join public.series_entry_spans sp on sp.series_id=i.series_id and sp.medium=p_medium
     where i.user_id=v_uid and (i.saved or i.followed)
 ), eligible as materialized (
   select e.* from public.release_events e join tracked t on t.id=coalesce(e.anime_id,e.manga_id)
   where e.medium=p_medium and e.precision='unknown' and e.status='announced'
 ), page as materialized (
   select * from eligible where v_after is null or id>v_after order by id limit v_limit+1
 ), visible as (
   select e.id,e.medium,coalesce(e.anime_id,e.manga_id) media_id,e.status,e.precision,
     e.source_local_date,e.source_zone,e.kind unit_label,
     coalesce(a.title_english,a.title_romaji,a.title_native,m.title_english,m.title_romaji,m.title_native,'Untitled') title,
     coalesce(a.cover_image_large,m.cover_image_large) cover_image
   from (select * from page order by id limit v_limit)e
   left join public.anime a on p_medium='anime' and a.id=e.anime_id
   left join public.manga m on p_medium='manga' and m.id=e.manga_id
 )
 select coalesce(jsonb_agg((to_jsonb(visible)-'id')||jsonb_build_object('event_id',id) order by id),'[]'::jsonb),
   (select count(*) from eligible),
   (select case when count(*)>v_limit then (select id::text from page order by id offset v_limit-1 limit 1) end from page)
 into v_items,v_total,v_next from visible;
 return jsonb_build_object('items',v_items,'total',v_total,'next_cursor',v_next);
end; $$;
revoke all on function public.home_pending_page_v1(text,integer,text) from public,anon;
grant execute on function public.home_pending_page_v1(text,integer,text) to authenticated;

-- R14: additive legacy catalogue bridge. Existing source rows retain their own identity;
-- no invented episode/chapter totals, chapter dates, editions or continuation boundaries.
alter table public.release_events add column if not exists source_identity text;
create unique index if not exists release_events_source_identity on public.release_events(source_identity) where source_identity is not null;
create index if not exists catalogue_units_source on public.catalogue_units(source_provenance);
create or replace function public._bridge_legacy_unit_v1(p_medium text,p_source_id integer,p_media_id integer,
 p_number integer,p_title text,p_synopsis text,p_image text,p_day date,p_instant timestamptz,p_removed boolean default false)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid; v_source text:='legacy:'||p_medium||':'||p_source_id||':'||p_media_id||':'||p_number; v_available boolean;
begin
 if p_medium not in ('anime','manga') or p_number<0 then raise exception 'INVALID_SOURCE_UNIT'; end if;
 v_available:=not p_removed and case when p_instant is not null then p_instant<=now()
   when p_day is not null then p_day<(now() at time zone 'UTC')::date else false end;
 if p_medium='anime' then
   insert into public.catalogue_units(medium,anime_id,label,order_key,edition_key,available,title,synopsis,image_url,source_provenance)
   values ('anime',p_media_id,p_number::text,p_number,'legacy_catalogue',v_available,p_title,p_synopsis,p_image,v_source)
   on conflict (anime_id,edition_key,order_key) where anime_id is not null do update set
     available=excluded.available,title=excluded.title,synopsis=excluded.synopsis,image_url=excluded.image_url
     where catalogue_units.source_provenance=excluded.source_provenance returning id into v_id;
 else
   insert into public.catalogue_units(medium,manga_id,label,order_key,edition_key,available,title,synopsis,image_url,source_provenance)
   values ('manga',p_media_id,p_number::text,p_number,'legacy_catalogue',v_available,p_title,p_synopsis,p_image,v_source)
   on conflict (manga_id,edition_key,order_key) where manga_id is not null do update set
     available=excluded.available,title=excluded.title,synopsis=excluded.synopsis,image_url=excluded.image_url
     where catalogue_units.source_provenance=excluded.source_provenance returning id into v_id;
 end if;
 if v_id is null then return; end if; -- another verified source owns this unit; do not overwrite it.
 if p_day is not null or p_instant is not null or p_removed then
   insert into public.release_events(medium,anime_id,manga_id,kind,precision,source_local_date,utc_instant,status,evidence,freshness,source_identity)
   values(p_medium,case when p_medium='anime' then p_media_id end,case when p_medium='manga' then p_media_id end,
     case when p_medium='anime' then 'Episode ' else 'Chapter ' end||p_number,
     case when p_instant is not null then 'instant' when p_day is not null then 'day' else 'unknown' end,
     p_day::text,p_instant,case when p_removed then 'withdrawn' when v_available then 'released' else 'scheduled' end,
     v_source,now(),v_source)
   on conflict(source_identity) where source_identity is not null do update set
     precision=excluded.precision,source_local_date=excluded.source_local_date,utc_instant=excluded.utc_instant,
     status=excluded.status,evidence=excluded.evidence,freshness=excluded.freshness,revision=release_events.revision+1;
 end if;
end; $$;
revoke all on function public._bridge_legacy_unit_v1(text,integer,integer,integer,text,text,text,date,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public._bridge_legacy_unit_v1(text,integer,integer,integer,text,text,text,date,timestamptz,boolean) to service_role;

create or replace function public.legacy_unit_bridge_trigger_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if TG_TABLE_NAME='episodes' then
   if TG_OP='DELETE' then
     perform public._bridge_legacy_unit_v1('anime',old.id,old.anime_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.air_date,old.air_at,true);
   else
     if TG_OP='UPDATE' and (old.anime_id,old.number) is distinct from (new.anime_id,new.number) then
       perform public._bridge_legacy_unit_v1('anime',old.id,old.anime_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.air_date,old.air_at,true);
     end if;
     perform public._bridge_legacy_unit_v1('anime',new.id,new.anime_id,new.number,coalesce(new.title,new.title_romaji),new.description,new.thumbnail,new.air_date,new.air_at,false);
   end if;
 else
   if TG_OP='DELETE' then
     perform public._bridge_legacy_unit_v1('manga',old.id,old.manga_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.release_date,old.release_at,true);
   else
     if TG_OP='UPDATE' and (old.manga_id,old.number) is distinct from (new.manga_id,new.number) then
       perform public._bridge_legacy_unit_v1('manga',old.id,old.manga_id,old.number,coalesce(old.title,old.title_romaji),old.description,old.thumbnail,old.release_date,old.release_at,true);
     end if;
     perform public._bridge_legacy_unit_v1('manga',new.id,new.manga_id,new.number,coalesce(new.title,new.title_romaji),new.description,new.thumbnail,new.release_date,new.release_at,false);
   end if;
 end if;
 return null;
end; $$;
revoke all on function public.legacy_unit_bridge_trigger_v1() from public,anon,authenticated;
drop trigger if exists series_bridge_episodes on public.episodes;
create trigger series_bridge_episodes after insert or update or delete on public.episodes for each row execute function public.legacy_unit_bridge_trigger_v1();
drop trigger if exists series_bridge_chapters on public.chapters;
create trigger series_bridge_chapters after insert or update or delete on public.chapters for each row execute function public.legacy_unit_bridge_trigger_v1();

-- Existing data backfill is a resumable SERVICE job: <=250 PK rows per call. Never a Home call.
create or replace function public.backfill_legacy_series_units_v1(p_medium text,p_after_id integer default 0,p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r record; n integer:=0; last_id integer:=coalesce(p_after_id,0); cap integer:=least(250,greatest(1,coalesce(p_limit,250)));
begin
 if p_medium not in ('anime','manga') then raise exception 'INVALID_MEDIUM'; end if;
 if p_medium='anime' then
   for r in select * from public.episodes where id>last_id order by id limit cap loop
     perform public._bridge_legacy_unit_v1('anime',r.id,r.anime_id,r.number,coalesce(r.title,r.title_romaji),r.description,r.thumbnail,r.air_date,r.air_at,false);
     n:=n+1; last_id:=r.id;
   end loop;
 else
   for r in select * from public.chapters where id>last_id order by id limit cap loop
     perform public._bridge_legacy_unit_v1('manga',r.id,r.manga_id,r.number,coalesce(r.title,r.title_romaji),r.description,r.thumbnail,r.release_date,r.release_at,false);
     n:=n+1; last_id:=r.id;
   end loop;
 end if;
 return jsonb_build_object('processed',n,'after_id',last_id,'has_more',n=cap);
end; $$;
revoke all on function public.backfill_legacy_series_units_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function public.backfill_legacy_series_units_v1(text,integer,integer) to service_role;


-- Imported PRIVATE entries never contribute to club aggregates or named rows.
create or replace function public.fetch_club_bundle(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _members jsonb;
  _rails jsonb;
  _polls jsonb;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Explicit caller authorization: this function reads every member's rows.
  IF NOT public.is_club_member(p_club_id) THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT cm.role, cm.sharing_level, cm.joined_at
  INTO _my_membership
  FROM public.club_members cm
  WHERE cm.club_id = p_club_id AND cm.user_id = _uid;

  IF _my_membership IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  INTO _club
  FROM public.clubs c
  WHERE c.id = p_club_id;

  IF _club IS NULL THEN
    RAISE EXCEPTION 'CLUB_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  _my_effective_level := CASE
    WHEN _my_membership.sharing_level IS NULL THEN _club.sharing_level
    WHEN public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      THEN _my_membership.sharing_level
    ELSE _club.sharing_level
  END;

  _club_sharing_rank := least(public.sharing_level_rank(_club.sharing_level),public.sharing_level_rank(_my_effective_level));

  -- current members only
  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = p_club_id;

  -- MEMBERS: private club or fewer than 3 members -> only the caller
  IF _club_sharing_rank = 0 OR _member_count < 3 THEN
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id AND cm.user_id = _uid
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  END IF;

  _members := COALESCE(_members, '[]'::jsonb);

  -- RAILS + ITEMS with media join + per-item aggregates + reactions
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'title', r.title,
      'description', r.description,
      'is_locked', r.is_locked,
      'sort_order', r.sort_order,
      'created_by', r.created_by,
      'items', COALESCE(r.items, '[]'::jsonb)
    ) ORDER BY r.sort_order, r.id
  ), '[]'::jsonb)
  INTO _rails
  FROM (
    SELECT
      cr.id, cr.title, cr.description, cr.is_locked, cr.sort_order, cr.created_by,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', enriched.item_id,
            'media_type', enriched.media_type,
            'media_id', enriched.media_id,
            'sort_order', enriched.sort_order,
            'note', enriched.note,
            'added_by', enriched.added_by,
            'title_display', enriched.title_display,
            'cover_image_medium', enriched.cover_image_medium,
            'average_score', enriched.average_score,
            'year', enriched.year,
            'format', enriched.format,
            'episode_count', enriched.episode_count,
            'chapter_count', enriched.chapter_count,
            'my_status', enriched.my_status,
            'my_progress', enriched.my_progress,
            'my_rating', enriched.my_rating,
            'member_status_counts', enriched.member_status_counts,
            'member_statuses', enriched.member_statuses,
            'reactions', enriched.reactions,
            'my_reactions', enriched.my_reactions
          ) ORDER BY enriched.sort_order, enriched.item_id
        )
        FROM (
          SELECT
            cri.id AS item_id,
            cri.media_type,
            cri.media_id,
            cri.sort_order,
            cri.note,
            cri.added_by,
            COALESCE(
              CASE WHEN cri.media_type = 'ANIME' THEN COALESCE(a.title_english, a.title_romaji)
                   WHEN cri.media_type = 'MANGA' THEN COALESCE(m.title_english, m.title_romaji)
              END, 'Unknown'
            ) AS title_display,
            CASE WHEN cri.media_type = 'ANIME' THEN a.cover_image_medium
                 WHEN cri.media_type = 'MANGA' THEN m.cover_image_medium
            END AS cover_image_medium,
            CASE WHEN cri.media_type = 'ANIME' THEN a.average_score
                 WHEN cri.media_type = 'MANGA' THEN m.average_score
            END AS average_score,
            CASE WHEN cri.media_type = 'ANIME' THEN a.season_year
                 WHEN cri.media_type = 'MANGA' THEN m.start_date_year
            END AS year,
            CASE WHEN cri.media_type = 'ANIME' THEN a.format
                 WHEN cri.media_type = 'MANGA' THEN m.format
            END AS format,
            CASE WHEN cri.media_type = 'ANIME' THEN a.episodes ELSE NULL END AS episode_count,
            CASE WHEN cri.media_type = 'MANGA' THEN m.chapters ELSE NULL END AS chapter_count,
            -- Caller's own status/progress/rating
            COALESCE(my_aul.list_type, my_mul.list_type) AS my_status,
            COALESCE(my_aul.progress, my_mul.progress) AS my_progress,
            COALESCE(my_aul.rating, my_mul.rating) AS my_rating,
            -- Aggregate status counts across CURRENT club members
            CASE
              -- Fewer than 3 members: no cross-member aggregate at all (H1 "only own data";
              -- a count over one other member would identify that person).
              WHEN _member_count < 3 THEN NULL
              WHEN _club_sharing_rank = 0 THEN
                -- private club (>= 3 members, so >= 2 others): anonymous count of the OTHER
                -- members who track the item; every member's effective level is private here,
                -- which docs/clubs-spec.md defines as "anonymous contribution to counts"
                jsonb_build_object('_tracking_count', (
                  SELECT count(*)
                  FROM public.club_members cm2
                  WHERE cm2.club_id = p_club_id
                    AND cm2.user_id != _uid
                    AND (
                      CASE WHEN cri.media_type = 'ANIME' THEN
                        EXISTS (SELECT 1 FROM public.anime_user_lists aul2
                                WHERE not aul2.entry_private AND aul2.user_id = cm2.user_id::text AND aul2.anime_id = cri.media_id)
                      WHEN cri.media_type = 'MANGA' THEN
                        EXISTS (SELECT 1 FROM public.manga_user_lists mul2
                                WHERE not mul2.entry_private AND mul2.user_id = cm2.user_id::text AND mul2.manga_id = cri.media_id)
                      END
                    )
                ))
              ELSE
                (
                  SELECT COALESCE(jsonb_object_agg(sa.list_type, sa.cnt), '{}'::jsonb)
                  FROM (
                    SELECT ul.list_type, count(*) AS cnt
                    FROM public.club_members cm3
                    JOIN LATERAL (
                      SELECT CASE
                        WHEN cm3.sharing_level IS NULL THEN _club_sharing_rank
                        WHEN public.sharing_level_rank(cm3.sharing_level) < _club_sharing_rank
                          THEN public.sharing_level_rank(cm3.sharing_level)
                        ELSE _club_sharing_rank
                      END AS eff_rank
                    ) eff ON true
                    LEFT JOIN LATERAL (
                      SELECT aul3.list_type FROM public.anime_user_lists aul3
                      WHERE cri.media_type = 'ANIME' AND not aul3.entry_private AND aul3.user_id = cm3.user_id::text AND aul3.anime_id = cri.media_id
                      UNION ALL
                      SELECT mul3.list_type FROM public.manga_user_lists mul3
                      WHERE cri.media_type = 'MANGA' AND not mul3.entry_private AND mul3.user_id = cm3.user_id::text AND mul3.manga_id = cri.media_id
                    ) ul ON true
                    WHERE cm3.club_id = p_club_id AND eff.eff_rank >= 1 AND ul.list_type IS NOT NULL
                    GROUP BY ul.list_type
                  ) sa
                )
            END AS member_status_counts,
            -- Per-member status: effective rank >= 1; progress only at effective rank >= 2
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN NULL
              ELSE (
                SELECT jsonb_agg(jsonb_build_object(
                  'user_id', ms.user_id,
                  'display_name', ms.display_name,
                  'status', ms.list_type,
                  'progress', CASE WHEN ms.eff_rank >= 2 THEN ms.progress ELSE NULL END,
                  'updated_at', ms.updated_at
                ) ORDER BY ms.updated_at DESC NULLS LAST, ms.user_id)
                FROM (
                  SELECT cm4.user_id, nullif(trim(coalesce(p4.display_name, '')), '') AS display_name,
                         ul4.list_type, ul4.progress, ul4.updated_at, eff4.eff_rank
                  FROM public.club_members cm4
                  LEFT JOIN public.profiles p4 ON p4.id = cm4.user_id
                  JOIN LATERAL (
                    SELECT CASE
                      WHEN cm4.sharing_level IS NULL THEN _club_sharing_rank
                      WHEN public.sharing_level_rank(cm4.sharing_level) < _club_sharing_rank
                        THEN public.sharing_level_rank(cm4.sharing_level)
                      ELSE _club_sharing_rank
                    END AS eff_rank
                  ) eff4 ON true
                  LEFT JOIN LATERAL (
                    SELECT aul4.list_type, aul4.progress, aul4.updated_at FROM public.anime_user_lists aul4
                    WHERE cri.media_type = 'ANIME' AND not aul4.entry_private AND aul4.user_id = cm4.user_id::text AND aul4.anime_id = cri.media_id
                    UNION ALL
                    SELECT mul4.list_type, mul4.progress, mul4.updated_at FROM public.manga_user_lists mul4
                    WHERE cri.media_type = 'MANGA' AND not mul4.entry_private AND mul4.user_id = cm4.user_id::text AND mul4.manga_id = cri.media_id
                  ) ul4 ON true
                  WHERE cm4.club_id = p_club_id AND eff4.eff_rank >= 1 AND ul4.list_type IS NOT NULL
                ) ms
              )
            END AS member_statuses,
            -- Reactions of CURRENT members: anonymous aggregate counts {fire: 3, heart: 1}
            (
              SELECT COALESCE(jsonb_object_agg(rc.emoji, rc.cnt), '{}'::jsonb)
              FROM (
                SELECT r2.emoji, count(*) AS cnt
                FROM public.club_rail_item_reactions r2
                JOIN public.club_members rm ON rm.club_id = p_club_id AND rm.user_id = r2.user_id
                WHERE r2.rail_item_id = cri.id
                GROUP BY r2.emoji
              ) rc
            ) AS reactions,
            -- My reactions: ["fire", "heart"]
            (
              SELECT COALESCE(jsonb_agg(r3.emoji), '[]'::jsonb)
              FROM public.club_rail_item_reactions r3
              WHERE r3.rail_item_id = cri.id AND r3.user_id = _uid
            ) AS my_reactions
          FROM public.club_rail_items cri
          LEFT JOIN public.anime a ON cri.media_type = 'ANIME' AND a.id = cri.media_id
          LEFT JOIN public.manga m ON cri.media_type = 'MANGA' AND m.id = cri.media_id
          LEFT JOIN public.anime_user_lists my_aul
            ON cri.media_type = 'ANIME' AND my_aul.user_id = _uid::text AND my_aul.anime_id = cri.media_id
          LEFT JOIN public.manga_user_lists my_mul
            ON cri.media_type = 'MANGA' AND my_mul.user_id = _uid::text AND my_mul.manga_id = cri.media_id
          WHERE cri.rail_id = cr.id
          ORDER BY cri.sort_order, cri.id
          LIMIT 50
        ) enriched
      ) AS items
    FROM public.club_rails cr
    WHERE cr.club_id = p_club_id
  ) r;

  -- POLLS + OPTIONS + VOTE COUNTS (current members' votes)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'question', p.question,
      'is_closed', p.is_closed,
      'closes_at', p.closes_at,
      'created_by', p.created_by,
      'created_at', p.created_at,
      'options', COALESCE(p.options, '[]'::jsonb),
      'my_vote_option_id', p.my_vote_option_id
    ) ORDER BY p.is_closed ASC, p.created_at DESC, p.id DESC
  ), '[]'::jsonb)
  INTO _polls
  FROM (
    SELECT
      cp.id, cp.question, cp.is_closed, cp.closes_at, cp.created_by, cp.created_at,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', option_rows.id,
            'label', option_rows.label,
            'media_type', option_rows.media_type,
            'media_id', option_rows.media_id,
            'sort_order', option_rows.sort_order,
            'vote_count', option_rows.vote_count
          ) ORDER BY option_rows.sort_order, option_rows.id
        )
        FROM (
          SELECT
            cpo.id,
            cpo.label,
            cpo.media_type,
            cpo.media_id,
            cpo.sort_order,
            COALESCE(vc.vote_count, 0)::int AS vote_count
          FROM public.club_poll_options cpo
          LEFT JOIN (
            SELECT cv.option_id, count(*) AS vote_count
            FROM public.club_votes cv
            JOIN public.club_members vm ON vm.club_id = p_club_id AND vm.user_id = cv.user_id
            WHERE cv.poll_id = cp.id
            GROUP BY cv.option_id
          ) vc ON vc.option_id = cpo.id
          WHERE cpo.poll_id = cp.id
        ) option_rows
      ) AS options,
      (
        SELECT cv2.option_id
        FROM public.club_votes cv2
        WHERE cv2.poll_id = cp.id AND cv2.user_id = _uid
        LIMIT 1
      ) AS my_vote_option_id
    FROM public.club_polls cp
    WHERE cp.club_id = p_club_id
    ORDER BY cp.is_closed ASC, cp.created_at DESC, cp.id DESC
    LIMIT 20
  ) p;

  RETURN jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      'invite_code', CASE WHEN _my_membership.role IN ('owner', 'admin') THEN _club.invite_code ELSE NULL END,
      'created_at', _club.created_at
    ),
    'members', _members,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', _rails,
    'polls', _polls,
    'member_count', _member_count
  );
END;
$function$;

create or replace function public.list_unit_owner_guard_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if new.unit_id is not null and not exists(select 1 from public.catalogue_units u
   where u.id=new.unit_id and ((TG_TABLE_NAME='anime_user_lists' and u.medium='anime' and u.anime_id=(to_jsonb(new)->>'anime_id')::integer)
     or (TG_TABLE_NAME='manga_user_lists' and u.medium='manga' and u.manga_id=(to_jsonb(new)->>'manga_id')::integer))) then
   raise exception 'INVALID_UNIT_OWNER';
 end if;
 return new;
end; $$;
revoke all on function public.list_unit_owner_guard_v1() from public,anon,authenticated;
drop trigger if exists series_unit_owner on public.anime_user_lists;
create trigger series_unit_owner before insert or update of unit_id,anime_id on public.anime_user_lists for each row execute function public.list_unit_owner_guard_v1();
drop trigger if exists series_unit_owner on public.manga_user_lists;
create trigger series_unit_owner before insert or update of unit_id,manga_id on public.manga_user_lists for each row execute function public.list_unit_owner_guard_v1();

-- A large approved continuity cannot hide its 51st tracked child. Group metadata is bounded;
-- children page independently by immutable internal ID with the SAME status/query scope.
create or replace function public.collection_series_children_v1(p_medium text,p_group_key text,
 p_status text default null,p_query text default null,p_after_id integer default null,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path=public,extensions as $$
declare v_user text:=auth.uid()::text; cap integer:=least(50,greatest(1,coalesce(p_limit,50))); q text:=left(replace(replace(coalesce(p_query,''),'%',''),'_',''),80); result jsonb; next_id integer;
begin
 if v_user is null then raise exception 'UNAUTHENTICATED'; end if;
 if p_medium not in ('anime','manga') or length(p_group_key)>128 then raise exception 'INVALID_TARGET'; end if;
 with entries as (
  select l.anime_id media_id,l.list_type,l.progress,l.server_revision,l.lifecycle_id,
    coalesce(a.title_english,a.title_romaji,a.title_native,'Untitled') title,
    coalesce(sp.series_id::text,'entry:anime:'||l.anime_id) group_key
  from public.anime_user_lists l join public.anime a on a.id=l.anime_id
  left join lateral (select sp.series_id from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
    where sp.anime_id=l.anime_id order by sp.id limit 1)sp on true
  where p_medium='anime' and l.user_id=v_user and (p_status is null or l.list_type=p_status)
    and (q='' or coalesce(a.title_english,'') ilike '%'||q||'%' or coalesce(a.title_romaji,'') ilike '%'||q||'%'
      or coalesce(a.title_native,'') ilike '%'||q||'%' or exists(select 1 from unnest(coalesce(a.title_synonyms,array[]::text[]))syn where syn ilike '%'||q||'%'))
  union all
  select l.manga_id,l.list_type,l.progress,l.server_revision,l.lifecycle_id,coalesce(m.title_english,m.title_romaji,m.title_native,'Untitled'),
    coalesce(sp.series_id::text,'entry:manga:'||l.manga_id)
  from public.manga_user_lists l join public.manga m on m.id=l.manga_id
  left join lateral (select sp.series_id from public.series_entry_spans sp join public.series sr on sr.id=sp.series_id and sr.grouping_state='approved'
    where sp.manga_id=l.manga_id order by sp.id limit 1)sp on true
  where p_medium='manga' and l.user_id=v_user and (p_status is null or l.list_type=p_status)
    and (q='' or coalesce(m.title_english,'') ilike '%'||q||'%' or coalesce(m.title_romaji,'') ilike '%'||q||'%' or coalesce(m.title_native,'') ilike '%'||q||'%')
 ), page as materialized (select * from entries where group_key=p_group_key and (p_after_id is null or media_id<p_after_id) order by media_id desc limit cap+1)
 select coalesce(jsonb_agg(to_jsonb(p)-'group_key' order by media_id desc),'[]'::jsonb),
   (select case when count(*)>cap then (select media_id from page order by media_id desc offset cap-1 limit 1) end from page)
 into result,next_id from (select * from page order by media_id desc limit cap)p;
 return jsonb_build_object('children',result,'next',next_id);
end; $$;
revoke all on function public.collection_series_children_v1(text,text,text,text,integer,integer) from public,anon;
grant execute on function public.collection_series_children_v1(text,text,text,text,integer,integer) to authenticated;

-- Every remaining viewer receives its OWN metadata signal when a peer is removed/downgraded.
-- This enables immediate Home/title-cache revocation without subscribing to raw member rows.
create or replace function public.club_disclosure_signal_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
declare cid uuid; member record;
begin
 if TG_TABLE_NAME='clubs' then cid:=new.id; else cid:=coalesce(new.club_id,old.club_id); end if;
 for member in select user_id from public.club_members where club_id=cid loop
   insert into public.club_membership_signals as signal(user_id,club_id,state,revision,changed_at)
   values(member.user_id,cid,'member',1,now()) on conflict(user_id,club_id) do update set
     state='member',revision=signal.revision+1,changed_at=now();
 end loop;
 return null;
end; $$;
revoke all on function public.club_disclosure_signal_v1() from public,anon,authenticated;
drop trigger if exists series_club_disclosure on public.club_members;
create trigger series_club_disclosure after insert or update of sharing_level or delete on public.club_members
 for each row execute function public.club_disclosure_signal_v1();
drop trigger if exists series_club_disclosure on public.clubs;
create trigger series_club_disclosure after update of sharing_level,is_archived on public.clubs
 for each row execute function public.club_disclosure_signal_v1();

-- Direct RLS and the reaction writer use the SAME disclosure rule as the paged reader.
create or replace function public.shares_club_with(p_other_user_id uuid)
returns boolean language sql stable security definer set search_path=public,extensions as $$
 select exists(select 1 from public.club_members viewer
  join public.club_members subject on subject.club_id=viewer.club_id
  join public.clubs c on c.id=viewer.club_id
  where viewer.user_id=auth.uid() and subject.user_id=p_other_user_id
   and viewer.user_id<>subject.user_id and not c.is_archived
   and least(public.sharing_level_rank(coalesce(viewer.sharing_level,c.sharing_level)),public.sharing_level_rank(coalesce(subject.sharing_level,c.sharing_level)),
     public.sharing_level_rank(c.sharing_level))>=1);
$$;

create or replace function public.list_disclosure_signal_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 if new.entry_private is not distinct from old.entry_private then return null; end if;
 insert into public.club_membership_signals as signal(user_id,club_id,state,revision,changed_at)
 select distinct viewer.user_id,viewer.club_id,'member',1,now()
 from public.club_members subject join public.club_members viewer on viewer.club_id=subject.club_id
 where subject.user_id::text=new.user_id
 on conflict(user_id,club_id) do update set state='member',revision=signal.revision+1,changed_at=now();
 return null;
end; $$;
revoke all on function public.list_disclosure_signal_v1() from public,anon,authenticated;
drop trigger if exists series_list_disclosure on public.anime_user_lists;
create trigger series_list_disclosure after update of entry_private on public.anime_user_lists
 for each row execute function public.list_disclosure_signal_v1();
drop trigger if exists series_list_disclosure on public.manga_user_lists;
create trigger series_list_disclosure after update of entry_private on public.manga_user_lists
 for each row execute function public.list_disclosure_signal_v1();

-- The existing catalogue ingestion owns its source rows. This bridge turns changes into
-- bounded, leased enrichment jobs; no synchronous artwork/API work in a user request.
create table if not exists public.series_enrichment_jobs (
 medium text not null check(medium in ('anime','manga')), media_id integer not null,
 source_revision text not null, payload jsonb not null,
 due_at timestamptz not null default now(), lease_token uuid, lease_until timestamptz,
 attempts integer not null default 0, last_error text, last_success_at timestamptz,
 primary key(medium,media_id)
);
alter table public.series_enrichment_jobs enable row level security;
revoke all on public.series_enrichment_jobs from anon,authenticated;
grant all on public.series_enrichment_jobs to service_role;
create index if not exists series_enrichment_due on public.series_enrichment_jobs(due_at,medium,media_id);
alter table public.detail_copy add column if not exists source_revision text;
alter table public.detail_copy add column if not exists freshness timestamptz;
create unique index if not exists detail_copy_bridge_anime on public.detail_copy(anime_id,locale)
 where provenance='catalogue_bridge_v1' and section_id is null and anime_id is not null;
create unique index if not exists detail_copy_bridge_manga on public.detail_copy(manga_id,locale)
 where provenance='catalogue_bridge_v1' and section_id is null and manga_id is not null;
alter table public.theme_links add column if not exists source_identity text;
alter table public.theme_links add column if not exists freshness timestamptz;
create unique index if not exists theme_links_source_identity on public.theme_links(source_identity)
 where source_identity is not null;

create or replace function public._queue_series_enrichment_v1(p_medium text,p_row jsonb)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare snapshot jsonb; revision text;
begin
 snapshot:=jsonb_build_object('medium',p_medium,'media_id',(p_row->>'id')::integer,
  'anilist_id',p_row->'anilist_id','mal_id',p_row->'mal_id','description',p_row->'description',
  'image_url',case when p_medium='anime' then coalesce(p_row->>'banner_image',p_row->>'cover_image_large')
    else p_row->>'cover_image_large' end);
 revision:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
 insert into public.series_enrichment_jobs as job(medium,media_id,source_revision,payload)
 values(p_medium,(p_row->>'id')::integer,revision,snapshot)
 on conflict(medium,media_id) do update set source_revision=excluded.source_revision,payload=excluded.payload,
  due_at=now(),lease_token=null,lease_until=null,attempts=0,last_error=null
 where job.source_revision<>excluded.source_revision;
end; $$;
revoke all on function public._queue_series_enrichment_v1(text,jsonb) from public,anon,authenticated;

create or replace function public.catalogue_series_enrichment_trigger_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 perform public._queue_series_enrichment_v1(TG_TABLE_NAME,to_jsonb(new)); return null;
end; $$;
revoke all on function public.catalogue_series_enrichment_trigger_v1() from public,anon,authenticated;
drop trigger if exists series_enrichment_source on public.anime;
create trigger series_enrichment_source after insert or update of description,banner_image,cover_image_large,anilist_id,mal_id
 on public.anime for each row execute function public.catalogue_series_enrichment_trigger_v1();
drop trigger if exists series_enrichment_source on public.manga;
create trigger series_enrichment_source after insert or update of description,cover_image_large,anilist_id,mal_id
 on public.manga for each row execute function public.catalogue_series_enrichment_trigger_v1();

-- Catalogue deletion must not leave a perpetually due orphan consuming worker
-- claims. Stale-revision completions still preserve a newer existing job.
create or replace function public.catalogue_series_enrichment_delete_v1() returns trigger
language plpgsql security definer set search_path=public,extensions as $$
begin
 delete from public.series_enrichment_jobs where medium=TG_TABLE_NAME and media_id=old.id;
 return null;
end; $$;
revoke all on function public.catalogue_series_enrichment_delete_v1() from public,anon,authenticated;
drop trigger if exists series_enrichment_delete on public.anime;
create trigger series_enrichment_delete after delete on public.anime
 for each row execute function public.catalogue_series_enrichment_delete_v1();
drop trigger if exists series_enrichment_delete on public.manga;
create trigger series_enrichment_delete after delete on public.manga
 for each row execute function public.catalogue_series_enrichment_delete_v1();

create or replace function public.backfill_series_enrichment_v1(p_medium text,p_after_id integer default 0,p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r record; last_id integer:=coalesce(p_after_id,0); n integer:=0; cap integer:=least(250,greatest(1,coalesce(p_limit,250)));
begin
 if p_medium='anime' then
  -- A backfill snapshot must not overtake a newer catalogue-triggered job.
  -- SHARE (not KEY SHARE) blocks non-key description/artwork updates until this
  -- bounded source-row -> job transaction completes, and rechecks waited rows.
  for r in select * from public.anime where id>last_id order by id limit cap for share loop
   perform public._queue_series_enrichment_v1('anime',to_jsonb(r));last_id:=r.id;n:=n+1;end loop;
 elsif p_medium='manga' then
  for r in select * from public.manga where id>last_id order by id limit cap for share loop
   perform public._queue_series_enrichment_v1('manga',to_jsonb(r));last_id:=r.id;n:=n+1;end loop;
 else raise exception 'INVALID_MEDIUM'; end if;
 return jsonb_build_object('processed',n,'after_id',last_id,'has_more',n=cap);
end; $$;
revoke all on function public.backfill_series_enrichment_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function public.backfill_series_enrichment_v1(text,integer,integer) to service_role;

create or replace function public.claim_series_enrichment_v1(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare jobs jsonb;
begin
 with candidates as (select medium,media_id from public.series_enrichment_jobs
  where due_at<=now() and (lease_until is null or lease_until<=now())
  order by due_at,medium,media_id limit least(20,greatest(1,coalesce(p_limit,10))) for update skip locked),
 claimed as (update public.series_enrichment_jobs j set lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes'
  from candidates c where (j.medium,j.media_id)=(c.medium,c.media_id) returning j.*)
 select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into jobs from claimed;
 return jobs;
end; $$;
revoke all on function public.claim_series_enrichment_v1(integer) from public,anon,authenticated;
grant execute on function public.claim_series_enrichment_v1(integer) to service_role;

-- Last-good data is updated only by the current source revision AND current claim.
-- A failed or superseded extraction cannot clear curated copy, theme links or palettes.
create or replace function public.finish_series_enrichment_v1(p_medium text,p_media_id integer,p_source_revision text,
 p_lease_token uuid,p_copy jsonb default null,p_material jsonb default null,p_themes jsonb default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare job public.series_enrichment_jobs%rowtype; theme jsonb; source text;
begin
 -- Catalogue writers/deletion take the catalogue row before their job trigger.
 -- Match that order before touching a job, including theme_links FK admission,
 -- so concurrent catalogue deletion cannot create a catalogue/job deadlock.
 if p_medium='anime' then perform 1 from public.anime where id=p_media_id for key share;
 elsif p_medium='manga' then perform 1 from public.manga where id=p_media_id for key share;
 else return jsonb_build_object('outcome','superseded');end if;
 if not found then return jsonb_build_object('outcome','superseded');end if;
 select * into job from public.series_enrichment_jobs where medium=p_medium and media_id=p_media_id for update;
 if not found or p_lease_token is null or p_source_revision is null
  or job.source_revision<>p_source_revision or job.lease_token is distinct from p_lease_token
  or job.lease_until is null or job.lease_until<=now()
 then return jsonb_build_object('outcome','superseded');end if;
 if p_error is not null then
  update public.series_enrichment_jobs set attempts=attempts+1,last_error=left(p_error,120),lease_token=null,lease_until=null,
   due_at=now()+make_interval(secs=>least(86400,60*power(2,least(attempts,10)))::integer) where medium=p_medium and media_id=p_media_id;
  return jsonb_build_object('outcome','retry');
 end if;
 if nullif(p_copy->>'synopsis','') is not null then
  if p_medium='anime' then
   insert into public.detail_copy(medium,anime_id,locale,premise,synopsis,provenance,review_state,source_revision,freshness)
   values('anime',p_media_id,'en',left(p_copy->>'premise',240),p_copy->>'synopsis','catalogue_bridge_v1','source',p_source_revision,now())
   on conflict(anime_id,locale) where provenance='catalogue_bridge_v1' and section_id is null and anime_id is not null
   do update set premise=excluded.premise,synopsis=excluded.synopsis,source_revision=excluded.source_revision,freshness=now();
  else
   insert into public.detail_copy(medium,manga_id,locale,premise,synopsis,provenance,review_state,source_revision,freshness)
   values('manga',p_media_id,'en',left(p_copy->>'premise',240),p_copy->>'synopsis','catalogue_bridge_v1','source',p_source_revision,now())
   on conflict(manga_id,locale) where provenance='catalogue_bridge_v1' and section_id is null and manga_id is not null
   do update set premise=excluded.premise,synopsis=excluded.synopsis,source_revision=excluded.source_revision,freshness=now();
  end if;
 end if;
 if p_material is not null then
  if p_material->>'image_url' is distinct from job.payload->>'image_url'
   or coalesce(p_material->>'digest','') !~ '^[0-9a-f]{64}$'
   or coalesce(p_material->>'base','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'deep','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'wash','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'edge','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'ink','') !~ '^#[0-9A-Fa-f]{6}$'
   or coalesce(p_material->>'contrast','') !~ '^[0-9]+(\.[0-9]+)?$'
  then raise exception 'INVALID_MATERIAL';end if;
  if (p_material->>'contrast')::numeric<7 then raise exception 'INVALID_MATERIAL';end if;
  -- Different catalogue jobs can share an artwork URL. Serialize the current-image
  -- flip independently of their job-row locks; the partial unique index remains
  -- the last backstop. Digest includes URL AND bytes in the worker, so identical
  -- content at two provider URLs has two identities without cross-URL mutation.
  perform pg_advisory_xact_lock(hashtextextended('series-artwork:'||(p_material->>'image_url'),0));
  if exists(select 1 from public.artwork_materials where image_digest=p_material->>'digest'
    and image_url is distinct from p_material->>'image_url') then raise exception 'INVALID_MATERIAL_IDENTITY';end if;
  update public.artwork_materials set is_current=false where image_url=p_material->>'image_url';
  insert into public.artwork_materials(image_digest,image_url,content_revision,extraction_version,base_color,deep_color,wash_color,edge_color,ink_color,contrast,is_current)
  values(p_material->>'digest',p_material->>'image_url',p_source_revision,'art-hue-v1',p_material->>'base',p_material->>'deep',
   p_material->>'wash',p_material->>'edge',p_material->>'ink',p_material->>'contrast',true)
  on conflict(image_digest) do update set is_current=true,content_revision=excluded.content_revision,
   extraction_version=excluded.extraction_version,base_color=excluded.base_color,deep_color=excluded.deep_color,
   wash_color=excluded.wash_color,edge_color=excluded.edge_color,ink_color=excluded.ink_color,contrast=excluded.contrast;
 end if;
 if p_medium='anime' and p_themes is not null then
  if jsonb_typeof(p_themes)<>'array' or jsonb_array_length(p_themes)>30 then raise exception 'INVALID_THEMES';end if;
  -- NULL means unknown/provider failure: retain last good. A known exact-ID set,
  -- including [], supersedes only this producer's rows, never curated links.
  delete from public.theme_links t where t.anime_id=p_media_id
   and t.source_identity like 'animethemes:'||p_media_id||':%'
   and not exists(select 1 from jsonb_array_elements(p_themes) incoming
     where t.source_identity='animethemes:'||p_media_id||':'||(incoming->>'source_id'));
  for theme in select * from jsonb_array_elements(p_themes) loop
   source:='animethemes:'||p_media_id||':'||(theme->>'source_id');
   if nullif(theme->>'source_id','') is null or theme->>'role' not in ('op','ed') then raise exception 'INVALID_THEME';end if;
   insert into public.theme_links(anime_id,role,sequence_order,song_title,artist,match_state,evidence,source_identity,freshness)
   values(p_media_id,theme->>'role',coalesce((theme->>'sequence_order')::integer,1),theme->>'song_title',theme->>'artist',
    'search','Exact external ID: '||coalesce(job.payload->>'anilist_id','')||' / '||coalesce(job.payload->>'mal_id',''),source,now())
   on conflict(source_identity) where source_identity is not null do update set song_title=excluded.song_title,
    artist=excluded.artist,sequence_order=excluded.sequence_order,role=excluded.role,
    match_state='search',external_url=null,evidence=excluded.evidence,freshness=now();
  end loop;
 end if;
 update public.series_enrichment_jobs set lease_token=null,lease_until=null,attempts=0,last_error=null,
  last_success_at=now(),due_at=now()+interval '7 days' where medium=p_medium and media_id=p_media_id;
 return jsonb_build_object('outcome','applied');
end; $$;
revoke all on function public.finish_series_enrichment_v1(text,integer,text,uuid,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.finish_series_enrichment_v1(text,integer,text,uuid,jsonb,jsonb,jsonb,text) to service_role;
$kuro_foundation_history$]),
('20261007130000','series_account_lifecycle',ARRAY[$kuro_lifecycle_history$-- Forward lifecycle repair for the integrated series foundation. Prepared only.
-- Auth foreign keys validate existing ownership; orphaned data aborts this migration
-- for explicit review rather than being silently purged or rewritten.
BEGIN;
ALTER TABLE public.library_import_jobs
    ADD CONSTRAINT library_import_jobs_auth_owner
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'user_series_intent', 'home_publications', 'mutation_receipts', 'list_entry_tombstones'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN account_user_id uuid GENERATED ALWAYS AS (user_id::uuid) STORED', relation_name);
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (account_user_id) REFERENCES auth.users(id) ON DELETE CASCADE',
            relation_name, relation_name || '_auth_owner');
        EXECUTE format('CREATE INDEX %I ON public.%I(account_user_id)',
            relation_name || '_auth_owner_idx', relation_name);
    END LOOP;
END;
$$;

CREATE FUNCTION public.series_account_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE owner_text text := to_jsonb(NEW)->>'user_id'; owner_id uuid;
BEGIN
    BEGIN
        owner_id := owner_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END;
    IF owner_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END IF;
    -- Reuse the existing deletion lock and committed barrier. Old JWT validity
    -- cannot admit writes while account deletion is in progress.
    PERFORM public._account_write_guard(owner_id::text);
    -- Hold the live owner until this transaction ends. GoTrue deletion either
    -- waits and cascades this write, or finishes first and this write is refused.
    PERFORM 1 FROM auth.users WHERE id = owner_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ACCOUNT_DELETION_IN_PROGRESS' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.series_account_write_guard() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'library_import_jobs', 'user_series_intent', 'mutation_receipts'
    ] LOOP
        EXECUTE format('CREATE TRIGGER series_account_write_guard BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.series_account_write_guard()', relation_name);
    END LOOP;
END;
$$;
-- Tombstones and Home publications have no client write grants. Internal list
-- deletion may write them after the deletion barrier; guarding that cleanup
-- would prevent deletion itself. Their validated auth FK still prevents orphan
-- creation and cascades the internal cleanup records with the deleted account.
COMMIT;
$kuro_lifecycle_history$]);
DO $kuro_postflight$
DECLARE relation_name text; after_digest text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY['list_entry_tombstones','mutation_receipts','series','series_sections','series_entry_spans','provider_entry_refs','mapping_revisions','mapping_revision_spans','user_series_intent','catalogue_units','artwork_materials','detail_copy','theme_links','adaptation_coverage','release_events','home_publications','library_import_jobs','library_import_baselines','library_import_items','series_enrichment_jobs'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||relation_name) AND relrowsecurity) THEN
      RAISE EXCEPTION 'Missing foundation table or RLS: %',relation_name;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.feature_flags WHERE flag_name IN ('series_foundation_v1','series_home_native_v1') AND NOT enabled AND rollout_percentage=0) <> 2 THEN
    RAISE EXCEPTION 'Global Home flags must remain disabled';
  END IF;
  SELECT md5(coalesce(string_agg((to_jsonb(l)-ARRAY['server_revision','lifecycle_id','unit_id','progress_label','repeat_count','score_raw','score_scale','started_raw','finished_raw','volumes_progress','entry_private','source_custom_lists','source_hidden','source_list_options'])::text,E'\n' ORDER BY id),'')) INTO after_digest FROM public.anime_user_lists l;
  IF after_digest IS DISTINCT FROM (SELECT digest FROM kuro_home_apply_snapshot WHERE medium='anime') THEN
    RAISE EXCEPTION 'Legacy anime fields changed unexpectedly';
  END IF;
  SELECT md5(coalesce(string_agg((to_jsonb(l)-ARRAY['server_revision','lifecycle_id','unit_id','progress_label','repeat_count','score_raw','score_scale','started_raw','finished_raw','volumes_progress','entry_private','source_custom_lists','source_hidden','source_list_options'])::text,E'\n' ORDER BY id),'')) INTO after_digest FROM public.manga_user_lists l;
  IF after_digest IS DISTINCT FROM (SELECT digest FROM kuro_home_apply_snapshot WHERE medium='manga') THEN
    RAISE EXCEPTION 'Legacy manga fields changed unexpectedly';
  END IF;
END;
$kuro_postflight$;
NOTIFY pgrst, 'reload schema';
COMMIT;
