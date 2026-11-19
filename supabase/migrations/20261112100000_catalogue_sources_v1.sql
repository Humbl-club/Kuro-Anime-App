-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 1). NOT applied.
--
-- Catalogue sources without AniList: raw source records, id crosswalk, rollback snapshots, shadow
-- values and the per-field-group cutover switch. All five tables are service-only: RLS on, no
-- client policy, no anon/authenticated grant (service_role only). Nothing reads or writes them yet;
-- every group starts in 'anilist' mode, so the AniList importers keep their behaviour.
--
-- catalogue_id_links.kuro_id is polymorphic over six tables (same pattern as external_links), so
-- it has no foreign key: a BEFORE INSERT/UPDATE trigger asserts the target exists, and DELETE
-- triggers on the six target tables remove the links of a deleted row. Triggers are SECURITY
-- INVOKER (writers are service-role importers that hold the table grants); trigger functions
-- need no EXECUTE for the invoking role and it is revoked from public/anon/authenticated anyway.
-- anime/manga.data_sources: nullable text[] naming the sources a composed title used.
-- The app flag `catalogue_source_credit_v1` (detail selects name data_sources, title pages show the source
-- credit) may be raised ONLY AFTER this migration is applied: until then the column does not exist and every
-- detail read that names it fails. The flag is off by default (absent feature_flags row = off).
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create table if not exists public.catalogue_source_records (
  source       text not null,
  source_key   text not null,
  medium       text not null constraint catalogue_source_records_medium_check check (medium in ('anime', 'manga')),
  payload      jsonb not null,
  payload_hash text not null,
  licence      text not null,
  fetched_at   timestamptz not null default now(),
  constraint catalogue_source_records_pkey primary key (source, source_key, medium)
);

create table if not exists public.catalogue_id_links (
  id          bigint generated always as identity primary key,
  kind        text not null constraint catalogue_id_links_kind_check
                check (kind in ('anime', 'manga', 'staff', 'studio', 'character', 'author')),
  kuro_id     integer not null,
  source      text not null,
  source_key  text not null,
  method      text not null constraint catalogue_id_links_method_check
                check (method in ('wikidata', 'id_match', 'title_match', 'name_match', 'editorial')),
  confidence  numeric(4, 3),
  status      text not null default 'proposed' constraint catalogue_id_links_status_check
                check (status in ('proposed', 'accepted', 'rejected')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);

create unique index if not exists catalogue_id_links_accepted_source_key_uq
  on public.catalogue_id_links (source, source_key, kind) where status = 'accepted';
create unique index if not exists catalogue_id_links_accepted_kuro_uq
  on public.catalogue_id_links (kind, kuro_id, source) where status = 'accepted';
-- A proposed link is unique per (kind, kuro_id, source, source_key): a repeated or concurrent run
-- cannot pile up duplicate proposals (applyLinks treats 23505 as "already there").
create unique index if not exists catalogue_id_links_proposed_uq
  on public.catalogue_id_links (kind, kuro_id, source, source_key) where status = 'proposed';
-- Delete cleanup and lookups by Kuro row.
create index if not exists catalogue_id_links_kuro_idx on public.catalogue_id_links (kind, kuro_id);

create table if not exists public.catalogue_rollback_snapshots (
  field_group text not null,
  medium      text not null,
  media_id    integer not null,
  payload     jsonb not null,
  taken_at    timestamptz not null,
  constraint catalogue_rollback_snapshots_pkey primary key (field_group, medium, media_id)
);

create table if not exists public.catalogue_shadow_values (
  medium      text not null,
  media_id    integer not null,
  field       text not null,
  value       jsonb,
  source      text,
  computed_at timestamptz not null default now(),
  constraint catalogue_shadow_values_pkey primary key (medium, media_id, field)
);

create table if not exists public.catalogue_cutover (
  field_group text primary key constraint catalogue_cutover_field_group_check check (field_group in (
                'identity', 'titles', 'facts', 'relations', 'credits', 'popularity',
                'tags', 'adult', 'synopsis', 'episodes', 'links', 'images')),
  mode        text not null default 'anilist' constraint catalogue_cutover_mode_check
                check (mode in ('anilist', 'shadow', 'new')),
  changed_at  timestamptz,
  changed_by  text
);

insert into public.catalogue_cutover (field_group)
values ('identity'), ('titles'), ('facts'), ('relations'), ('credits'), ('popularity'),
       ('tags'), ('adult'), ('synopsis'), ('episodes'), ('links'), ('images')
on conflict (field_group) do nothing;

alter table public.anime add column if not exists data_sources text[];
alter table public.manga add column if not exists data_sources text[];

-- ---- service-only posture -----------------------------------------------------------
alter table public.catalogue_source_records enable row level security;
alter table public.catalogue_id_links enable row level security;
alter table public.catalogue_rollback_snapshots enable row level security;
alter table public.catalogue_shadow_values enable row level security;
alter table public.catalogue_cutover enable row level security;
-- No policies on purpose: anon/authenticated get nothing even if a grant reappears.
revoke all on table public.catalogue_source_records from public, anon, authenticated;
revoke all on table public.catalogue_id_links from public, anon, authenticated;
revoke all on table public.catalogue_rollback_snapshots from public, anon, authenticated;
revoke all on table public.catalogue_shadow_values from public, anon, authenticated;
revoke all on table public.catalogue_cutover from public, anon, authenticated;
revoke all on sequence public.catalogue_id_links_id_seq from public, anon, authenticated;
grant select, insert, update, delete on table public.catalogue_source_records to service_role;
grant select, insert, update, delete on table public.catalogue_id_links to service_role;
grant select, insert, update, delete on table public.catalogue_rollback_snapshots to service_role;
grant select, insert, update, delete on table public.catalogue_shadow_values to service_role;
grant select, insert, update, delete on table public.catalogue_cutover to service_role;
grant usage, select on sequence public.catalogue_id_links_id_seq to service_role;

-- ---- link target existence ------------------------------------------------------------
create or replace function public.catalogue_id_links_check_target()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
declare
  _found boolean;
begin
  -- FOR KEY SHARE on the target row: a concurrent DELETE of that row (which takes the stronger
  -- lock) waits until this insert commits, and its AFTER DELETE cleanup then sees and removes the
  -- new link. Without it the check could pass, the row be deleted and cleaned, and an orphan link commit.
  if new.kind = 'anime' then
    perform 1 from public.anime where id = new.kuro_id for key share;
  elsif new.kind = 'manga' then
    perform 1 from public.manga where id = new.kuro_id for key share;
  elsif new.kind = 'staff' then
    perform 1 from public.staff where id = new.kuro_id for key share;
  elsif new.kind = 'studio' then
    perform 1 from public.studios where id = new.kuro_id for key share;
  elsif new.kind = 'character' then
    perform 1 from public.characters where id = new.kuro_id for key share;
  elsif new.kind = 'author' then
    perform 1 from public.authors where id = new.kuro_id for key share;
  else
    perform 1 where false;
  end if;
  _found := found;
  if not _found then
    raise exception 'catalogue_id_links: % % does not exist', new.kind, new.kuro_id
      using errcode = 'foreign_key_violation';
  end if;
  return new;
end;
$$;

-- Deleting a title/entity removes its links (any status). Deleting an anime/manga also removes its
-- shadow values and rollback snapshots (they are keyed (medium, media_id) with no foreign key, so
-- nothing else would). User list rows are not touched here (their own foreign keys decide).
create or replace function public.catalogue_id_links_cleanup_anime()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  delete from public.catalogue_id_links where kind = 'anime' and kuro_id = old.id;
  delete from public.catalogue_shadow_values where medium = 'anime' and media_id = old.id;
  delete from public.catalogue_rollback_snapshots where medium = 'anime' and media_id = old.id;
  return old;
end;
$$;

create or replace function public.catalogue_id_links_cleanup_manga()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  delete from public.catalogue_id_links where kind = 'manga' and kuro_id = old.id;
  delete from public.catalogue_shadow_values where medium = 'manga' and media_id = old.id;
  delete from public.catalogue_rollback_snapshots where medium = 'manga' and media_id = old.id;
  return old;
end;
$$;

-- One function for the four entity tables; TG_ARGV[0] carries the kind.
create or replace function public.catalogue_id_links_cleanup_entity()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  delete from public.catalogue_id_links where kind = tg_argv[0] and kuro_id = old.id;
  return old;
end;
$$;

revoke all on function public.catalogue_id_links_check_target() from public, anon, authenticated;
revoke all on function public.catalogue_id_links_cleanup_anime() from public, anon, authenticated;
revoke all on function public.catalogue_id_links_cleanup_manga() from public, anon, authenticated;
revoke all on function public.catalogue_id_links_cleanup_entity() from public, anon, authenticated;

drop trigger if exists catalogue_id_links_check_target on public.catalogue_id_links;
create trigger catalogue_id_links_check_target
  before insert or update of kind, kuro_id on public.catalogue_id_links
  for each row execute function public.catalogue_id_links_check_target();

drop trigger if exists catalogue_id_links_cleanup on public.anime;
create trigger catalogue_id_links_cleanup after delete on public.anime
  for each row execute function public.catalogue_id_links_cleanup_anime();
drop trigger if exists catalogue_id_links_cleanup on public.manga;
create trigger catalogue_id_links_cleanup after delete on public.manga
  for each row execute function public.catalogue_id_links_cleanup_manga();
drop trigger if exists catalogue_id_links_cleanup on public.staff;
create trigger catalogue_id_links_cleanup after delete on public.staff
  for each row execute function public.catalogue_id_links_cleanup_entity('staff');
drop trigger if exists catalogue_id_links_cleanup on public.studios;
create trigger catalogue_id_links_cleanup after delete on public.studios
  for each row execute function public.catalogue_id_links_cleanup_entity('studio');
drop trigger if exists catalogue_id_links_cleanup on public.characters;
create trigger catalogue_id_links_cleanup after delete on public.characters
  for each row execute function public.catalogue_id_links_cleanup_entity('character');
drop trigger if exists catalogue_id_links_cleanup on public.authors;
create trigger catalogue_id_links_cleanup after delete on public.authors
  for each row execute function public.catalogue_id_links_cleanup_entity('author');

notify pgrst, 'reload schema';
commit;
