-- ADR 2026-07-31: Taste Math v2 (spec: docs/superpowers/specs/2026-07-31-taste-math-v2-critical-review.md §3/§5).
-- One unified IDF-weighted tag-vector space for titles and users; all taste
-- consumers (deck dealing, NEW TO YOU fit, seed similarity) read the same math.
--
-- Constants (spec §3/§5, contract docs/personalization_execution_contract.md):
--   tag weight      w = (rank/100) * ln(1 + N/(1+df)); df = distinct titles
--                     (anime + manga) carrying the tag; N = total anime+manga.
--   genre pseudo-tag key 'genre:'||lower(genre), w = 0.6 * ln(1 + N/(1+df)).
--   user vector     = SUM(strength * 0.5^(age_days/180) * (import ? 0.25 : 1) * title_vector)
--                     per-tag negative floor -1.0, title positive mass cap 8%,
--                     franchise positive mass cap 15%, then L2-normalized.
--   evidence n      = SUM(case when abs(strength) >= 0.3 then 1.0 else 0.5 end).
--   avoided tag     = >= 2 negative events OR cumulative negative <= -0.8,
--                     computed on per-tag RAW sums (decayed strength x rank/100;
--                     genres x0.6) BEFORE IDF weighting, caps and normalization,
--                     so one skip can never exile a tag (spec SS4.3).
--   deck dealing    explore_ratio = greatest(0.25, 0.75*exp(-n/50));
--                   exploit score = cosine_fit * (0.5 + 0.5 * score/100)
--                     (popularity-free: quality only);
--                   explore UCB per title = mean over its tags of
--                     (alpha+1)/(alpha+beta+2) + 0.5/sqrt(alpha+beta+1)
--                     (Beta(1,1) prior baked in: missing stat row -> alpha=beta=0);
--                   stratification = 6 genre clusters x 3 popularity strata
--                     (percent_rank over the pool: head pr >= 0.9,
--                      mid 0.1 <= pr < 0.6, gems pr < 0.4 with average_score >= 75;
--                      gems takes priority over mid for pr < 0.4);
--                   MMR assembly lambda = 0.7: 0.7*slot_score - 0.3*max_overlap,
--                     overlap = Jaccard over each title's top 15 tags by |w|
--                     (spec allowed cosine or Jaccard; Jaccard over top tags is
--                     cheaper inside the procedural loop and scale-free);
--                   slot_score is min-max normalized per slot group before MMR
--                     (cosine fits and UCB live on different scales; without
--                     normalization UCB ~1.0 would always beat fit ~0.5);
--                   hard caps <= ceil(4/12 * lim) per cluster,
--                     <= ceil(2/12 * lim) per franchise, half anime/half manga
--                     with v1 cross-fill on starvation;
--                   negative-space probe: p = 0.10 per batch, replaces the last
--                     explore slot with a pool title carrying an avoided tag
--                     (rank >= 60) when one exists.
--   NTY             w = 0.20 * n/(n+20) (contract max_user_influence 0.20);
--                   final = (1-w)*editorial_prior + w*fit; fit = cosine with
--                   -0.5 avoided-tag penalty (rank >= 60), clamped [-1, 1].
--   similarity      full cosine over media_tag_vectors between the averaged
--                   seed vector and each candidate, x craft multiplier
--                   (1 + 0.5*shared_director_or_creator + 0.15*shared_studio
--                        + 0.5*shared_author), capped x2;
--                   log(favourites)/log(popularity)/score/recency terms REMOVED;
--                   popularity kept only as a tiebreak.
--   tag stats       love -> alpha += 1.0, known -> alpha += 0.5, skip -> beta += 1.0
--                   over the title's tags with rank >= 40 plus its genres as
--                   'genre:' keys; retract (and mind-change replace) reverses
--                   the prior action's deltas, clamped at 0; weekly decay x0.95
--                   (Sunday 04:10 UTC).
--
-- Genre clusters (deterministic, first matching genre in the title's array):
--   action:  Action, Adventure, Sports
--   drama:   Drama, Romance, Slice of Life
--   fantasy: Fantasy, Supernatural, Mahou Shoujo
--   scifi:   Sci-Fi, Mecha
--   comedy:  Comedy, Music
--   dark:    Horror, Mystery, Psychological, Thriller
--   Ecchi/Hentai (excluded from pools anyway) and unmapped -> 'other'.
--
-- Craft multiplier role mapping (no precedent in the old RPC, documented):
--   ANIME: director_or_creator = anime_staff role ILIKE '%director%';
--          studio = shared anime_studios.studio_id;
--          author = anime_staff role ILIKE '%creator%' (AniList 'Original Creator').
--   MANGA: director_or_creator = manga_authors role ILIKE '%story%' (the writer);
--          studio = false (no studio concept); author = any shared manga_authors
--          row. A shared 'Story & Art' mangaka fires both terms (x2 cap), which
--          is deliberate: "same mangaka" is the strongest L3 signal (spec §2).
--   The genre gate from 20260204235500 and the allow_gimmicks editorial penalty
--   are kept (quality floors, not popularity terms); editorial_boosts /
--   editorial_tag_boosts score terms are removed with the popularity terms.

-- ---------------------------------------------------------------------------
-- 1) media_tag_vectors: the shared vector space (matview, nightly refresh)
-- ---------------------------------------------------------------------------
-- taste_pipeline_status (recreated at the end of this file) references the
-- matview, so it must be dropped first for idempotent re-application.
drop view if exists public.taste_pipeline_status;

drop materialized view if exists public.media_tag_vectors;

create materialized view public.media_tag_vectors as
with n as (
  select ((select count(*) from public.anime) + (select count(*) from public.manga))::double precision as total
),
-- df per tag_key (lower(name)), not per tag row: case-variant tag rows
-- (e.g. 'Sci-Fi' vs 'Sci-fi') count a shared title once.
tag_df as (
  select x.tag_key, sum(x.c) as df
  from (
    select lower(t.name) as tag_key, count(distinct at.anime_id) as c
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    group by lower(t.name)
    union all
    select lower(t.name) as tag_key, count(distinct mt.manga_id) as c
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    group by lower(t.name)
  ) x
  group by x.tag_key
),
genre_df as (
  select x.genre_key, sum(x.c) as df
  from (
    select lower(g) as genre_key, count(distinct a.id) as c
    from public.anime a cross join lateral unnest(coalesce(a.genres, '{}'::text[])) as g
    group by lower(g)
    union all
    select lower(g) as genre_key, count(distinct m.id) as c
    from public.manga m cross join lateral unnest(coalesce(m.genres, '{}'::text[])) as g
    group by lower(g)
  ) x
  group by x.genre_key
),
base as (
  -- One row per (media_type, media_id, tag_key) BY CONSTRUCTION:
  -- case-variant tag rows collapse to a single entry with w from the MAX
  -- rank (category picked deterministically via min()).
  select
    'ANIME'::text as media_type,
    at.anime_id as media_id,
    lower(t.name) as tag_key,
    min(t.category) as category,
    (max(coalesce(at.rank, 0))::double precision / 100.0)
      * ln(1.0 + (select total from n) / (1.0 + coalesce(d.df, 0))) as w
  from public.anime_tags at
  join public.tags t on t.id = at.tag_id
  left join tag_df d on d.tag_key = lower(t.name)
  group by at.anime_id, lower(t.name), d.df
  union all
  select
    'MANGA'::text,
    mt.manga_id,
    lower(t.name),
    min(t.category),
    (max(coalesce(mt.rank, 0))::double precision / 100.0)
      * ln(1.0 + (select total from n) / (1.0 + coalesce(d.df, 0)))
  from public.manga_tags mt
  join public.tags t on t.id = mt.tag_id
  left join tag_df d on d.tag_key = lower(t.name)
  group by mt.manga_id, lower(t.name), d.df
  union all
  -- Genres folded as pseudo-tags at 0.6 x IDF; distinct lower() per title so
  -- duplicated/case-variant array entries (e.g. '{Fantasy,fantasy}') emit once.
  select
    'ANIME'::text,
    a.id,
    'genre:' || g.genre_key,
    'Genre'::text,
    0.6 * ln(1.0 + (select total from n) / (1.0 + coalesce(gd.df, 0)))
  from public.anime a
  cross join lateral (
    select distinct lower(u) as genre_key
    from unnest(coalesce(a.genres, '{}'::text[])) as u
  ) g
  left join genre_df gd on gd.genre_key = g.genre_key
  union all
  select
    'MANGA'::text,
    m.id,
    'genre:' || g.genre_key,
    'Genre'::text,
    0.6 * ln(1.0 + (select total from n) / (1.0 + coalesce(gd.df, 0)))
  from public.manga m
  cross join lateral (
    select distinct lower(u) as genre_key
    from unnest(coalesce(m.genres, '{}'::text[])) as u
  ) g
  left join genre_df gd on gd.genre_key = g.genre_key
)
select
  media_type,
  media_id,
  tag_key,
  category,
  w::real as w,
  sqrt(sum(w * w) over (partition by media_type, media_id))::real as l2_norm
from base;

-- Unique index (required for REFRESH ... CONCURRENTLY) + tag_key lookup index.
create unique index media_tag_vectors_uidx
  on public.media_tag_vectors (media_type, media_id, tag_key);
create index media_tag_vectors_tag_key_idx
  on public.media_tag_vectors (tag_key);

revoke all on public.media_tag_vectors from public;
grant select on public.media_tag_vectors to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) taste_tag_stats: per-user Beta posteriors over tag keys (deck-driven)
-- ---------------------------------------------------------------------------
create table if not exists public.taste_tag_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  tag_key text not null,
  alpha real not null default 0,
  beta real not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, tag_key)
);

alter table public.taste_tag_stats enable row level security;

drop policy if exists taste_tag_stats_select_own on public.taste_tag_stats;
create policy taste_tag_stats_select_own
  on public.taste_tag_stats
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Writes happen only through SECURITY DEFINER paths (record_taste_deck_signal
-- via _taste_deck_apply_tag_stats, and the decay cron).
revoke insert, update, delete on public.taste_tag_stats from anon, authenticated;
grant select on public.taste_tag_stats to authenticated;
grant all on public.taste_tag_stats to service_role;

-- ---------------------------------------------------------------------------
-- 3) Tag-key helpers for deck stats / UCB (SECURITY INVOKER, catalog reads)
-- ---------------------------------------------------------------------------
drop function if exists public._taste_deck_title_tag_keys(text, integer);

create function public._taste_deck_title_tag_keys(p_media_type text, p_media_id integer)
returns table (tag_key text)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  -- The deck stats key space: tags with rank >= 40 plus genres as 'genre:' keys.
  select lower(t.name)
  from public.anime_tags at
  join public.tags t on t.id = at.tag_id
  where p_media_type = 'ANIME'
    and at.anime_id = p_media_id
    and coalesce(at.rank, 0) >= 40
  union
  select lower(t.name)
  from public.manga_tags mt
  join public.tags t on t.id = mt.tag_id
  where p_media_type = 'MANGA'
    and mt.manga_id = p_media_id
    and coalesce(mt.rank, 0) >= 40
  union
  select 'genre:' || lower(g)
  from public.anime a
  cross join lateral unnest(coalesce(a.genres, '{}'::text[])) as g
  where p_media_type = 'ANIME'
    and a.id = p_media_id
  union
  select 'genre:' || lower(g)
  from public.manga m
  cross join lateral unnest(coalesce(m.genres, '{}'::text[])) as g
  where p_media_type = 'MANGA'
    and m.id = p_media_id;
$$;

revoke all on function public._taste_deck_title_tag_keys(text, integer) from public;
grant execute on function public._taste_deck_title_tag_keys(text, integer) to authenticated, service_role;

-- Internal stats writer: p_sign +1 applies the action's deltas, -1 reverses
-- them (clamped at 0; the weekly decay makes exact reversal impossible, so a
-- reversed stat can never go negative).
drop function if exists public._taste_deck_apply_tag_stats(uuid, text, integer, text, integer);

create function public._taste_deck_apply_tag_stats(
  p_user_id uuid,
  p_media_type text,
  p_media_id integer,
  p_action text,
  p_sign integer
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_da real := case p_action when 'love' then 1.0 when 'known' then 0.5 else 0.0 end;
  v_db real := case p_action when 'skip' then 1.0 else 0.0 end;
begin
  if p_user_id is null or p_action is null or coalesce(p_sign, 0) = 0 then
    return;
  end if;
  if v_da = 0.0 and v_db = 0.0 then
    return;
  end if;

  if p_sign > 0 then
    insert into public.taste_tag_stats as s (user_id, tag_key, alpha, beta, updated_at)
    select p_user_id, k.tag_key, v_da, v_db, now()
    from public._taste_deck_title_tag_keys(p_media_type, p_media_id) k
    on conflict (user_id, tag_key) do update
      set alpha = s.alpha + v_da,
          beta = s.beta + v_db,
          updated_at = now();
  else
    update public.taste_tag_stats s
    set alpha = greatest(0.0, s.alpha - v_da),
        beta = greatest(0.0, s.beta - v_db),
        updated_at = now()
    where s.user_id = p_user_id
      and s.tag_key in (
        select k.tag_key
        from public._taste_deck_title_tag_keys(p_media_type, p_media_id) k
      );
  end if;
end;
$$;

revoke all on function public._taste_deck_apply_tag_stats(uuid, text, integer, text, integer) from public;
-- No grants: only callable from SECURITY DEFINER paths owned by the same role.

-- ---------------------------------------------------------------------------
-- 4) record_taste_deck_signal v2: v1 semantics + taste_tag_stats maintenance
-- ---------------------------------------------------------------------------
drop function if exists public.record_taste_deck_signal(text, integer, text);

create function public.record_taste_deck_signal(
  p_media_type text,
  p_media_id integer,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_media_type text := upper(trim(coalesce(p_media_type, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_event_type text;
  v_strength real;
  v_deleted integer := 0;
  v_prior_event_type text;
  v_day_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_media_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;
  if p_media_id is null then
    raise exception 'media_id required' using errcode = '22023';
  end if;
  if v_action not in ('love', 'known', 'skip', 'retract') then
    raise exception 'unsupported deck action: %', p_action using errcode = '22023';
  end if;

  -- Rate limit: max 300 deck events per user per rolling 24h (inserts only).
  -- Checked before the dedupe delete so a limited user keeps their prior signal.
  if v_action <> 'retract' then
    select count(*) into v_day_count
    from public.taste_signal_events
    where user_id = v_uid
      and event_type in ('deck_love', 'deck_known', 'deck_skip')
      and created_at > now() - interval '1 day';
    if v_day_count >= 300 then
      raise exception 'taste deck signal rate limit exceeded'
        using errcode = 'P0001', detail = 'RATE_LIMITED';
    end if;
  end if;

  -- One deck signal per user/media: drop the prior deck_* event first so a
  -- changed mind replaces instead of stacking. Non-deck events are untouched.
  -- The prior event type is captured so its taste_tag_stats deltas can be
  -- reversed (retract = "undo the last action on this title").
  with d as (
    delete from public.taste_signal_events
    where user_id = v_uid
      and media_type = v_media_type
      and media_id = p_media_id
      and event_type in ('deck_love', 'deck_known', 'deck_skip')
    returning event_type
  )
  select count(*), max(d.event_type)
    into v_deleted, v_prior_event_type
  from d;

  if v_prior_event_type is not null then
    perform public._taste_deck_apply_tag_stats(
      v_uid, v_media_type, p_media_id, replace(v_prior_event_type, 'deck_', ''), -1
    );
  end if;

  if v_action = 'retract' then
    if v_deleted > 0 then
      perform public._taste_enqueue_recompute(v_uid, 'deck_retract');
    end if;
    return jsonb_build_object(
      'ok', true,
      'action', 'retract',
      'media_type', v_media_type,
      'media_id', case when v_deleted > 0 then p_media_id else null end,
      'deleted', v_deleted
    );
  end if;

  v_event_type := case v_action
    when 'love' then 'deck_love'
    when 'known' then 'deck_known'
    when 'skip' then 'deck_skip'
  end;
  v_strength := case v_action
    when 'love' then 0.55
    when 'known' then 0.25
    when 'skip' then -0.45
  end;

  insert into public.taste_signal_events (
    user_id, media_id, media_type, event_type, event_strength,
    signal_value, source_transition, is_import
  ) values (
    v_uid, p_media_id, v_media_type, v_event_type, v_strength,
    jsonb_build_object('action', v_action),
    jsonb_build_object('source', 'taste_deck'),
    false
  );

  -- Beta-posterior maintenance for the explore UCB.
  perform public._taste_deck_apply_tag_stats(v_uid, v_media_type, p_media_id, v_action, 1);

  -- Mirror _taste_emit_event: every inserted signal enqueues a profile recompute.
  perform public._taste_enqueue_recompute(v_uid, v_event_type);

  return jsonb_build_object(
    'ok', true,
    'action', v_action,
    'event_type', v_event_type,
    'event_strength', v_strength,
    'media_type', v_media_type,
    'media_id', p_media_id,
    'replaced_prior', v_deleted > 0
  );
end;
$$;

revoke all on function public.record_taste_deck_signal(text, integer, text) from public;
grant execute on function public.record_taste_deck_signal(text, integer, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) recompute_user_taste_profile v3: user vector in the media_tag_vectors space
-- ---------------------------------------------------------------------------
drop function if exists public.recompute_user_taste_profile(uuid);

create function public.recompute_user_taste_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_event_count integer;
  v_strong_count integer;
  v_evidence double precision;
  v_confidence real;
  v_vector jsonb;
begin
  if p_user_id is null then
    return;
  end if;

  select
    count(*),
    count(*) filter (where abs(e.event_strength) >= 0.3),
    coalesce(sum(case when abs(e.event_strength) >= 0.3 then 1.0 else 0.5 end), 0)
  into v_event_count, v_strong_count, v_evidence
  from public.taste_signal_events e
  where e.user_id = p_user_id;

  -- Display-tier confidence (contract copy tiers, unchanged).
  v_confidence := case
    when v_strong_count >= 30 then 0.20
    when v_strong_count >= 15 then 0.15
    when v_strong_count >= 5 then 0.10
    else 0.05
  end;

  with recursive
  ev as (
    select
      e.media_type,
      e.media_id,
      e.event_strength::double precision
        * case when e.is_import then 0.25 else 1.0 end          -- import discount x0.25
        * power(0.5, greatest(extract(epoch from (now() - e.created_at)) / 86400.0, 0.0) / 180.0) as w, -- 180-day half-life
      (e.event_strength < 0) as negative_event
    from public.taste_signal_events e
    where e.user_id = p_user_id
  ),
  contrib as (
    -- strength x title_vector, both in the media_tag_vectors space.
    select
      c.media_type,
      c.media_id,
      v.tag_key,
      c.w * v.w::double precision as weight,
      c.negative_event
    from ev c
    join public.media_tag_vectors v
      on v.media_type = c.media_type
     and v.media_id = c.media_id
  ),
  -- Per-title cap: one title's positive mass <= 8% of profile positive mass.
  title_pos as (
    select media_type, media_id, sum(greatest(weight, 0)) as pos_mass
    from contrib
    group by media_type, media_id
  ),
  total_pos as (
    select coalesce(sum(pos_mass), 0) as v from title_pos
  ),
  title_scale as (
    select
      tp.media_type,
      tp.media_id,
      case
        when tp.pos_mass > 0 and (select v from total_pos) > 0
          then least(1.0, 0.08 * (select v from total_pos) / tp.pos_mass)
        else 1.0
      end as scale
    from title_pos tp
  ),
  capped as (
    select c.tag_key, c.media_type, c.media_id,
           c.weight * ts.scale as weight,
           c.negative_event
    from contrib c
    join title_scale ts
      on ts.media_type = c.media_type
     and ts.media_id = c.media_id
  ),
  -- Franchise family = connected component over media_relations, restricted to
  -- titles this user actually signaled (small subgraph). UNION (not UNION ALL)
  -- makes the recursion cycle-safe. Guard: histories with >2000 distinct titles
  -- skip grouping (each title becomes its own family).
  nodes as (
    select distinct media_type, media_id from ev
  ),
  node_ok as (
    select count(*) <= 2000 as ok from nodes
  ),
  edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
    where (select ok from node_ok)
  ),
  adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from edges
    union
    select b_t, b_i, a_t, a_i from edges
  ),
  reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from nodes n
    union
    select r.s_t, r.s_i, a.nt, a.ni
    from reach r
    join adj a on a.t = r.t and a.i = r.i
  ),
  family_label as (
    select r.t as media_type, r.i as media_id,
           min(r.s_t || ':' || r.s_i::text) as label
    from reach r
    group by r.t, r.i
  ),
  capped_labeled as (
    select c.tag_key, c.weight, c.negative_event,
           coalesce(fl.label, c.media_type || ':' || c.media_id::text) as family
    from capped c
    left join family_label fl
      on fl.media_type = c.media_type
     and fl.media_id = c.media_id
  ),
  -- Franchise cap: one family's positive mass <= 15% of profile positive mass.
  family_pos as (
    select family, sum(greatest(weight, 0)) as pos_mass
    from capped_labeled
    group by family
  ),
  family_total as (
    select coalesce(sum(pos_mass), 0) as v from family_pos
  ),
  family_scale as (
    select
      fp.family,
      case
        when fp.pos_mass > 0 and (select v from family_total) > 0
          then least(1.0, 0.15 * (select v from family_total) / fp.pos_mass)
        else 1.0
      end as scale
    from family_pos fp
  ),
  final_contrib as (
    select cl.tag_key, cl.weight * fs.scale as weight, cl.negative_event
    from capped_labeled cl
    join family_scale fs on fs.family = cl.family
  ),
  agg as (
    select
      tag_key,
      sum(weight) as weight
    from final_contrib
    group by tag_key
  ),
  floored as (
    select
      tag_key,
      greatest(weight, -1.0) as weight -- per-tag negative mass floor -1.0
    from agg
  ),
  vec_norm as (
    select nullif(sqrt(sum(weight * weight)), 0) as n from floored
  ),
  normalized as (
    select
      f.tag_key,
      case when (select n from vec_norm) is null then 0.0
           else f.weight / (select n from vec_norm) end as weight
    from floored f
  ),
  -- Avoidance basis: per-tag RAW sums (decayed strength x rank/100, import-
  -- discounted; genres at x0.6) BEFORE IDF weighting, caps and L2
  -- normalization. One skip (e.g. -0.45 x 0.80 = -0.36) must never exile a
  -- tag (spec SS4.3); in the IDF space a single rare-tag skip would already
  -- cross the -0.8 cumulative floor, so the floors are evaluated here.
  -- 'genre:*' keys can be avoided too; consumers only match rank-bearing
  -- tags, making genre entries informational.
  avoid_contrib as (
    select c.media_type, c.media_id, lower(t.name) as tag_key,
           c.w * (coalesce(at.rank, 0)::double precision / 100.0) as weight,
           c.negative_event
    from ev c
    join public.anime_tags at on c.media_type = 'ANIME' and at.anime_id = c.media_id
    join public.tags t on t.id = at.tag_id
    union all
    select c.media_type, c.media_id, lower(t.name),
           c.w * (coalesce(mt.rank, 0)::double precision / 100.0),
           c.negative_event
    from ev c
    join public.manga_tags mt on c.media_type = 'MANGA' and mt.manga_id = c.media_id
    join public.tags t on t.id = mt.tag_id
    union all
    select c.media_type, c.media_id, 'genre:' || lower(g),
           c.w * 0.6, c.negative_event
    from ev c
    join public.anime a on c.media_type = 'ANIME' and a.id = c.media_id
    cross join lateral unnest(coalesce(a.genres, '{}'::text[])) as g
    union all
    select c.media_type, c.media_id, 'genre:' || lower(g),
           c.w * 0.6, c.negative_event
    from ev c
    join public.manga m on c.media_type = 'MANGA' and m.id = c.media_id
    cross join lateral unnest(coalesce(m.genres, '{}'::text[])) as g
  ),
  avoid_agg as (
    select
      tag_key,
      count(*) filter (where negative_event) as neg_events,
      sum(weight) filter (where weight < 0) as neg_weight
    from avoid_contrib
    group by tag_key
  ),
  avoided as (
    select tag_key
    from avoid_agg
    where neg_events >= 2 or coalesce(neg_weight, 0) <= -0.8
  ),
  vec_json as (
    select coalesce(jsonb_object_agg(tag_key, w), '{}'::jsonb) as j
    from (
      select tag_key, round(weight::numeric, 4) as w
      from normalized
      where round(weight::numeric, 4) <> 0
      order by abs(weight) desc, tag_key asc
      limit 60
    ) t
  ),
  avoided_json as (
    select coalesce(jsonb_agg(tag_key order by tag_key), '[]'::jsonb) as j
    from avoided
  )
  select jsonb_build_object(
    'vector', (select j from vec_json),
    'avoided_tags', (select j from avoided_json),
    'evidence', round(v_evidence::numeric, 2),
    'confidence', v_confidence,
    'event_count', v_event_count,
    'computed_at', now()
  )
  into v_vector;

  insert into public.user_taste_profiles as p (user_id, vector, updated_at)
  values (p_user_id, v_vector, now())
  on conflict (user_id) do update
    set vector = excluded.vector,
        updated_at = now();
end;
$$;

revoke all on function public.recompute_user_taste_profile(uuid) from public;
grant execute on function public.recompute_user_taste_profile(uuid) to service_role;

-- drain_taste_recompute_queue (20260731011000) calls recompute by name with the
-- same (uuid) signature, so it keeps working unchanged.

-- Existing v1-shaped profiles are in the old space; enqueue their owners so the
-- next drain recomputes them in the v2 space.
insert into public.taste_profile_recompute_queue as q (user_id, reason, requested_at, processed_at)
select p.user_id, 'taste_math_v2', now(), null
from public.user_taste_profiles p
on conflict (user_id) do update
  set reason = excluded.reason,
      requested_at = excluded.requested_at,
      processed_at = null;

-- ---------------------------------------------------------------------------
-- 6) Genre cluster helper (deterministic 18-genre -> 6-cluster mapping)
-- ---------------------------------------------------------------------------
drop function if exists public._taste_genre_cluster(text[]);

create function public._taste_genre_cluster(p_genres text[])
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  g text;
begin
  -- First matching genre in the title's own array order wins (deterministic).
  --   action:  Action, Adventure, Sports
  --   drama:   Drama, Romance, Slice of Life
  --   fantasy: Fantasy, Supernatural, Mahou Shoujo
  --   scifi:   Sci-Fi, Mecha
  --   comedy:  Comedy, Music
  --   dark:    Horror, Mystery, Psychological, Thriller
  -- Ecchi/Hentai (pool-excluded) and anything unmapped -> 'other'.
  if p_genres is null then
    return 'other';
  end if;
  foreach g in array p_genres loop
    if lower(g) in ('action', 'adventure', 'sports') then
      return 'action';
    elsif lower(g) in ('drama', 'romance', 'slice of life') then
      return 'drama';
    elsif lower(g) in ('fantasy', 'supernatural', 'mahou shoujo') then
      return 'fantasy';
    elsif lower(g) in ('sci-fi', 'mecha') then
      return 'scifi';
    elsif lower(g) in ('comedy', 'music') then
      return 'comedy';
    elsif lower(g) in ('horror', 'mystery', 'psychological', 'thriller') then
      return 'dark';
    end if;
  end loop;
  return 'other';
end;
$$;

revoke all on function public._taste_genre_cluster(text[]) from public;
grant execute on function public._taste_genre_cluster(text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) fetch_taste_deck_batch v3: stratified dealing over the v1 pool
--    Return type identical to 20260731050000 -> drop first; iOS unchanged.
--    VOLATILE (was STABLE in v1) because dealing uses session temp tables.
-- ---------------------------------------------------------------------------
drop function if exists public.fetch_taste_deck_batch(integer);

create function public.fetch_taste_deck_batch(p_limit integer default 12)
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
  seasons_count integer,
  has_dub boolean,
  has_sub boolean
)
language plpgsql
volatile
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(2, least(coalesce(p_limit, 12), 40));
  v_half integer;
  v_pool_lim integer;
  v_profile jsonb;
  v_avoided jsonb := '[]'::jsonb;
  v_unorm double precision := 0;
  v_evidence double precision := 0;
  v_explore_ratio double precision;
  v_explore_slots integer;
  v_exploit_slots integer;
  v_cluster_cap integer;
  v_franchise_cap integer;
  v_a_count integer;
  v_m_count integer;
  v_a_take integer;
  v_m_take integer;
  v_pa integer := 0;
  v_pm integer := 0;
  v_picked integer := 0;
  v_explore_target integer;
  v_prog boolean;
  v_clusters text[] := array['action', 'drama', 'fantasy', 'scifi', 'comedy', 'dark'];
  v_strata text[] := array['head', 'mid', 'gems'];
  v_ci integer;
  v_si integer;
  v_min_s double precision;
  v_max_s double precision;
  v_mmr double precision;
  v_best_mmr double precision;
  v_max_ovl double precision;
  v_tags text[];
  v_slot text;
  r record;
  v_best record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  v_half := v_lim / 2;
  -- Deeper than v1 (v_lim per type) so the dealing policy has room to work;
  -- <= 60 rows for the default batch of 12.
  v_pool_lim := greatest(v_lim + 18, 24);
  -- Hard caps, scaled from the spec's <=4/12 cluster and <=2/12 franchise.
  v_cluster_cap := greatest(1, (v_lim * 4) / 12);
  v_franchise_cap := greatest(1, (v_lim * 2) / 12);

  select p.vector into v_profile
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_profile is not null then
    v_evidence := coalesce((v_profile->>'evidence')::double precision, 0);
    v_avoided := coalesce(v_profile->'avoided_tags', '[]'::jsonb);
    select coalesce(sqrt(sum(uv.uval * uv.uval)), 0)
      into v_unorm
    from (
      select value::double precision as uval
      from jsonb_each_text(v_profile->'vector')
    ) uv;
  end if;

  -- Explore/exploit split from evidence mass (new user -> 0.75 -> 9 of 12 explore).
  v_explore_ratio := greatest(0.25, 0.75 * exp(-v_evidence / 50.0));
  v_explore_slots := greatest(0, least(v_lim, round(v_lim * v_explore_ratio)::integer));
  v_exploit_slots := v_lim - v_explore_slots;

  create temporary table if not exists taste_deck_cand (
    media_type text not null,
    media_id integer not null,
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
    mirrored boolean,
    popularity integer,
    cluster text,
    stratum text,
    fit double precision default 0,
    ucb double precision default 1,
    slot text,
    slot_raw double precision,
    slot_score double precision,
    franchise text,
    top_tags text[],
    picked boolean not null default false,
    primary key (media_type, media_id)
  ) on commit drop;
  delete from taste_deck_cand;

  -- Selection pool: identical eligibility to v1 (score >= 70, not adult, no
  -- Ecchi/Hentai, ancillary formats excluded, not in lists, no prior deck
  -- signal), mirrored-first pull, just deeper.
  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'ANIME', a.id,
    coalesce(nullif(a.title_english, ''), a.title_romaji),
    a.cover_image_large, a.cover_image_medium, a.cover_image_color,
    a.genres, a.average_score, a.format,
    coalesce(a.season_year, a.start_date_year),
    left(coalesce(a.description_normalized, ''), 300),
    a.episodes, null::integer, null::integer,
    (a.cover_image_large like '%/storage/v1/%'),
    coalesce(a.popularity, 0)
  from public.anime a
  where coalesce(a.is_adult, false) = false
    and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    and coalesce(a.average_score, 0) >= 70
    and a.cover_image_large is not null
    and not exists (
      select 1 from public.anime_user_lists ul
      where ul.user_id = v_uid::text
        and ul.anime_id = a.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'ANIME'
        and e.media_id = a.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
    )
  order by (a.cover_image_large like '%/storage/v1/%') desc, coalesce(a.popularity, 0) desc, a.id desc
  limit v_pool_lim;

  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'MANGA', m.id,
    coalesce(nullif(m.title_english, ''), m.title_romaji),
    m.cover_image_large, m.cover_image_medium, m.cover_image_color,
    m.genres, m.average_score, m.format,
    m.start_date_year,
    left(coalesce(m.description_normalized, ''), 300),
    null::integer, m.chapters, m.volumes,
    (m.cover_image_large like '%/storage/v1/%'),
    coalesce(m.popularity, 0)
  from public.manga m
  where coalesce(m.is_adult, false) = false
    and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    and coalesce(m.average_score, 0) >= 70
    and m.cover_image_large is not null
    and not exists (
      select 1 from public.manga_user_lists ul
      where ul.user_id = v_uid::text
        and ul.manga_id = m.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'MANGA'
        and e.media_id = m.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
    )
  order by (m.cover_image_large like '%/storage/v1/%') desc, coalesce(m.popularity, 0) desc, m.id desc
  limit v_pool_lim;

  update taste_deck_cand c
  set cluster = public._taste_genre_cluster(c.genres);

  -- Popularity strata over the pool (percent_rank ascending by popularity):
  -- head pr >= 0.9; gems pr < 0.4 with average_score >= 75; mid 0.1 <= pr < 0.6;
  -- anything left (bottom decile without the gems score, 0.4-0.6 without mid is
  -- impossible) -> 'tail' (only reachable via exploit or starvation fill).
  with s as (
    select
      c.media_type,
      c.media_id,
      percent_rank() over (order by c.popularity asc, c.media_id asc) as pr
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set stratum = case
    when s.pr >= 0.9 then 'head'
    when s.pr < 0.4 and c.average_score >= 75 then 'gems'
    when s.pr >= 0.1 and s.pr < 0.6 then 'mid'
    else 'tail'
  end
  from s
  where s.media_type = c.media_type
    and s.media_id = c.media_id;

  -- Exploit fit: cosine(user vector, title vector) in the shared space.
  -- The stored user vector is L2-normalized; v_unorm recomputes its true norm
  -- (jsonb rounding) so the cosine stays exact.
  if v_unorm > 0 then
    update taste_deck_cand c
    set fit = f.fit
    from (
      select
        c2.media_type,
        c2.media_id,
        case
          when max(v.l2_norm)::double precision > 0
            then least(greatest(
              coalesce(sum(uv.uval * v.w::double precision), 0.0)
                / (v_unorm * max(v.l2_norm)::double precision),
              -1.0), 1.0)
          else 0.0
        end as fit
      from taste_deck_cand c2
      left join public.media_tag_vectors v
        on v.media_type = c2.media_type
       and v.media_id = c2.media_id
      left join (
        select key, value::double precision as uval
        from jsonb_each_text(v_profile->'vector')
      ) uv on uv.key = v.tag_key
      group by c2.media_type, c2.media_id
    ) f
    where f.media_type = c.media_type
      and f.media_id = c.media_id;
  end if;

  -- Explore UCB: mean over the title's deck-stats keys (rank >= 40 tags plus
  -- 'genre:' keys) of (alpha+1)/(alpha+beta+2) + 0.5/sqrt(alpha+beta+1);
  -- missing stat rows -> alpha = beta = 0 (Beta(1,1) prior baked in).
  update taste_deck_cand c
  set ucb = x.ucb
  from (
    select
      c2.media_type,
      c2.media_id,
      avg(
        (coalesce(s.alpha, 0)::double precision + 1.0)
          / (coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 2.0)
        + 0.5 / sqrt(coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 1.0)
      ) as ucb
    from taste_deck_cand c2
    left join lateral (
      select k.tag_key
      from public._taste_deck_title_tag_keys(c2.media_type, c2.media_id) k
    ) keys on true
    left join public.taste_tag_stats s
      on s.user_id = v_uid
     and s.tag_key = keys.tag_key
    group by c2.media_type, c2.media_id
  ) x
  where x.media_type = c.media_type
    and x.media_id = c.media_id;

  -- Slot candidates. Buffers (+6 each side) give MMR and the hard caps room
  -- to skip without starving the batch.
  with ranked as (
    select
      c.media_type,
      c.media_id,
      c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) as es,
      row_number() over (
        order by c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) desc,
                 c.popularity desc, c.media_id desc
      ) as rn
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set slot = 'exploit',
      slot_raw = rk.es
  from ranked rk
  where rk.media_type = c.media_type
    and rk.media_id = c.media_id
    and rk.rn <= v_exploit_slots + 6;

  -- Stratified explore: round-robin over 6 clusters x 3 strata, best UCB per
  -- cell, skipping cells that run dry. A title already slotted for exploit is
  -- not double-dealt as explore.
  v_explore_target := v_explore_slots + 6;
  <<explore_loop>>
  while (select count(*) from taste_deck_cand where slot = 'explore') < v_explore_target loop
    v_prog := false;
    for v_ci in 1..6 loop
      for v_si in 1..3 loop
        select c2.media_type, c2.media_id, c2.ucb
          into r
        from taste_deck_cand c2
        where c2.slot is null
          and c2.cluster = v_clusters[v_ci]
          and c2.stratum = v_strata[v_si]
        order by c2.ucb desc, c2.popularity desc, c2.media_id desc
        limit 1;
        if found then
          update taste_deck_cand c
          set slot = 'explore', slot_raw = r.ucb
          where c.media_type = r.media_type
            and c.media_id = r.media_id;
          v_prog := true;
          exit explore_loop when (select count(*) from taste_deck_cand where slot = 'explore') >= v_explore_target;
        end if;
      end loop;
    end loop;
    exit when not v_prog;
  end loop;

  -- Negative-space probe: p = 0.10 per batch, from the *avoided* list only.
  if random() < 0.10 and coalesce(jsonb_array_length(v_avoided), 0) > 0 then
    select c2.media_type, c2.media_id, c2.ucb
      into r
    from taste_deck_cand c2
    where c2.slot is null
      and exists (
        select 1
        from public.anime_tags at
        join public.tags t on t.id = at.tag_id
        where c2.media_type = 'ANIME'
          and at.anime_id = c2.media_id
          and coalesce(at.rank, 0) >= 60
          and v_avoided ? lower(t.name)
        union all
        select 1
        from public.manga_tags mt
        join public.tags t on t.id = mt.tag_id
        where c2.media_type = 'MANGA'
          and mt.manga_id = c2.media_id
          and coalesce(mt.rank, 0) >= 60
          and v_avoided ? lower(t.name)
      )
    order by c2.ucb desc, c2.popularity desc, c2.media_id desc
    limit 1;
    if found then
      -- Drop the weakest explore pick; the probe takes its slot.
      update taste_deck_cand c
      set slot = null, slot_raw = null
      where c.slot = 'explore'
        and (c.media_type, c.media_id) = (
          select c3.media_type, c3.media_id
          from taste_deck_cand c3
          where c3.slot = 'explore'
          order by c3.slot_raw asc, c3.popularity asc, c3.media_id asc
          limit 1
        );
      update taste_deck_cand c
      set slot = 'explore', slot_raw = r.ucb
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
    end if;
  end if;

  -- Franchise labels: connected components over media_relations restricted to
  -- pool titles (same approach as the profile recompute).
  with recursive
  nodes as (
    select c.media_type, c.media_id from taste_deck_cand c
  ),
  edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from edges
    union
    select b_t, b_i, a_t, a_i from edges
  ),
  reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from nodes n
    union
    select r2.s_t, r2.s_i, a.nt, a.ni
    from reach r2
    join adj a on a.t = r2.t and a.i = r2.i
  ),
  labels as (
    select r2.t as media_type, r2.i as media_id,
           min(r2.s_t || ':' || r2.s_i::text) as label
    from reach r2
    group by r2.t, r2.i
  )
  update taste_deck_cand c
  set franchise = coalesce(l.label, c.media_type || ':' || c.media_id::text)
  from labels l
  where l.media_type = c.media_type
    and l.media_id = c.media_id;

  update taste_deck_cand c
  set franchise = c.media_type || ':' || c.media_id::text
  where c.franchise is null;

  -- MMR overlap space: each title's top 15 tags by |w|.
  update taste_deck_cand c
  set top_tags = (
    select array_agg(v.tag_key)
    from (
      select v2.tag_key
      from public.media_tag_vectors v2
      where v2.media_type = c.media_type
        and v2.media_id = c.media_id
      order by abs(v2.w) desc
      limit 15
    ) v
  );

  -- slot_score: min-max normalize per slot group so UCB (0..~1.5) and cosine
  -- exploit scores (-1..1) compete on a shared 0..1 scale. Degenerate group:
  -- all-equal positives -> 1.0, all-zero -> 0.0.
  for v_slot in select 'exploit' union select 'explore' loop
    select min(c.slot_raw), max(c.slot_raw)
      into v_min_s, v_max_s
    from taste_deck_cand c
    where c.slot = v_slot;
    if v_max_s is null then
      continue;
    elsif v_max_s > v_min_s then
      update taste_deck_cand c
      set slot_score = (c.slot_raw - v_min_s) / (v_max_s - v_min_s)
      where c.slot = v_slot;
    elsif v_max_s > 0 then
      update taste_deck_cand c set slot_score = 1.0 where c.slot = v_slot;
    else
      update taste_deck_cand c set slot_score = 0.0 where c.slot = v_slot;
    end if;
  end loop;

  -- Half anime / half manga with v1 cross-fill on starvation.
  select
    count(*) filter (where c.media_type = 'ANIME'),
    count(*) filter (where c.media_type = 'MANGA')
  into v_a_count, v_m_count
  from taste_deck_cand c;
  v_a_take := least(v_a_count, v_lim - least(v_m_count, v_half));
  v_m_take := least(v_m_count, v_lim - v_a_take);

  -- MMR assembly (lambda = 0.7) with hard caps.
  while v_picked < v_lim loop
    v_best := null;
    v_best_mmr := null;
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.cluster = r.cluster
      ) >= v_cluster_cap;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.franchise = r.franchise
      ) >= v_franchise_cap;

      v_tags := r.top_tags;
      select coalesce(max(o.ovl), 0.0)
        into v_max_ovl
      from (
        select (
          select count(*)::double precision
          from (select unnest(v_tags) intersect select unnest(p2.top_tags)) i
        ) / nullif((
          select count(*)::double precision
          from (select unnest(v_tags) union select unnest(p2.top_tags)) u
        ), 0) as ovl
        from taste_deck_cand p2
        where p2.picked
      ) o;

      v_mmr := 0.7 * r.slot_score - 0.3 * coalesce(v_max_ovl, 0.0);
      if v_best_mmr is null or v_mmr > v_best_mmr then
        v_best := r;
        v_best_mmr := v_mmr;
      end if;
    end loop;
    exit when v_best is null;

    update taste_deck_cand c
    set picked = true
    where c.media_type = v_best.media_type
      and c.media_id = v_best.media_id;
    if v_best.media_type = 'ANIME' then
      v_pa := v_pa + 1;
    else
      v_pm := v_pm + 1;
    end if;
    v_picked := v_picked + 1;
  end loop;

  -- Starvation fill 1: remaining slotted candidates, caps relaxed, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Starvation fill 2: unslotted pool in v1 mirrored-first order, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where not c.picked
      order by c.mirrored desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Final output keeps v1's mirrored-first ordering and the 050000 meta strip.
  return query
  select
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.cover_image_medium,
    c.cover_image_color,
    c.genres,
    c.average_score,
    c.format,
    c.year,
    c.synopsis,
    c.episodes,
    c.chapters,
    c.volumes,
    case
      when c.media_type = 'ANIME' and c.format = 'TV'
        then public._taste_deck_seasons_count(c.media_id)
      else null
    end as seasons_count,
    avail.has_dub,
    avail.has_sub
  from taste_deck_cand c
  left join lateral (
    select
      bool_or(exists (
        select 1
        from unnest(pa.audio_langs) as lang
        where lower(trim(lang)) not in ('', 'ja', 'jpn', 'japanese', 'unknown')
      )) as has_dub,
      bool_or(coalesce(array_length(pa.subtitle_langs, 1), 0) > 0) as has_sub
    from public.provider_availability pa
    where pa.media_type = c.media_type
      and pa.media_id = c.media_id
  ) avail on true
  where c.picked
  order by c.mirrored desc, c.popularity desc, c.media_id desc;
end;
$$;

revoke all on function public.fetch_taste_deck_batch(integer) from public;
grant execute on function public.fetch_taste_deck_batch(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8) fetch_personalized_new_to_you v2: cosine fit + evidence-ramped blend
--    Same signature/columns as v1 -> drop first; iOS unchanged.
-- ---------------------------------------------------------------------------
drop function if exists public.fetch_personalized_new_to_you(integer, text);

create function public.fetch_personalized_new_to_you(
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
  v_profile jsonb;
  v_avoided jsonb := '[]'::jsonb;
  v_unorm double precision := 0;
  v_evidence double precision := 0;
  v_w double precision := 0;
  v_ids integer[] := '{}'::integer[];
  r record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;

  select p.vector into v_profile
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_profile is not null then
    v_evidence := coalesce((v_profile->>'evidence')::double precision, 0);
    v_avoided := coalesce(v_profile->'avoided_tags', '[]'::jsonb);
    select coalesce(sqrt(sum(uv.uval * uv.uval)), 0)
      into v_unorm
    from (
      select value::double precision as uval
      from jsonb_each_text(v_profile->'vector')
    ) uv;
  end if;

  -- Contract-capped ramp: w = 0.20 * n/(n+20); n = 0 -> pure editorial fallback.
  v_w := case
    when v_evidence > 0 and v_unorm > 0
      then 0.20 * v_evidence / (v_evidence + 20.0)
    else 0.0
  end;

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
          -- Cosine fit in the shared vector space; -0.5 avoided-tag penalty
          -- (rank >= 60) on fit, then clamped to [-1, 1].
          least(greatest(
            case
              when v_w > 0 and f.tnorm > 0
                then least(greatest(f.dot / (v_unorm * f.tnorm), -1.0), 1.0)
              else 0.0
            end
            + case when exists (
                select 1
                from public.anime_tags at3
                join public.tags t3 on t3.id = at3.tag_id
                where at3.anime_id = c.media_id
                  and at3.rank >= 60
                  and v_avoided ? lower(t3.name)
              ) then -0.5 else 0.0 end,
            -1.0), 1.0) as fit
        from candidates c
        left join lateral (
          select
            sum(v.w::double precision * uv.uval) as dot,
            max(v.l2_norm)::double precision as tnorm
          from public.media_tag_vectors v
          join (
            select key, value::double precision as uval
            from jsonb_each_text(v_profile->'vector')
          ) uv on uv.key = v.tag_key
          where v.media_type = 'ANIME'
            and v.media_id = c.media_id
        ) f on true
      )
      select
        'ANIME'::text as media_type,
        s.media_id,
        s.title,
        s.cover_image_large,
        s.cover_image_medium,
        s.cover_image_color,
        s.genres,
        s.average_score,
        s.format,
        s.year,
        s.synopsis
      from scored s
      order by
        ((1.0 - v_w) * s.editorial_prior + v_w * s.fit) desc,
        s.popularity desc,
        s.average_score desc,
        s.favourites desc,
        s.media_id desc
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
          least(greatest(
            case
              when v_w > 0 and f.tnorm > 0
                then least(greatest(f.dot / (v_unorm * f.tnorm), -1.0), 1.0)
              else 0.0
            end
            + case when exists (
                select 1
                from public.manga_tags mt3
                join public.tags t3 on t3.id = mt3.tag_id
                where mt3.manga_id = c.media_id
                  and mt3.rank >= 60
                  and v_avoided ? lower(t3.name)
              ) then -0.5 else 0.0 end,
            -1.0), 1.0) as fit
        from candidates c
        left join lateral (
          select
            sum(v.w::double precision * uv.uval) as dot,
            max(v.l2_norm)::double precision as tnorm
          from public.media_tag_vectors v
          join (
            select key, value::double precision as uval
            from jsonb_each_text(v_profile->'vector')
          ) uv on uv.key = v.tag_key
          where v.media_type = 'MANGA'
            and v.media_id = c.media_id
        ) f on true
      )
      select
        'MANGA'::text as media_type,
        s.media_id,
        s.title,
        s.cover_image_large,
        s.cover_image_medium,
        s.cover_image_color,
        s.genres,
        s.average_score,
        s.format,
        s.year,
        s.synopsis
      from scored s
      order by
        ((1.0 - v_w) * s.editorial_prior + v_w * s.fit) desc,
        s.popularity desc,
        s.average_score desc,
        s.favourites desc,
        s.media_id desc
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
-- 9) recommend_ids_similar_to_seeds v2: content-pure cosine + craft multiplier
--    Same signature/output columns -> drop first; iOS + concierge unchanged.
-- ---------------------------------------------------------------------------
drop function if exists public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean);

create function public.recommend_ids_similar_to_seeds(
  p_media_type text,
  p_seed_ids integer[],
  p_limit integer default 10,
  p_allow_gimmicks boolean default false
)
returns table (
  media_id integer,
  overlap_count integer,
  score real
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  seed_vec as (
    -- Seed set vector = element-wise average of the seed title vectors.
    select v.tag_key, avg(v.w)::double precision as w
    from public.media_tag_vectors v
    where v.media_type = p_media_type
      and p_seed_ids is not null
      and v.media_id = any(p_seed_ids)
    group by v.tag_key
  ),
  seed_norm as (
    select nullif(sqrt(sum(sv.w * sv.w)), 0)::double precision as n
    from seed_vec sv
  ),
  seed_genres_anime as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.anime a
    cross join unnest(coalesce(a.genres, '{}'::text[])) as g
    where p_media_type = 'ANIME'
      and p_seed_ids is not null
      and a.id = any(p_seed_ids)
  ),
  seed_genres_manga as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.manga m
    cross join unnest(coalesce(m.genres, '{}'::text[])) as g
    where p_media_type = 'MANGA'
      and p_seed_ids is not null
      and m.id = any(p_seed_ids)
  ),
  cand_cos as (
    -- Full cosine over the shared vector space. No popularity/score/recency.
    select
      v.media_id,
      count(*)::integer as overlap_count,
      sum(v.w::double precision * sv.w)
        / ((select n from seed_norm) * max(v.l2_norm)::double precision) as similarity
    from public.media_tag_vectors v
    join seed_vec sv on sv.tag_key = v.tag_key
    where v.media_type = p_media_type
      and not (v.media_id = any(p_seed_ids))
    group by v.media_id
    having max(v.l2_norm) > 0
  ),
  anime_pen as (
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_pen as (
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id
  ),
  anime_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%director%'
          and ys.role ilike '%director%'
      ) as shared_creator,
      exists (
        select 1
        from public.anime_studios xs
        join public.anime_studios ys
          on ys.studio_id = xs.studio_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
      ) as shared_studio,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%creator%'
          and ys.role ilike '%creator%'
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'ANIME'
  ),
  manga_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
          and xs.role ilike '%story%'
          and ys.role ilike '%story%'
      ) as shared_creator,
      false as shared_studio,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'MANGA'
  )
  select ranked.media_id, ranked.overlap_count, ranked.score
  from (
    select
      a.id as media_id,
      cc.overlap_count as overlap_count,
      (
        cc.similarity * least(2.0, 1.0
          + 0.5 * coalesce(ac.shared_creator, false)::int
          + 0.15 * coalesce(ac.shared_studio, false)::int
          + 0.5 * coalesce(ac.shared_author, false)::int)
        - case when (select allow_gimmicks from req) then 0.0
               else coalesce(ap.penalty, 0)::double precision end
      )::real as score,
      coalesce(a.popularity, 0) as popularity
    from cand_cos cc
    join public.anime a on a.id = cc.media_id
    left join anime_craft ac on ac.media_id = cc.media_id
    left join anime_pen ap on ap.media_id = cc.media_id
    where p_media_type = 'ANIME'
      and cc.similarity is not null
      and a.cover_image_large is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_anime), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(a.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_anime)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_anime), 0) >= 4 then 2
              else 1
            end
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      m.id as media_id,
      cc.overlap_count as overlap_count,
      (
        cc.similarity * least(2.0, 1.0
          + 0.5 * coalesce(mc.shared_creator, false)::int
          + 0.15 * coalesce(mc.shared_studio, false)::int
          + 0.5 * coalesce(mc.shared_author, false)::int)
        - case when (select allow_gimmicks from req) then 0.0
               else coalesce(mp.penalty, 0)::double precision end
      )::real as score,
      coalesce(m.popularity, 0) as popularity
    from cand_cos cc
    join public.manga m on m.id = cc.media_id
    left join manga_craft mc on mc.media_id = cc.media_id
    left join manga_pen mp on mp.media_id = cc.media_id
    where p_media_type = 'MANGA'
      and cc.similarity is not null
      and m.cover_image_large is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_manga), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(m.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_manga)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_manga), 0) >= 4 then 2
              else 1
            end
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ) ranked
  order by score desc, popularity desc, media_id desc
  limit (select lim from req);
$$;

-- Mirrors the live grants (no revoke: PUBLIC default execute preserved, as before).
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 10) Ops view v2 (service_role only)
-- ---------------------------------------------------------------------------
drop view if exists public.taste_pipeline_status;

create view public.taste_pipeline_status as
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
  coalesce((
    select jsonb_object_agg(s.event_type, s.n)
    from (
      select e.event_type, count(*) as n
      from public.taste_signal_events e
      where e.created_at > now() - interval '7 days'
      group by e.event_type
    ) s
  ), '{}'::jsonb) as events_by_type_7d,
  (
    -- deal -> love conversion over the last 7 days (deck events only)
    select round(
      count(*) filter (where e.event_type = 'deck_love')::numeric
        / nullif(count(*), 0),
      4)
    from public.taste_signal_events e
    where e.created_at > now() - interval '7 days'
      and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
  ) as deck_love_rate_7d,
  (
    select count(*)::integer
    from public.user_taste_profiles p
  ) as users_with_profiles,
  (
    select round(avg((p.vector->>'confidence')::numeric), 4)
    from public.user_taste_profiles p
  ) as avg_confidence,
  (
    select round(avg((p.vector->>'evidence')::numeric), 2)
    from public.user_taste_profiles p
    where p.vector ? 'evidence'
  ) as avg_evidence,
  (
    select count(*)::integer
    from public.user_taste_profiles p
    where coalesce((p.vector->>'evidence')::double precision, 0) >= 20
  ) as users_evidence_20plus,
  (
    -- Cheap catalog coverage note (planner estimate, no matview scan).
    select 'media_tag_vectors rows (est): ' || c.reltuples::bigint
    from pg_class c
    where c.oid = 'public.media_tag_vectors'::regclass
  ) as catalog_coverage_note;

revoke all on public.taste_pipeline_status from anon, authenticated;
grant select on public.taste_pipeline_status to service_role;

-- ---------------------------------------------------------------------------
-- 11) pg_cron: nightly vector refresh + weekly posterior decay (pure SQL)
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid)
from cron.job
where jobname in ('taste-tag-vectors-refresh', 'taste-tag-stats-decay');

-- 03:50 UTC nightly (single statement: pg_cron cannot run multi-statement commands).
select cron.schedule(
  'taste-tag-vectors-refresh',
  '50 3 * * *',
  $cmd$refresh materialized view concurrently public.media_tag_vectors;$cmd$
);

-- Sunday 04:10 UTC: posterior decay re-widens old posteriors (drift -> explore).
select cron.schedule(
  'taste-tag-stats-decay',
  '10 4 * * 0',
  $cmd$update public.taste_tag_stats set alpha = alpha * 0.95, beta = beta * 0.95;$cmd$
);
