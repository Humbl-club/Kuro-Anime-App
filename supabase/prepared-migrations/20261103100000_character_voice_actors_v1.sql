-- 20261103100000_character_voice_actors_v1.sql
-- PREPARED, NOT DEPLOYED (2026-11-03 details/songs pass, DATA lane). Deploying needs explicit
-- owner approval. Nothing here schedules a job or writes catalogue data.
--
-- What it adds (owner item 4: characters + cast, voice actors):
--   1. public.character_voice_actors: one row per (anime, character, voice actor, language),
--      written by bulk-import-anime from AniList characters.edges.voiceActors(language: JAPANESE).
--      Local ids only (anime.id, characters.id, staff.id), ON DELETE CASCADE from all three.
--      RLS on: public SELECT (catalogue data, like anime_characters / staff), NO client writes
--      (INSERT/UPDATE/DELETE/TRUNCATE revoked from anon + authenticated; service_role writes).
--   2. Three public read RPCs (SECURITY INVOKER: every table they read is public-read under RLS,
--      so the caller's own policies apply; nothing private is reachable):
--        anime_cast_v1(p_anime_id, p_language, p_limit)       characters of one anime + primary VA
--        character_voice_actors_v1(p_character_id, p_language) voice actors of one character
--        staff_voice_roles_v1(p_staff_id, p_limit)            characters one person voiced
--      Error codes in the MESSAGE prefix (INVALID_MEDIA_ID:, INVALID_LANGUAGE:), because
--      supabase-swift does not surface PostgREST `details` (CLAUDE.md caveat).
--   The app falls back silently while these are absent live (PGRST202/PGRST205): cast without
--   voice actors from anime_characters, and no voice-actor rows.
--
-- Apply order: this migration BEFORE deploying the bulk-import-anime build that writes
-- character_voice_actors (that build only sends the voice-actor fragment when the
-- `voiceActors` track option is on, default off).
-- Rollback: drop the three functions, then drop table public.character_voice_actors (no other
-- object depends on it).

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. Link table
-- ---------------------------------------------------------------------------
create table if not exists public.character_voice_actors (
  anime_id     integer     not null references public.anime (id) on delete cascade,
  character_id integer     not null references public.characters (id) on delete cascade,
  staff_id     integer     not null references public.staff (id) on delete cascade,
  language     text        not null default 'JAPANESE',
  sort_order   smallint    not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (anime_id, character_id, staff_id, language),
  constraint character_voice_actors_language_check check (language ~ '^[A-Z_]{2,32}$'),
  constraint character_voice_actors_sort_check check (sort_order between 0 and 999)
);

comment on table public.character_voice_actors is
  '20261103100000 (prepared): voice actors per character per anime (AniList characters.edges.voiceActors, JAPANESE first). Written only by bulk-import-anime (service role); public read. Local ids, cascades from anime/characters/staff.';

-- The primary key serves the per-anime read (anime_id leads). The character page and the staff
-- page read by the other two ids.
create index if not exists character_voice_actors_character_idx
  on public.character_voice_actors (character_id, language, sort_order);
create index if not exists character_voice_actors_staff_idx
  on public.character_voice_actors (staff_id);

alter table public.character_voice_actors enable row level security;

drop policy if exists "Public read access" on public.character_voice_actors;
create policy "Public read access" on public.character_voice_actors
  as permissive for select to anon, authenticated using (true);

revoke all on public.character_voice_actors from public, anon, authenticated;
grant select on public.character_voice_actors to anon, authenticated;
grant all on public.character_voice_actors to service_role;

-- ---------------------------------------------------------------------------
-- 2. anime_cast_v1: the characters of one anime, each with its primary voice actor
--    (lowest sort_order, then lowest staff id) in p_language. Characters without a voice-actor
--    row are still returned (va_* null), so the cast rail is populated whenever characters exist.
--    Order: MAIN, then SUPPORTING, then BACKGROUND/other, then the importer's row order.
-- ---------------------------------------------------------------------------
create or replace function public.anime_cast_v1(p_anime_id integer, p_language text default 'JAPANESE',
  p_limit integer default 25)
returns table (
  character_id integer, character_anilist_id integer, character_name_full text, character_name_native text,
  character_image_large text, role text,
  staff_id integer, staff_anilist_id integer, staff_name_full text, staff_name_native text,
  staff_image_large text, language text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_lang text := upper(coalesce(nullif(btrim(p_language), ''), 'JAPANESE'));
  v_limit integer := least(50, greatest(1, coalesce(p_limit, 25)));
begin
  if p_anime_id is null or p_anime_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_anime_id must be a positive id';
  end if;
  if v_lang !~ '^[A-Z_]{2,32}$' then
    raise exception 'INVALID_LANGUAGE: p_language must be an AniList StaffLanguage';
  end if;
  return query
  select c.id, c.anilist_id, c.name_full, c.name_native, c.image_large, coalesce(ac.role, 'SUPPORTING'),
         va.staff_id, va.anilist_id, va.name_full, va.name_native, va.image_large, va.language
  from public.anime_characters ac
  join public.characters c on c.id = ac.character_id
  left join lateral (
    select s.id as staff_id, s.anilist_id, s.name_full, s.name_native, s.image_large, cva.language
    from public.character_voice_actors cva
    join public.staff s on s.id = cva.staff_id
    where cva.anime_id = ac.anime_id
      and cva.character_id = ac.character_id
      and cva.language = v_lang
    order by cva.sort_order, s.id
    limit 1
  ) va on true
  where ac.anime_id = p_anime_id
  order by case upper(coalesce(ac.role, '')) when 'MAIN' then 0 when 'SUPPORTING' then 1 else 2 end, ac.id
  limit v_limit;
end;
$$;

revoke all on function public.anime_cast_v1(integer, text, integer) from public;
grant execute on function public.anime_cast_v1(integer, text, integer) to anon, authenticated, service_role;
comment on function public.anime_cast_v1(integer, text, integer) is
  '20261103100000 (prepared). Public read: up to p_limit (1-50, default 25) characters of one anime (MAIN, SUPPORTING, other; then import order) with the primary voice actor in p_language (default JAPANESE; va columns null when none is stored). SECURITY INVOKER over public-read tables. Raises INVALID_MEDIA_ID: / INVALID_LANGUAGE:.';

-- ---------------------------------------------------------------------------
-- 3. character_voice_actors_v1: the voice actors of one character in p_language, one row per
--    person, with the anime ids (non-adult only) in which they voice this character.
-- ---------------------------------------------------------------------------
create or replace function public.character_voice_actors_v1(p_character_id integer, p_language text default 'JAPANESE')
returns table (
  staff_id integer, anilist_id integer, name_full text, name_native text, image_large text,
  language text, anime_ids integer[]
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_lang text := upper(coalesce(nullif(btrim(p_language), ''), 'JAPANESE'));
begin
  if p_character_id is null or p_character_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_character_id must be a positive id';
  end if;
  if v_lang !~ '^[A-Z_]{2,32}$' then
    raise exception 'INVALID_LANGUAGE: p_language must be an AniList StaffLanguage';
  end if;
  return query
  select s.id, s.anilist_id, s.name_full, s.name_native, s.image_large, v_lang,
         array_agg(cva.anime_id order by cva.anime_id)
  from public.character_voice_actors cva
  join public.staff s on s.id = cva.staff_id
  join public.anime a on a.id = cva.anime_id
  where cva.character_id = p_character_id
    and cva.language = v_lang
    and coalesce(a.is_adult, false) = false
  group by s.id, s.anilist_id, s.name_full, s.name_native, s.image_large
  order by min(cva.sort_order), count(*) desc, s.id
  limit 10;
end;
$$;

revoke all on function public.character_voice_actors_v1(integer, text) from public;
grant execute on function public.character_voice_actors_v1(integer, text) to anon, authenticated, service_role;
comment on function public.character_voice_actors_v1(integer, text) is
  '20261103100000 (prepared). Public read: up to 10 voice actors of one character in p_language (default JAPANESE), one row per person with the non-adult anime ids of the role, primary first. SECURITY INVOKER. Raises INVALID_MEDIA_ID: / INVALID_LANGUAGE:.';

-- ---------------------------------------------------------------------------
-- 4. staff_voice_roles_v1: the characters one person voiced (any language), one row per
--    (character, anime), non-adult anime only, most popular anime first.
-- ---------------------------------------------------------------------------
create or replace function public.staff_voice_roles_v1(p_staff_id integer, p_limit integer default 50)
returns table (
  character_id integer, character_anilist_id integer, character_name_full text, character_name_native text,
  character_image_large text, role text, language text,
  anime_id integer, title_english text, title_romaji text, title_native text,
  cover_image_large text, format text, season_year integer, start_date_year integer
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_limit integer := least(100, greatest(1, coalesce(p_limit, 50)));
begin
  if p_staff_id is null or p_staff_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_staff_id must be a positive id';
  end if;
  return query
  select c.id, c.anilist_id, c.name_full, c.name_native, c.image_large,
         coalesce(ac.role, 'SUPPORTING'), cva.language,
         a.id, a.title_english, a.title_romaji, a.title_native, a.cover_image_large, a.format,
         a.season_year, a.start_date_year
  from public.character_voice_actors cva
  join public.characters c on c.id = cva.character_id
  join public.anime a on a.id = cva.anime_id
  left join public.anime_characters ac on ac.anime_id = cva.anime_id and ac.character_id = cva.character_id
  where cva.staff_id = p_staff_id
    and coalesce(a.is_adult, false) = false
  order by case upper(coalesce(ac.role, '')) when 'MAIN' then 0 when 'SUPPORTING' then 1 else 2 end,
           a.popularity desc nulls last, a.id, c.id
  limit v_limit;
end;
$$;

revoke all on function public.staff_voice_roles_v1(integer, integer) from public;
grant execute on function public.staff_voice_roles_v1(integer, integer) to anon, authenticated, service_role;
comment on function public.staff_voice_roles_v1(integer, integer) is
  '20261103100000 (prepared). Public read: up to p_limit (1-100, default 50) characters one person voiced, one row per (character, anime), non-adult anime only; MAIN roles first, then anime popularity. SECURITY INVOKER. Raises INVALID_MEDIA_ID:.';

commit;
