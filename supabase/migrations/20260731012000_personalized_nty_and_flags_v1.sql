-- ADR 2026-07-31: personalized NEW TO YOU consumer (flag: personalized_new_to_you_v1, 0%).
-- Candidate pool mirrors discover_bundle NEW TO YOU (20260326234000):
--   not adult, no Hentai/Ecchi, anime formats SPECIAL/MUSIC/TV_SHORT excluded,
--   not in caller's lists, average_score >= 80, impression rotation memory.
-- Ranking: final = editorial_prior * 0.8 + personalized_fit * confidence.
--   editorial_prior = popularity normalized to [0,1] over the candidate set
--     (the existing popularity/score ordering value, made comparable to fit).
--   personalized_fit = caller's profile genre weights + tag weights * rank/100,
--     -0.5 if the title carries an avoided_tag with rank >= 60; normalized by the
--     best raw fit in the set and clamped to [-1, 1], so fit * confidence <= 0.20
--     and the editorial prior always stays the dominant term (contract invariant).
-- Fallback: no profile row, or confidence = 0.05 with event_count = 0 -> pure editorial.
-- discover_bundle and the matviews are untouched.

-- ---------------------------------------------------------------------------
-- 0) Impression helpers. discover_rail_impressions is revoked from anon/
-- authenticated by design; these SECURITY DEFINER helpers touch ONLY the
-- caller's own rows (auth.uid()), which is why definer is needed here.
-- Rotation window: 7 days (interpreted; discover_bundle has no explicit window,
-- it only soft-orders by last_shown_at).
-- ---------------------------------------------------------------------------
create or replace function public._taste_recent_impressed_ids(
  p_rail_key text,
  p_media_type text,
  p_window interval default interval '7 days'
)
returns integer[]
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(array_agg(i.media_id), '{}'::integer[])
  from public.discover_rail_impressions i
  where i.user_id = auth.uid()::text
    and i.rail_key = p_rail_key
    and i.media_type = lower(p_media_type)
    and i.last_shown_at > now() - p_window;
$$;

create or replace function public._taste_stamp_impressions(
  p_rail_key text,
  p_media_type text,
  p_media_ids integer[]
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null or p_media_ids is null then
    return;
  end if;
  insert into public.discover_rail_impressions (user_id, rail_key, media_type, media_id, last_shown_at)
  select auth.uid()::text, p_rail_key, lower(p_media_type), id, now()
  from unnest(p_media_ids) as id
  on conflict (user_id, rail_key, media_type, media_id)
  do update set last_shown_at = excluded.last_shown_at;
end;
$$;

revoke all on function public._taste_recent_impressed_ids(text, text, interval) from public;
revoke all on function public._taste_stamp_impressions(text, text, integer[]) from public;
grant execute on function public._taste_recent_impressed_ids(text, text, interval) to authenticated, service_role;
grant execute on function public._taste_stamp_impressions(text, text, integer[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1) Personalized NEW TO YOU (SECURITY INVOKER: catalog + caller's own rows)
-- ---------------------------------------------------------------------------
create or replace function public.fetch_personalized_new_to_you(
  p_limit integer default 20,
  p_media_type text default 'ANIME'
)
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text
)
language plpgsql
volatile
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_type text := upper(trim(coalesce(p_media_type, 'ANIME')));
  v_lim integer := greatest(1, least(coalesce(p_limit, 20), 60));
  v_vector jsonb;
  v_confidence double precision := 0;
  v_event_count integer := 0;
  v_personalize boolean := false;
  v_ids integer[] := '{}'::integer[];
  r record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;

  select p.vector into v_vector
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_vector is not null then
    v_confidence := coalesce((v_vector->>'confidence')::double precision, 0);
    v_event_count := coalesce((v_vector->>'event_count')::integer, 0);
    -- Cold start: confidence 0.05 with zero events means "no evidence" -> editorial only.
    v_personalize := v_confidence > 0
      and not (v_confidence = 0.05 and v_event_count = 0);
  end if;

  if v_type = 'ANIME' then
    for r in
      with candidates as (
        select
          a.id as media_id,
          coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
          a.cover_image_large,
          a.cover_image_medium,
          a.cover_image_color,
          a.genres,
          a.average_score,
          a.format,
          coalesce(a.season_year, a.start_date_year) as year,
          left(coalesce(a.description_normalized, ''), 300) as synopsis,
          coalesce(a.popularity, 0) as popularity,
          coalesce(a.favourites, 0) as favourites
        from public.anime a
        where coalesce(a.is_adult, false) = false
          and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
          and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
          and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
          and coalesce(a.average_score, 0) >= 80
          and not exists (
            select 1 from public.anime_user_lists ul
            where ul.user_id = v_uid::text
              and ul.anime_id = a.id
          )
          and not (a.id = any (public._taste_recent_impressed_ids('discover_new_to_you', 'anime')))
        order by coalesce(a.popularity, 0) desc, coalesce(a.average_score, 0) desc,
                 coalesce(a.favourites, 0) desc, a.id desc
        limit greatest(v_lim * 6, 60)
      ),
      scored as (
        select
          c.*,
          case
            when coalesce(max(c.popularity) over (), 0) > 0
              then c.popularity::double precision / max(c.popularity) over ()
            else 0.0
          end as editorial_prior,
          (
            coalesce((
              select sum((v_vector->'genres'->>g)::double precision)
              from unnest(c.genres) as g
            ), 0.0)
            + coalesce((
              select sum(
                (v_vector->'tags'->>t.name)::double precision
                * (coalesce(at2.rank, 0)::double precision / 100.0)
              )
              from public.anime_tags at2
              join public.tags t on t.id = at2.tag_id
              where at2.anime_id = c.media_id
            ), 0.0)
            + case when exists (
              select 1
              from public.anime_tags at3
              join public.tags t3 on t3.id = at3.tag_id
              where at3.anime_id = c.media_id
                and at3.rank >= 60
                and coalesce(v_vector->'avoided_tags', '[]'::jsonb) ? t3.name
            ) then -0.5 else 0.0 end
          ) as raw_fit
        from candidates c
      ),
      normed as (
        select
          s.*,
          -- Normalize by the best positive raw fit; when nothing is positive
          -- (e.g. avoidance-only profile) keep raw negatives so the avoided-tag
          -- penalty still bites. Clamped to [-1, 1] so |fit * confidence| <= 0.20.
          case
            when not v_personalize then 0.0
            when coalesce(max(s.raw_fit) over (), 0) > 0
              then greatest(least(s.raw_fit / max(s.raw_fit) over (), 1.0), -1.0)
            else greatest(s.raw_fit, -1.0)
          end as fit
        from scored s
      )
      select
        'ANIME'::text as media_type,
        n.media_id,
        n.title,
        n.cover_image_large,
        n.cover_image_medium,
        n.cover_image_color,
        n.genres,
        n.average_score,
        n.format,
        n.year,
        n.synopsis
      from normed n
      order by
        (n.editorial_prior * 0.8 + n.fit * v_confidence) desc,
        n.popularity desc,
        n.average_score desc,
        n.favourites desc,
        n.media_id desc
      limit v_lim
    loop
      v_ids := v_ids || r.media_id;
      media_type := r.media_type;
      media_id := r.media_id;
      title := r.title;
      cover_image_large := r.cover_image_large;
      cover_image_medium := r.cover_image_medium;
      cover_image_color := r.cover_image_color;
      genres := r.genres;
      average_score := r.average_score;
      format := r.format;
      year := r.year;
      synopsis := r.synopsis;
      return next;
    end loop;
    perform public._taste_stamp_impressions('discover_new_to_you', 'anime', v_ids);
  else
    for r in
      with candidates as (
        select
          m.id as media_id,
          coalesce(nullif(m.title_english, ''), m.title_romaji) as title,
          m.cover_image_large,
          m.cover_image_medium,
          m.cover_image_color,
          m.genres,
          m.average_score,
          m.format,
          m.start_date_year as year,
          left(coalesce(m.description_normalized, ''), 300) as synopsis,
          coalesce(m.popularity, 0) as popularity,
          coalesce(m.favourites, 0) as favourites
        from public.manga m
        where coalesce(m.is_adult, false) = false
          and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
          and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
          and coalesce(m.average_score, 0) >= 80
          and not exists (
            select 1 from public.manga_user_lists ul
            where ul.user_id = v_uid::text
              and ul.manga_id = m.id
          )
          and not (m.id = any (public._taste_recent_impressed_ids('discover_new_to_you', 'manga')))
        order by coalesce(m.popularity, 0) desc, coalesce(m.average_score, 0) desc,
                 coalesce(m.favourites, 0) desc, m.id desc
        limit greatest(v_lim * 6, 60)
      ),
      scored as (
        select
          c.*,
          case
            when coalesce(max(c.popularity) over (), 0) > 0
              then c.popularity::double precision / max(c.popularity) over ()
            else 0.0
          end as editorial_prior,
          (
            coalesce((
              select sum((v_vector->'genres'->>g)::double precision)
              from unnest(c.genres) as g
            ), 0.0)
            + coalesce((
              select sum(
                (v_vector->'tags'->>t.name)::double precision
                * (coalesce(mt2.rank, 0)::double precision / 100.0)
              )
              from public.manga_tags mt2
              join public.tags t on t.id = mt2.tag_id
              where mt2.manga_id = c.media_id
            ), 0.0)
            + case when exists (
              select 1
              from public.manga_tags mt3
              join public.tags t3 on t3.id = mt3.tag_id
              where mt3.manga_id = c.media_id
                and mt3.rank >= 60
                and coalesce(v_vector->'avoided_tags', '[]'::jsonb) ? t3.name
            ) then -0.5 else 0.0 end
          ) as raw_fit
        from candidates c
      ),
      normed as (
        select
          s.*,
          -- Same normalization as the anime branch: raw negatives survive when
          -- there is no positive fit, so avoidance penalties stay active.
          case
            when not v_personalize then 0.0
            when coalesce(max(s.raw_fit) over (), 0) > 0
              then greatest(least(s.raw_fit / max(s.raw_fit) over (), 1.0), -1.0)
            else greatest(s.raw_fit, -1.0)
          end as fit
        from scored s
      )
      select
        'MANGA'::text as media_type,
        n.media_id,
        n.title,
        n.cover_image_large,
        n.cover_image_medium,
        n.cover_image_color,
        n.genres,
        n.average_score,
        n.format,
        n.year,
        n.synopsis
      from normed n
      order by
        (n.editorial_prior * 0.8 + n.fit * v_confidence) desc,
        n.popularity desc,
        n.average_score desc,
        n.favourites desc,
        n.media_id desc
      limit v_lim
    loop
      v_ids := v_ids || r.media_id;
      media_type := r.media_type;
      media_id := r.media_id;
      title := r.title;
      cover_image_large := r.cover_image_large;
      cover_image_medium := r.cover_image_medium;
      cover_image_color := r.cover_image_color;
      genres := r.genres;
      average_score := r.average_score;
      format := r.format;
      year := r.year;
      synopsis := r.synopsis;
      return next;
    end loop;
    perform public._taste_stamp_impressions('discover_new_to_you', 'manga', v_ids);
  end if;

  return;
end;
$$;

revoke all on function public.fetch_personalized_new_to_you(integer, text) from public;
grant execute on function public.fetch_personalized_new_to_you(integer, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Feature flags (rollout percentages are evaluated client-side)
-- ---------------------------------------------------------------------------
insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
values
  ('taste_deck_v1', true, 100, '{}', 'Taste Deck replaces Concierge at pager index 0'),
  ('personalized_new_to_you_v1', true, 0, '{}', 'Personalized NEW TO YOU rail via taste profile')
on conflict (flag_name) do nothing;

-- ---------------------------------------------------------------------------
-- 3) discover_rail_impressions: enable RLS for consistency. Privileges stay
-- revoked from anon/authenticated; the table is written only by SECURITY
-- DEFINER paths (discover_bundle, _taste_stamp_impressions) whose owner
-- bypasses RLS, and service_role bypasses RLS, so no policies are needed.
-- ---------------------------------------------------------------------------
alter table public.discover_rail_impressions enable row level security;

-- ---------------------------------------------------------------------------
-- 4) Ops view (service_role only)
-- ---------------------------------------------------------------------------
create or replace view public.taste_pipeline_status as
select
  (
    select count(*)::integer
    from public.taste_profile_recompute_queue q
    where q.processed_at is null
  ) as queue_depth,
  (
    select max(q.processed_at)
    from public.taste_profile_recompute_queue q
  ) as last_processed_at,
  coalesce((
    select jsonb_object_agg(s.event_type, s.n)
    from (
      select e.event_type, count(*) as n
      from public.taste_signal_events e
      where e.created_at > now() - interval '24 hours'
      group by e.event_type
    ) s
  ), '{}'::jsonb) as events_by_type_24h,
  (
    select count(*)::integer
    from public.user_taste_profiles p
  ) as users_with_profiles,
  (
    select round(avg((p.vector->>'confidence')::numeric), 4)
    from public.user_taste_profiles p
  ) as avg_confidence;

revoke all on public.taste_pipeline_status from anon, authenticated;
grant select on public.taste_pipeline_status to service_role;
