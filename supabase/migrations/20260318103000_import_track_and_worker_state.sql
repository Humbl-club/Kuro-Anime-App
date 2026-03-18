begin;

-- ---------------------------------------------------------------------------
-- Import track state: additive cursor/visibility table for AniList imports.
-- ---------------------------------------------------------------------------
create table if not exists public.import_track_state (
  track_key text primary key,
  media_type text not null check (media_type in ('ANIME', 'MANGA')),
  track_preset text not null default 'catalog_backfill'
    check (track_preset in ('popularity_core', 'airing_or_releasing', 'recent_updates', 'catalog_backfill')),
  last_page integer not null default 0,
  state text not null default 'idle'
    check (state in ('idle', 'running', 'success', 'skipped', 'error')),
  visibility text not null default 'active'
    check (visibility in ('active', 'paused', 'complete')),
  last_run_at timestamptz,
  last_message text,
  last_results jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_import_track_state_media_type_updated_at
  on public.import_track_state (media_type, updated_at desc);

create index if not exists idx_import_track_state_preset_state
  on public.import_track_state (track_preset, state);

alter table public.import_track_state enable row level security;

do $$
begin
  create policy "service_role_all" on public.import_track_state
    for all to service_role
    using (true)
    with check (true);
exception when duplicate_object then null;
end $$;

insert into public.import_track_state (track_key, media_type, track_preset, last_page, state, visibility)
values
  ('anime:catalog_backfill', 'ANIME', 'catalog_backfill', 0, 'idle', 'active'),
  ('manga:catalog_backfill', 'MANGA', 'catalog_backfill', 0, 'idle', 'active')
on conflict (track_key) do nothing;

-- Lightweight queryable summary for dashboards / cron health.
create or replace view public.import_track_state_metrics as
select
  media_type,
  track_preset,
  state,
  visibility,
  count(*)::bigint as row_count,
  max(last_page)::bigint as max_last_page,
  max(last_run_at) as last_run_at,
  max(updated_at) as updated_at
from public.import_track_state
group by media_type, track_preset, state, visibility;

revoke all on public.import_track_state_metrics from public, anon, authenticated;
grant select on public.import_track_state_metrics to service_role;

-- ---------------------------------------------------------------------------
-- Manga chapter enrich state: per-manga latest status + visibility.
-- ---------------------------------------------------------------------------
create table if not exists public.manga_chapter_enrich_state (
  manga_id integer primary key references public.manga(id) on delete cascade,
  state text not null default 'pending'
    check (state in ('pending', 'running', 'mapped', 'unresolved', 'skipped', 'error')),
  visibility text not null default 'visible'
    check (visibility in ('visible', 'review', 'hidden')),
  mapping_method text,
  provider_media_id text,
  chapter_row_count integer not null default 0,
  inserted_count integer not null default 0,
  fractional_skipped integer not null default 0,
  last_run_at timestamptz,
  last_message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_manga_chapter_enrich_state_state_visibility
  on public.manga_chapter_enrich_state (state, visibility);

create index if not exists idx_manga_chapter_enrich_state_last_run_at
  on public.manga_chapter_enrich_state (last_run_at desc);

alter table public.manga_chapter_enrich_state enable row level security;

do $$
begin
  create policy "service_role_all" on public.manga_chapter_enrich_state
    for all to service_role
    using (true)
    with check (true);
exception when duplicate_object then null;
end $$;

create or replace view public.manga_chapter_enrich_state_metrics as
select
  state,
  visibility,
  count(*)::bigint as row_count,
  coalesce(sum(inserted_count), 0)::bigint as inserted_count,
  coalesce(sum(fractional_skipped), 0)::bigint as fractional_skipped,
  max(last_run_at) as last_run_at,
  max(updated_at) as updated_at
from public.manga_chapter_enrich_state
group by state, visibility;

revoke all on public.manga_chapter_enrich_state_metrics from public, anon, authenticated;
grant select on public.manga_chapter_enrich_state_metrics to service_role;

-- ---------------------------------------------------------------------------
-- Image mirror state: per-media asset latest status + visibility.
-- ---------------------------------------------------------------------------
create table if not exists public.image_mirror_state (
  media_type text not null check (media_type in ('ANIME', 'MANGA', 'CHARACTER', 'STAFF')),
  media_id integer not null,
  asset_key text not null,
  source_url text,
  mirrored_url text,
  state text not null default 'pending'
    check (state in ('pending', 'running', 'mirrored', 'skipped', 'failed')),
  visibility text not null default 'remote'
    check (visibility in ('public', 'remote', 'hidden')),
  last_run_at timestamptz,
  last_message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (media_type, media_id, asset_key)
);

create index if not exists idx_image_mirror_state_state_visibility
  on public.image_mirror_state (state, visibility);

create index if not exists idx_image_mirror_state_last_run_at
  on public.image_mirror_state (last_run_at desc);

alter table public.image_mirror_state enable row level security;

do $$
begin
  create policy "service_role_all" on public.image_mirror_state
    for all to service_role
    using (true)
    with check (true);
exception when duplicate_object then null;
end $$;

create or replace view public.image_mirror_state_metrics as
select
  media_type,
  state,
  visibility,
  count(*)::bigint as row_count,
  max(last_run_at) as last_run_at,
  max(updated_at) as updated_at
from public.image_mirror_state
group by media_type, state, visibility;

revoke all on public.image_mirror_state_metrics from public, anon, authenticated;
grant select on public.image_mirror_state_metrics to service_role;

commit;
