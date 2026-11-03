-- 20261103100200_theme_links_apple_v1.sql
-- PREPARED, NOT DEPLOYED (2026-11-03 details/songs pass, DATA lane). Deploying needs explicit
-- owner approval. Nothing here schedules a job or writes data. REQUIRES
-- 20261101000000_release_schedule_and_themes_v2.sql (media_themes_v1 and the theme_links
-- provenance columns) first: applied live on 2026-11-02 (docs/go-live/2026-11-02/STAGE2_RECEIPT.md).
-- media_themes_v1 is therefore a LIVE read: the DROP + CREATE below runs in this file's single
-- transaction (callers never see it missing), and today's app ignores the new trailing columns.
--
-- Owner item 7 (songs: Apple artwork + 30-second preview + "Open in Apple Music"):
--   1. Nullable Apple match columns on theme_links (apple_track_id, apple_artwork_url,
--      apple_preview_url, apple_music_url, apple_match_confidence, apple_checked_at) plus
--      apple_match_key: md5 of the normalised title + artist the match was made FOR. A match is
--      served only while that key still equals the row's current title/artist, so a later
--      AnimeThemes correction (any producer) can never leave a stale Apple match attached to a
--      different song. Table CHECKs pin every URL to Apple's own hosts and a stored match to
--      confidence >= 0.8; a row without a track id carries no Apple URL at all.
--   2. media_themes_v1 is DROPPED and re-created (a function's result columns cannot change
--      with CREATE OR REPLACE) with the SAME first ten columns in the same order and five new
--      TRAILING columns (apple_track_id, apple_artwork_url, apple_preview_url, apple_music_url,
--      apple_match_confidence). Security, search_path, grants, ordering, filters and limit are
--      unchanged. Clients decoding the old shape keep working (extra keys are ignored).
--   3. upsert_theme_apple_matches_v1(jsonb): service-role writer for the --apple pass of
--      scripts/series_enrichment_worker.py. All-or-nothing validation, <= 500 rows per call.
--      A row whose expected title/artist no longer equals the stored row is skipped ("stale"),
--      never written. A row without a track id records "checked, no match" and clears any
--      previous match (the latest successful check is authoritative; never a guess).
--
-- Error codes in the MESSAGE prefix (INVALID_PAYLOAD:, LOW_CONFIDENCE:, INVALID_APPLE_URL: ...).
-- Rollback: drop upsert_theme_apple_matches_v1 and _theme_apple_key; re-create media_themes_v1
-- from 20261101000000 (drop first: the result columns differ); drop the new constraints, index
-- and columns.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. theme_links: Apple match columns (additive, nullable)
-- ---------------------------------------------------------------------------
alter table public.theme_links
  add column if not exists apple_track_id bigint,
  add column if not exists apple_artwork_url text,
  add column if not exists apple_preview_url text,
  add column if not exists apple_music_url text,
  add column if not exists apple_match_confidence real,
  add column if not exists apple_checked_at timestamptz,
  add column if not exists apple_match_key text;

do $$
declare c record;
begin
  for c in select * from (values
    ('theme_links_apple_track_check',
     $c$check (apple_track_id is null or apple_track_id between 1 and 999999999999)$c$),
    ('theme_links_apple_artwork_check',
     $c$check (apple_artwork_url is null or (char_length(apple_artwork_url) <= 2048
        and apple_artwork_url ~ '^https://[a-z0-9-]+\.mzstatic\.com/[^[:space:]]+$'))$c$),
    ('theme_links_apple_preview_check',
     $c$check (apple_preview_url is null or (char_length(apple_preview_url) <= 2048
        and apple_preview_url ~ '^https://(audio-ssl\.itunes\.apple\.com|[a-z0-9-]+\.mzstatic\.com)/[^[:space:]]+$'))$c$),
    ('theme_links_apple_music_check',
     $c$check (apple_music_url is null or (char_length(apple_music_url) <= 2048
        and apple_music_url ~ '^https://(music|itunes)\.apple\.com/[^[:space:]]+$'))$c$),
    ('theme_links_apple_key_check',
     $c$check (apple_match_key is null or apple_match_key ~ '^[0-9a-f]{32}$')$c$),
    -- A stored match is complete and confident; "checked, no match" carries no Apple data.
    ('theme_links_apple_match_shape_check',
     $c$check (
        (apple_track_id is null and apple_artwork_url is null and apple_preview_url is null
          and apple_music_url is null and apple_match_confidence is null and apple_match_key is null)
        or (apple_track_id is not null and apple_match_key is not null and apple_music_url is not null
          and apple_match_confidence is not null and apple_match_confidence between 0.8 and 1.0)
     )$c$)
  ) as t(name, def) loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.theme_links'::regclass and conname = c.name) then
      execute format('alter table public.theme_links add constraint %I %s', c.name, c.def);
    end if;
  end loop;
end $$;

comment on column public.theme_links.apple_match_key is
  '20261103100200: md5 of the normalised title + artist an Apple match was made for (_theme_apple_key). media_themes_v1 serves the apple_* fields only while it equals the current row, so a corrected title/artist never keeps a stale match.';
comment on column public.theme_links.apple_checked_at is
  '20261103100200: last successful iTunes Search check by the --apple worker pass (match or no match).';

-- The worker's candidate scan: never-checked rows first, then the oldest checks.
create index if not exists theme_links_apple_checked
  on public.theme_links (apple_checked_at nulls first, id);

-- ---------------------------------------------------------------------------
-- 2. The match key (immutable; also used by the reader)
-- ---------------------------------------------------------------------------
create or replace function public._theme_apple_key(p_title text, p_artist text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select md5(lower(regexp_replace(btrim(coalesce(p_title, '')), '\s+', ' ', 'g')) || chr(31)
          || lower(regexp_replace(btrim(coalesce(p_artist, '')), '\s+', ' ', 'g')))
$$;
revoke all on function public._theme_apple_key(text, text) from public, anon, authenticated;
grant execute on function public._theme_apple_key(text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 3. media_themes_v1: same contract + five trailing Apple columns
-- ---------------------------------------------------------------------------
drop function if exists public.media_themes_v1(integer);

create function public.media_themes_v1(p_anime_id integer)
returns table (kind text, sequence integer, title text, artist text, episodes text, version integer,
  is_spoiler boolean, is_nsfw boolean, source text, source_url text,
  apple_track_id bigint, apple_artwork_url text, apple_preview_url text, apple_music_url text,
  apple_match_confidence real)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select case t.role when 'op' then 'OP' when 'ed' then 'ED' else 'IN' end,
         t.sequence_order, t.song_title, t.artist, t.episodes, t.version,
         t.is_spoiler, t.is_nsfw,
         coalesce(t.source, case when t.source_identity like 'animethemes:%' then 'animethemes' end),
         t.source_url,
         case when m.served then t.apple_track_id end,
         case when m.served then t.apple_artwork_url end,
         case when m.served then t.apple_preview_url end,
         case when m.served then t.apple_music_url end,
         case when m.served then t.apple_match_confidence end
  from public.theme_links t
  cross join lateral (
    select (t.apple_track_id is not null
            and t.apple_match_confidence >= 0.8
            and t.apple_match_key = public._theme_apple_key(t.song_title, t.artist)) as served
  ) m
  where t.anime_id = p_anime_id
    and nullif(btrim(t.song_title), '') is not null
    and t.match_state <> 'unmatched'
  order by case t.role when 'op' then 0 when 'ed' then 1 else 2 end, t.sequence_order, t.version nulls first, t.id
  limit 60
$$;
revoke all on function public.media_themes_v1(integer) from public;
grant execute on function public.media_themes_v1(integer) to anon, authenticated;
comment on function public.media_themes_v1(integer) is
  'Spec 3.3 (2026-11-01), Apple columns 20261103100200. Public read: OP/ED/IN themes of one anime ordered OP, ED, IN then sequence then version. Columns: kind, sequence, title, artist, episodes, version, is_spoiler, is_nsfw, source (animethemes), source_url, then (trailing, null unless a confident (>= 0.8) iTunes match made for the current title + artist is stored) apple_track_id, apple_artwork_url, apple_preview_url, apple_music_url, apple_match_confidence. Spoiler/NSFW rows are returned flagged; the client decides.';

-- ---------------------------------------------------------------------------
-- 4. upsert_theme_apple_matches_v1(jsonb): service-role writer for the --apple pass
--
-- Input: JSON array (<= 500) of objects:
--   theme_id         theme_links.id (uuid)                                     required
--   expected_title   the song_title the worker matched (must equal the row)    required
--   expected_artist  the artist the worker matched (null allowed; must equal)  required key
--   apple_track_id   iTunes trackId (positive integer) or null = checked, no match
--   apple_artwork_url / apple_preview_url / apple_music_url   Apple-host https URLs (match only;
--                    music URL required for a match)
--   confidence       0.8..1.0 for a match (a lower value raises LOW_CONFIDENCE)
-- Returns {"matched":n,"cleared":n,"stale":n}. Unknown theme ids and rows whose title/artist
-- changed since the worker read them count as stale and write nothing.
-- ---------------------------------------------------------------------------
create or replace function public.upsert_theme_apple_matches_v1(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r jsonb; i integer := 0;
  v_id uuid; v_title text; v_artist text; v_track bigint; v_art text; v_preview text; v_music text;
  v_conf real; v_row public.theme_links%rowtype;
  v_matched integer := 0; v_cleared integer := 0; v_stale integer := 0;
  v_validated jsonb := '[]'::jsonb;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'INVALID_PAYLOAD: expected a JSON array of Apple match rows';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception 'PAYLOAD_TOO_LARGE: at most 500 Apple match rows per call';
  end if;

  -- Pass 1: validate every row (all-or-nothing) before writing anything.
  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1;
    if jsonb_typeof(r) <> 'object' then raise exception 'INVALID_ROW: row % is not an object', i; end if;
    if coalesce(r->>'theme_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'INVALID_THEME_ID: row % theme_id must be a uuid', i;
    end if;
    if nullif(btrim(coalesce(r->>'expected_title', '')), '') is null then
      raise exception 'INVALID_TITLE: row % expected_title is required', i;
    end if;
    if not (r ? 'expected_artist') or jsonb_typeof(r->'expected_artist') not in ('string', 'null') then
      raise exception 'INVALID_ARTIST: row % expected_artist must be a string or null', i;
    end if;

    if r ? 'apple_track_id' and jsonb_typeof(r->'apple_track_id') <> 'null' then
      if jsonb_typeof(r->'apple_track_id') <> 'number' or (r->>'apple_track_id') !~ '^[1-9][0-9]{0,11}$' then
        raise exception 'INVALID_TRACK_ID: row % apple_track_id must be a positive integer', i;
      end if;
      if jsonb_typeof(r->'confidence') is distinct from 'number' then
        raise exception 'LOW_CONFIDENCE: row % a match needs a numeric confidence', i;
      end if;
      if (r->>'confidence')::numeric < 0.8 or (r->>'confidence')::numeric > 1 then
        raise exception 'LOW_CONFIDENCE: row % confidence must be 0.8..1.0 for a match', i;
      end if;
      if coalesce(r->>'apple_music_url', '') !~ '^https://(music|itunes)\.apple\.com/[^[:space:]]+$'
         or char_length(r->>'apple_music_url') > 2048 then
        raise exception 'INVALID_APPLE_URL: row % apple_music_url must be an https://music.apple.com/ link', i;
      end if;
      if nullif(r->>'apple_artwork_url', '') is not null
         and ((r->>'apple_artwork_url') !~ '^https://[a-z0-9-]+\.mzstatic\.com/[^[:space:]]+$'
              or char_length(r->>'apple_artwork_url') > 2048) then
        raise exception 'INVALID_APPLE_URL: row % apple_artwork_url must be an https://*.mzstatic.com/ link', i;
      end if;
      if nullif(r->>'apple_preview_url', '') is not null
         and ((r->>'apple_preview_url') !~ '^https://(audio-ssl\.itunes\.apple\.com|[a-z0-9-]+\.mzstatic\.com)/[^[:space:]]+$'
              or char_length(r->>'apple_preview_url') > 2048) then
        raise exception 'INVALID_APPLE_URL: row % apple_preview_url must be an Apple preview link', i;
      end if;
    else
      if nullif(r->>'apple_music_url', '') is not null or nullif(r->>'apple_artwork_url', '') is not null
         or nullif(r->>'apple_preview_url', '') is not null then
        raise exception 'INVALID_ROW: row % carries Apple URLs without a track id', i;
      end if;
    end if;
    v_validated := v_validated || jsonb_build_array(r);
  end loop;

  -- Pass 2: write.
  for r in select value from jsonb_array_elements(v_validated) loop
    v_id := (r->>'theme_id')::uuid;
    v_title := r->>'expected_title';
    v_artist := r->>'expected_artist';
    select * into v_row from public.theme_links where id = v_id for update;
    if not found
       or v_row.song_title is distinct from v_title
       or v_row.artist is distinct from v_artist then
      v_stale := v_stale + 1;
      continue;
    end if;

    if r ? 'apple_track_id' and jsonb_typeof(r->'apple_track_id') <> 'null' then
      v_track := (r->>'apple_track_id')::bigint;
      v_art := nullif(r->>'apple_artwork_url', '');
      v_preview := nullif(r->>'apple_preview_url', '');
      v_music := r->>'apple_music_url';
      v_conf := (r->>'confidence')::real;
      update public.theme_links
         set apple_track_id = v_track, apple_artwork_url = v_art, apple_preview_url = v_preview,
             apple_music_url = v_music, apple_match_confidence = greatest(0.8::real, least(1.0::real, v_conf)),
             apple_match_key = public._theme_apple_key(v_row.song_title, v_row.artist),
             apple_checked_at = now()
       where id = v_id;
      v_matched := v_matched + 1;
    else
      update public.theme_links
         set apple_track_id = null, apple_artwork_url = null, apple_preview_url = null,
             apple_music_url = null, apple_match_confidence = null, apple_match_key = null,
             apple_checked_at = now()
       where id = v_id;
      v_cleared := v_cleared + 1;
    end if;
  end loop;

  return jsonb_build_object('matched', v_matched, 'cleared', v_cleared, 'stale', v_stale);
end;
$$;
revoke all on function public.upsert_theme_apple_matches_v1(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_theme_apple_matches_v1(jsonb) to service_role;
comment on function public.upsert_theme_apple_matches_v1(jsonb) is
  '20261103100200 (prepared). Service-role writer for the --apple worker pass: per theme row either a confident (>= 0.8) iTunes match (Apple-host URLs only) or "checked, no match" (clears a previous match). Rows whose title/artist changed since the worker read them are skipped as stale. All-or-nothing validation, <= 500 rows. Returns {"matched","cleared","stale"}.';

commit;
