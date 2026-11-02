-- Discover P1 (proposal: docs/superpowers/specs/2026-07-31-discover-browse-redesign-proposal.md).
-- Two readers for the reworked Discover page:
--   fetch_daily_feature()      -> "The One Thing": one boosted title per day with
--                                 a 2-3 sentence argument, rotated by day-of-year.
--   fetch_because_you_rail(n)  -> "Because you loved X": similar-to-seeds cards
--                                 from the caller's top positive taste signals.
-- Both are SECURITY INVOKER (catalog + caller's own rows only), auth required.
-- No new tables.

-- ---------------------------------------------------------------------------
-- 0) editorial_boosts read access. The table is RLS-locked to service_role
--    (20260206150000). fetch_daily_feature is SECURITY INVOKER per the design
--    contract, so authenticated callers need a plain read policy. The table
--    holds public catalog ids + editorial weights/labels (no user data), so a
--    read-only policy for authenticated users is the minimal, safe opening.
-- ---------------------------------------------------------------------------
drop policy if exists editorial_boosts_authenticated_read on public.editorial_boosts;
create policy editorial_boosts_authenticated_read
  on public.editorial_boosts
  for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 0a) _discover_sentence_trim: trim a long argument to the last sentence end
--     (. ! ?) within p_max chars, floored at 120 chars so a boundary-hugging
--     trim can't produce a stub; hard-truncates at p_max when no sentence end
--     exists in range. Keeps The One Thing's 2-3 sentence argument from ever
--     cutting mid-word on the glass card.
-- ---------------------------------------------------------------------------
create or replace function public._discover_sentence_trim(p_text text, p_max integer)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select case
    when p_text is null then null
    when length(p_text) <= p_max then p_text
    else coalesce(
      (select left(p_text, bounds.last_end)
       from (
         select max(p) as last_end
         from generate_series(120, p_max) as p
         where substring(p_text from p for 1) in ('.', '!', '?')
       ) bounds
       where bounds.last_end is not null),
      left(p_text, p_max))
  end;
$$;

revoke all on function public._discover_sentence_trim(text, integer) from public;
grant execute on function public._discover_sentence_trim(text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1) fetch_daily_feature: one hero per day.
--    Pool: editorial_boosts joined to eligible titles (not adult, has cover or
--    banner), ordered by weight desc (deterministic tiebreak). Rotation index
--    = (day_of_year - 1) mod pool_size, computed on the server's UTC clock, so
--    every user sees the same "cover" on the same day.
--    argument = coalesce(boost label, synopsis_enhanced when its pipeline
--    state is 'ready' else description_normalized, trimmed to the last
--    sentence boundary within ~320 chars via _discover_sentence_trim).
-- ---------------------------------------------------------------------------
create or replace function public.fetch_daily_feature()
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  banner_image text,
  genres text[],
  score integer,
  year integer,
  format text,
  argument text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  return query
  with pool as (
    select
      b.weight,
      b.label,
      'ANIME'::text as p_media_type,
      a.id as p_media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as p_title,
      a.cover_image_large as p_cover,
      a.banner_image as p_banner,
      a.genres as p_genres,
      a.average_score as p_score,
      coalesce(a.season_year, a.start_date_year) as p_year,
      a.format as p_format,
      case
        when a.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
          then a.synopsis_enhanced
        else a.description_normalized
      end as p_synopsis
    from public.editorial_boosts b
    join public.anime a on a.id = b.media_id
    where b.media_type = 'ANIME'
      and coalesce(a.is_adult, false) = false
      and (a.cover_image_large is not null or a.banner_image is not null)

    union all

    select
      b.weight,
      b.label,
      'MANGA'::text,
      m.id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      case
        when m.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
          then m.synopsis_enhanced
        else m.description_normalized
      end
    from public.editorial_boosts b
    join public.manga m on m.id = b.media_id
    where b.media_type = 'MANGA'
      and coalesce(m.is_adult, false) = false
      and (m.cover_image_large is not null or m.banner_image is not null)
  ),
  numbered as (
    select
      p.*,
      row_number() over (order by p.weight desc, p.p_media_type, p.p_media_id) as rn,
      count(*) over () as n
    from pool p
  )
  select
    numbered.p_media_type,
    numbered.p_media_id,
    numbered.p_title,
    numbered.p_cover,
    numbered.p_banner,
    numbered.p_genres,
    numbered.p_score,
    numbered.p_year,
    numbered.p_format,
    coalesce(
      nullif(btrim(numbered.label), ''),
      nullif(public._discover_sentence_trim(numbered.p_synopsis, 320), '')
    ) as argument
  from numbered
  where numbered.rn = ((extract(doy from now()))::integer - 1) % numbered.n + 1;
end;
$$;

revoke all on function public.fetch_daily_feature() from public;
grant execute on function public.fetch_daily_feature() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fetch_because_you_rail: personalized flagship rail with the reason printed.
--    Seeds: the caller's top 3 positive titles from taste_signal_events —
--    sum of positive strengths per (media_type, media_id) over ALL positive
--    event types (deck_love, deck_known, planned_add, ...), tiebreak by most
--    recent signal for determinism. Requires >= 2 distinct positive titles,
--    else 0 rows (caller falls back to the editorial NEW TO YOU rail).
--    Candidates: recommend_ids_similar_to_seeds v2 per media type present in
--    the seeds (its built-in exclusions already dedupe against the caller's
--    lists); when seeds span both types the two ranked lists are interleaved.
--    On top of the RPC exclusions we drop titles the caller already signaled
--    in the deck (love/known/skip/pass) so the rail never echoes them back.
--    reason_title = display title of the #1 seed (same on every row).
-- ---------------------------------------------------------------------------
create or replace function public.fetch_because_you_rail(p_limit integer default 12)
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
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer,
  reason_title text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(1, least(coalesce(p_limit, 12), 40));
  v_seed_count integer := 0;
  v_anime_seeds integer[] := '{}'::integer[];
  v_manga_seeds integer[] := '{}'::integer[];
  v_seed1_type text;
  v_seed1_id integer;
  v_reason text;
  v_anime_recs integer[] := '{}'::integer[];
  v_manga_recs integer[] := '{}'::integer[];
  v_out_types text[] := '{}'::text[];
  v_out_ids integer[] := '{}'::integer[];
  v_a_len integer;
  v_m_len integer;
  v_i integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Top 3 positive titles by summed positive strength (deterministic ties).
  with positive as (
    select
      e.media_type,
      e.media_id,
      sum(e.event_strength) as s,
      max(e.created_at) as last_at
    from public.taste_signal_events e
    where e.user_id = v_uid
      and e.event_strength > 0
    group by e.media_type, e.media_id
  ),
  ranked as (
    select
      p.media_type,
      p.media_id,
      row_number() over (order by p.s desc, p.last_at desc, p.media_type, p.media_id) as rn
    from positive p
  )
  select
    count(*),
    coalesce(array_agg(r.media_id) filter (where r.media_type = 'ANIME'), '{}'::integer[]),
    coalesce(array_agg(r.media_id) filter (where r.media_type = 'MANGA'), '{}'::integer[]),
    max(r.media_type) filter (where r.rn = 1),
    max(r.media_id) filter (where r.rn = 1)
  into v_seed_count, v_anime_seeds, v_manga_seeds, v_seed1_type, v_seed1_id
  from ranked r
  where r.rn <= 3;

  -- Below confidence: not enough distinct positive evidence -> 0 rows.
  if v_seed_count < 2 then
    return;
  end if;

  -- The reason names the #1 seed.
  if v_seed1_type = 'ANIME' then
    select coalesce(nullif(a.title_english, ''), a.title_romaji)
      into v_reason
      from public.anime a
     where a.id = v_seed1_id;
  else
    select coalesce(nullif(m.title_english, ''), m.title_romaji)
      into v_reason
      from public.manga m
     where m.id = v_seed1_id;
  end if;

  -- Per-type candidates from the v2 similarity RPC (list dedupe built in).
  if array_length(v_anime_seeds, 1) is not null then
    select array_agg(x.media_id order by x.score desc, x.media_id desc)
      into v_anime_recs
      from public.recommend_ids_similar_to_seeds('ANIME', v_anime_seeds, v_lim, false) x;
  end if;
  if array_length(v_manga_seeds, 1) is not null then
    select array_agg(x.media_id order by x.score desc, x.media_id desc)
      into v_manga_recs
      from public.recommend_ids_similar_to_seeds('MANGA', v_manga_seeds, v_lim, false) x;
  end if;

  -- Interleave when both types have candidates; otherwise one list alone.
  v_a_len := coalesce(array_length(v_anime_recs, 1), 0);
  v_m_len := coalesce(array_length(v_manga_recs, 1), 0);
  for v_i in 1..greatest(v_a_len, v_m_len) loop
    if v_i <= v_a_len and coalesce(array_length(v_out_ids, 1), 0) < v_lim then
      v_out_types := v_out_types || 'ANIME'::text;
      v_out_ids := v_out_ids || v_anime_recs[v_i];
    end if;
    if v_i <= v_m_len and coalesce(array_length(v_out_ids, 1), 0) < v_lim then
      v_out_types := v_out_types || 'MANGA'::text;
      v_out_ids := v_out_ids || v_manga_recs[v_i];
    end if;
  end loop;

  return query
  with ordered as (
    select t.mt, t.mi, t.ord
    from unnest(v_out_types, v_out_ids) with ordinality as t(mt, mi, ord)
  ),
  cards as (
    select
      o.ord,
      'ANIME'::text as c_media_type,
      a.id as c_media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as c_title,
      a.cover_image_large as c_cover_large,
      a.cover_image_medium as c_cover_medium,
      a.cover_image_color as c_cover_color,
      a.genres as c_genres,
      a.average_score as c_score,
      a.format as c_format,
      coalesce(a.season_year, a.start_date_year) as c_year,
      left(coalesce(a.description_normalized, ''), 300) as c_synopsis,
      a.episodes as c_episodes,
      null::integer as c_chapters,
      null::integer as c_volumes
    from ordered o
    join public.anime a on o.mt = 'ANIME' and a.id = o.mi
    where not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'ANIME'
        and e.media_id = a.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )

    union all

    select
      o.ord,
      'MANGA'::text,
      m.id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.cover_image_medium,
      m.cover_image_color,
      m.genres,
      m.average_score,
      m.format,
      m.start_date_year,
      left(coalesce(m.description_normalized, ''), 300),
      null::integer,
      m.chapters,
      m.volumes
    from ordered o
    join public.manga m on o.mt = 'MANGA' and m.id = o.mi
    where not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'MANGA'
        and e.media_id = m.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )
  )
  select
    cards.c_media_type,
    cards.c_media_id,
    cards.c_title,
    cards.c_cover_large,
    cards.c_cover_medium,
    cards.c_cover_color,
    cards.c_genres,
    cards.c_score,
    cards.c_format,
    cards.c_year,
    cards.c_synopsis,
    cards.c_episodes,
    cards.c_chapters,
    cards.c_volumes,
    v_reason
  from cards
  order by cards.ord;
end;
$$;

revoke all on function public.fetch_because_you_rail(integer) from public;
grant execute on function public.fetch_because_you_rail(integer) to authenticated, service_role;
