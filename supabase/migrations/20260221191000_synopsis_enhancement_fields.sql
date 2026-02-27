-- Add additive enhanced synopsis columns (raw source description remains canonical).

begin;

alter table if exists public.anime
  add column if not exists synopsis_enhanced text null,
  add column if not exists synopsis_enhanced_source text null,
  add column if not exists synopsis_enhanced_model text null,
  add column if not exists synopsis_enhanced_version text null,
  add column if not exists synopsis_enhanced_updated_at timestamptz null,
  add column if not exists synopsis_enhanced_state text not null default 'pending';

alter table if exists public.manga
  add column if not exists synopsis_enhanced text null,
  add column if not exists synopsis_enhanced_source text null,
  add column if not exists synopsis_enhanced_model text null,
  add column if not exists synopsis_enhanced_version text null,
  add column if not exists synopsis_enhanced_updated_at timestamptz null,
  add column if not exists synopsis_enhanced_state text not null default 'pending';

alter table if exists public.anime
  drop constraint if exists anime_synopsis_enhanced_state_check;
alter table if exists public.anime
  add constraint anime_synopsis_enhanced_state_check
  check (synopsis_enhanced_state in ('pending', 'ready', 'failed'));

alter table if exists public.manga
  drop constraint if exists manga_synopsis_enhanced_state_check;
alter table if exists public.manga
  add constraint manga_synopsis_enhanced_state_check
  check (synopsis_enhanced_state in ('pending', 'ready', 'failed'));

create index if not exists idx_anime_synopsis_enhanced_queue
  on public.anime (synopsis_enhanced_state, synopsis_enhanced_updated_at, updated_at)
  where description is not null;

create index if not exists idx_manga_synopsis_enhanced_queue
  on public.manga (synopsis_enhanced_state, synopsis_enhanced_updated_at, updated_at)
  where description is not null;

commit;
