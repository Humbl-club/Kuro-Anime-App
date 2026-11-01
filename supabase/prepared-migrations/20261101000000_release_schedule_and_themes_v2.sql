-- 20261101000000_release_schedule_and_themes_v2.sql
-- PREPARED, NOT DEPLOYED (2026-11-01 overnight production pass, lane 1 / SQL).
-- Deploying needs explicit owner approval. Nothing here schedules a job or writes data.
--
-- What it adds (spec docs/superpowers/specs/2026-11-01-overnight-production-pass-design.md
-- sections 2 D10, 3.1-3.3):
--   1. Additive columns on release_events (unit_kind, unit_number, unit_label, basis,
--      confidence, source, source_url, observed_at) and theme_links (episodes, version,
--      is_spoiler, is_nsfw, source, source_url). Every existing column, constraint, index,
--      policy and reader keeps working; the new columns are nullable or defaulted.
--   2. Certainty model (D10): basis confirmed | announced | estimated. A confirmed row is
--      always precision 'instant' (the source states the time); a source date or window
--      without a time is 'announced'. An estimated row must carry a confidence, use source
--      'kuro_estimate' and status 'scheduled'. Estimated rows are stored but only READ back
--      when confidence >= 0.7 (compared as real). Credit links (source_url) must point at the
--      source's own host (table CHECK + writer).
--   3. home_events_page_v1 (live Home RPC) is re-created byte-for-byte except that it now
--      ignores basis='estimated' rows, so a stored estimate can never surface there as a
--      fact. home_pending_page_v1 needs no change: it reads status='announced' only and an
--      estimate is always status='scheduled' (constraint release_events_estimate_check).
--   4. Read RPCs (exact contracts in the function comments):
--        user_release_schedule_v1(p_medium, p_limit)       authenticated only
--        media_release_schedule_v1(p_medium, p_media_id, p_limit)  anon + authenticated
--        media_themes_v1(p_anime_id)                        anon + authenticated
--      The release RPCs read only rows written through the v2 contract (basis IS NOT NULL;
--      legacy bridge rows carry no source and are not shown) plus the existing
--      anime.next_airing_at / next_episode_number fallback (basis confirmed, source anilist).
--   5. Service-role writers for the intake code (D11: that code ships UNSCHEDULED):
--        upsert_release_events_v1(jsonb)   upsert_theme_links_v1(jsonb)
--      Validation is all-or-nothing per call (one bad row raises, nothing is written);
--      natural keys make re-runs idempotent (an identical re-run changes no business field
--      and does not advance revision).
--   6. finish_series_enrichment_v1 re-created with one predicate so it can never delete theme
--      rows owned by upsert_theme_links_v1 (section 10).
--
-- Error codes are in the MESSAGE prefix (UNAUTHENTICATED:, INVALID_MEDIUM:, ...), because
-- supabase-swift does not surface PostgREST `details` (CLAUDE.md caveat).
-- Rollback: drop the five new functions, re-create home_events_page_v1 and
-- finish_series_enrichment_v1 from 20261007040000, drop the new constraints/indexes/columns (no reader depends on them).

begin;

-- release_events / theme_links are tiny, but ALTER TABLE takes an ACCESS EXCLUSIVE lock: fail
-- fast instead of queueing every reader behind a busy lock; the apply can simply be retried.
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. release_events: unit, certainty and provenance (additive)
-- ---------------------------------------------------------------------------
alter table public.release_events
  add column if not exists unit_kind text,
  add column if not exists unit_number numeric,
  add column if not exists unit_label text,
  add column if not exists basis text,
  add column if not exists confidence real,
  add column if not exists source text,
  add column if not exists source_url text,
  add column if not exists observed_at timestamptz;

do $$
declare c record;
begin
  for c in select * from (values
    ('release_events_unit_kind_check',
     $c$check (unit_kind is null or unit_kind in ('episode','chapter','volume','season'))$c$),
    ('release_events_unit_number_check',
     $c$check (unit_number is null or (unit_number >= 0 and unit_number < 100000))$c$),
    ('release_events_unit_label_check',
     $c$check (unit_label is null or char_length(unit_label) between 1 and 64)$c$),
    ('release_events_basis_check',
     $c$check (basis is null or basis in ('confirmed','announced','estimated'))$c$),
    ('release_events_confidence_check',
     $c$check (confidence is null or (confidence >= 0 and confidence <= 1))$c$),
    ('release_events_source_check',
     $c$check (source is null or source in ('anilist','mangaupdates','mangadex','publisher','kuro_estimate'))$c$),
    -- the credit link must point at the source's own site (writer applies the same rule)
    ('release_events_source_url_check',
     $c$check (source_url is null or (char_length(source_url) <= 2048 and source_url !~ '[[:space:]]' and case source
        when 'anilist' then source_url ~ '^https://anilist\.co/'
        when 'mangaupdates' then source_url ~ '^https://(www\.)?mangaupdates\.com/'
        when 'kuro_estimate' then source_url ~ '^https://(www\.)?mangaupdates\.com/'
        when 'mangadex' then source_url ~ '^https://mangadex\.org/'
        else false end))$c$),
    -- D10: confirmed = the source states the instant; a date or window without a time is announced
    ('release_events_confirmed_instant_check',
     $c$check (basis is distinct from 'confirmed' or precision = 'instant')$c$),
    -- an estimate is always labelled, scored and Kuro-computed; only an estimate uses kuro_estimate
    ('release_events_estimate_check',
     $c$check ((basis is distinct from 'estimated' or (source = 'kuro_estimate' and confidence is not null and status = 'scheduled'))
               and (source is distinct from 'kuro_estimate' or basis = 'estimated'))$c$),
    -- a row that claims a basis is a full v2 row (the read RPCs rely on this)
    ('release_events_v2_complete_check',
     $c$check ((basis is null and source is null)
               or (basis is not null and source is not null and unit_kind is not null and unit_number is not null
                   and observed_at is not null and unit_label is not null))$c$)
  ) as t(name, def) loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.release_events'::regclass and conname = c.name) then
      execute format('alter table public.release_events add constraint %I %s', c.name, c.def);
    end if;
  end loop;
end $$;

-- Per-title hot path of all three read paths (v2 rows only; the legacy indexes stay).
create index if not exists idx_release_events_v2_anime
  on public.release_events (anime_id, unit_kind, utc_instant)
  where basis is not null and anime_id is not null;
create index if not exists idx_release_events_v2_manga
  on public.release_events (manga_id, unit_kind, utc_instant)
  where basis is not null and manga_id is not null;

comment on column public.release_events.basis is
  'D10 certainty: confirmed (source states the date/instant), announced (source states a window or a date without time), estimated (Kuro cadence estimate; read back only when confidence >= 0.7). NULL = legacy bridge row, not served by the v2 RPCs.';
comment on column public.release_events.source is
  'Provenance of the row: anilist | mangaupdates | mangadex | publisher | kuro_estimate. Credit it in the UI (Data sources & credits).';

-- ---------------------------------------------------------------------------
-- 2. theme_links: entry coverage, flags and provenance (additive)
-- ---------------------------------------------------------------------------
alter table public.theme_links
  add column if not exists episodes text,
  add column if not exists version integer,
  add column if not exists is_spoiler boolean not null default false,
  add column if not exists is_nsfw boolean not null default false,
  add column if not exists source text,
  add column if not exists source_url text;

do $$
declare c record;
begin
  for c in select * from (values
    ('theme_links_episodes_check', $c$check (episodes is null or char_length(episodes) between 1 and 64)$c$),
    ('theme_links_version_check',  $c$check (version is null or version between 1 and 99)$c$),
    ('theme_links_source_check',   $c$check (source is null or source in ('animethemes'))$c$),
    ('theme_links_source_url_check',
     $c$check (source_url is null or (char_length(source_url) <= 2048 and source_url !~ '[[:space:]]'
        and source_url ~ '^https://animethemes\.moe/'))$c$)
  ) as t(name, def) loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.theme_links'::regclass and conname = c.name) then
      execute format('alter table public.theme_links add constraint %I %s', c.name, c.def);
    end if;
  end loop;
end $$;
-- theme_links_entry_section (anime_id, section_id, sequence_order) already serves the
-- per-anime read; theme_links_source_identity serves the writer's natural key.

-- ---------------------------------------------------------------------------
-- 3. home_events_page_v1: identical to 20261007040000 except the two
--    `r.basis is distinct from 'estimated'` predicates (estimates never shown as fact).
-- ---------------------------------------------------------------------------
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
   where r.medium=p_medium and r.status in ('scheduled','announced') and r.basis is distinct from 'estimated' and (
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
     and not exists(select 1 from public.release_events r where r.anime_id=a.id and r.status in ('scheduled','announced') and r.basis is distinct from 'estimated' and r.utc_instant=a.next_airing_at)
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

-- ---------------------------------------------------------------------------
-- 4. Internal: candidate units for a set of titles (owner-only helper)
--    One row per (medium, media_id, unit_kind, unit_number) with the best basis:
--    v2 confirmed (rank 0) > anime.next_airing_at fallback (1) > announced (2) > estimated (3).
--    release_at: precision instant -> the instant; day/month/quarter/year -> the START of the
--    stated window at 00:00 in source_zone (UTC when unknown); unknown -> NULL.
--    release_end: the END of that window (instant: the instant). A unit is past when its
--    window has ended or its status is 'released'.
-- ---------------------------------------------------------------------------
create or replace function public._release_schedule_units_v1(p_anime_ids integer[], p_manga_ids integer[])
returns table (medium text, media_id integer, unit_kind text, unit_number numeric, unit_label text,
  release_at timestamptz, release_end timestamptz, basis text, confidence real, source text,
  source_url text, release_precision text, is_past boolean, basis_rank integer)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with ev as (
    select r.medium, coalesce(r.anime_id, r.manga_id) as media_id, r.unit_kind, r.unit_number, r.unit_label,
           case when r.precision = 'instant' then r.utc_instant
                when r.precision in ('day','month','quarter','year') and r.source_local_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                  then (r.source_local_date::date)::timestamp at time zone coalesce(r.source_zone, 'UTC')
           end as release_at,
           r.precision, r.basis, r.confidence, r.source, r.source_url, r.status, r.observed_at
    from public.release_events r
    where r.basis is not null
      and ((r.medium = 'anime' and r.anime_id = any (coalesce(p_anime_ids, '{}')))
        or (r.medium = 'manga' and r.manga_id = any (coalesce(p_manga_ids, '{}'))))
      and r.status in ('scheduled', 'announced', 'delayed', 'released')
      -- compare in real: confidence is real, and 0.7::real widens to 0.699999988 against a
      -- numeric 0.7, which would hide every estimate scored exactly 0.70
      and (r.basis <> 'estimated' or r.confidence >= 0.7::real)
  ), ev2 as (
    select ev.*,
           case ev.precision when 'instant' then ev.release_at
                             when 'day' then ev.release_at + interval '1 day'
                             when 'month' then ev.release_at + interval '1 month'
                             when 'quarter' then ev.release_at + interval '3 months'
                             when 'year' then ev.release_at + interval '1 year' end as release_end
    from ev
  ), scored as (
    select ev2.medium, ev2.media_id, ev2.unit_kind, ev2.unit_number, ev2.unit_label, ev2.release_at, ev2.release_end,
           ev2.basis, coalesce(ev2.confidence, 1)::real as confidence, ev2.source, ev2.source_url, ev2.precision,
           (ev2.status = 'released' or coalesce(ev2.release_end < now(), false)) as is_past,
           case ev2.basis when 'confirmed' then 0 when 'announced' then 2 else 3 end as basis_rank,
           ev2.observed_at
    from ev2
  ), fallback as (
    -- The existing AniList-imported single next episode. Suppressed when a v2 AniList
    -- confirmed upcoming row exists for the title (that row is fresher, e.g. a delay).
    select 'anime'::text, a.id, 'episode'::text, a.next_episode_number::numeric,
           case when a.next_episode_number is null then 'Next episode' else 'Ep. ' || a.next_episode_number end,
           a.next_airing_at, a.next_airing_at, 'confirmed'::text, 1::real, 'anilist'::text,
           case when a.anilist_id is not null then 'https://anilist.co/anime/' || a.anilist_id end,
           'instant'::text, false, 1, null::timestamptz
    from public.anime a
    where a.id = any (coalesce(p_anime_ids, '{}'))
      and a.next_airing_at >= now()
      and not exists (select 1 from scored s
                      where s.medium = 'anime' and s.media_id = a.id and s.source = 'anilist'
                        and s.basis = 'confirmed' and not s.is_past)
  ), allrows as (
    select * from scored
    union all
    select * from fallback
  )
  select distinct on (x.medium, x.media_id, x.unit_kind, x.unit_number)
         x.medium, x.media_id, x.unit_kind, x.unit_number, x.unit_label, x.release_at, x.release_end,
         x.basis, x.confidence, x.source, x.source_url, x.precision, x.is_past, x.basis_rank
  from allrows x
  order by x.medium, x.media_id, x.unit_kind, x.unit_number, x.basis_rank, x.observed_at desc nulls last
$$;
revoke all on function public._release_schedule_units_v1(integer[], integer[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. user_release_schedule_v1 (spec 3.1)
-- ---------------------------------------------------------------------------
create or replace function public.user_release_schedule_v1(p_medium text default null, p_limit integer default 60)
returns table (medium text, media_id integer, title text, cover_image text, unit_kind text, unit_number numeric,
  unit_label text, release_at timestamptz, basis text, confidence real, source text, source_url text,
  release_precision text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid text := lower(auth.uid()::text);
  v_limit integer := least(200, greatest(1, coalesce(p_limit, 60)));
  v_anime integer[];
  v_manga integer[];
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED: sign in to read your release schedule';
  end if;
  if p_medium is not null and p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM: p_medium must be anime, manga or null';
  end if;

  -- Tracked = Watching/Reading, Planning, Paused (there is no CURRENT/REPEATING list_type).
  -- user_id is TEXT: auth.uid()::text is lower-case; the upper-case spelling covers rows
  -- written before the canonical-case trigger. Both spellings use the user_id index.
  select coalesce(array_agg(distinct l.anime_id), '{}') into v_anime
  from public.anime_user_lists l
  where (p_medium is null or p_medium = 'anime')
    and l.user_id in (v_uid, upper(v_uid))
    and l.list_type in ('WATCHING', 'PLANNING', 'PAUSED');
  select coalesce(array_agg(distinct l.manga_id), '{}') into v_manga
  from public.manga_user_lists l
  where (p_medium is null or p_medium = 'manga')
    and l.user_id in (v_uid, upper(v_uid))
    and l.list_type in ('WATCHING', 'READING', 'PLANNING', 'PAUSED');

  return query
  select n.medium, n.media_id,
         coalesce(a.title_english, a.title_romaji, a.title_native, m.title_english, m.title_romaji, m.title_native, 'Untitled'),
         coalesce(a.cover_image_large, m.cover_image_large),
         n.unit_kind, n.unit_number, n.unit_label, n.release_at, n.basis, n.confidence, n.source, n.source_url,
         n.release_precision
  from (
    select distinct on (u.medium, u.media_id) u.*
    from public._release_schedule_units_v1(v_anime, v_manga) u
    where not u.is_past
    order by u.medium, u.media_id, u.release_at asc nulls last, u.basis_rank, u.unit_number
  ) n
  left join public.anime a on n.medium = 'anime' and a.id = n.media_id
  left join public.manga m on n.medium = 'manga' and m.id = n.media_id
  order by n.release_at asc nulls last, n.medium, n.media_id
  limit v_limit;
end;
$$;
revoke all on function public.user_release_schedule_v1(text, integer) from public, anon;
grant execute on function public.user_release_schedule_v1(text, integer) to authenticated;
comment on function public.user_release_schedule_v1(text, integer) is
  'Spec 3.1 (2026-11-01). Next upcoming unit per title the caller tracks (WATCHING/READING, PLANNING, PAUSED), ordered by release_at NULLS LAST. Columns: medium, media_id, title, cover_image, unit_kind, unit_number, unit_label, release_at, basis (confirmed|announced|estimated; estimated only when confidence >= 0.7), confidence (0-1; 1 for confirmed/announced without a score), source, source_url, release_precision (instant|day|month|quarter|year|unknown; additive column: for announced rows release_at is the START of that window, render the window, never a time). Raises UNAUTHENTICATED: without a JWT user.';

-- ---------------------------------------------------------------------------
-- 6. media_release_schedule_v1 (spec 3.2): public catalog read
-- ---------------------------------------------------------------------------
create or replace function public.media_release_schedule_v1(p_medium text, p_media_id integer, p_limit integer default 6)
returns table (medium text, media_id integer, title text, cover_image text, unit_kind text, unit_number numeric,
  unit_label text, release_at timestamptz, basis text, confidence real, source text, source_url text,
  is_past boolean, release_precision text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_limit integer := least(24, greatest(1, coalesce(p_limit, 6)));
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM: p_medium must be anime or manga';
  end if;
  if p_media_id is null or p_media_id <= 0 then
    raise exception 'INVALID_MEDIA_ID: p_media_id must be a positive id';
  end if;

  return query
  with u as (
    select * from public._release_schedule_units_v1(
      case when p_medium = 'anime' then array[p_media_id] end,
      case when p_medium = 'manga' then array[p_media_id] end)
  ), past as (
    -- the last confirmed unit whose release has passed
    select * from u where u.is_past and u.basis = 'confirmed' and u.release_at is not null
    order by u.release_at desc, u.unit_number desc limit 1
  ), upcoming as (
    select * from u where not u.is_past
    order by u.release_at asc nulls last, u.basis_rank, u.unit_number limit v_limit
  ), picked as (
    select * from past union all select * from upcoming
  )
  select p.medium, p.media_id,
         coalesce(a.title_english, a.title_romaji, a.title_native, m.title_english, m.title_romaji, m.title_native, 'Untitled'),
         coalesce(a.cover_image_large, m.cover_image_large),
         p.unit_kind, p.unit_number, p.unit_label, p.release_at, p.basis, p.confidence, p.source, p.source_url,
         p.is_past, p.release_precision
  from picked p
  left join public.anime a on p.medium = 'anime' and a.id = p.media_id
  left join public.manga m on p.medium = 'manga' and m.id = p.media_id
  order by p.is_past desc, p.release_at asc nulls last, p.unit_number;
end;
$$;
revoke all on function public.media_release_schedule_v1(text, integer, integer) from public;
grant execute on function public.media_release_schedule_v1(text, integer, integer) to anon, authenticated;
comment on function public.media_release_schedule_v1(text, integer, integer) is
  'Spec 3.2 (2026-11-01). Public read for one title: up to p_limit (1-24, default 6) upcoming units (one per unit, best basis) plus the last confirmed past unit (is_past = true, listed first). Same columns as user_release_schedule_v1 plus is_past, then release_precision. Raises INVALID_MEDIUM: / INVALID_MEDIA_ID:.';

-- ---------------------------------------------------------------------------
-- 7. media_themes_v1 (spec 3.3): public catalog read
-- ---------------------------------------------------------------------------
create or replace function public.media_themes_v1(p_anime_id integer)
returns table (kind text, sequence integer, title text, artist text, episodes text, version integer,
  is_spoiler boolean, is_nsfw boolean, source text, source_url text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select case t.role when 'op' then 'OP' when 'ed' then 'ED' else 'IN' end,
         t.sequence_order, t.song_title, t.artist, t.episodes, t.version,
         t.is_spoiler, t.is_nsfw,
         coalesce(t.source, case when t.source_identity like 'animethemes:%' then 'animethemes' end),
         t.source_url
  from public.theme_links t
  where t.anime_id = p_anime_id
    and nullif(btrim(t.song_title), '') is not null
    and t.match_state <> 'unmatched'
  order by case t.role when 'op' then 0 when 'ed' then 1 else 2 end, t.sequence_order, t.version nulls first, t.id
  limit 60
$$;
revoke all on function public.media_themes_v1(integer) from public;
grant execute on function public.media_themes_v1(integer) to anon, authenticated;
comment on function public.media_themes_v1(integer) is
  'Spec 3.3 (2026-11-01). Public read: OP/ED/IN themes of one anime ordered OP, ED, IN then sequence then version. Columns: kind, sequence, title, artist, episodes, version, is_spoiler, is_nsfw, source (animethemes), source_url. Spoiler/NSFW rows are returned flagged; the client decides. No music-service URL is stored (Listen = on-device search URL, D11).';

-- ---------------------------------------------------------------------------
-- 8. upsert_release_events_v1(jsonb): service-role writer for intake code
--
-- Input: JSON array (<= 500) of objects:
--   medium        'anime' | 'manga'                                  required
--   media_id      Kuro anime.id / manga.id (must exist)              required
--   unit_kind     anime: episode | season; manga: chapter | volume   required
--   unit_number   0 <= n < 100000, <= 3 decimals (e.g. 10.5)         required
--   basis         confirmed | announced | estimated                  required
--   source        anilist | mangaupdates | mangadex | publisher | kuro_estimate (estimated <=> kuro_estimate)
--   confidence    0..1; required for estimated
--   precision     instant | day | month | quarter | year | unknown   (default: instant when
--                 release_at, day when source_local_date, else unknown)
--   release_at    ISO-8601 instant 'YYYY-MM-DDTHH:MM...' (precision instant); finite,
--                 within now()-100y .. now()+5y ('infinity'/'tomorrow' are rejected)
--   source_local_date  'YYYY-MM-DD' = start of the window (day/month/quarter/year)
--   source_zone   IANA zone of source_local_date (optional, default UTC)
--   status        scheduled | released | delayed | cancelled | announced (default:
--                 announced for basis announced, released for a past instant, else scheduled;
--                 estimated rows are always scheduled)
--   unit_label    <= 64 chars (default 'Ep. 7' / 'Ch. 10.5' / 'Vol. 3' / 'Season 2')
--   source_url    credit link, optional; host must match the source:
--                   anilist https://anilist.co/...  mangaupdates / kuro_estimate
--                   https://(www.)mangaupdates.com/...  mangadex https://mangadex.org/...
--                   publisher: must be null until a publisher host list exists
--   observed_at   ISO-8601 instant the source was read (default now()); finite, not
--                 older than 5 years, not more than 1 hour in the future
--   territory     ISO 3166-1 alpha-2, optional
--   external_id   source-side id for evidence, optional (<= 120 chars)
-- Natural key (source_identity):
--   <source>:<medium>:<media_id>:<unit_kind>:<unit_number>    confirmed / announced
--   kuro_estimate:<medium>:<media_id>:<unit_kind>:next        estimated (one per title+kind;
--                                                              a new estimate replaces the old)
-- Basis rules (D10): confirmed needs precision instant (a source-stated date without a time is
-- announced); estimated needs instant or day; announced any.
-- Returns {"inserted":n,"updated":n,"unchanged":n}. Any invalid row raises (nothing written).
-- ---------------------------------------------------------------------------
create or replace function public.upsert_release_events_v1(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r jsonb; i integer := 0;
  v_medium text; v_media integer; v_kind text; v_num numeric; v_label text; v_basis text;
  v_conf real; v_source text; v_url text; v_prec text; v_instant timestamptz; v_day text;
  v_zone text; v_status text; v_observed timestamptz; v_identity text; v_territory text;
  v_evidence text; v_old public.release_events%rowtype; v_n integer; v_host_ok boolean;
  v_inserted integer := 0; v_updated integer := 0; v_unchanged integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'INVALID_PAYLOAD: expected a JSON array of release rows';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception 'PAYLOAD_TOO_LARGE: at most 500 release rows per call';
  end if;

  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1;
    if jsonb_typeof(r) <> 'object' then raise exception 'INVALID_ROW: row % is not an object', i; end if;

    v_medium := r->>'medium';
    if v_medium is null or v_medium not in ('anime', 'manga') then
      raise exception 'INVALID_MEDIUM: row % medium must be anime or manga', i;
    end if;
    if coalesce(r->>'media_id', '') !~ '^[1-9][0-9]{0,9}$' or (r->>'media_id')::bigint > 2147483647 then
      raise exception 'INVALID_MEDIA_ID: row % media_id must be a positive integer id', i;
    end if;
    v_media := (r->>'media_id')::integer;
    if (v_medium = 'anime' and not exists (select 1 from public.anime where id = v_media))
       or (v_medium = 'manga' and not exists (select 1 from public.manga where id = v_media)) then
      raise exception 'MEDIA_NOT_FOUND: row % (% %)', i, v_medium, v_media;
    end if;

    v_kind := r->>'unit_kind';
    if v_kind is null or (v_medium = 'anime' and v_kind not in ('episode', 'season'))
       or (v_medium = 'manga' and v_kind not in ('chapter', 'volume')) then
      raise exception 'INVALID_UNIT_KIND: row % unit_kind % is not valid for %', i, coalesce(v_kind, 'null'), v_medium;
    end if;
    if coalesce(r->>'unit_number', '') !~ '^[0-9]{1,5}(\.[0-9]{1,3})?$' then
      raise exception 'INVALID_UNIT_NUMBER: row % unit_number must be 0..99999 with at most 3 decimals', i;
    end if;
    v_num := trim_scale((r->>'unit_number')::numeric);

    v_basis := r->>'basis';
    if v_basis is null or v_basis not in ('confirmed', 'announced', 'estimated') then
      raise exception 'INVALID_BASIS: row % basis must be confirmed, announced or estimated', i;
    end if;
    v_source := r->>'source';
    if v_source is null or v_source not in ('anilist', 'mangaupdates', 'mangadex', 'publisher', 'kuro_estimate') then
      raise exception 'INVALID_SOURCE: row % source is not an allowed provider', i;
    end if;
    if (v_basis = 'estimated') <> (v_source = 'kuro_estimate') then
      raise exception 'INVALID_SOURCE: row % estimated rows (and only they) use source kuro_estimate', i;
    end if;

    v_conf := null;
    if r ? 'confidence' and jsonb_typeof(r->'confidence') <> 'null' then
      if jsonb_typeof(r->'confidence') <> 'number' or (r->>'confidence')::numeric < 0 or (r->>'confidence')::numeric > 1 then
        raise exception 'INVALID_CONFIDENCE: row % confidence must be a number 0..1', i;
      end if;
      v_conf := (r->>'confidence')::real;
    end if;
    if v_basis = 'estimated' and v_conf is null then
      raise exception 'INVALID_CONFIDENCE: row % estimated rows need a confidence', i;
    end if;

    v_url := nullif(r->>'source_url', '');
    if v_url is not null and (v_url !~ '^https://[^[:space:]]+$' or char_length(v_url) > 2048) then
      raise exception 'INVALID_SOURCE_URL: row % source_url must be an https URL', i;
    end if;
    -- the credit link must point at the source's own site (same rule as release_events_source_url_check)
    -- (assigned first: a CASE inside an IF condition would end the condition at its first THEN)
    v_host_ok := v_url is null or case v_source
         when 'anilist' then v_url ~ '^https://anilist\.co/'
         when 'mangaupdates' then v_url ~ '^https://(www\.)?mangaupdates\.com/'
         when 'kuro_estimate' then v_url ~ '^https://(www\.)?mangaupdates\.com/'
         when 'mangadex' then v_url ~ '^https://mangadex\.org/'
         else false end;
    if not v_host_ok then
      raise exception 'INVALID_SOURCE_URL: row % source_url host does not belong to source %', i, v_source;
    end if;

    v_instant := null; v_day := null;
    if nullif(r->>'release_at', '') is not null then
      -- ISO-8601 only: the bare ::timestamptz cast also accepts 'infinity', 'tomorrow', 'epoch'
      if (r->>'release_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' then
        raise exception 'INVALID_RELEASE_AT: row % release_at is not an ISO-8601 instant', i;
      end if;
      begin
        v_instant := (r->>'release_at')::timestamptz;
      exception when others then
        raise exception 'INVALID_RELEASE_AT: row % release_at is not an ISO-8601 instant', i;
      end;
      if not isfinite(v_instant) or v_instant < now() - interval '100 years' or v_instant > now() + interval '5 years' then
        raise exception 'INVALID_RELEASE_AT: row % release_at is outside the accepted range', i;
      end if;
    end if;
    if nullif(r->>'source_local_date', '') is not null then
      v_day := r->>'source_local_date';
      if v_day !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        raise exception 'INVALID_LOCAL_DATE: row % source_local_date must be YYYY-MM-DD', i;
      end if;
      begin
        perform v_day::date;
      exception when others then
        raise exception 'INVALID_LOCAL_DATE: row % source_local_date is not a calendar date', i;
      end;
    end if;
    v_prec := coalesce(nullif(r->>'precision', ''),
                       case when v_instant is not null then 'instant' when v_day is not null then 'day' else 'unknown' end);
    if v_prec not in ('instant', 'day', 'month', 'quarter', 'year', 'unknown') then
      raise exception 'INVALID_PRECISION: row % precision is not valid', i;
    end if;
    if (v_prec = 'instant' and (v_instant is null or v_day is not null))
       or (v_prec in ('day', 'month', 'quarter', 'year') and (v_day is null or v_instant is not null))
       or (v_prec = 'unknown' and (v_day is not null or v_instant is not null))
       or (v_prec = 'month' and substr(v_day, 9, 2) <> '01')
       or (v_prec = 'quarter' and (substr(v_day, 9, 2) <> '01' or substr(v_day, 6, 2) not in ('01', '04', '07', '10')))
       or (v_prec = 'year' and substr(v_day, 6, 5) <> '01-01') then
      raise exception 'INVALID_PRECISION: row % precision % does not match release_at/source_local_date', i, v_prec;
    end if;
    -- D10: confirmed means the source states the instant; a date without a time is announced.
    if v_basis = 'confirmed' and v_prec <> 'instant' then
      raise exception 'INVALID_PRECISION: row % confirmed rows need an instant (a date without a time is announced)', i;
    end if;
    if v_basis = 'estimated' and v_prec not in ('instant', 'day') then
      raise exception 'INVALID_PRECISION: row % estimated rows need an instant or a day', i;
    end if;

    v_zone := nullif(r->>'source_zone', '');
    if v_zone is not null and not exists (select 1 from pg_timezone_names where name = v_zone) then
      raise exception 'INVALID_SOURCE_ZONE: row % source_zone is not an IANA zone', i;
    end if;

    v_status := nullif(r->>'status', '');
    if v_status is null then
      v_status := case when v_basis = 'announced' then 'announced'
                       when v_basis = 'confirmed' and v_instant is not null and v_instant < now() then 'released'
                       else 'scheduled' end;
    end if;
    if v_status not in ('scheduled', 'released', 'delayed', 'cancelled', 'announced')
       or (v_basis = 'estimated' and v_status <> 'scheduled') then
      raise exception 'INVALID_STATUS: row % status % is not allowed for basis %', i, v_status, v_basis;
    end if;

    v_label := nullif(btrim(coalesce(r->>'unit_label', '')), '');
    if v_label is null then
      v_label := case v_kind when 'episode' then 'Ep. ' when 'chapter' then 'Ch. '
                             when 'volume' then 'Vol. ' else 'Season ' end || v_num::text;
    end if;
    if char_length(v_label) > 64 then
      raise exception 'INVALID_UNIT_LABEL: row % unit_label is longer than 64 characters', i;
    end if;

    v_observed := now();
    if nullif(r->>'observed_at', '') is not null then
      if (r->>'observed_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' then
        raise exception 'INVALID_OBSERVED_AT: row % observed_at is not an ISO-8601 instant', i;
      end if;
      begin
        v_observed := (r->>'observed_at')::timestamptz;
      exception when others then
        raise exception 'INVALID_OBSERVED_AT: row % observed_at is not an ISO-8601 instant', i;
      end;
      if not isfinite(v_observed) or v_observed < now() - interval '5 years' then
        raise exception 'INVALID_OBSERVED_AT: row % observed_at is outside the accepted range', i;
      end if;
      if v_observed > now() + interval '1 hour' then
        raise exception 'INVALID_OBSERVED_AT: row % observed_at is in the future', i;
      end if;
    end if;

    v_territory := nullif(r->>'territory', '');
    if v_territory is not null and v_territory !~ '^[A-Z]{2}$' then
      raise exception 'INVALID_TERRITORY: row % territory must be ISO 3166-1 alpha-2', i;
    end if;
    if char_length(coalesce(r->>'external_id', '')) > 120 then
      raise exception 'INVALID_EXTERNAL_ID: row % external_id is longer than 120 characters', i;
    end if;
    v_evidence := v_source || coalesce(':' || nullif(r->>'external_id', ''), '');

    v_identity := case when v_basis = 'estimated'
                       then 'kuro_estimate:' || v_medium || ':' || v_media || ':' || v_kind || ':next'
                       else v_source || ':' || v_medium || ':' || v_media || ':' || v_kind || ':' || v_num::text end;

    insert into public.release_events (medium, anime_id, manga_id, kind, precision, source_local_date, source_zone,
      utc_instant, territory, status, evidence, freshness, source_identity, unit_kind, unit_number, unit_label,
      basis, confidence, source, source_url, observed_at)
    values (v_medium, case when v_medium = 'anime' then v_media end, case when v_medium = 'manga' then v_media end,
      v_label, v_prec, v_day, v_zone, v_instant, v_territory, v_status, v_evidence, now(), v_identity, v_kind, v_num,
      v_label, v_basis, v_conf, v_source, v_url, v_observed)
    on conflict (source_identity) where source_identity is not null do nothing;
    get diagnostics v_n = row_count;
    if v_n = 1 then
      v_inserted := v_inserted + 1;
      continue;
    end if;

    select * into v_old from public.release_events where source_identity = v_identity for update;
    if (v_old.kind, v_old.precision, v_old.source_local_date, v_old.source_zone, v_old.utc_instant, v_old.territory,
        v_old.status, v_old.evidence, v_old.unit_number, v_old.unit_label, v_old.basis, v_old.confidence,
        v_old.source_url)
       is not distinct from
       (v_label, v_prec, v_day, v_zone, v_instant, v_territory, v_status, v_evidence, v_num, v_label, v_basis, v_conf,
        v_url) then
      -- identical facts: record that the source still says so, nothing else
      update public.release_events
         set observed_at = greatest(observed_at, v_observed), freshness = now()
       where id = v_old.id;
      v_unchanged := v_unchanged + 1;
    else
      update public.release_events
         set kind = v_label, precision = v_prec, source_local_date = v_day, source_zone = v_zone,
             utc_instant = v_instant, territory = v_territory, status = v_status, evidence = v_evidence,
             unit_number = v_num, unit_label = v_label, basis = v_basis, confidence = v_conf,
             source_url = v_url, observed_at = greatest(coalesce(observed_at, v_observed), v_observed),
             freshness = now(), revision = revision + 1
       where id = v_old.id;
      v_updated := v_updated + 1;
    end if;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke all on function public.upsert_release_events_v1(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_release_events_v1(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 9. upsert_theme_links_v1(jsonb): service-role writer for the themes worker
--
-- Input: JSON array (<= 500) of objects:
--   anime_id   Kuro anime.id (must exist)                          required
--   source_id  AnimeThemes theme/entry id, [A-Za-z0-9._-]{1,64}     required
--   kind       OP | ED | IN   (or role op | ed | insert)            required
--   sequence   1..99 (default 1)        version  1..99 or null
--   title      song title, 1..300 chars                             required
--   artist     <= 500 chars             episodes  e.g. '1-12', <= 64 chars
--   is_spoiler / is_nsfw  booleans (default false)
--   source     'animethemes' (default)  source_url  https credit link
-- Natural key: source_identity = 'animethemes:<anime_id>:<source_id>', the key
-- finish_series_enrichment_v1 already writes, so both producers converge on one row.
-- match_state stays 'search' and external_url NULL: no music-service URL is stored (D11).
-- Rows of other producers (curated links) are never touched. Nothing is deleted.
-- Returns {"inserted":n,"updated":n,"unchanged":n}. Any invalid row raises (nothing written).
-- ---------------------------------------------------------------------------
create or replace function public.upsert_theme_links_v1(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r jsonb; i integer := 0;
  v_anime integer; v_source_id text; v_role text; v_seq integer; v_version integer; v_title text;
  v_artist text; v_episodes text; v_spoiler boolean; v_nsfw boolean; v_url text; v_identity text;
  v_old public.theme_links%rowtype; v_n integer;
  v_inserted integer := 0; v_updated integer := 0; v_unchanged integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'INVALID_PAYLOAD: expected a JSON array of theme rows';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception 'PAYLOAD_TOO_LARGE: at most 500 theme rows per call';
  end if;

  for r in select value from jsonb_array_elements(p_rows) loop
    i := i + 1;
    if jsonb_typeof(r) <> 'object' then raise exception 'INVALID_ROW: row % is not an object', i; end if;

    if coalesce(r->>'anime_id', '') !~ '^[1-9][0-9]{0,9}$' or (r->>'anime_id')::bigint > 2147483647 then
      raise exception 'INVALID_MEDIA_ID: row % anime_id must be a positive integer id', i;
    end if;
    v_anime := (r->>'anime_id')::integer;
    if not exists (select 1 from public.anime where id = v_anime) then
      raise exception 'MEDIA_NOT_FOUND: row % (anime %)', i, v_anime;
    end if;

    v_source_id := r->>'source_id';
    if coalesce(v_source_id, '') !~ '^[A-Za-z0-9._-]{1,64}$' then
      raise exception 'INVALID_SOURCE_ID: row % source_id must be 1-64 of [A-Za-z0-9._-]', i;
    end if;

    v_role := case coalesce(r->>'kind', r->>'role')
                when 'OP' then 'op' when 'op' then 'op'
                when 'ED' then 'ed' when 'ed' then 'ed'
                when 'IN' then 'insert' when 'insert' then 'insert' end;
    if v_role is null then
      raise exception 'INVALID_KIND: row % kind must be OP, ED or IN', i;
    end if;

    if r ? 'sequence' and jsonb_typeof(r->'sequence') <> 'null' then
      if jsonb_typeof(r->'sequence') <> 'number' or (r->>'sequence') !~ '^[0-9]{1,2}$' or (r->>'sequence')::integer < 1 then
        raise exception 'INVALID_SEQUENCE: row % sequence must be 1..99', i;
      end if;
      v_seq := (r->>'sequence')::integer;
    else
      v_seq := 1;
    end if;
    v_version := null;
    if r ? 'version' and jsonb_typeof(r->'version') <> 'null' then
      if jsonb_typeof(r->'version') <> 'number' or (r->>'version') !~ '^[0-9]{1,2}$' or (r->>'version')::integer < 1 then
        raise exception 'INVALID_VERSION: row % version must be 1..99 or null', i;
      end if;
      v_version := (r->>'version')::integer;
    end if;

    v_title := nullif(btrim(coalesce(r->>'title', '')), '');
    if v_title is null or char_length(v_title) > 300 then
      raise exception 'INVALID_TITLE: row % title must be 1..300 characters', i;
    end if;
    v_artist := nullif(btrim(coalesce(r->>'artist', '')), '');
    if char_length(coalesce(v_artist, '')) > 500 then
      raise exception 'INVALID_ARTIST: row % artist is longer than 500 characters', i;
    end if;
    v_episodes := nullif(btrim(coalesce(r->>'episodes', '')), '');
    if char_length(coalesce(v_episodes, '')) > 64 then
      raise exception 'INVALID_EPISODES: row % episodes is longer than 64 characters', i;
    end if;

    if (r ? 'is_spoiler' and jsonb_typeof(r->'is_spoiler') not in ('boolean', 'null'))
       or (r ? 'is_nsfw' and jsonb_typeof(r->'is_nsfw') not in ('boolean', 'null')) then
      raise exception 'INVALID_FLAG: row % is_spoiler / is_nsfw must be booleans', i;
    end if;
    v_spoiler := coalesce((r->>'is_spoiler')::boolean, false);
    v_nsfw := coalesce((r->>'is_nsfw')::boolean, false);

    if coalesce(nullif(r->>'source', ''), 'animethemes') <> 'animethemes' then
      raise exception 'INVALID_SOURCE: row % source must be animethemes', i;
    end if;
    v_url := nullif(r->>'source_url', '');
    if v_url is not null and (v_url !~ '^https://animethemes\.moe/[^[:space:]]*$' or char_length(v_url) > 2048) then
      raise exception 'INVALID_SOURCE_URL: row % source_url must be an https://animethemes.moe/ link', i;
    end if;

    v_identity := 'animethemes:' || v_anime || ':' || v_source_id;

    insert into public.theme_links (anime_id, role, sequence_order, song_title, artist, external_url, match_state,
      evidence, source_identity, freshness, episodes, version, is_spoiler, is_nsfw, source, source_url)
    values (v_anime, v_role, v_seq, v_title, v_artist, null, 'search', 'animethemes:' || v_source_id, v_identity,
      now(), v_episodes, v_version, v_spoiler, v_nsfw, 'animethemes', v_url)
    on conflict (source_identity) where source_identity is not null do nothing;
    get diagnostics v_n = row_count;
    if v_n = 1 then
      v_inserted := v_inserted + 1;
      continue;
    end if;

    select * into v_old from public.theme_links where source_identity = v_identity for update;
    if v_old.anime_id <> v_anime then
      raise exception 'IDENTITY_CONFLICT: row % source identity belongs to another anime', i;
    end if;
    if (v_old.role, v_old.sequence_order, v_old.song_title, v_old.artist, v_old.episodes, v_old.version,
        v_old.is_spoiler, v_old.is_nsfw, v_old.source, v_old.source_url)
       is not distinct from
       (v_role, v_seq, v_title, v_artist, v_episodes, v_version, v_spoiler, v_nsfw, 'animethemes'::text, v_url) then
      update public.theme_links set freshness = now() where id = v_old.id;
      v_unchanged := v_unchanged + 1;
    else
      update public.theme_links
         set role = v_role, sequence_order = v_seq, song_title = v_title, artist = v_artist,
             episodes = v_episodes, version = v_version, is_spoiler = v_spoiler, is_nsfw = v_nsfw,
             source = 'animethemes', source_url = v_url, match_state = 'search', external_url = null,
             evidence = 'animethemes:' || v_source_id, freshness = now()
       where id = v_old.id;
      v_updated := v_updated + 1;
    end if;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke all on function public.upsert_theme_links_v1(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_theme_links_v1(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 10. finish_series_enrichment_v1 (live since 2026-10-08): re-created from 20261007040000
--     byte-for-byte except ONE added predicate in its theme delete,
--       and t.source is distinct from 'animethemes'
--     RULE: theme rows written by upsert_theme_links_v1 (source = 'animethemes', including
--     the '<theme>.v<n>' / '<theme>.e<entry>' version keys only that writer knows) are owned
--     by it. An older worker build or a manual finish call that still passes p_themes can
--     update its own keys but can no longer delete those rows. The current worker omits
--     p_themes (themes moved to the --themes pass).
-- ---------------------------------------------------------------------------
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
   and t.source is distinct from 'animethemes'
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

commit;
