-- 20261104100000_discover_usability_v1.sql
-- PREPARED, NOT DEPLOYED (2026-11-04 Discover usability pass, DATA lane). Deploying needs explicit
-- owner approval. Nothing here schedules a job, writes data or changes an existing function.
-- Depends on nothing pending: every object it reads is in the deployed chain
-- (anime, manga, anime_user_lists, manga_user_lists, taste_signal_events, media_franchise_components,
-- curated_rail_items, media_realm_membership_effective, recommend_ids_similar_to_seeds).
-- Spec: docs/superpowers/specs/2026-11-04-discover-usability-design.md ("Data contracts").
--
-- What it adds (all read-only, all plpgsql so the bodies are validated at call time):
--
--   media_franchise_ids_v1(p_anime_ids integer[], p_manga_ids integer[])
--     The franchise of every requested title: coalesce(media_franchise_components.component_label,
--     media_id). media_franchise_components (20260804140000) has RLS on, no policies and no client
--     grants on purpose, so this is a SECURITY DEFINER reader of exactly that one mapping (public
--     catalogue data). Components are SAME-MEDIUM only (built over same-type media_relations):
--     the anime and the manga of one series are different franchises here. Singletons (no row)
--     come back labelled as themselves. At most 300 ids per medium (TOO_MANY_IDS:).
--
--   discover_section_page_v1(p_section, p_media_type, p_sort, p_format, p_length, p_status,
--                            p_limit, p_offset)
--     The "See all" page of one Discover section, with sort and filters, offset-paged over a
--     deterministic order (sort key, then id desc). Sections and their own order:
--       essentials      curated gateway_anime / gateway_manga by rank (fallback: score >= 85 by
--                       favourites, as discover_bundle)
--       classics        curated classics_anime / classics_manga by rank (fallback: before 2015,
--                       score >= 80, as discover_bundle)
--       new_to_you      score >= 80, not on the caller's list, by popularity (NO impression
--                       rotation: this reader never writes; the bundle stays the rotating writer)
--       trending        trending > 0, by trending
--       top_rated       score >= 80, by score
--       newly_added     by created_at (the date the title entered Kuro)
--       current_season  anime only: this season/year (current_season rule of discover_bundle)
--       airing_today    anime only: RELEASING with next_airing_at on the Berlin day
--     p_sort: null/'default' (the section's order), 'popular' (popularity), 'newest' (RELEASE
--     date: start_date_year/month/day, then season_year; never created_at), 'top_rated' (score).
--     p_format: one AniList format (anime default surface hides SPECIAL / MUSIC / TV_SHORT unless
--     asked for explicitly, as browse_anime_page). p_length: anime 'short' 1-13 episodes,
--     'standard' 14-50, 'long' 51+ (D10: "Over 50 episodes"); manga 'short' 1-50 chapters (or 1-5 volumes when chapters are
--     unknown), 'standard' 51-150, 'long' 151+; unknown counts never match a length filter.
--     p_status: 'finished' / 'releasing' / 'upcoming' (FINISHED / RELEASING / NOT_YET_RELEASED).
--
--   discover_mood_v1(p_mood, p_media_type, p_limit, p_offset)
--     The mood journeys at the top of Discover, over existing data only:
--       short            anime: TV / ONA / OVA FINISHED with 1-13 episodes, or a MOVIE of at most
--                        25 minutes; manga: FINISHED with 1-50 chapters (or 1-5 volumes when
--                        chapters are unknown). Score >= 70, by popularity.
--       cozy             media_realm_membership_effective weight >= 0.25 (the realm membership
--                        threshold, _realm_membership_threshold() = 0.25) in any of
--                        slice-of-life-iyashikei, food-craft, family-generations, and NOT >= 0.25
--                        in horror-dread / tragedy-tearjerker / psychological-thriller; no Horror
--                        genre. Score >= 65, by summed cozy weight then popularity.
--       intense          weight >= 0.25 in any of psychological-thriller, horror-dread,
--                        dark-fantasy, war-military, crime-underworld, mind-game-strategy.
--                        Score >= 65, by summed weight then popularity.
--                        cozy / intense fall back to genres when the realm view is absent:
--                        cozy = 'Slice of Life' without Horror / Thriller / Psychological;
--                        intense = any of Thriller / Horror / Psychological.
--       like_last_loved  recommend_ids_similar_to_seeds(medium, [seed], ...) where the seed is the
--                        caller's most recently updated COMPLETED title rated >= 8 (1-10 scale),
--                        else the most recent COMPLETED one, else the most recent deck 'love'.
--                        reason_media_id / reason_title name the seed on every row. Signed out or
--                        no seed: no rows. At most 60 ranked candidates (the similar store depth).
--
-- Shared rules of both page readers (one internal finisher, _discover_page_v1):
--   * excluded: adult, Hentai / Ecchi genres, titles without a cover;
--   * hidden (R5): the caller's taste_signal_events 'deck_skip' (Not interested) and 'deck_known'
--     (Seen it) of the last 365 days are never returned. 'deck_pass' ("dealt, undecided",
--     20260731090000) does NOT hide: an undecided swipe in the Taste deck must not vanish from
--     Discover;
--   * owned (R2): personal sections (new_to_you) and every mood HIDE titles on the caller's list;
--     editorial sections keep them and return list_status (the caller's list_type) so the card
--     can carry the status word;
--   * franchise dedupe (R2): one title per franchise component, the first in the page order wins,
--     applied over the whole ordered pool BEFORE the offset, so pages never repeat a franchise;
--   * rank = 1-based position in that deduped order (stable across pages for an unchanged
--     catalogue), franchise_id on every row so the client can dedupe across sections.
--   Owner comparison: list rows match on user_id = auth.uid()::text, the same comparison the list
--   RLS policy uses (rows stored in another spelling are invisible to their owner under RLS too;
--   the canonical-case trigger 20261005180000 keeps new writes lower-case).
--
-- Row shape (both page readers): media_type, rank, id, title_english, title_romaji, title_native,
--   cover_image_large, cover_image_medium, banner_image, format, status, episode_count,
--   chapter_count, volumes, season_year, start_date_year, average_score, popularity, trending,
--   favourites, genres, created_at, franchise_id, list_status, reason_media_id, reason_title.
--   The names match AnimeCard / MangaCard (episode_count / chapter_count) so the app's existing
--   card models decode the rows.
--
-- Errors are in the MESSAGE ('CODE: text'; supabase-swift does not decode DETAIL):
--   INVALID_MEDIUM:, INVALID_SECTION:, INVALID_SORT:, INVALID_LENGTH:, INVALID_STATUS:,
--   INVALID_MOOD:, TOO_MANY_IDS:.
-- Grants: the internal finisher has NO client EXECUTE; the three readers are granted to anon and
--   authenticated (signed out: no personal exclusions, like_last_loved answers no rows).
--
-- Rollback:
--   drop function public.discover_mood_v1(text, text, integer, integer);
--   drop function public.discover_section_page_v1(text, text, text, text, text, text, integer, integer);
--   drop function public.media_franchise_ids_v1(integer[], integer[]);
--   drop function public._discover_page_v1(uuid, text, integer[], boolean, integer, integer, integer, text);

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1) media_franchise_ids_v1
-- ---------------------------------------------------------------------------
create or replace function public.media_franchise_ids_v1(
  p_anime_ids integer[] default '{}'::integer[],
  p_manga_ids integer[] default '{}'::integer[]
)
returns table (media_type text, media_id integer, franchise_id integer)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
begin
  if coalesce(cardinality(p_anime_ids), 0) > 300 or coalesce(cardinality(p_manga_ids), 0) > 300 then
    raise exception 'TOO_MANY_IDS: at most 300 ids per medium';
  end if;

  return query
  with wanted as (
    select distinct 'ANIME'::text as t, x.i
    from unnest(coalesce(p_anime_ids, '{}'::integer[])) as x(i)
    where x.i is not null and x.i > 0
    union
    select distinct 'MANGA'::text, x.i
    from unnest(coalesce(p_manga_ids, '{}'::integer[])) as x(i)
    where x.i is not null and x.i > 0
  )
  select w.t, w.i, coalesce(fc.component_label, w.i)
  from wanted w
  left join public.media_franchise_components fc
    on fc.media_type = w.t and fc.media_id = w.i
  order by w.t, w.i;
end;
$$;

revoke all on function public.media_franchise_ids_v1(integer[], integer[]) from public, anon, authenticated;
grant execute on function public.media_franchise_ids_v1(integer[], integer[]) to anon, authenticated, service_role;

comment on function public.media_franchise_ids_v1(integer[], integer[]) is
  '20261104100000 (prepared). Franchise of each requested title: coalesce(media_franchise_components.component_label, id). Same-medium components only. SECURITY DEFINER reader of that one public mapping (the table has no client grants). At most 300 ids per medium (TOO_MANY_IDS:).';

-- ---------------------------------------------------------------------------
-- 2) _discover_page_v1 (internal finisher; no client EXECUTE)
--    p_ids is the ordered candidate pool. Applies: catalogue exclusions, hidden titles,
--    the owned rule, franchise dedupe (first in order wins), then offset/limit.
-- ---------------------------------------------------------------------------
create or replace function public._discover_page_v1(
  p_uid uuid,
  p_media_type text,
  p_ids integer[],
  p_hide_owned boolean,
  p_limit integer,
  p_offset integer,
  p_reason_media_id integer default null,
  p_reason_title text default null
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid_text text := p_uid::text;
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(500, greatest(0, coalesce(p_offset, 0)));
begin
  if p_media_type = 'ANIME' then
    return query
    with ordered as (
      select x.mid, min(x.ord) as ord
      from unnest(coalesce(p_ids, '{}'::integer[])) with ordinality as x(mid, ord)
      where x.mid is not null
      group by x.mid
    ),
    eligible as (
      select o.ord, a.id as aid, coalesce(fc.component_label, a.id) as fid, ul.list_type as lt
      from ordered o
      join public.anime a on a.id = o.mid
      left join public.media_franchise_components fc
        on fc.media_type = 'ANIME' and fc.media_id = a.id
      left join public.anime_user_lists ul
        on p_uid is not null and ul.user_id = v_uid_text and ul.anime_id = a.id
      where coalesce(a.is_adult, false) = false
        and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
        and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
        and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
        and (not coalesce(p_hide_owned, false) or ul.anime_id is null)
        and not exists (
          select 1 from public.taste_signal_events e
          where p_uid is not null
            and e.user_id = p_uid
            and e.media_type = 'ANIME'
            and e.media_id = a.id
            and e.event_type in ('deck_skip', 'deck_known')
            and e.created_at > now() - interval '365 days'
        )
    ),
    deduped as (
      select distinct on (e.fid) e.ord, e.aid, e.fid, e.lt
      from eligible e
      order by e.fid, e.ord
    ),
    ranked as (
      select d.*, (row_number() over (order by d.ord))::integer as rn
      from deduped d
    )
    select 'ANIME'::text, r.rn, a.id,
           a.title_english, a.title_romaji, a.title_native,
           a.cover_image_large, a.cover_image_medium, a.banner_image,
           a.format, a.status, a.episodes, null::integer, null::integer,
           a.season_year, a.start_date_year,
           a.average_score, a.popularity, a.trending, a.favourites,
           a.genres, a.created_at,
           r.fid, r.lt,
           p_reason_media_id, p_reason_title
    from ranked r
    join public.anime a on a.id = r.aid
    where r.rn > v_offset
    order by r.rn
    limit v_limit;
  elsif p_media_type = 'MANGA' then
    return query
    with ordered as (
      select x.mid, min(x.ord) as ord
      from unnest(coalesce(p_ids, '{}'::integer[])) with ordinality as x(mid, ord)
      where x.mid is not null
      group by x.mid
    ),
    eligible as (
      select o.ord, m.id as mid2, coalesce(fc.component_label, m.id) as fid, ul.list_type as lt
      from ordered o
      join public.manga m on m.id = o.mid
      left join public.media_franchise_components fc
        on fc.media_type = 'MANGA' and fc.media_id = m.id
      left join public.manga_user_lists ul
        on p_uid is not null and ul.user_id = v_uid_text and ul.manga_id = m.id
      where coalesce(m.is_adult, false) = false
        and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
        and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
        and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
        and (not coalesce(p_hide_owned, false) or ul.manga_id is null)
        and not exists (
          select 1 from public.taste_signal_events e
          where p_uid is not null
            and e.user_id = p_uid
            and e.media_type = 'MANGA'
            and e.media_id = m.id
            and e.event_type in ('deck_skip', 'deck_known')
            and e.created_at > now() - interval '365 days'
        )
    ),
    deduped as (
      select distinct on (e.fid) e.ord, e.mid2, e.fid, e.lt
      from eligible e
      order by e.fid, e.ord
    ),
    ranked as (
      select d.*, (row_number() over (order by d.ord))::integer as rn
      from deduped d
    )
    select 'MANGA'::text, r.rn, m.id,
           m.title_english, m.title_romaji, m.title_native,
           m.cover_image_large, m.cover_image_medium, m.banner_image,
           m.format, m.status, null::integer, m.chapters, m.volumes,
           null::integer, m.start_date_year,
           m.average_score, m.popularity, m.trending, m.favourites,
           m.genres, m.created_at,
           r.fid, r.lt,
           p_reason_media_id, p_reason_title
    from ranked r
    join public.manga m on m.id = r.mid2
    where r.rn > v_offset
    order by r.rn
    limit v_limit;
  else
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
end;
$$;

revoke all on function public._discover_page_v1(uuid, text, integer[], boolean, integer, integer, integer, text) from public, anon, authenticated;
-- No grants: called only by the SECURITY DEFINER readers below (same owner), which pass auth.uid().

comment on function public._discover_page_v1(uuid, text, integer[], boolean, integer, integer, integer, text) is
  '20261104100000 (prepared). Internal finisher of the Discover page readers: catalogue exclusions (adult, Hentai/Ecchi, no cover), the caller''s deck_skip/deck_known of 365 days hidden, owned titles hidden (p_hide_owned) or marked (list_status), franchise dedupe over the whole ordered pool (first wins), then offset/limit. No client EXECUTE.';

-- ---------------------------------------------------------------------------
-- 3) discover_section_page_v1
-- ---------------------------------------------------------------------------
create or replace function public.discover_section_page_v1(
  p_section text,
  p_media_type text default 'ANIME',
  p_sort text default null,
  p_format text default null,
  p_length text default null,
  p_status text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_section text := lower(btrim(coalesce(p_section, '')));
  v_sort text := lower(btrim(coalesce(nullif(btrim(p_sort), ''), 'default')));
  v_format text := upper(nullif(btrim(coalesce(p_format, '')), ''));
  v_length text := lower(nullif(btrim(coalesce(p_length, '')), ''));
  v_status_in text := lower(nullif(btrim(coalesce(p_status, '')), ''));
  v_status text;
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(440, greatest(0, coalesce(p_offset, 0)));
  -- Pool depth: enough for the requested page after hidden/owned/franchise removals.
  v_pool integer;
  v_season text := case
    when extract(month from now())::int in (12, 1, 2) then 'WINTER'
    when extract(month from now())::int in (3, 4, 5) then 'SPRING'
    when extract(month from now())::int in (6, 7, 8) then 'SUMMER'
    else 'FALL' end;
  v_year integer := extract(year from now())::int;
  v_day_start timestamptz := (date_trunc('day', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin');
  v_day_end timestamptz := ((date_trunc('day', now() at time zone 'Europe/Berlin') + interval '1 day') at time zone 'Europe/Berlin');
  v_curated_rail text;
  v_has_curated boolean := false;
  v_ids integer[];
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if v_section not in ('essentials', 'classics', 'new_to_you', 'trending', 'top_rated', 'newly_added',
                       'current_season', 'airing_today')
     or (v_type = 'MANGA' and v_section in ('current_season', 'airing_today')) then
    raise exception 'INVALID_SECTION: % is not a % Discover section', p_section, v_type;
  end if;
  if v_sort not in ('default', 'popular', 'newest', 'top_rated') then
    raise exception 'INVALID_SORT: p_sort must be default, popular, newest or top_rated';
  end if;
  if v_length is not null and v_length not in ('short', 'standard', 'long') then
    raise exception 'INVALID_LENGTH: p_length must be short, standard or long';
  end if;
  v_status := case v_status_in
    when 'finished' then 'FINISHED'
    when 'releasing' then 'RELEASING'
    when 'upcoming' then 'NOT_YET_RELEASED'
    else null end;
  if v_status_in is not null and v_status is null then
    raise exception 'INVALID_STATUS: p_status must be finished, releasing or upcoming';
  end if;

  v_pool := least(500, v_offset + v_limit * 4 + 40);

  if v_section in ('essentials', 'classics') then
    v_curated_rail := case v_section when 'essentials' then 'gateway_' else 'classics_' end
                      || lower(v_type);
    if to_regclass('public.curated_rail_items') is not null then
      execute 'select exists (select 1 from public.curated_rail_items where rail_id = $1 and media_type = $2)'
        into v_has_curated using v_curated_rail, v_type;
    end if;
  end if;

  if v_type = 'ANIME' then
    if v_has_curated then
      execute $q$
        select array_agg(s.aid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last, s.aid desc)
        from (
          select a.id as aid,
                 case when $3 = 'default' then -min(i.rank)::bigint
                      when $3 = 'popular' then max(a.popularity)::bigint
                      when $3 = 'top_rated' then max(a.average_score)::bigint
                      else max(coalesce(a.start_date_year, a.season_year))::bigint end as k1,
                 case when $3 = 'newest' then max(a.start_date_month)::bigint else null end as k2,
                 case when $3 = 'newest' then max(a.start_date_day)::bigint else null end as k3
          from public.curated_rail_items i
          join public.anime a on a.anilist_id = i.anilist_id
          where i.rail_id = $1 and i.media_type = 'ANIME'
            and (($2::text is null and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
                 or upper(coalesce(a.format, '')) = $2)
            and ($4::text is null
                 or ($4 = 'short' and a.episodes between 1 and 13)
                 or ($4 = 'standard' and a.episodes between 14 and 50)
                 or ($4 = 'long' and a.episodes >= 51))
            and ($5::text is null or a.status = $5)
          group by a.id
          order by 2 desc nulls last, 3 desc nulls last, 4 desc nulls last, 1 desc
          limit $6
        ) s
      $q$ into v_ids using v_curated_rail, v_format, v_sort, v_length, v_status, v_pool;
    else
      select array_agg(s.aid order by s.ord) into v_ids
      from (
        select a.id as aid,
               row_number() over (
                 order by
                   -- the section's own order (default)
                   case when v_sort = 'default' and v_section = 'essentials' then coalesce(a.favourites, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section in ('essentials', 'classics', 'top_rated') then coalesce(a.average_score, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section = 'trending' then coalesce(a.trending, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section = 'newly_added' then a.created_at end desc nulls last,
                   -- chosen sorts
                   case when v_sort = 'top_rated' then a.average_score end desc nulls last,
                   case when v_sort = 'newest' then coalesce(a.start_date_year, a.season_year) end desc nulls last,
                   case when v_sort = 'newest' then a.start_date_month end desc nulls last,
                   case when v_sort = 'newest' then a.start_date_day end desc nulls last,
                   -- popularity: the 'popular' sort and every section's tiebreak
                   coalesce(a.popularity, 0) desc,
                   a.id desc
               ) as ord
        from public.anime a
        where coalesce(a.is_adult, false) = false
          and ((v_format is null and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
               or upper(coalesce(a.format, '')) = v_format)
          and (v_length is null
               or (v_length = 'short' and a.episodes between 1 and 13)
               or (v_length = 'standard' and a.episodes between 14 and 50)
               or (v_length = 'long' and a.episodes >= 51))
          and (v_status is null or a.status = v_status)
          and case v_section
                when 'essentials' then coalesce(a.average_score, 0) >= 85
                when 'classics' then coalesce(a.season_year, a.start_date_year, 9999) < 2015
                                     and coalesce(a.average_score, 0) >= 80
                when 'new_to_you' then coalesce(a.average_score, 0) >= 80
                when 'trending' then coalesce(a.trending, 0) > 0
                when 'top_rated' then coalesce(a.average_score, 0) >= 80
                when 'newly_added' then true
                when 'current_season' then a.season = v_season and a.season_year = v_year
                when 'airing_today' then a.status = 'RELEASING' and a.next_airing_at >= v_day_start
                                         and a.next_airing_at < v_day_end
                else false
              end
        order by ord
        limit v_pool
      ) s;
    end if;
  else
    if v_has_curated then
      execute $q$
        select array_agg(s.mid order by s.k1 desc nulls last, s.k2 desc nulls last, s.k3 desc nulls last, s.mid desc)
        from (
          select m.id as mid,
                 case when $3 = 'default' then -min(i.rank)::bigint
                      when $3 = 'popular' then max(m.popularity)::bigint
                      when $3 = 'top_rated' then max(m.average_score)::bigint
                      else max(m.start_date_year)::bigint end as k1,
                 case when $3 = 'newest' then max(m.start_date_month)::bigint else null end as k2,
                 case when $3 = 'newest' then max(m.start_date_day)::bigint else null end as k3
          from public.curated_rail_items i
          join public.manga m on m.anilist_id = i.anilist_id
          where i.rail_id = $1 and i.media_type = 'MANGA'
            and ($2::text is null or upper(coalesce(m.format, '')) = $2)
            and ($4::text is null
                 or ($4 = 'short' and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5)))
                 or ($4 = 'standard' and m.chapters between 51 and 150)
                 or ($4 = 'long' and m.chapters >= 151))
            and ($5::text is null or m.status = $5)
          group by m.id
          order by 2 desc nulls last, 3 desc nulls last, 4 desc nulls last, 1 desc
          limit $6
        ) s
      $q$ into v_ids using v_curated_rail, v_format, v_sort, v_length, v_status, v_pool;
    else
      select array_agg(s.mid order by s.ord) into v_ids
      from (
        select m.id as mid,
               row_number() over (
                 order by
                   case when v_sort = 'default' and v_section = 'essentials' then coalesce(m.favourites, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section in ('essentials', 'classics', 'top_rated') then coalesce(m.average_score, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section = 'trending' then coalesce(m.trending, 0) end desc nulls last,
                   case when v_sort = 'default' and v_section = 'newly_added' then m.created_at end desc nulls last,
                   case when v_sort = 'top_rated' then m.average_score end desc nulls last,
                   case when v_sort = 'newest' then m.start_date_year end desc nulls last,
                   case when v_sort = 'newest' then m.start_date_month end desc nulls last,
                   case when v_sort = 'newest' then m.start_date_day end desc nulls last,
                   coalesce(m.popularity, 0) desc,
                   m.id desc
               ) as ord
        from public.manga m
        where coalesce(m.is_adult, false) = false
          and (v_format is null or upper(coalesce(m.format, '')) = v_format)
          and (v_length is null
               or (v_length = 'short' and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5)))
               or (v_length = 'standard' and m.chapters between 51 and 150)
               or (v_length = 'long' and m.chapters >= 151))
          and (v_status is null or m.status = v_status)
          and case v_section
                when 'essentials' then coalesce(m.average_score, 0) >= 85
                when 'classics' then coalesce(m.start_date_year, 9999) < 2015 and coalesce(m.average_score, 0) >= 80
                when 'new_to_you' then coalesce(m.average_score, 0) >= 80
                when 'trending' then coalesce(m.trending, 0) > 0
                when 'top_rated' then coalesce(m.average_score, 0) >= 80
                when 'newly_added' then true
                else false
              end
        order by ord
        limit v_pool
      ) s;
    end if;
  end if;

  return query
  select * from public._discover_page_v1(
    v_uid, v_type, coalesce(v_ids, '{}'::integer[]), v_section = 'new_to_you', v_limit, v_offset
  );
end;
$$;

revoke all on function public.discover_section_page_v1(text, text, text, text, text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.discover_section_page_v1(text, text, text, text, text, text, integer, integer) to anon, authenticated, service_role;

comment on function public.discover_section_page_v1(text, text, text, text, text, text, integer, integer) is
  '20261104100000 (prepared). "See all" page of one Discover section (essentials, classics, new_to_you, trending, top_rated, newly_added, current_season and airing_today for anime) with sort default/popular/newest(release date)/top_rated and filters format/length/status, offset-paged over a deterministic order. Hidden (deck_skip/deck_known, 365 d) never returned; new_to_you hides owned titles, the other sections mark them (list_status); franchise-deduped before the offset. Read-only (no impressions).';

-- ---------------------------------------------------------------------------
-- 4) discover_mood_v1
-- ---------------------------------------------------------------------------
create or replace function public.discover_mood_v1(
  p_mood text,
  p_media_type text default 'ANIME',
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_mood text := lower(btrim(coalesce(p_mood, '')));
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(440, greatest(0, coalesce(p_offset, 0)));
  v_pool integer;
  v_threshold real := 0.25;
  v_cozy text[] := array['slice-of-life-iyashikei', 'food-craft', 'family-generations'];
  v_not_cozy text[] := array['horror-dread', 'tragedy-tearjerker', 'psychological-thriller'];
  v_intense text[] := array['psychological-thriller', 'horror-dread', 'dark-fantasy', 'war-military',
                            'crime-underworld', 'mind-game-strategy'];
  v_realms boolean := to_regclass('public.media_realm_membership_effective') is not null;
  v_seed integer;
  v_seed_title text;
  v_ids integer[];
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if v_mood not in ('short', 'cozy', 'intense', 'like_last_loved') then
    raise exception 'INVALID_MOOD: p_mood must be short, cozy, intense or like_last_loved';
  end if;
  v_pool := least(500, v_offset + v_limit * 4 + 40);

  if v_mood = 'short' then
    if v_type = 'ANIME' then
      select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
      from (
        select a.id as aid, coalesce(a.popularity, 0) as pop
        from public.anime a
        where coalesce(a.is_adult, false) = false
          and coalesce(a.average_score, 0) >= 70
          and ((upper(coalesce(a.format, '')) in ('TV', 'ONA', 'OVA') and a.status = 'FINISHED'
                and a.episodes between 1 and 13)
               or (upper(coalesce(a.format, '')) = 'MOVIE' and a.duration between 1 and 25))
        order by coalesce(a.popularity, 0) desc, a.id desc
        limit v_pool
      ) s;
    else
      select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
      from (
        select m.id as mid, coalesce(m.popularity, 0) as pop
        from public.manga m
        where coalesce(m.is_adult, false) = false
          and coalesce(m.average_score, 0) >= 70
          and m.status = 'FINISHED'
          and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5))
        order by coalesce(m.popularity, 0) desc, m.id desc
        limit v_pool
      ) s;
    end if;
  elsif v_mood in ('cozy', 'intense') then
    if v_realms then
      execute $q$
        select array_agg(s.mid order by s.w desc, s.pop desc, s.mid desc)
        from (
          select r.media_id as mid, sum(r.weight)::real as w, max(coalesce(t.pop, 0)) as pop
          from public.media_realm_membership_effective r
          join (
            select a.id, a.popularity as pop, a.average_score as sc, a.genres as g, a.is_adult as adult, a.format as f
            from public.anime a where $1 = 'ANIME'
            union all
            select m.id, m.popularity, m.average_score, m.genres, m.is_adult, m.format
            from public.manga m where $1 = 'MANGA'
          ) t on t.id = r.media_id
          where r.media_type = $1
            and r.realm = any($2)
            and r.weight >= $4
            and coalesce(t.adult, false) = false
            and coalesce(t.sc, 0) >= 65
            and ($1 = 'MANGA' or upper(coalesce(t.f, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
            and ($5 = false or not ('Horror' = any(coalesce(t.g, '{}'::text[]))))
            and not exists (
              select 1 from public.media_realm_membership_effective x
              where x.media_type = r.media_type and x.media_id = r.media_id
                and x.realm = any($3) and x.weight >= $4
            )
          group by r.media_id
          order by 2 desc, 3 desc, 1 desc
          limit $6
        ) s
      $q$ into v_ids
      using v_type,
            case when v_mood = 'cozy' then v_cozy else v_intense end,
            case when v_mood = 'cozy' then v_not_cozy else array[]::text[] end,
            v_threshold, v_mood = 'cozy', v_pool;
    elsif v_type = 'ANIME' then
      select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
      from (
        select a.id as aid, coalesce(a.popularity, 0) as pop
        from public.anime a
        where coalesce(a.is_adult, false) = false
          and coalesce(a.average_score, 0) >= 65
          and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(a.genres, '{}'::text[]))
                        and not (coalesce(a.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(a.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
        order by coalesce(a.popularity, 0) desc, a.id desc
        limit v_pool
      ) s;
    else
      select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
      from (
        select m.id as mid, coalesce(m.popularity, 0) as pop
        from public.manga m
        where coalesce(m.is_adult, false) = false
          and coalesce(m.average_score, 0) >= 65
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(m.genres, '{}'::text[]))
                        and not (coalesce(m.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(m.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
        order by coalesce(m.popularity, 0) desc, m.id desc
        limit v_pool
      ) s;
    end if;
  else
    -- like_last_loved: the caller's seed; signed out or no seed answers no rows.
    if v_uid is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select ul.anime_id into v_seed
      from public.anime_user_lists ul
      where ul.user_id = v_uid::text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.anime_id desc
      limit 1;
    else
      select ul.manga_id into v_seed
      from public.manga_user_lists ul
      where ul.user_id = v_uid::text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.manga_id desc
      limit 1;
    end if;
    if v_seed is null then
      select e.media_id into v_seed
      from public.taste_signal_events e
      where e.user_id = v_uid and e.media_type = v_type and e.event_type = 'deck_love'
      order by e.created_at desc, e.id desc
      limit 1;
    end if;
    if v_seed is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select coalesce(a.title_english, a.title_romaji, a.title_native) into v_seed_title
      from public.anime a where a.id = v_seed;
    else
      select coalesce(m.title_english, m.title_romaji, m.title_native) into v_seed_title
      from public.manga m where m.id = v_seed;
    end if;
    select array_agg(r.media_id order by r.ord) into v_ids
    from public.recommend_ids_similar_to_seeds(v_type, array[v_seed], 60, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    where r.media_id <> v_seed;

    return query
    select * from public._discover_page_v1(
      v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset, v_seed, v_seed_title
    );
    return;
  end if;

  return query
  select * from public._discover_page_v1(
    v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset
  );
end;
$$;

revoke all on function public.discover_mood_v1(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.discover_mood_v1(text, text, integer, integer) to anon, authenticated, service_role;

comment on function public.discover_mood_v1(text, text, integer, integer) is
  '20261104100000 (prepared). Discover mood journeys over existing data: short (episode/chapter counts, short movies), cozy / intense (media_realm_membership_effective realm sets at the 0.25 membership threshold; genre fallback when the view is absent), like_last_loved (recommend_ids_similar_to_seeds from the caller''s latest COMPLETED title rated >= 8, else latest COMPLETED, else latest deck love; reason_media_id/reason_title name it). Owned and hidden (deck_skip/deck_known, 365 d) titles never returned; franchise-deduped before the offset. Read-only.';

commit;
