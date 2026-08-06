-- Realm Graph Stage 1b — core SQL (spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md
-- §0, §3, §4, §8). Builds on 20260731120000 (realm_signatures/realm_meta) and
-- 20260731130000 (canon_seed); consumes media_tag_vectors (20260731070000 form).
--
-- Chain note: media_realm_membership depends on media_tag_vectors, so the
-- historical 20260731060000/20260731070000 files (which DROP that matview
-- WITHOUT cascade) can no longer be re-applied after this migration — drop
-- this file's three matviews first if that is ever needed. Production
-- applies migrations once, in order, so this only affects local replays.
--
-- Contents:
--   1) media_realm_membership  matview  — title x realm fuzzy membership (0..1)
--   2) realm_affinity          matview  — measured realm x realm co-membership cosine
--      realm_affinity_overrides table   — editorial veto point #2 (RLS public read)
--      realm_affinity_effective view    — coalesce(override, measured)
--   3) media_realm_tier        matview  — per-title tier within its top realm
--   4) recommend_ids_similar_to_seeds v4 — v2 cosine/craft/exclusions + realm gate
--      + tier compatibility + curated-rail co-membership boost (acclaim band
--      REMOVED: the realm/tier gate replaces it; popularity stays tiebreak-only)
--   5) fetch_because_you_rail v2 — v4-gated similarity + realm stamp per row
--   6) recompute_user_taste_profile v4 — 090000 form + profile.realms (top 6)
--   7) fetch_taste_deck_batch v4 — 090000 form + explore realm-family axis
--   8) pg_cron refresh jobs (one per matview; pg_cron runs single statements)
--
-- Membership formula (spec §3): weight = dot(title, signature over SHARED
-- tag_keys) / (|title| x |signature|), where |title| is the title's stored
-- l2_norm over ALL its tags (media_tag_vectors.l2_norm) and |signature| is the
-- realm signature's norm over its full key set. Kept per title: top 4 realms
-- by weight (tiebreak realm asc) UNION any realm with weight >= T.
--
-- T (membership threshold) = 0.25 — CALIBRATION EVIDENCE (2026-08-01, PG 17
-- scratch, 320-title synthetic catalog seeded from the realm signature
-- vocabulary with weighted key draws 4-8/title + 1-3 genres + 35% cross-realm
-- noise; df/IDF structure mirrors the production formula):
--   nonzero title x realm weights: 8520 pairs over 320 titles
--     p50 0.076 / p75 0.139 / p90 0.244 / p95 0.372 / p99 0.663 / max 0.901
--   rank-stratified medians (per-title weight rank):
--     #1 0.600 (p10 0.475) / #2 0.311 / #3 0.236 / #4 0.196 / #5 0.171 / #8 0.123
-- T = 0.25 ~= the p90 of nonzero memberships (0.244, rounded to 0.05). It sits
-- above the rank-5+ noise floor (median <= 0.17) while genuine #2-#3
-- memberships (medians 0.31/0.24) pass; the spec's 0.35 guess (~p94 here)
-- would fail most #3 memberships and leave the >=T keep-clause nearly inert
-- (avg realms >= 0.35 per title: 1.42; >= 0.25: ~2.6). RE-VERIFY against the
-- production catalog after first refresh (same one-liner on
-- media_realm_membership's full-score CTE) — calibration ran on a synthetic
-- sample, not the live catalog.
--
-- Documented decisions (all inspectable in SQL, spec §9):
--   * realm_affinity is computed over the STORED membership rows (top-4 + >=T
--     graph) — the same graph the gates see — not over unkept tail weights.
--     affinity = sum(min(m_ta, m_tb)) / sqrt(sum(m_ta^2) * sum(m_tb^2)) over
--     titles with membership in either realm; all 40x40 pairs stored in both
--     directions, a = b excluded, pairs with no shared members -> 0.
--     NOTE (scale): this is the spec's min-cosine VERBATIM and it is NOT
--     bounded by 1 — with n shared members of comparable weight, min-sum
--     grows ~linearly in n while the norms grow ~sqrt(n), so pairs with many
--     weak co-members read > 1 (observed 2.13 on the test fixture). Treat
--     affinity as an unbounded similarity score: the 0.25 gate threshold is
--     correspondingly low on this scale, and realm_affinity_overrides
--     (confined to [-1,1]) is the editorial escape hatch for both directions
--     (boost a weak pair over the gate, or zero out a noisy one).
--   * Tier percentiles: percent_rank over (average_score, favourites, media_id)
--     within the realm's >=T member set. A realm whose member set has exactly
--     one title is treated as p = 1.0 (a singleton is trivially the best of
--     its set); production realms have hundreds of members, this only matters
--     for fixtures/edge realms.
--   * canon_seed.media_id is the AniList id; the catalog's anime.id/manga.id
--     are internal serials. The canon force therefore joins canon_seed via
--     anime.anilist_id / manga.anilist_id.
--   * Craft lift (spec §3): the title's director (ANIME: anime_staff role
--     ILIKE '%director%') or author (MANGA: any manga_authors row — same
--     mapping as the v2 craft multiplier) must have >= 2 OTHER pre-lift
--     canon-tier works in the same media type. Lift is exactly one step
--     (tail -> solid -> acclaimed -> canon), applied AFTER the canon_seed
--     force; "other" excludes the title itself when it is already canon.
--   * Similarity v4 gates are VACUOUS when the seed set carries no realm
--     (resp. tier) signal — untagged seeds keep exact v2 behavior instead of
--     returning nothing.
--   * Editorial co-membership boost: candidate shares >= 1 curated_rails rail
--     with any seed -> x1.25. Craft multiplier keeps its v2 x2.0 cap; the
--     TOTAL multiplier is capped at x2.5 (2.0 x 1.25 = 2.5 exactly, so a
--     max-craft + same-rail candidate saturates both caps simultaneously).
--   * Deck family axis: "signaled families" = families of the top realms of
--     titles with any non-pass taste event in the last 30 days; explore UCB
--     is multiplied by 1.5 for candidates whose top-realm family is not in
--     that set (candidates with no realm row are not boosted). Exploit fit,
--     MMR, caps, pass memory and all meta columns are byte-identical to
--     20260731090000.

-- ---------------------------------------------------------------------------
-- 0) Idempotent re-application: drop dependents before the matviews they
--    reference. recommend_* is LANGUAGE sql (hard dependencies on the
--    matviews/view); the plpgsql functions are dropped at their sections.
-- ---------------------------------------------------------------------------
drop function if exists public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean);
drop view if exists public.realm_affinity_effective;
drop materialized view if exists public.media_realm_tier;
drop materialized view if exists public.realm_affinity;
drop materialized view if exists public.media_realm_membership;

-- ---------------------------------------------------------------------------
-- 1) Membership threshold T — single source of truth for the matview keep-rule
--    and the v4 similarity gates. Changing T requires refreshing
--    media_realm_membership / realm_affinity / media_realm_tier (cron does it
--    nightly). Value + calibration evidence in the header comment.
-- ---------------------------------------------------------------------------
create or replace function public._realm_membership_threshold()
returns real
language sql
immutable
set search_path = public, extensions
as $$ select 0.25::real $$;

revoke all on function public._realm_membership_threshold() from public;
grant execute on function public._realm_membership_threshold() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) media_realm_membership
-- ---------------------------------------------------------------------------
create materialized view public.media_realm_membership as
with sig as (
  select rs.realm, rs.family, rs.tag_key, rs.weight::double precision as w
  from public.realm_signatures rs
),
sig_norm as (
  select s.realm, nullif(sqrt(sum(s.w * s.w)), 0) as n
  from sig s
  group by s.realm
),
scored as (
  -- dot over shared tag_keys; title norm = stored l2_norm over ALL its tags.
  select
    v.media_type,
    v.media_id,
    s.realm,
    min(s.family) as family,
    sum(v.w::double precision * s.w)
      / (max(v.l2_norm)::double precision * max(sn.n)) as weight
  from public.media_tag_vectors v
  join sig s on s.tag_key = v.tag_key
  join sig_norm sn on sn.realm = s.realm
  where v.l2_norm > 0
  group by v.media_type, v.media_id, s.realm
),
kept as (
  select
    sc.media_type,
    sc.media_id,
    sc.realm,
    sc.family,
    sc.weight,
    row_number() over (
      partition by sc.media_type, sc.media_id
      order by sc.weight desc, sc.realm asc
    ) as rn
  from scored sc
  where sc.weight > 0
)
select
  k.media_type,
  k.media_id,
  k.realm,
  k.family,
  k.weight::real as weight
from kept k
where k.rn <= 4
   or k.weight >= public._realm_membership_threshold();

create unique index media_realm_membership_uidx
  on public.media_realm_membership (media_type, media_id, realm);
create index media_realm_membership_media_idx
  on public.media_realm_membership (media_type, media_id);
create index media_realm_membership_realm_idx
  on public.media_realm_membership (realm);

revoke all on public.media_realm_membership from public;
grant select on public.media_realm_membership to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) realm_affinity + realm_affinity_overrides + realm_affinity_effective
-- ---------------------------------------------------------------------------
create materialized view public.realm_affinity as
with pairs as (
  -- computed once per unordered pair (lo, hi), then fanned out to both
  -- directions so lookups only ever probe realm_a.
  select
    a.realm as realm_lo,
    b.realm as realm_hi,
    sum(least(a.weight::double precision, b.weight::double precision)) as min_sum
  from public.media_realm_membership a
  join public.media_realm_membership b
    on b.media_type = a.media_type
   and b.media_id = a.media_id
   and b.realm > a.realm
  group by a.realm, b.realm
),
norms as (
  select m.realm, sum(m.weight::double precision * m.weight::double precision) as ss
  from public.media_realm_membership m
  group by m.realm
),
measured as (
  select
    p.realm_lo,
    p.realm_hi,
    (p.min_sum / nullif(sqrt(nl.ss * nh.ss), 0))::real as affinity
  from pairs p
  join norms nl on nl.realm = p.realm_lo
  join norms nh on nh.realm = p.realm_hi
),
all_pairs as (
  select ra.realm as realm_a, rb.realm as realm_b
  from public.realm_meta ra
  cross join public.realm_meta rb
  where ra.realm <> rb.realm
)
select
  ap.realm_a,
  ap.realm_b,
  coalesce(m.affinity, 0)::real as affinity
from all_pairs ap
left join measured m
  on m.realm_lo = least(ap.realm_a, ap.realm_b)
 and m.realm_hi = greatest(ap.realm_a, ap.realm_b);

create unique index realm_affinity_uidx
  on public.realm_affinity (realm_a, realm_b);
create index realm_affinity_b_idx
  on public.realm_affinity (realm_b);

revoke all on public.realm_affinity from public;
grant select on public.realm_affinity to authenticated, service_role;

-- Editorial veto point #2 (spec §9): hand-set adjacencies that beat the
-- measured value. Catalog-level editorial data, no user data: public SELECT.
create table if not exists public.realm_affinity_overrides (
  realm_a text not null references public.realm_meta(realm),
  realm_b text not null references public.realm_meta(realm),
  affinity real not null check (affinity between -1 and 1),
  reason text not null default '',
  primary key (realm_a, realm_b),
  check (realm_a <> realm_b)
);

alter table public.realm_affinity_overrides enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='realm_affinity_overrides' and policyname='realm_affinity_overrides_select_all'
  ) then
    create policy realm_affinity_overrides_select_all on public.realm_affinity_overrides
      for select using (true);
  end if;
end $$;

grant select on public.realm_affinity_overrides to anon, authenticated;

-- Effective affinity = coalesce(override, measured). Overrides are directed
-- rows: to override both directions, insert both (documented on the table).
comment on table public.realm_affinity_overrides is
  'Editorial realm-affinity overrides (directed: insert both (a,b) and (b,a) to override both directions). Effective affinity = coalesce(override, measured) via public.realm_affinity_effective.';

create view public.realm_affinity_effective as
select
  a.realm_a,
  a.realm_b,
  coalesce(o.affinity, a.affinity)::real as affinity,
  case when o.affinity is not null then 'override' else 'measured' end as source
from public.realm_affinity a
left join public.realm_affinity_overrides o
  on o.realm_a = a.realm_a
 and o.realm_b = a.realm_b;

revoke all on public.realm_affinity_effective from public;
grant select on public.realm_affinity_effective to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) media_realm_tier: each title's tier inside its TOP realm.
--    Acclaim = average_score with favourites as tiebreak; percentile within
--    the realm's >=T member set: canon >= p97, acclaimed >= p85, solid >= p60,
--    else tail. canon_seed membership forces 'canon' in the title's top realm.
--    Craft lift: director (anime) / author (manga) with >= 2 other pre-lift
--    canon-tier works lifts one tier. Text tiers for readability (spec §3).
-- ---------------------------------------------------------------------------
create materialized view public.media_realm_tier as
with cat as (
  select 'ANIME'::text as media_type, a.id, a.anilist_id,
         coalesce(a.average_score, 0) as score, coalesce(a.favourites, 0) as favourites
  from public.anime a
  union all
  select 'MANGA'::text, m.id, m.anilist_id,
         coalesce(m.average_score, 0), coalesce(m.favourites, 0)
  from public.manga m
),
top_realm as (
  -- exactly one row per title: its highest-weight membership (deterministic).
  select s.media_type, s.media_id, s.realm
  from (
    select
      m.media_type,
      m.media_id,
      m.realm,
      row_number() over (
        partition by m.media_type, m.media_id
        order by m.weight desc, m.realm asc
      ) as rn
    from public.media_realm_membership m
  ) s
  where s.rn = 1
),
realm_members as (
  -- the percentile basis: members of each realm at weight >= T.
  select
    m.media_type,
    m.media_id,
    m.realm,
    c.score,
    c.favourites
  from public.media_realm_membership m
  join cat c on c.media_type = m.media_type and c.id = m.media_id
  where m.weight >= public._realm_membership_threshold()
),
ranked as (
  select
    rm.media_type,
    rm.media_id,
    rm.realm,
    case
      when count(*) over (partition by rm.realm) = 1 then 1.0
      else percent_rank() over (
        partition by rm.realm
        order by rm.score asc, rm.favourites asc, rm.media_id asc
      )
    end as pct
  from realm_members rm
),
base_tier as (
  select
    tr.media_type,
    tr.media_id,
    tr.realm,
    c.anilist_id,
    r.pct,
    case
      when r.pct >= 0.97 then 'canon'
      when r.pct >= 0.85 then 'acclaimed'
      when r.pct >= 0.60 then 'solid'
      else 'tail'
    end as pct_tier
  from top_realm tr
  join ranked r
    on r.media_type = tr.media_type
   and r.media_id = tr.media_id
   and r.realm = tr.realm
  join cat c
    on c.media_type = tr.media_type
   and c.id = tr.media_id
),
forced as (
  -- canon_seed force (joined via anilist_id — canon_seed.media_id = AniList id).
  select
    bt.media_type,
    bt.media_id,
    bt.realm,
    case
      when cs.media_id is not null then 'canon'
      else bt.pct_tier
    end as tier_pre_lift
  from base_tier bt
  left join (
    select distinct cs2.media_type, cs2.media_id
    from public.canon_seed cs2
  ) cs
    on cs.media_type = bt.media_type
   and cs.media_id = bt.anilist_id
),
canon_directors as (
  select s.staff_id as person_id, count(distinct s.anime_id) as n
  from public.anime_staff s
  join forced f
    on f.media_type = 'ANIME'
   and f.media_id = s.anime_id
   and f.tier_pre_lift = 'canon'
  where s.role ilike '%director%'
  group by s.staff_id
),
canon_authors as (
  select ma.author_id as person_id, count(distinct ma.manga_id) as n
  from public.manga_authors ma
  join forced f
    on f.media_type = 'MANGA'
   and f.media_id = ma.manga_id
   and f.tier_pre_lift = 'canon'
  group by ma.author_id
),
lifted as (
  select
    f.media_type,
    f.media_id,
    f.realm,
    f.tier_pre_lift,
    case
      when f.tier_pre_lift = 'canon' then 'canon'
      when (
        exists (
          select 1
          from public.anime_staff s
          join canon_directors cd on cd.person_id = s.staff_id
          where f.media_type = 'ANIME'
            and s.anime_id = f.media_id
            and s.role ilike '%director%'
            and cd.n >= 2
        )
        or exists (
          select 1
          from public.manga_authors ma
          join canon_authors ca on ca.person_id = ma.author_id
          where f.media_type = 'MANGA'
            and ma.manga_id = f.media_id
            and ca.n >= 2
        )
      ) then
        case f.tier_pre_lift
          when 'tail' then 'solid'
          when 'solid' then 'acclaimed'
          else 'canon'
        end
      else f.tier_pre_lift
    end as tier
  from forced f
)
select
  l.media_type,
  l.media_id,
  l.realm,
  l.tier
from lifted l;

-- One row per title (its top realm), so (media_type, media_id) is unique;
-- that is also the lookup shape used by the deck and Because-You.
create unique index media_realm_tier_uidx
  on public.media_realm_tier (media_type, media_id);
create index media_realm_tier_realm_idx
  on public.media_realm_tier (realm);

revoke all on public.media_realm_tier from public;
grant select on public.media_realm_tier to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) recommend_ids_similar_to_seeds v4 (spec §3):
--    v2's full cosine x craft multiplier x gimmick penalty + exclusions
--    (adult/Ecchi/Hentai, has-cover, not-in-list, seed-genre gate) UNCHANGED,
--    PLUS:
--      realm gate — candidate shares >= 1 realm at weight >= T with the seed
--        set's realms S, OR its top realm has effective affinity >= 0.25 with
--        any S realm. Vacuous when S is empty (untagged seeds -> v2 behavior).
--      tier compatibility — candidate tier within +-1 of the HIGHEST seed
--        tier (canon 4 / acclaimed 3 / solid 2 / tail 1): canon seeds admit
--        canon+acclaimed, acclaimed admit canon..solid, solid admit
--        acclaimed..tail, tail admits solid+tail. Vacuous when no seed has a
--        tier row.
--      ordering — cosine x craft (cap x2.0, unchanged) x curated-rail
--        co-membership boost (shared rail with any seed: x1.25), total
--        multiplier capped x2.5. The 112000-era acclaim band is REMOVED (the
--        realm/tier gate replaces it); popularity remains tiebreak-only.
-- ---------------------------------------------------------------------------
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
  seed_realms as (
    -- S: realms where any seed holds membership at weight >= T.
    select distinct m.realm
    from public.media_realm_membership m
    where m.media_type = p_media_type
      and p_seed_ids is not null
      and m.media_id = any(p_seed_ids)
      and m.weight >= public._realm_membership_threshold()
  ),
  seed_tier_rank as (
    -- Highest tier among seeds (canon 4 / acclaimed 3 / solid 2 / tail 1).
    select max(case t.tier
                 when 'canon' then 4
                 when 'acclaimed' then 3
                 when 'solid' then 2
                 else 1
               end) as r
    from public.media_realm_tier t
    where t.media_type = p_media_type
      and p_seed_ids is not null
      and t.media_id = any(p_seed_ids)
  ),
  seed_rails as (
    -- curated_rails rails containing any seed (items key on AniList ids).
    select distinct i.rail_id
    from public.curated_rail_items i
    where p_seed_ids is not null
      and (
        (p_media_type = 'ANIME' and i.media_type = 'ANIME' and i.anilist_id in (
          select a2.anilist_id from public.anime a2 where a2.id = any(p_seed_ids)))
        or
        (p_media_type = 'MANGA' and i.media_type = 'MANGA' and i.anilist_id in (
          select m2.anilist_id from public.manga m2 where m2.id = any(p_seed_ids)))
      )
  ),
  rail_cands_anime as (
    select distinct a3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.anime a3 on a3.anilist_id = i.anilist_id
    where i.media_type = 'ANIME'
      and p_media_type = 'ANIME'
  ),
  rail_cands_manga as (
    select distinct m3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.manga m3 on m3.anilist_id = i.anilist_id
    where i.media_type = 'MANGA'
      and p_media_type = 'MANGA'
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
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(ac.shared_creator, false)::int
            + 0.15 * coalesce(ac.shared_studio, false)::int
            + 0.5 * coalesce(ac.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
        - case when (select allow_gimmicks from req) then 0.0
               else coalesce(ap.penalty, 0)::double precision end
      )::real as score,
      coalesce(a.popularity, 0) as popularity
    from cand_cos cc
    join public.anime a on a.id = cc.media_id
    left join anime_craft ac on ac.media_id = cc.media_id
    left join anime_pen ap on ap.media_id = cc.media_id
    left join rail_cands_anime rc on rc.media_id = cc.media_id
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
      and (
        not exists (select 1 from seed_realms)
        or exists (
          select 1
          from public.media_realm_membership cm
          join seed_realms sr on sr.realm = cm.realm
          where cm.media_type = p_media_type
            and cm.media_id = a.id
            and cm.weight >= public._realm_membership_threshold()
        )
        or exists (
          select 1
          from public.media_realm_tier ct
          join public.realm_affinity_effective e on e.realm_a = ct.realm
          join seed_realms sr on sr.realm = e.realm_b
          where ct.media_type = p_media_type
            and ct.media_id = a.id
            and e.affinity >= 0.25
        )
      )
      and (
        (select r from seed_tier_rank) is null
        or (
          select abs(
            case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
            - (select r from seed_tier_rank)
          )
          from public.media_realm_tier ct
          where ct.media_type = p_media_type
            and ct.media_id = a.id
        ) <= 1
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
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(mc.shared_creator, false)::int
            + 0.15 * coalesce(mc.shared_studio, false)::int
            + 0.5 * coalesce(mc.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
        - case when (select allow_gimmicks from req) then 0.0
               else coalesce(mp.penalty, 0)::double precision end
      )::real as score,
      coalesce(m.popularity, 0) as popularity
    from cand_cos cc
    join public.manga m on m.id = cc.media_id
    left join manga_craft mc on mc.media_id = cc.media_id
    left join manga_pen mp on mp.media_id = cc.media_id
    left join rail_cands_manga rc on rc.media_id = cc.media_id
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
      and (
        not exists (select 1 from seed_realms)
        or exists (
          select 1
          from public.media_realm_membership cm
          join seed_realms sr on sr.realm = cm.realm
          where cm.media_type = p_media_type
            and cm.media_id = m.id
            and cm.weight >= public._realm_membership_threshold()
        )
        or exists (
          select 1
          from public.media_realm_tier ct
          join public.realm_affinity_effective e on e.realm_a = ct.realm
          join seed_realms sr on sr.realm = e.realm_b
          where ct.media_type = p_media_type
            and ct.media_id = m.id
            and e.affinity >= 0.25
        )
      )
      and (
        (select r from seed_tier_rank) is null
        or (
          select abs(
            case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
            - (select r from seed_tier_rank)
          )
          from public.media_realm_tier ct
          where ct.media_type = p_media_type
            and ct.media_id = m.id
        ) <= 1
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
-- 6) fetch_because_you_rail v2: the 100000 form, now riding the v4-gated
--    recommend_ids_similar_to_seeds (realm + tier gates inherited), plus a
--    `realm` column stamped with the candidate's top realm (from
--    media_realm_tier) so iOS can group/label later. All other behavior
--    (seed pick, >= 2 distinct positives guard, interleave, deck-echo
--    suppression, reason_title) unchanged.
-- ---------------------------------------------------------------------------
drop function if exists public.fetch_because_you_rail(integer);

create function public.fetch_because_you_rail(p_limit integer default 12)
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
  reason_title text,
  realm text
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

  -- Per-type candidates from the v4 similarity RPC (list dedupe built in).
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
    v_reason,
    rt.realm
  from cards
  left join public.media_realm_tier rt
    on rt.media_type = cards.c_media_type
   and rt.media_id = cards.c_media_id
  order by cards.ord;
end;
$$;

revoke all on function public.fetch_because_you_rail(integer) from public;
grant execute on function public.fetch_because_you_rail(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) recompute_user_taste_profile v4: 090000 form (pass memory, symmetric
--    caps, genre retention, net-sentiment avoidance guard, evidence math —
--    all unchanged) PLUS profile.realms: the user's top 6 realms by weight,
--    [{realm, family, weight}], where user-realm weight = normalized dot of
--    the STORED user vector with the realm signature, computed exactly like
--    title membership (dot over shared tag_keys / (|user| x |signature|);
--    |user| recomputed from the stored vector like the deck's v_unorm).
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

  -- deck_pass excluded at the source (chosen over an abs(strength) check so
  -- event_count stays honest too): a pass is durable "dealt, undecided"
  -- memory at strength 0.00, not taste evidence; counting it would inflate
  -- evidence mass (0.5 per weak event) and event_count for a non-opinion.
  select
    count(*),
    count(*) filter (where abs(e.event_strength) >= 0.3),
    coalesce(sum(case when abs(e.event_strength) >= 0.3 then 1.0 else 0.5 end), 0)
  into v_event_count, v_strong_count, v_evidence
  from public.taste_signal_events e
  where e.user_id = p_user_id
    and e.event_type <> 'deck_pass';

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
      -- deck_pass excluded at the source CTE: strength 0.00 is harmless to
      -- the sums, but the row would still feed per-title cap bookkeeping
      -- (title_abs, franchise nodes) for zero contribution.
      and e.event_type <> 'deck_pass'
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
  -- Per-title cap (SYMMETRIC, hotfix P3): a title's ABSOLUTE mass may not
  -- exceed 8% of total profile positive mass, and the scale factor applies to
  -- ALL of the title's contributions, positive and negative alike. v2 capped
  -- positive mass only: skipped titles (all-negative) entered unscaled while
  -- loved titles were crushed toward 8%, so small profiles came out
  -- negative-dominated (52/60 negative keys in production).
  title_abs as (
    select media_type, media_id, sum(abs(weight)) as abs_mass
    from contrib
    group by media_type, media_id
  ),
  total_pos as (
    select coalesce(sum(greatest(weight, 0)), 0) as v from contrib
  ),
  title_scale as (
    select
      ta.media_type,
      ta.media_id,
      case
        when ta.abs_mass > 0 and (select v from total_pos) > 0
          then least(1.0, 0.08 * (select v from total_pos) / ta.abs_mass)
        else 1.0
      end as scale
    from title_abs ta
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
  -- Franchise cap (SYMMETRIC): one family's absolute mass <= 15% of profile
  -- positive mass; the scale factor applies to both signs together.
  family_abs as (
    select family,
           sum(abs(weight)) as abs_mass,
           sum(greatest(weight, 0)) as pos_mass
    from capped_labeled
    group by family
  ),
  family_total as (
    select coalesce(sum(pos_mass), 0) as v from family_abs
  ),
  family_scale as (
    select
      fa.family,
      case
        when fa.abs_mass > 0 and (select v from family_total) > 0
          then least(1.0, 0.15 * (select v from family_total) / fa.abs_mass)
        else 1.0
      end as scale
    from family_abs fa
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
      sum(weight) filter (where weight < 0) as neg_weight,
      sum(weight) filter (where weight > 0) as pos_weight
    from avoid_contrib
    group by tag_key
  ),
  -- fix2 net-sentiment guard: the event/cumulative floors alone could exile a
  -- register the user mostly LOVES when two skips happen to carry it (live:
  -- genre:drama avoided despite 3 loves + 3 knowns). Avoidance now also
  -- requires the tag's net sentiment to be strictly negative.
  avoided as (
    select tag_key
    from avoid_agg
    where (neg_events >= 2 or coalesce(neg_weight, 0) <= -0.8)
      and (coalesce(pos_weight, 0) + coalesce(neg_weight, 0)) < 0
  ),
  vec_json as (
    select coalesce(jsonb_object_agg(tag_key, w), '{}'::jsonb) as j
    from (
      -- fix2: top 60 TAG keys by abs + ALL 'genre:' keys with abs(w) > 0.001.
      -- Genres are the bounded backbone register (~36 keys); truncating them
      -- by rank loses the persona's most load-bearing signal (verified live:
      -- genre:drama/genre:fantasy cut at ranks 91/104 of 126).
      select tag_key, round(weight::numeric, 4) as w
      from (
        select
          n2.tag_key,
          n2.weight,
          row_number() over (
            partition by (n2.tag_key not like 'genre:%')
            order by abs(n2.weight) desc, n2.tag_key asc
          ) as rn
        from normalized n2
      ) s
      where round(s.weight::numeric, 4) <> 0
        and (
          (s.tag_key like 'genre:%' and abs(s.weight) > 0.001)
          or (s.tag_key not like 'genre:%' and s.rn <= 60)
        )
    ) t
  ),
  avoided_json as (
    select coalesce(jsonb_agg(tag_key order by tag_key), '[]'::jsonb) as j
    from avoided
  ),
  -- Realm Graph v1: the user's realm mixture, projected through the same
  -- signatures exactly like title membership (dot over shared tag_keys /
  -- (|user| x |signature|)), over the STORED vector (top-60 tags + genres).
  user_vec as (
    select kv.key as tag_key, kv.value::double precision as w
    from jsonb_each_text((select j from vec_json)) kv
  ),
  user_norm as (
    select nullif(sqrt(sum(uv.w * uv.w)), 0) as n from user_vec uv
  ),
  sig_norm as (
    select rs.realm, nullif(sqrt(sum(rs.weight::double precision * rs.weight)), 0) as n
    from public.realm_signatures rs
    group by rs.realm
  ),
  realm_scored as (
    select
      rs.realm,
      min(rs.family) as family,
      sum(uv.w * rs.weight::double precision)
        / ((select n from user_norm) * max(sn.n)) as weight
    from user_vec uv
    join public.realm_signatures rs on rs.tag_key = uv.tag_key
    join sig_norm sn on sn.realm = rs.realm
    where (select n from user_norm) is not null
    group by rs.realm
  ),
  realms_json as (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.weight desc, x.realm asc),
      '[]'::jsonb
    ) as j
    from (
      select r2.realm, r2.family, round(r2.weight::numeric, 4) as weight
      from realm_scored r2
      where r2.weight > 0
      order by r2.weight desc, r2.realm asc
      limit 6
    ) x
  )
  select jsonb_build_object(
    'vector', (select j from vec_json),
    'avoided_tags', (select j from avoided_json),
    'realms', (select j from realms_json),
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
revoke execute on function public.recompute_user_taste_profile(uuid) from public, anon, authenticated;
grant execute on function public.recompute_user_taste_profile(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 8) fetch_taste_deck_batch v4: 090000 form (all meta columns, pass memory,
--    mirrored-first pool, UCB explore, MMR, caps, starvation fills) with ONE
--    addition — the Realm Graph family axis on explore scoring: a candidate
--    whose top-realm family is NOT among the families the user signaled in
--    the last 30 days gets ucb x 1.5 (gentle push into untouched families).
--    Signaled families = families (realm_meta.family of the top-realm row)
--    of titles with any non-deck_pass taste event in the last 30 days;
--    candidates with no realm row are not boosted. Everything else is
--    byte-identical to 20260731090000.
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
  delete from taste_deck_cand where true; -- P0: pg_safeupdate blocks bare DELETE

  -- Realm Graph v1: families the user signaled in the last 30 days (explore
  -- family axis; see the boost application below the UCB computation).
  create temporary table if not exists taste_deck_signaled_families (
    family text primary key
  ) on commit drop;
  delete from taste_deck_signaled_families where true; -- pg_safeupdate

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
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
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
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    )
  order by (m.cover_image_large like '%/storage/v1/%') desc, coalesce(m.popularity, 0) desc, m.id desc
  limit v_pool_lim;

  update taste_deck_cand c
  set cluster = public._taste_genre_cluster(c.genres)
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

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

  -- Realm Graph v1 (family axis): collect the families signaled in the last
  -- 30 days, then lift explore scoring x1.5 for candidates whose top-realm
  -- family is untouched. Runs AFTER the base UCB update so slot_raw records
  -- the boosted value; candidates with no realm row keep their base UCB.
  insert into taste_deck_signaled_families (family)
  select distinct rm.family
  from public.taste_signal_events e
  join public.media_realm_tier t
    on t.media_type = e.media_type
   and t.media_id = e.media_id
  join public.realm_meta rm on rm.realm = t.realm
  where e.user_id = v_uid
    and e.event_type <> 'deck_pass'
    and e.created_at > now() - interval '30 days'
  on conflict (family) do nothing;

  update taste_deck_cand c
  set ucb = c.ucb * 1.5
  where exists (
    select 1
    from public.media_realm_tier t
    join public.realm_meta rm on rm.realm = t.realm
    where t.media_type = c.media_type
      and t.media_id = c.media_id
      and not exists (
        select 1
        from taste_deck_signaled_families sf
        where sf.family = rm.family
      )
  );

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
  )
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

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
-- 9) pg_cron: nightly concurrent refreshes, one job per matview (pg_cron
--    commands are single statements). Chained AFTER taste-tag-vectors-refresh
--    (03:50 UTC, 20260731060000): membership -> affinity -> tier, staggered
--    10 minutes in dependency order.
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid)
from cron.job
where jobname in ('realm-membership-refresh', 'realm-affinity-refresh', 'realm-tier-refresh');

select cron.schedule(
  'realm-membership-refresh',
  '30 4 * * *',
  $cmd$refresh materialized view concurrently public.media_realm_membership;$cmd$
);

select cron.schedule(
  'realm-affinity-refresh',
  '40 4 * * *',
  $cmd$refresh materialized view concurrently public.realm_affinity;$cmd$
);

select cron.schedule(
  'realm-tier-refresh',
  '50 4 * * *',
  $cmd$refresh materialized view concurrently public.media_realm_tier;$cmd$
);
