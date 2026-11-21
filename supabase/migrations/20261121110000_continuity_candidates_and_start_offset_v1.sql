-- PREPARED ONLY (Wave 3): start-offset consumption accounting (`started_at_progress`)
-- and service-role-only `series_candidates` staging table for reviewed watch-order spines
-- and anime-to-manga adaptation spans (`D-G`, Tier 1.5, Tier 2.2).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local search_path = public, extensions;

-- 1. Honest start offset: bookmarking Ch. 64 after finishing an anime stores started_at_progress = 63
--    so stats (`greatest(0, progress - started_at_progress)`) count actually read/watched units.
alter table public.anime_user_lists
  add column if not exists started_at_progress integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.anime_user_lists'::regclass
      and conname = 'anime_user_lists_started_at_progress_check'
  ) then
    alter table public.anime_user_lists
      add constraint anime_user_lists_started_at_progress_check check (started_at_progress >= 0);
  end if;
end $$;

alter table public.manga_user_lists
  add column if not exists started_at_progress integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.manga_user_lists'::regclass
      and conname = 'manga_user_lists_started_at_progress_check'
  ) then
    alter table public.manga_user_lists
      add constraint manga_user_lists_started_at_progress_check check (started_at_progress >= 0);
  end if;
end $$;

-- 2. Service-role-only continuity staging table (zero user_id FKs; zero client policies/grants).
create table if not exists public.series_candidates (
  id bigserial primary key,
  root_media_type text not null check (root_media_type in ('anime', 'manga')),
  root_media_id integer not null,
  member_media_type text not null check (member_media_type in ('anime', 'manga')),
  member_media_id integer not null,
  section_kind text not null check (section_kind in ('main', 'side', 'adaptation')),
  ordinal integer not null default 0,
  source_start_unit integer check (source_start_unit is null or source_start_unit >= 0),
  source_end_unit integer check (source_end_unit is null or source_end_unit >= 0),
  source_volume integer check (source_volume is null or source_volume >= 0),
  raw_note text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint series_candidates_unique_member unique (root_media_type, root_media_id, member_media_type, member_media_id)
);

create index if not exists idx_series_candidates_status_root
  on public.series_candidates (status, root_media_type, root_media_id, ordinal);

alter table public.series_candidates enable row level security;

revoke all on table public.series_candidates from public, anon, authenticated;
grant all on table public.series_candidates to service_role;

do $$
begin
  if to_regclass('public.series_candidates_id_seq') is not null then
    revoke all on sequence public.series_candidates_id_seq from public, anon, authenticated;
    grant all on sequence public.series_candidates_id_seq to service_role;
  end if;
end $$;

commit;
