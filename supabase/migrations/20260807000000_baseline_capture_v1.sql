-- ============================================================================
-- baseline_capture_v1 — captured from LIVE production database 2026-08-06/07
-- (project bkdifromsqxkndnllmdj) via Supabase Management API read-only catalog
-- queries (information_schema / pg_catalog / pg_get_viewdef / pg_get_functiondef
-- / pg_policies / cron.job).
--
-- WHY THIS FILE EXISTS: the migration chain could not rebuild a fresh
-- environment. The entire core catalog schema (anime, manga, episodes,
-- chapters, volumes, characters, staff, studios, authors, tags + join tables,
-- anime_user_lists, manga_user_lists, anime_comments, manga_comments,
-- import_state, external_links) existed only in legacy_sql/, while
-- import_runs / import_locks, the acquire/release_import_lock RPCs, the 7
-- mv_* materialized views and the kuro-refresh-matviews cron job existed only
-- in production. In addition, four hollowed February migrations
-- (20260215124919, 20260215124946, 20260215125056, 20260215125312 — file
-- contents literally ';') dropped create_club_rail / create_club_poll /
-- club_rail_item_reactions from the chain; they are re-captured here from
-- production.
--
-- IDEMPOTENCY CONTRACT: every statement is guarded
-- (create ... if not exists / do $$ ... if not exists ... $$ / dependency
-- probes), so applying this file over existing production is a no-op, while a
-- fresh database receives the full missing baseline. Functions use
-- CREATE OR REPLACE (pg_get_functiondef output) preceded by DROP IF EXISTS
-- for the RPCs, and all functions carry SET search_path.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Sequences (serial backing sequences, values themselves are data)
-- ----------------------------------------------------------------------------
create sequence if not exists public.anime_id_seq;
create sequence if not exists public.anime_characters_id_seq;
create sequence if not exists public.anime_comments_id_seq;
create sequence if not exists public.anime_staff_id_seq;
create sequence if not exists public.anime_studios_id_seq;
create sequence if not exists public.anime_tags_id_seq;
create sequence if not exists public.anime_user_lists_id_seq;
create sequence if not exists public.authors_id_seq;
create sequence if not exists public.chapters_id_seq;
create sequence if not exists public.characters_id_seq;
create sequence if not exists public.episodes_id_seq;
create sequence if not exists public.external_links_id_seq;
create sequence if not exists public.import_runs_id_seq;
create sequence if not exists public.manga_id_seq;
create sequence if not exists public.manga_authors_id_seq;
create sequence if not exists public.manga_characters_id_seq;
create sequence if not exists public.manga_comments_id_seq;
create sequence if not exists public.manga_staff_id_seq;
create sequence if not exists public.manga_tags_id_seq;
create sequence if not exists public.manga_user_lists_id_seq;
create sequence if not exists public.staff_id_seq;
create sequence if not exists public.studios_id_seq;
create sequence if not exists public.tags_id_seq;
create sequence if not exists public.volumes_id_seq;

-- ----------------------------------------------------------------------------
-- 2. Core catalog / user-list / comments / import tables
-- ----------------------------------------------------------------------------
create table if not exists public.anime (
  id integer default nextval('public.anime_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  title_synonyms text[],
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  banner_image text,
  format text,
  status text,
  description text,
  description_normalized text,
  episodes integer,
  duration integer,
  total_duration integer,
  season text,
  season_year integer,
  next_episode_number integer,
  next_airing_at timestamp with time zone,
  start_date_year integer,
  start_date_month integer,
  start_date_day integer,
  end_date_year integer,
  end_date_month integer,
  end_date_day integer,
  average_score integer,
  mean_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[],
  source text,
  country_of_origin text,
  is_adult boolean default false not null,
  age_rating text,
  site_url text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  last_synced_at timestamp with time zone default now(),
  updated_at_anilist timestamp with time zone,
  synopsis_enhanced text,
  synopsis_enhanced_source text,
  synopsis_enhanced_model text,
  synopsis_enhanced_version text,
  synopsis_enhanced_updated_at timestamp with time zone,
  synopsis_enhanced_state text default 'pending'::text not null,
  synopsis_enhanced_retry_count integer default 0 not null,
  synopsis_enhanced_last_attempt_at timestamp with time zone,
  synopsis_enhanced_next_retry_at timestamp with time zone,
  synopsis_enhanced_last_error text,
  synopsis_enhanced_source_hash text,
  safety_state text default 'pending'::text not null,
  safety_blocked boolean default false not null,
  safety_reason_codes text[] default '{}'::text[] not null,
  safety_rule_hits text[] default '{}'::text[] not null,
  safety_model_label text,
  safety_model_confidence numeric(4,3),
  safety_model_rationale text,
  safety_suggested_lexicon text[] default '{}'::text[] not null,
  safety_source_hash text,
  safety_last_scanned_at timestamp with time zone,
  safety_last_attempt_at timestamp with time zone,
  safety_next_scan_at timestamp with time zone,
  safety_retry_count integer default 0 not null,
  safety_last_error text
);

create table if not exists public.anime_characters (
  id integer default nextval('public.anime_characters_id_seq'::regclass) not null,
  anime_id integer not null,
  character_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.anime_comments (
  id integer default nextval('public.anime_comments_id_seq'::regclass) not null,
  anime_id integer not null,
  user_id text not null,
  comment text not null,
  rating integer,
  is_spoiler boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists public.anime_staff (
  id integer default nextval('public.anime_staff_id_seq'::regclass) not null,
  anime_id integer not null,
  staff_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.anime_studios (
  id integer default nextval('public.anime_studios_id_seq'::regclass) not null,
  anime_id integer not null,
  studio_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.anime_tags (
  id integer default nextval('public.anime_tags_id_seq'::regclass) not null,
  anime_id integer not null,
  tag_id integer not null,
  rank integer default 0,
  created_at timestamp with time zone default now()
);

create table if not exists public.anime_user_lists (
  id integer default nextval('public.anime_user_lists_id_seq'::regclass) not null,
  user_id text not null,
  anime_id integer not null,
  list_type text not null,
  progress integer default 0 not null,
  rating integer,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  verdict text
);

create table if not exists public.authors (
  id integer default nextval('public.authors_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  name_full text,
  name_native text,
  name_romaji text,
  image_large text,
  image_medium text,
  description text,
  birth_date date,
  death_date date,
  hometown text,
  blood_type text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now()
);

create table if not exists public.chapters (
  id integer default nextval('public.chapters_id_seq'::regclass) not null,
  manga_id integer not null,
  anilist_id integer,
  mal_id integer,
  number integer not null,
  title text,
  title_romaji text,
  description text,
  release_date date,
  release_at timestamp with time zone,
  thumbnail text,
  pages integer,
  is_side_story boolean default false,
  is_extra boolean default false,
  is_omake boolean default false,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.characters (
  id integer default nextval('public.characters_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  name_full text,
  name_native text,
  name_alternative text[],
  image_large text,
  image_medium text,
  description text,
  gender text,
  age integer,
  birthday date,
  blood_type text,
  height integer,
  weight integer,
  hair_color text,
  eye_color text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now()
);

create table if not exists public.club_rail_item_reactions (
  id uuid default gen_random_uuid() not null,
  rail_item_id uuid not null,
  user_id uuid not null,
  emoji text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.episodes (
  id integer default nextval('public.episodes_id_seq'::regclass) not null,
  anime_id integer not null,
  anilist_id integer,
  mal_id integer,
  number integer not null,
  title text,
  title_romaji text,
  description text,
  air_date date,
  air_at timestamp with time zone,
  thumbnail text,
  duration integer,
  is_filler boolean default false not null,
  is_recap boolean default false not null,
  is_mixed boolean default false not null,
  filler_source text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  stream_url text,
  stream_site text
);

create table if not exists public.external_links (
  id integer default nextval('public.external_links_id_seq'::regclass) not null,
  media_type text not null,
  media_id integer not null,
  site text,
  url text not null,
  language text,
  color text,
  priority integer default 999,
  is_disabled boolean default false not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.import_locks (
  lock_key text not null,
  locked_at timestamp with time zone default now() not null
);

create table if not exists public.import_runs (
  id bigint default nextval('public.import_runs_id_seq'::regclass) not null,
  media_type text not null,
  run_type text not null,
  status text not null,
  payload jsonb,
  results jsonb,
  message text,
  started_at timestamp with time zone default now() not null,
  finished_at timestamp with time zone,
  duration_ms integer
);

create table if not exists public.import_state (
  media_type text not null,
  last_page integer default 0 not null,
  updated_at timestamp with time zone default now()
);

create table if not exists public.manga (
  id integer default nextval('public.manga_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  title_synonyms text[],
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  banner_image text,
  format text,
  status text,
  description text,
  description_normalized text,
  chapters integer,
  volumes integer,
  next_chapter_number integer,
  next_chapter_at timestamp with time zone,
  start_date_year integer,
  start_date_month integer,
  start_date_day integer,
  end_date_year integer,
  end_date_month integer,
  end_date_day integer,
  average_score integer,
  mean_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[],
  source text,
  country_of_origin text,
  is_adult boolean default false not null,
  age_rating text,
  site_url text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  last_synced_at timestamp with time zone default now(),
  updated_at_anilist timestamp with time zone,
  synopsis_enhanced text,
  synopsis_enhanced_source text,
  synopsis_enhanced_model text,
  synopsis_enhanced_version text,
  synopsis_enhanced_updated_at timestamp with time zone,
  synopsis_enhanced_state text default 'pending'::text not null,
  synopsis_enhanced_retry_count integer default 0 not null,
  synopsis_enhanced_last_attempt_at timestamp with time zone,
  synopsis_enhanced_next_retry_at timestamp with time zone,
  synopsis_enhanced_last_error text,
  synopsis_enhanced_source_hash text,
  safety_state text default 'pending'::text not null,
  safety_blocked boolean default false not null,
  safety_reason_codes text[] default '{}'::text[] not null,
  safety_rule_hits text[] default '{}'::text[] not null,
  safety_model_label text,
  safety_model_confidence numeric(4,3),
  safety_model_rationale text,
  safety_suggested_lexicon text[] default '{}'::text[] not null,
  safety_source_hash text,
  safety_last_scanned_at timestamp with time zone,
  safety_last_attempt_at timestamp with time zone,
  safety_next_scan_at timestamp with time zone,
  safety_retry_count integer default 0 not null,
  safety_last_error text
);

create table if not exists public.manga_authors (
  id integer default nextval('public.manga_authors_id_seq'::regclass) not null,
  manga_id integer not null,
  author_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.manga_characters (
  id integer default nextval('public.manga_characters_id_seq'::regclass) not null,
  manga_id integer not null,
  character_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.manga_comments (
  id integer default nextval('public.manga_comments_id_seq'::regclass) not null,
  manga_id integer not null,
  user_id text not null,
  comment text not null,
  rating integer,
  is_spoiler boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists public.manga_staff (
  id integer default nextval('public.manga_staff_id_seq'::regclass) not null,
  manga_id integer not null,
  staff_id integer not null,
  role text,
  role_notes text,
  created_at timestamp with time zone default now()
);

create table if not exists public.manga_tags (
  id integer default nextval('public.manga_tags_id_seq'::regclass) not null,
  manga_id integer not null,
  tag_id integer not null,
  rank integer default 0,
  created_at timestamp with time zone default now()
);

create table if not exists public.manga_user_lists (
  id integer default nextval('public.manga_user_lists_id_seq'::regclass) not null,
  user_id text not null,
  manga_id integer not null,
  list_type text not null,
  progress integer default 0 not null,
  rating integer,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  verdict text
);

create table if not exists public.staff (
  id integer default nextval('public.staff_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  name_full text,
  name_native text,
  name_romaji text,
  image_large text,
  image_medium text,
  description text,
  primary_occupations text[],
  birth_date date,
  death_date date,
  hometown text,
  blood_type text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now()
);

create table if not exists public.studios (
  id integer default nextval('public.studios_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  kitsu_id integer,
  name text not null,
  name_romaji text,
  name_native text,
  description text,
  is_animation_studio boolean default false,
  is_producer boolean default false,
  is_licensor boolean default false,
  site_url text,
  favourites integer default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now()
);

create table if not exists public.tags (
  id integer default nextval('public.tags_id_seq'::regclass) not null,
  anilist_id integer,
  mal_id integer,
  name text not null,
  name_romaji text,
  name_native text,
  description text,
  category text,
  is_general_spoiler boolean default false,
  is_media_spoiler boolean default false,
  is_adult boolean default false,
  rank integer default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now(),
  kitsu_id integer
);

create table if not exists public.volumes (
  id integer default nextval('public.volumes_id_seq'::regclass) not null,
  manga_id integer not null,
  anilist_id integer,
  mal_id integer,
  number integer not null,
  title text,
  title_romaji text,
  description text,
  cover_image_large text,
  cover_image_medium text,
  release_date date,
  release_at timestamp with time zone,
  pages integer,
  isbn text,
  price_jpy integer,
  price_usd numeric(10,2),
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now()
);

alter sequence public.anime_id_seq owned by public.anime.id;
alter sequence public.anime_characters_id_seq owned by public.anime_characters.id;
alter sequence public.anime_comments_id_seq owned by public.anime_comments.id;
alter sequence public.anime_staff_id_seq owned by public.anime_staff.id;
alter sequence public.anime_studios_id_seq owned by public.anime_studios.id;
alter sequence public.anime_tags_id_seq owned by public.anime_tags.id;
alter sequence public.anime_user_lists_id_seq owned by public.anime_user_lists.id;
alter sequence public.authors_id_seq owned by public.authors.id;
alter sequence public.chapters_id_seq owned by public.chapters.id;
alter sequence public.characters_id_seq owned by public.characters.id;
alter sequence public.episodes_id_seq owned by public.episodes.id;
alter sequence public.external_links_id_seq owned by public.external_links.id;
alter sequence public.import_runs_id_seq owned by public.import_runs.id;
alter sequence public.manga_id_seq owned by public.manga.id;
alter sequence public.manga_authors_id_seq owned by public.manga_authors.id;
alter sequence public.manga_characters_id_seq owned by public.manga_characters.id;
alter sequence public.manga_comments_id_seq owned by public.manga_comments.id;
alter sequence public.manga_staff_id_seq owned by public.manga_staff.id;
alter sequence public.manga_tags_id_seq owned by public.manga_tags.id;
alter sequence public.manga_user_lists_id_seq owned by public.manga_user_lists.id;
alter sequence public.staff_id_seq owned by public.staff.id;
alter sequence public.studios_id_seq owned by public.studios.id;
alter sequence public.tags_id_seq owned by public.tags.id;
alter sequence public.volumes_id_seq owned by public.volumes.id;

-- ----------------------------------------------------------------------------
-- 3. Constraints (primary keys, unique, foreign keys, checks)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_pkey'
  ) then
    alter table public.anime add constraint anime_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_characters' and c.conname = 'anime_characters_pkey'
  ) then
    alter table public.anime_characters add constraint anime_characters_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_comments' and c.conname = 'anime_comments_pkey'
  ) then
    alter table public.anime_comments add constraint anime_comments_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_staff' and c.conname = 'anime_staff_pkey'
  ) then
    alter table public.anime_staff add constraint anime_staff_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_studios' and c.conname = 'anime_studios_pkey'
  ) then
    alter table public.anime_studios add constraint anime_studios_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_tags' and c.conname = 'anime_tags_pkey'
  ) then
    alter table public.anime_tags add constraint anime_tags_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_pkey'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'authors' and c.conname = 'authors_pkey'
  ) then
    alter table public.authors add constraint authors_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'chapters' and c.conname = 'chapters_pkey'
  ) then
    alter table public.chapters add constraint chapters_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'characters' and c.conname = 'characters_pkey'
  ) then
    alter table public.characters add constraint characters_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'club_rail_item_reactions' and c.conname = 'club_rail_item_reactions_pkey'
  ) then
    alter table public.club_rail_item_reactions add constraint club_rail_item_reactions_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'episodes' and c.conname = 'episodes_pkey'
  ) then
    alter table public.episodes add constraint episodes_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'external_links' and c.conname = 'external_links_pkey'
  ) then
    alter table public.external_links add constraint external_links_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'import_locks' and c.conname = 'import_locks_pkey'
  ) then
    alter table public.import_locks add constraint import_locks_pkey PRIMARY KEY (lock_key);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'import_runs' and c.conname = 'import_runs_pkey'
  ) then
    alter table public.import_runs add constraint import_runs_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'import_state' and c.conname = 'import_state_pkey'
  ) then
    alter table public.import_state add constraint import_state_pkey PRIMARY KEY (media_type);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_pkey'
  ) then
    alter table public.manga add constraint manga_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_authors' and c.conname = 'manga_authors_pkey'
  ) then
    alter table public.manga_authors add constraint manga_authors_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_characters' and c.conname = 'manga_characters_pkey'
  ) then
    alter table public.manga_characters add constraint manga_characters_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_comments' and c.conname = 'manga_comments_pkey'
  ) then
    alter table public.manga_comments add constraint manga_comments_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_staff' and c.conname = 'manga_staff_pkey'
  ) then
    alter table public.manga_staff add constraint manga_staff_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_tags' and c.conname = 'manga_tags_pkey'
  ) then
    alter table public.manga_tags add constraint manga_tags_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_pkey'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'staff' and c.conname = 'staff_pkey'
  ) then
    alter table public.staff add constraint staff_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'studios' and c.conname = 'studios_pkey'
  ) then
    alter table public.studios add constraint studios_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'tags' and c.conname = 'tags_pkey'
  ) then
    alter table public.tags add constraint tags_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'volumes' and c.conname = 'volumes_pkey'
  ) then
    alter table public.volumes add constraint volumes_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_anilist_id_key'
  ) then
    alter table public.anime add constraint anime_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_kitsu_id_key'
  ) then
    alter table public.anime add constraint anime_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_mal_id_key'
  ) then
    alter table public.anime add constraint anime_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_characters' and c.conname = 'anime_characters_anime_id_character_id_key'
  ) then
    alter table public.anime_characters add constraint anime_characters_anime_id_character_id_key UNIQUE (anime_id, character_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_staff' and c.conname = 'anime_staff_anime_id_staff_id_key'
  ) then
    alter table public.anime_staff add constraint anime_staff_anime_id_staff_id_key UNIQUE (anime_id, staff_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_studios' and c.conname = 'anime_studios_anime_id_studio_id_key'
  ) then
    alter table public.anime_studios add constraint anime_studios_anime_id_studio_id_key UNIQUE (anime_id, studio_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_tags' and c.conname = 'anime_tags_anime_id_tag_id_key'
  ) then
    alter table public.anime_tags add constraint anime_tags_anime_id_tag_id_key UNIQUE (anime_id, tag_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_user_id_anime_id_key'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_user_id_anime_id_key UNIQUE (user_id, anime_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'authors' and c.conname = 'authors_anilist_id_key'
  ) then
    alter table public.authors add constraint authors_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'authors' and c.conname = 'authors_kitsu_id_key'
  ) then
    alter table public.authors add constraint authors_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'authors' and c.conname = 'authors_mal_id_key'
  ) then
    alter table public.authors add constraint authors_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'chapters' and c.conname = 'chapters_anilist_id_key'
  ) then
    alter table public.chapters add constraint chapters_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'chapters' and c.conname = 'chapters_mal_id_key'
  ) then
    alter table public.chapters add constraint chapters_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'characters' and c.conname = 'characters_anilist_id_key'
  ) then
    alter table public.characters add constraint characters_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'characters' and c.conname = 'characters_kitsu_id_key'
  ) then
    alter table public.characters add constraint characters_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'characters' and c.conname = 'characters_mal_id_key'
  ) then
    alter table public.characters add constraint characters_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'club_rail_item_reactions' and c.conname = 'club_rail_item_reactions_rail_item_id_user_id_emoji_key'
  ) then
    alter table public.club_rail_item_reactions add constraint club_rail_item_reactions_rail_item_id_user_id_emoji_key UNIQUE (rail_item_id, user_id, emoji);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'episodes' and c.conname = 'episodes_anilist_id_key'
  ) then
    alter table public.episodes add constraint episodes_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'episodes' and c.conname = 'episodes_mal_id_key'
  ) then
    alter table public.episodes add constraint episodes_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'external_links' and c.conname = 'external_links_media_type_media_id_url_key'
  ) then
    alter table public.external_links add constraint external_links_media_type_media_id_url_key UNIQUE (media_type, media_id, url);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_anilist_id_key'
  ) then
    alter table public.manga add constraint manga_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_kitsu_id_key'
  ) then
    alter table public.manga add constraint manga_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_mal_id_key'
  ) then
    alter table public.manga add constraint manga_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_authors' and c.conname = 'manga_authors_manga_id_author_id_key'
  ) then
    alter table public.manga_authors add constraint manga_authors_manga_id_author_id_key UNIQUE (manga_id, author_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_characters' and c.conname = 'manga_characters_manga_id_character_id_key'
  ) then
    alter table public.manga_characters add constraint manga_characters_manga_id_character_id_key UNIQUE (manga_id, character_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_staff' and c.conname = 'manga_staff_manga_id_staff_id_key'
  ) then
    alter table public.manga_staff add constraint manga_staff_manga_id_staff_id_key UNIQUE (manga_id, staff_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_tags' and c.conname = 'manga_tags_manga_id_tag_id_key'
  ) then
    alter table public.manga_tags add constraint manga_tags_manga_id_tag_id_key UNIQUE (manga_id, tag_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_user_id_manga_id_key'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_user_id_manga_id_key UNIQUE (user_id, manga_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'staff' and c.conname = 'staff_anilist_id_key'
  ) then
    alter table public.staff add constraint staff_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'staff' and c.conname = 'staff_kitsu_id_key'
  ) then
    alter table public.staff add constraint staff_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'staff' and c.conname = 'staff_mal_id_key'
  ) then
    alter table public.staff add constraint staff_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'studios' and c.conname = 'studios_anilist_id_key'
  ) then
    alter table public.studios add constraint studios_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'studios' and c.conname = 'studios_kitsu_id_key'
  ) then
    alter table public.studios add constraint studios_kitsu_id_key UNIQUE (kitsu_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'studios' and c.conname = 'studios_mal_id_key'
  ) then
    alter table public.studios add constraint studios_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'tags' and c.conname = 'tags_anilist_id_key'
  ) then
    alter table public.tags add constraint tags_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'tags' and c.conname = 'tags_mal_id_key'
  ) then
    alter table public.tags add constraint tags_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'volumes' and c.conname = 'volumes_anilist_id_key'
  ) then
    alter table public.volumes add constraint volumes_anilist_id_key UNIQUE (anilist_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'volumes' and c.conname = 'volumes_mal_id_key'
  ) then
    alter table public.volumes add constraint volumes_mal_id_key UNIQUE (mal_id);
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_safety_state_check'
  ) then
    alter table public.anime add constraint anime_safety_state_check CHECK ((safety_state = ANY (ARRAY['pending'::text, 'safe'::text, 'blocked'::text, 'uncertain'::text, 'failed'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime' and c.conname = 'anime_synopsis_enhanced_state_check'
  ) then
    alter table public.anime add constraint anime_synopsis_enhanced_state_check CHECK ((synopsis_enhanced_state = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_comments' and c.conname = 'anime_comments_rating_check'
  ) then
    alter table public.anime_comments add constraint anime_comments_rating_check CHECK (((rating >= 1) AND (rating <= 10)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_list_type_check'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_list_type_check CHECK ((list_type = ANY (ARRAY['WATCHING'::text, 'PLANNING'::text, 'COMPLETED'::text, 'DROPPED'::text, 'PAUSED'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_progress_check'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_progress_check CHECK (((progress IS NULL) OR (progress >= 0)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_rating_check'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_rating_check CHECK (((rating >= 1) AND (rating <= 10)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_verdict_check'
  ) then
    alter table public.anime_user_lists add constraint anime_user_lists_verdict_check CHECK (((verdict IS NULL) OR (verdict = ANY (ARRAY['MASTERPIECE'::text, 'OKAY'::text, 'BAD'::text]))));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'club_rail_item_reactions' and c.conname = 'club_rail_item_reactions_emoji_check'
  ) then
    alter table public.club_rail_item_reactions add constraint club_rail_item_reactions_emoji_check CHECK (((char_length(emoji) >= 1) AND (char_length(emoji) <= 8)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'external_links' and c.conname = 'external_links_media_type_check'
  ) then
    alter table public.external_links add constraint external_links_media_type_check CHECK ((media_type = ANY (ARRAY['ANIME'::text, 'MANGA'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_safety_state_check'
  ) then
    alter table public.manga add constraint manga_safety_state_check CHECK ((safety_state = ANY (ARRAY['pending'::text, 'safe'::text, 'blocked'::text, 'uncertain'::text, 'failed'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga' and c.conname = 'manga_synopsis_enhanced_state_check'
  ) then
    alter table public.manga add constraint manga_synopsis_enhanced_state_check CHECK ((synopsis_enhanced_state = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_comments' and c.conname = 'manga_comments_rating_check'
  ) then
    alter table public.manga_comments add constraint manga_comments_rating_check CHECK (((rating >= 1) AND (rating <= 10)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_list_type_check'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_list_type_check CHECK ((list_type = ANY (ARRAY['WATCHING'::text, 'READING'::text, 'PLANNING'::text, 'COMPLETED'::text, 'DROPPED'::text, 'PAUSED'::text])));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_progress_check'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_progress_check CHECK (((progress IS NULL) OR (progress >= 0)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_rating_check'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_rating_check CHECK (((rating >= 1) AND (rating <= 10)));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_verdict_check'
  ) then
    alter table public.manga_user_lists add constraint manga_user_lists_verdict_check CHECK (((verdict IS NULL) OR (verdict = ANY (ARRAY['MASTERPIECE'::text, 'OKAY'::text, 'BAD'::text]))));
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_characters' and c.conname = 'anime_characters_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_characters add constraint anime_characters_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_characters' and c.conname = 'anime_characters_character_id_fkey'
  )
    and to_regclass('public.characters') is not null then
    alter table public.anime_characters add constraint anime_characters_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_comments' and c.conname = 'anime_comments_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_comments add constraint anime_comments_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_staff' and c.conname = 'anime_staff_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_staff add constraint anime_staff_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_staff' and c.conname = 'anime_staff_staff_id_fkey'
  )
    and to_regclass('public.staff') is not null then
    alter table public.anime_staff add constraint anime_staff_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_studios' and c.conname = 'anime_studios_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_studios add constraint anime_studios_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_studios' and c.conname = 'anime_studios_studio_id_fkey'
  )
    and to_regclass('public.studios') is not null then
    alter table public.anime_studios add constraint anime_studios_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_tags' and c.conname = 'anime_tags_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_tags add constraint anime_tags_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_tags' and c.conname = 'anime_tags_tag_id_fkey'
  )
    and to_regclass('public.tags') is not null then
    alter table public.anime_tags add constraint anime_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'anime_user_lists' and c.conname = 'anime_user_lists_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.anime_user_lists add constraint anime_user_lists_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'chapters' and c.conname = 'chapters_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.chapters add constraint chapters_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'club_rail_item_reactions' and c.conname = 'club_rail_item_reactions_rail_item_id_fkey'
  )
    and to_regclass('public.club_rail_items') is not null then
    alter table public.club_rail_item_reactions add constraint club_rail_item_reactions_rail_item_id_fkey FOREIGN KEY (rail_item_id) REFERENCES public.club_rail_items(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'club_rail_item_reactions' and c.conname = 'club_rail_item_reactions_user_id_fkey'
  )
    and to_regclass('auth.users') is not null then
    alter table public.club_rail_item_reactions add constraint club_rail_item_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'episodes' and c.conname = 'episodes_anime_id_fkey'
  )
    and to_regclass('public.anime') is not null then
    alter table public.episodes add constraint episodes_anime_id_fkey FOREIGN KEY (anime_id) REFERENCES public.anime(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_authors' and c.conname = 'manga_authors_author_id_fkey'
  )
    and to_regclass('public.authors') is not null then
    alter table public.manga_authors add constraint manga_authors_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_authors' and c.conname = 'manga_authors_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_authors add constraint manga_authors_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_characters' and c.conname = 'manga_characters_character_id_fkey'
  )
    and to_regclass('public.characters') is not null then
    alter table public.manga_characters add constraint manga_characters_character_id_fkey FOREIGN KEY (character_id) REFERENCES public.characters(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_characters' and c.conname = 'manga_characters_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_characters add constraint manga_characters_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_comments' and c.conname = 'manga_comments_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_comments add constraint manga_comments_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_staff' and c.conname = 'manga_staff_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_staff add constraint manga_staff_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_staff' and c.conname = 'manga_staff_staff_id_fkey'
  )
    and to_regclass('public.staff') is not null then
    alter table public.manga_staff add constraint manga_staff_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_tags' and c.conname = 'manga_tags_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_tags add constraint manga_tags_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_tags' and c.conname = 'manga_tags_tag_id_fkey'
  )
    and to_regclass('public.tags') is not null then
    alter table public.manga_tags add constraint manga_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'manga_user_lists' and c.conname = 'manga_user_lists_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.manga_user_lists add constraint manga_user_lists_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'volumes' and c.conname = 'volumes_manga_id_fkey'
  )
    and to_regclass('public.manga') is not null then
    alter table public.volumes add constraint volumes_manga_id_fkey FOREIGN KEY (manga_id) REFERENCES public.manga(id) ON DELETE CASCADE;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 4. Indexes (constraint-backed indexes are created by section 3)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_anime_anilist_id ON public.anime USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_anime_average_score ON public.anime USING btree (average_score DESC);
CREATE INDEX IF NOT EXISTS idx_anime_created_at ON public.anime USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anime_genres ON public.anime USING gin (genres);
CREATE INDEX IF NOT EXISTS idx_anime_id ON public.anime USING btree (id);
CREATE INDEX IF NOT EXISTS idx_anime_mal_id ON public.anime USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_anime_next_airing_at ON public.anime USING btree (next_airing_at);
CREATE INDEX IF NOT EXISTS idx_anime_popularity ON public.anime USING btree (popularity DESC);
CREATE INDEX IF NOT EXISTS idx_anime_popularity_id ON public.anime USING btree (popularity DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_anime_safety_blocked ON public.anime USING btree (safety_blocked, id) WHERE (safety_blocked = true);
CREATE INDEX IF NOT EXISTS idx_anime_safety_queue ON public.anime USING btree (safety_state, safety_next_scan_at, safety_last_scanned_at, id);
CREATE INDEX IF NOT EXISTS idx_anime_score_id ON public.anime USING btree (average_score DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_anime_season_year ON public.anime USING btree (season_year);
CREATE INDEX IF NOT EXISTS idx_anime_season_year_popularity_id ON public.anime USING btree (season, season_year, popularity DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_anime_status ON public.anime USING btree (status);
CREATE INDEX IF NOT EXISTS idx_anime_status_popularity_id ON public.anime USING btree (status, popularity DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_anime_synopsis_enhanced_queue ON public.anime USING btree (synopsis_enhanced_state, synopsis_enhanced_updated_at, updated_at) WHERE (description IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_anime_synopsis_retry_queue ON public.anime USING btree (synopsis_enhanced_state, synopsis_enhanced_next_retry_at, synopsis_enhanced_updated_at, updated_at) WHERE (description IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_anime_title_english ON public.anime USING btree (title_english);
CREATE INDEX IF NOT EXISTS idx_anime_title_romaji ON public.anime USING btree (title_romaji);
CREATE INDEX IF NOT EXISTS idx_anime_trending ON public.anime USING btree (trending DESC);
CREATE INDEX IF NOT EXISTS idx_anime_trending_id ON public.anime USING btree (trending DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_anime_characters_anime_id ON public.anime_characters USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_characters_character_id ON public.anime_characters USING btree (character_id);
CREATE INDEX IF NOT EXISTS idx_anime_comments_anime_id ON public.anime_comments USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_comments_user_id ON public.anime_comments USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_anime_staff_anime_id ON public.anime_staff USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_staff_staff_id ON public.anime_staff USING btree (staff_id);
CREATE INDEX IF NOT EXISTS idx_anime_studios_anime_id ON public.anime_studios USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_studios_studio_id ON public.anime_studios USING btree (studio_id);
CREATE INDEX IF NOT EXISTS idx_anime_tags_anime_id ON public.anime_tags USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_tags_tag_id ON public.anime_tags USING btree (tag_id);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_anime_id ON public.anime_user_lists USING btree (anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_list_type ON public.anime_user_lists USING btree (list_type);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_user_id ON public.anime_user_lists USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_user_updated_id ON public.anime_user_lists USING btree (user_id, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_authors_anilist_id ON public.authors USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_authors_id ON public.authors USING btree (id);
CREATE INDEX IF NOT EXISTS idx_authors_mal_id ON public.authors USING btree (mal_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chapters_manga_id_number_unique ON public.chapters USING btree (manga_id, number) WHERE (number IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_characters_anilist_id ON public.characters USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_characters_id ON public.characters USING btree (id);
CREATE INDEX IF NOT EXISTS idx_characters_mal_id ON public.characters USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_club_reactions_item ON public.club_rail_item_reactions USING btree (rail_item_id);
CREATE INDEX IF NOT EXISTS idx_club_reactions_user ON public.club_rail_item_reactions USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_episodes_anime_id_number_unique ON public.episodes USING btree (anime_id, number) WHERE (number IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_external_links_media ON public.external_links USING btree (media_type, media_id);
CREATE INDEX IF NOT EXISTS idx_import_runs_media_started_at ON public.import_runs USING btree (media_type, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_import_runs_status ON public.import_runs USING btree (status);
CREATE INDEX IF NOT EXISTS idx_manga_anilist_id ON public.manga USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_manga_average_score ON public.manga USING btree (average_score DESC);
CREATE INDEX IF NOT EXISTS idx_manga_created_at ON public.manga USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_manga_id ON public.manga USING btree (id);
CREATE INDEX IF NOT EXISTS idx_manga_mal_id ON public.manga USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_manga_next_chapter ON public.manga USING btree (next_chapter_at);
CREATE INDEX IF NOT EXISTS idx_manga_popularity ON public.manga USING btree (popularity DESC);
CREATE INDEX IF NOT EXISTS idx_manga_popularity_id ON public.manga USING btree (popularity DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_manga_safety_blocked ON public.manga USING btree (safety_blocked, id) WHERE (safety_blocked = true);
CREATE INDEX IF NOT EXISTS idx_manga_safety_queue ON public.manga USING btree (safety_state, safety_next_scan_at, safety_last_scanned_at, id);
CREATE INDEX IF NOT EXISTS idx_manga_score_id ON public.manga USING btree (average_score DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_manga_status ON public.manga USING btree (status);
CREATE INDEX IF NOT EXISTS idx_manga_synopsis_enhanced_queue ON public.manga USING btree (synopsis_enhanced_state, synopsis_enhanced_updated_at, updated_at) WHERE (description IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_manga_synopsis_retry_queue ON public.manga USING btree (synopsis_enhanced_state, synopsis_enhanced_next_retry_at, synopsis_enhanced_updated_at, updated_at) WHERE (description IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_manga_title_english ON public.manga USING btree (title_english);
CREATE INDEX IF NOT EXISTS idx_manga_title_romaji ON public.manga USING btree (title_romaji);
CREATE INDEX IF NOT EXISTS idx_manga_trending ON public.manga USING btree (trending DESC);
CREATE INDEX IF NOT EXISTS idx_manga_trending_id ON public.manga USING btree (trending DESC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_manga_authors_author_id ON public.manga_authors USING btree (author_id);
CREATE INDEX IF NOT EXISTS idx_manga_authors_manga_id ON public.manga_authors USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_characters_character_id ON public.manga_characters USING btree (character_id);
CREATE INDEX IF NOT EXISTS idx_manga_characters_manga_id ON public.manga_characters USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_comments_manga_id ON public.manga_comments USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_comments_user_id ON public.manga_comments USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_manga_staff_manga_id ON public.manga_staff USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_staff_staff_id ON public.manga_staff USING btree (staff_id);
CREATE INDEX IF NOT EXISTS idx_manga_tags_manga_id ON public.manga_tags USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_tags_tag_id ON public.manga_tags USING btree (tag_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_list_type ON public.manga_user_lists USING btree (list_type);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_manga_id ON public.manga_user_lists USING btree (manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_user_id ON public.manga_user_lists USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_user_updated_id ON public.manga_user_lists USING btree (user_id, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_staff_anilist_id ON public.staff USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_staff_id ON public.staff USING btree (id);
CREATE INDEX IF NOT EXISTS idx_staff_mal_id ON public.staff USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_studios_anilist_id ON public.studios USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_studios_id ON public.studios USING btree (id);
CREATE INDEX IF NOT EXISTS idx_studios_mal_id ON public.studios USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_tags_anilist_id ON public.tags USING btree (anilist_id);
CREATE INDEX IF NOT EXISTS idx_tags_id ON public.tags USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_kitsu_id_unique ON public.tags USING btree (kitsu_id) WHERE (kitsu_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_tags_mal_id ON public.tags USING btree (mal_id);
CREATE INDEX IF NOT EXISTS idx_volumes_id ON public.volumes USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_volumes_manga_id_number_unique ON public.volumes USING btree (manga_id, number) WHERE (number IS NOT NULL);

-- ----------------------------------------------------------------------------
-- 5. Remote-only trigger functions (referenced by triggers in section 6,
--    never present in the migration chain)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_description()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    IF NEW.description IS NOT NULL THEN
        -- Remove HTML tags, convert to lowercase, remove extra whitespace
        NEW.description_normalized = LOWER(
            regexp_replace(
                regexp_replace(NEW.description, '<[^>]+>', '', 'g'),
                '\s+', ' ', 'g'
            )
        );
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 6. Triggers (guarded on both trigger absence and executor function presence;
--    protect_mirrored_image_columns / taste_* functions come from earlier
--    chain migrations 20260731020000 / 20260730160000)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'protect_mirrored_image_columns_anime')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'protect_mirrored_image_columns'
     ) then
    CREATE TRIGGER protect_mirrored_image_columns_anime BEFORE UPDATE ON public.anime FOR EACH ROW EXECUTE FUNCTION protect_mirrored_image_columns();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'set_anime_description_normalized')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'normalize_description'
     ) then
    CREATE TRIGGER set_anime_description_normalized BEFORE INSERT OR UPDATE OF description ON public.anime FOR EACH ROW EXECUTE FUNCTION normalize_description();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_anime_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_anime_updated_at BEFORE UPDATE ON public.anime FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'taste_bump_anime_user_lists_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'taste_bump_list_updated_at'
     ) then
    CREATE TRIGGER taste_bump_anime_user_lists_updated_at BEFORE UPDATE ON public.anime_user_lists FOR EACH ROW EXECUTE FUNCTION taste_bump_list_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'taste_capture_anime_user_lists')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'taste_capture_list_mutation'
     ) then
    CREATE TRIGGER taste_capture_anime_user_lists AFTER INSERT OR DELETE OR UPDATE ON public.anime_user_lists FOR EACH ROW EXECUTE FUNCTION taste_capture_list_mutation();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_authors_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_authors_updated_at BEFORE UPDATE ON public.authors FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_chapters_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON public.chapters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'protect_mirrored_image_columns_characters')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'protect_mirrored_image_columns'
     ) then
    CREATE TRIGGER protect_mirrored_image_columns_characters BEFORE UPDATE ON public.characters FOR EACH ROW EXECUTE FUNCTION protect_mirrored_image_columns();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_characters_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON public.characters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_episodes_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_episodes_updated_at BEFORE UPDATE ON public.episodes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'protect_mirrored_image_columns_manga')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'protect_mirrored_image_columns'
     ) then
    CREATE TRIGGER protect_mirrored_image_columns_manga BEFORE UPDATE ON public.manga FOR EACH ROW EXECUTE FUNCTION protect_mirrored_image_columns();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'set_manga_description_normalized')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'normalize_description'
     ) then
    CREATE TRIGGER set_manga_description_normalized BEFORE INSERT OR UPDATE OF description ON public.manga FOR EACH ROW EXECUTE FUNCTION normalize_description();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_manga_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_manga_updated_at BEFORE UPDATE ON public.manga FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'taste_bump_manga_user_lists_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'taste_bump_list_updated_at'
     ) then
    CREATE TRIGGER taste_bump_manga_user_lists_updated_at BEFORE UPDATE ON public.manga_user_lists FOR EACH ROW EXECUTE FUNCTION taste_bump_list_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'taste_capture_manga_user_lists')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'taste_capture_list_mutation'
     ) then
    CREATE TRIGGER taste_capture_manga_user_lists AFTER INSERT OR DELETE OR UPDATE ON public.manga_user_lists FOR EACH ROW EXECUTE FUNCTION taste_capture_list_mutation();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'protect_mirrored_image_columns_staff')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'protect_mirrored_image_columns'
     ) then
    CREATE TRIGGER protect_mirrored_image_columns_staff BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION protect_mirrored_image_columns();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_staff_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_studios_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_studios_updated_at BEFORE UPDATE ON public.studios FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_tags_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON public.tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'update_volumes_updated_at')
     and exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'update_updated_at_column'
     ) then
    CREATE TRIGGER update_volumes_updated_at BEFORE UPDATE ON public.volumes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 7. Row level security (all 27 tables RLS-enabled in prod, none forced)
-- ----------------------------------------------------------------------------
alter table public.anime enable row level security;
alter table public.anime_characters enable row level security;
alter table public.anime_comments enable row level security;
alter table public.anime_staff enable row level security;
alter table public.anime_studios enable row level security;
alter table public.anime_tags enable row level security;
alter table public.anime_user_lists enable row level security;
alter table public.authors enable row level security;
alter table public.chapters enable row level security;
alter table public.characters enable row level security;
alter table public.club_rail_item_reactions enable row level security;
alter table public.episodes enable row level security;
alter table public.external_links enable row level security;
alter table public.import_locks enable row level security;
alter table public.import_runs enable row level security;
alter table public.import_state enable row level security;
alter table public.manga enable row level security;
alter table public.manga_authors enable row level security;
alter table public.manga_characters enable row level security;
alter table public.manga_comments enable row level security;
alter table public.manga_staff enable row level security;
alter table public.manga_tags enable row level security;
alter table public.manga_user_lists enable row level security;
alter table public.staff enable row level security;
alter table public.studios enable row level security;
alter table public.tags enable row level security;
alter table public.volumes enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.anime as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_characters' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.anime_characters as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_comments' and policyname = 'Users can manage their own comments'
  )
     and to_regprocedure('auth.uid()') is not null then
    create policy "Users can manage their own comments" on public.anime_comments as permissive for all to authenticated using (((( SELECT auth.uid() AS uid))::text = user_id)) with check (((( SELECT auth.uid() AS uid))::text = user_id));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_staff' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.anime_staff as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_studios' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.anime_studios as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_tags' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.anime_tags as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'anime_user_lists' and policyname = 'Users can manage their own lists'
  )
     and to_regprocedure('auth.uid()') is not null then
    create policy "Users can manage their own lists" on public.anime_user_lists as permissive for all to authenticated using (((( SELECT auth.uid() AS uid))::text = user_id)) with check (((( SELECT auth.uid() AS uid))::text = user_id));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'authors' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.authors as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'chapters' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.chapters as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'characters' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.characters as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'club_rail_item_reactions' and policyname = 'club_reactions_delete_own'
  )
     and to_regprocedure('auth.uid()') is not null then
    create policy "club_reactions_delete_own" on public.club_rail_item_reactions as permissive for delete to authenticated using ((auth.uid() = user_id));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'club_rail_item_reactions' and policyname = 'club_reactions_insert_member'
  )
     and to_regprocedure('auth.uid()') is not null
     and to_regclass('public.club_rail_items') is not null
     and to_regclass('public.club_rails') is not null
     and exists (select 1 from pg_proc f join pg_namespace fn on fn.oid = f.pronamespace
         where fn.nspname = 'public' and f.proname = 'is_club_member') then
    create policy "club_reactions_insert_member" on public.club_rail_item_reactions as permissive for insert to authenticated with check (((auth.uid() = user_id) AND (EXISTS ( SELECT 1
   FROM (club_rail_items cri
     JOIN club_rails cr ON ((cri.rail_id = cr.id)))
  WHERE ((cri.id = club_rail_item_reactions.rail_item_id) AND is_club_member(cr.club_id))))));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'club_rail_item_reactions' and policyname = 'club_reactions_select_member'
  )
     and to_regclass('public.club_rail_items') is not null
     and to_regclass('public.club_rails') is not null
     and exists (select 1 from pg_proc f join pg_namespace fn on fn.oid = f.pronamespace
         where fn.nspname = 'public' and f.proname = 'is_club_member') then
    create policy "club_reactions_select_member" on public.club_rail_item_reactions as permissive for select to public using ((EXISTS ( SELECT 1
   FROM (club_rail_items cri
     JOIN club_rails cr ON ((cri.rail_id = cr.id)))
  WHERE ((cri.id = club_rail_item_reactions.rail_item_id) AND is_club_member(cr.club_id)))));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'episodes' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.episodes as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'external_links' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.external_links as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.manga as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_authors' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.manga_authors as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_characters' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.manga_characters as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_comments' and policyname = 'Users can manage their own comments'
  )
     and to_regprocedure('auth.uid()') is not null then
    create policy "Users can manage their own comments" on public.manga_comments as permissive for all to authenticated using (((( SELECT auth.uid() AS uid))::text = user_id)) with check (((( SELECT auth.uid() AS uid))::text = user_id));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_staff' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.manga_staff as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_tags' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.manga_tags as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'manga_user_lists' and policyname = 'Users can manage their own lists'
  )
     and to_regprocedure('auth.uid()') is not null then
    create policy "Users can manage their own lists" on public.manga_user_lists as permissive for all to authenticated using (((( SELECT auth.uid() AS uid))::text = user_id)) with check (((( SELECT auth.uid() AS uid))::text = user_id));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'staff' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.staff as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'studios' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.studios as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'tags' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.tags as permissive for select to public using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'volumes' and policyname = 'Public read access'
  ) then
    create policy "Public read access" on public.volumes as permissive for select to public using (true);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 8. RPCs captured from prod (import locks were remote-only; create_club_rail /
--    create_club_poll come from the four hollowed 2026-02-15 migrations).
--    DROP IF EXISTS + CREATE per capture; SET search_path preserved from prod.
-- ----------------------------------------------------------------------------
drop function if exists public.acquire_import_lock(text, integer);
CREATE OR REPLACE FUNCTION public.acquire_import_lock(p_key text, p_ttl_seconds integer DEFAULT 1800)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
     DECLARE acquired boolean;
     BEGIN
       INSERT INTO public.import_locks (lock_key, locked_at)
       VALUES (p_key, now())
       ON CONFLICT (lock_key) DO UPDATE
         SET locked_at = EXCLUDED.locked_at
         WHERE public.import_locks.locked_at < now() - make_interval(secs => p_ttl_seconds)
       RETURNING true INTO acquired;
       IF acquired IS NULL THEN
         RETURN false;
       END IF;
       RETURN true;
     END;
     $function$;
do $$
begin
  if to_regrole('anon') is not null then
    grant execute on function public.acquire_import_lock(text, integer) to anon;
  end if;
  if to_regrole('authenticated') is not null then
    grant execute on function public.acquire_import_lock(text, integer) to authenticated;
  end if;
  if to_regrole('service_role') is not null then
    grant execute on function public.acquire_import_lock(text, integer) to service_role;
  end if;
end $$;

drop function if exists public.create_club_poll(uuid, text, text[], timestamp with time zone);
CREATE OR REPLACE FUNCTION public.create_club_poll(p_club_id uuid, p_question text, p_options text[], p_closes_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid;
  _is_member boolean;
  _clean_question text;
  _poll_id uuid;
  _option_label text;
  _sort int := 0;
  _options_out jsonb := '[]'::jsonb;
  _option_id uuid;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Any member can create polls
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Sanitize question
  _clean_question := regexp_replace(trim(p_question), '[\x00-\x1F\x7F]', '', 'g');
  IF _clean_question IS NULL OR char_length(_clean_question) = 0 THEN
    RAISE EXCEPTION 'INVALID_QUESTION: question must not be empty' USING ERRCODE = 'P0001';
  END IF;
  IF char_length(_clean_question) > 200 THEN
    RAISE EXCEPTION 'INVALID_QUESTION: question must be <= 200 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Validate options
  IF p_options IS NULL OR array_length(p_options, 1) < 2 THEN
    RAISE EXCEPTION 'INVALID_OPTIONS: at least 2 options required' USING ERRCODE = 'P0001';
  END IF;
  IF array_length(p_options, 1) > 10 THEN
    RAISE EXCEPTION 'INVALID_OPTIONS: max 10 options' USING ERRCODE = 'P0001';
  END IF;

  -- Validate closes_at is in the future (if provided)
  IF p_closes_at IS NOT NULL AND p_closes_at <= now() THEN
    RAISE EXCEPTION 'INVALID_CLOSES_AT: must be in the future' USING ERRCODE = 'P0001';
  END IF;

  -- Insert poll
  INSERT INTO public.club_polls (club_id, question, created_by, closes_at)
  VALUES (p_club_id, _clean_question, _uid, p_closes_at)
  RETURNING id INTO _poll_id;

  -- Insert options
  FOREACH _option_label IN ARRAY p_options
  LOOP
    IF char_length(trim(_option_label)) > 120 THEN
      RAISE EXCEPTION 'OPTION_TOO_LONG: each option must be <= 120 characters' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.club_poll_options (poll_id, label, sort_order)
    VALUES (_poll_id, trim(_option_label), _sort)
    RETURNING id INTO _option_id;

    _options_out := _options_out || jsonb_build_array(jsonb_build_object(
      'id', _option_id,
      'label', trim(_option_label),
      'sort_order', _sort
    ));

    _sort := _sort + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'poll_id', _poll_id,
    'question', _clean_question,
    'options', _options_out
  );
END;
$function$;
do $$
begin
  if to_regrole('anon') is not null then
    grant execute on function public.create_club_poll(uuid, text, text[], timestamp with time zone) to anon;
  end if;
  if to_regrole('authenticated') is not null then
    grant execute on function public.create_club_poll(uuid, text, text[], timestamp with time zone) to authenticated;
  end if;
  if to_regrole('service_role') is not null then
    grant execute on function public.create_club_poll(uuid, text, text[], timestamp with time zone) to service_role;
  end if;
end $$;

drop function if exists public.create_club_rail(uuid, text, text);
CREATE OR REPLACE FUNCTION public.create_club_rail(p_club_id uuid, p_title text, p_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid;
  _is_admin boolean;
  _clean_title text;
  _next_sort int;
  _rail_id uuid;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Only owner/admin can create rails
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = _uid AND role IN ('owner', 'admin')
  ) INTO _is_admin;

  IF NOT _is_admin THEN
    RAISE EXCEPTION 'NOT_ADMIN: only owner or admin can create rails' USING ERRCODE = 'P0001';
  END IF;

  -- Sanitize title
  _clean_title := regexp_replace(trim(p_title), '[\x00-\x1F\x7F]', '', 'g');
  IF _clean_title IS NULL OR char_length(_clean_title) = 0 THEN
    RAISE EXCEPTION 'INVALID_TITLE: title must not be empty' USING ERRCODE = 'P0001';
  END IF;
  IF char_length(_clean_title) > 120 THEN
    RAISE EXCEPTION 'INVALID_TITLE: title must be <= 120 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Validate description length
  IF p_description IS NOT NULL AND char_length(p_description) > 500 THEN
    RAISE EXCEPTION 'DESCRIPTION_TOO_LONG: max 500 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Compute next sort_order
  SELECT COALESCE(max(sort_order), -1) + 1 INTO _next_sort
  FROM public.club_rails
  WHERE club_id = p_club_id;

  -- Insert rail
  INSERT INTO public.club_rails (club_id, title, description, created_by, sort_order)
  VALUES (p_club_id, _clean_title, p_description, _uid, _next_sort)
  RETURNING id INTO _rail_id;

  RETURN jsonb_build_object(
    'rail_id', _rail_id,
    'title', _clean_title,
    'sort_order', _next_sort
  );
END;
$function$;
do $$
begin
  if to_regrole('anon') is not null then
    grant execute on function public.create_club_rail(uuid, text, text) to anon;
  end if;
  if to_regrole('authenticated') is not null then
    grant execute on function public.create_club_rail(uuid, text, text) to authenticated;
  end if;
  if to_regrole('service_role') is not null then
    grant execute on function public.create_club_rail(uuid, text, text) to service_role;
  end if;
end $$;

drop function if exists public.release_import_lock(text);
CREATE OR REPLACE FUNCTION public.release_import_lock(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
     BEGIN
       DELETE FROM public.import_locks WHERE lock_key = p_key;
       RETURN FOUND;
     END;
     $function$;
do $$
begin
  if to_regrole('anon') is not null then
    grant execute on function public.release_import_lock(text) to anon;
  end if;
  if to_regrole('authenticated') is not null then
    grant execute on function public.release_import_lock(text) to authenticated;
  end if;
  if to_regrole('service_role') is not null then
    grant execute on function public.release_import_lock(text) to service_role;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 9. The 7 remote-only materialized views (from pg_get_viewdef, FROM clause
--    schema-qualified; refreshed by the kuro-refresh-matviews cron, section 10)
-- ----------------------------------------------------------------------------
create materialized view if not exists public.mv_anime_current_season as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.anime
  WHERE ((status = 'RELEASING'::text) AND (season_year IS NOT NULL) AND (season_year >= ((EXTRACT(year FROM now()))::integer - 1)))
with data;

create materialized view if not exists public.mv_anime_newly_added as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.anime
with data;

create materialized view if not exists public.mv_anime_top_rated as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.anime
  WHERE ((average_score IS NOT NULL) AND (average_score >= 80))
with data;

create materialized view if not exists public.mv_anime_trending as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    episodes,
    duration,
    total_duration,
    season,
    season_year,
    next_episode_number,
    next_airing_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.anime
  WHERE ((trending IS NOT NULL) AND (trending > 0))
with data;

create materialized view if not exists public.mv_manga_newly_added as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    chapters,
    volumes,
    next_chapter_number,
    next_chapter_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.manga
with data;

create materialized view if not exists public.mv_manga_top_rated as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    chapters,
    volumes,
    next_chapter_number,
    next_chapter_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.manga
  WHERE ((average_score IS NOT NULL) AND (average_score >= 80))
with data;

create materialized view if not exists public.mv_manga_trending as
SELECT id,
    anilist_id,
    mal_id,
    kitsu_id,
    title_english,
    title_romaji,
    title_native,
    title_synonyms,
    cover_image_large,
    cover_image_medium,
    cover_image_color,
    banner_image,
    format,
    status,
    description,
    description_normalized,
    chapters,
    volumes,
    next_chapter_number,
    next_chapter_at,
    start_date_year,
    start_date_month,
    start_date_day,
    end_date_year,
    end_date_month,
    end_date_day,
    average_score,
    mean_score,
    popularity,
    trending,
    favourites,
    genres,
    source,
    country_of_origin,
    is_adult,
    age_rating,
    site_url,
    created_at,
    updated_at,
    last_synced_at,
    updated_at_anilist
   FROM public.manga
  WHERE ((trending IS NOT NULL) AND (trending > 0))
with data;

-- existing prod indexes on the matviews:
CREATE INDEX IF NOT EXISTS idx_mv_anime_current_season_popularity ON public.mv_anime_current_season USING btree (popularity DESC);
CREATE INDEX IF NOT EXISTS idx_mv_anime_newly_added_created ON public.mv_anime_newly_added USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mv_anime_top_rated_score ON public.mv_anime_top_rated USING btree (average_score DESC);
CREATE INDEX IF NOT EXISTS idx_mv_anime_trending_trending ON public.mv_anime_trending USING btree (trending DESC);
CREATE INDEX IF NOT EXISTS idx_mv_manga_newly_added_created ON public.mv_manga_newly_added USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mv_manga_top_rated_score ON public.mv_manga_top_rated USING btree (average_score DESC);
CREATE INDEX IF NOT EXISTS idx_mv_manga_trending_trending ON public.mv_manga_trending USING btree (trending DESC);

-- unique indexes for REFRESH MATERIALIZED VIEW CONCURRENTLY: none of the 7
-- matviews had one in prod (verified 2026-08-07, pg_indexes). id is the base
-- table primary key, hence unique per matview row.
create unique index if not exists mv_anime_current_season_id_uidx on public.mv_anime_current_season (id);
create unique index if not exists mv_anime_newly_added_id_uidx on public.mv_anime_newly_added (id);
create unique index if not exists mv_anime_top_rated_id_uidx on public.mv_anime_top_rated (id);
create unique index if not exists mv_anime_trending_id_uidx on public.mv_anime_trending (id);
create unique index if not exists mv_manga_newly_added_id_uidx on public.mv_manga_newly_added (id);
create unique index if not exists mv_manga_top_rated_id_uidx on public.mv_manga_top_rated (id);
create unique index if not exists mv_manga_trending_id_uidx on public.mv_manga_trending (id);

-- ----------------------------------------------------------------------------
-- 10. kuro-refresh-matviews cron (remote-only, jobid 11 in prod; schedule and
--     command captured verbatim from cron.job). Re-registered idempotently:
--     unschedule-by-name then schedule. Guarded on pg_cron being installed.
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and to_regnamespace('cron') is not null then
    perform cron.unschedule('kuro-refresh-matviews');
    perform cron.schedule(
      'kuro-refresh-matviews',
      '30 1 * * *',
      $cmd$
        REFRESH MATERIALIZED VIEW public.mv_anime_trending;
        REFRESH MATERIALIZED VIEW public.mv_anime_top_rated;
        REFRESH MATERIALIZED VIEW public.mv_anime_current_season;
        REFRESH MATERIALIZED VIEW public.mv_anime_newly_added;
        REFRESH MATERIALIZED VIEW public.mv_manga_trending;
        REFRESH MATERIALIZED VIEW public.mv_manga_top_rated;
        REFRESH MATERIALIZED VIEW public.mv_manga_newly_added;
        $cmd$
    );
  end if;
end $$;
