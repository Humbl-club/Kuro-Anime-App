-- Realm repair Phase 1, Fixes 1+2 (spec: 2026-08-04-realm-repair-and-critique-plan.md §3.1/§3.2).
--
-- FIX 1 — penalty operator restored to the February convention.
--   History: 20260203190000/201000 seeded editorial_penalty_tags with NEGATIVE values,
--   applied as `+ coalesce(penalty, 0)` (negative value demotes). The July realm
--   rewrite flipped the operator to `- penalty`, which turned every negative penalty
--   into a BOOST (isekai junk rose +up to 28). 20260731200000 "fixed" that with
--   `- greatest(0, coalesce(penalty, 0))` — but over an all-negative table
--   greatest(0, ·) is always 0, so the penalty term has been INERT ever since.
--   This migration restores `+ coalesce(penalty, 0)`: values stay negative in the
--   table (do NOT flip stored signs), the operator makes them demote again.
--
-- FIX 2 — realm gates become costs.
--   The 0.35/0.25 membership entry cliffs, the canon-seed top-realm-in-S
--   requirement, and the affinity >= 0.9 side door were brittle hard tests tuned
--   seed by seed (whack-a-mole, see 20260802140000). They are replaced by:
--     HARD exclusion (only two):
--       (a) tier distance > 1 between seed and candidate
--           (missing candidate tier counts as 'solid' — never NULL-dropped;
--            M2/Fix 3 backfills tiers properly);
--       (b) candidate shares NO family with the seed realm set AND its top realm
--           has max affinity < 0.6 to that set.
--     COST ladder (multiplier on the cosine score):
--       candidate top realm in S            x1.00
--       adjacent realm (affinity >= 0.6)    x0.85
--       same family only                    x0.65
--     WEIGHT term (the converted cliffs): shared-realm membership strength
--       (max over shared realms of least(seed weight, candidate weight)) scales
--       contribution smoothly — full at the old 0.35 anchor, floor 0.5 at zero.
--   The two Spirited Away seed-specific affinity vetoes from 20260802140000
--   (battle-shounen <-> supernatural-yokai, isekai-reincarnation <-> auteur-cinema)
--   were realm_affinity_overrides rows; with distance now a cost instead of a
--   gate they are removed below (targeted DELETE, pg_safeupdate-compliant).
--
-- Function shape unchanged: same name, signature (text, integer[], integer, boolean),
-- return columns (media_id, overlap_count, score) — iOS depends on this shape.

begin;

-- ---------------------------------------------------------------------------
-- 1) Remove the two Spirited Away seed-specific affinity vetoes (4 directed rows).
--    Tuned on one seed; superseded by the cost ladder.
-- ---------------------------------------------------------------------------

delete from public.realm_affinity_overrides
where (realm_a, realm_b) in (
  ('battle-shounen', 'supernatural-yokai'),
  ('supernatural-yokai', 'battle-shounen'),
  ('isekai-reincarnation', 'auteur-cinema'),
  ('auteur-cinema', 'isekai-reincarnation')
);

-- ---------------------------------------------------------------------------
-- 2) recommend_ids_similar_to_seeds — penalty operator + gates-to-costs rewrite.
-- ---------------------------------------------------------------------------

create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language sql
stable
security definer
set search_path = public, extensions
as $function$
  with recursive req as (
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
  seed_realm_w as (
    -- S: the seed realm set WITH weights. No entry cliff (the old >= 0.35 /
    -- >= 0.25 tests are weight terms now — see cand_realm_cost.mem_term).
    select m.realm, min(m.family) as family, max(m.weight)::double precision as w
    from public.media_realm_membership_effective m
    where m.media_type = p_media_type
      and p_seed_ids is not null
      and m.media_id = any(p_seed_ids)
    group by m.realm
  ),
  seed_families as (
    select distinct s.family from seed_realm_w s where s.family is not null
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
  cand_top_realm as (
    -- Candidate top realm = its highest-weight effective membership row
    -- (deterministic; same ordering as the media_realm_tier build).
    select s.media_id, s.realm, s.family
    from (
      select
        m.media_id,
        m.realm,
        m.family,
        row_number() over (
          partition by m.media_id
          order by m.weight desc, m.realm asc
        ) as rn
      from public.media_realm_membership_effective m
      join cand_cos cc on cc.media_id = m.media_id
      where m.media_type = p_media_type
    ) s
    where s.rn = 1
  ),
  cand_shared as (
    -- Per-candidate shared-realm strength: max over shared realms of
    -- least(seed weight, candidate weight). Set-based on purpose — the
    -- effective view's FULL OUTER JOIN defeats index probes, so correlated
    -- per-candidate subqueries would rescan it per row.
    select
      cm.media_id,
      max(least(s.w, cm.weight::double precision)) as shared_w
    from public.media_realm_membership_effective cm
    join seed_realm_w s on s.realm = cm.realm
    join cand_cos cc on cc.media_id = cm.media_id
    where cm.media_type = p_media_type
    group by cm.media_id
  ),
  cand_family as (
    -- Candidates holding ANY realm whose family matches a seed family.
    select distinct f.media_id
    from public.media_realm_membership_effective f
    join seed_families sf on sf.family = f.family
    join cand_cos cc on cc.media_id = f.media_id
    where f.media_type = p_media_type
  ),
  top_adj as (
    -- Per realm: max affinity to the seed realm set (40x40 space — tiny).
    select e.realm_a as realm, max(e.affinity)::double precision as aff
    from public.realm_affinity_effective e
    join seed_realm_w s on s.realm = e.realm_b
    group by e.realm_a
  ),
  cand_realm_cost as (
    -- Gates -> costs (spec §3.2). realm_mult NULL = the only realm hard
    -- exclusion left: no shared family AND top-realm affinity < 0.6.
    -- Ladder: top realm in S x1.0 · adjacent (affinity >= 0.6) x0.85 ·
    -- same family only x0.65. Seeds with no realm data: neutral, no exclusion.
    select
      cc.media_id,
      case
        when not exists (select 1 from seed_realm_w) then 1.0
        when ctr.media_id is null then null
        when s_top.realm is not null then 1.0
        when coalesce(adj.aff, 0) >= 0.6 then 0.85
        when cf.media_id is not null then 0.65
        else null
      end::double precision as realm_mult,
      case
        when not exists (select 1 from seed_realm_w) then 1.0
        else
          -- The converted membership cliffs (old >= 0.35 / >= 0.25 entry
          -- tests): full contribution at the old 0.35 anchor, smooth ramp
          -- below, floor 0.5 (adjacency/family entrants with no shared realm).
          0.5 + 0.5 * least(1.0, coalesce(cs.shared_w, 0) / 0.35)
      end::double precision as mem_term
    from cand_cos cc
    left join cand_top_realm ctr on ctr.media_id = cc.media_id
    left join seed_realm_w s_top on s_top.realm = ctr.realm
    left join top_adj adj on adj.realm = ctr.realm
    left join cand_family cf on cf.media_id = cc.media_id
    left join cand_shared cs on cs.media_id = cc.media_id
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
  ),
  ranked as (
    select
      p_media_type as mt,
      a.id as media_id,
      cc.overlap_count as overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(ac.shared_creator, false)::int
            + 0.15 * coalesce(ac.shared_studio, false)::int
            + 0.5 * coalesce(ac.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
          * crc.realm_mult
          * crc.mem_term
        + case when (select allow_gimmicks from req) then 0.0
               else coalesce(ap.penalty, 0)::double precision end
      )::real as score,
      coalesce(a.popularity, 0) as popularity
    from cand_cos cc
    join public.anime a on a.id = cc.media_id
    join cand_realm_cost crc on crc.media_id = cc.media_id
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
      -- Realm hard exclusion (b): no shared family AND affinity < 0.6.
      -- Everything softer is a cost inside cand_realm_cost.
      and crc.realm_mult is not null
      -- Realm hard exclusion (a): tier distance > 1. Missing candidate tier
      -- counts as 'solid' (rank 2) so backlog titles are demotable, not dropped.
      and (
        (select r from seed_tier_rank) is null
        or abs(
             coalesce((
               select case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
               from public.media_realm_tier ct
               where ct.media_type = p_media_type
                 and ct.media_id = a.id
             ), 2)
             - (select r from seed_tier_rank)
           ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000): within-realm tier
        -- measures *good for its kind*; cross-realm gates to legend-tier
        -- require absolute merit. Non-canon seeds: no floor (tier
        -- compatibility alone). canon_seed.media_id = AniList id (150000).
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(a.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = a.anilist_id
            and cs.blessed = true
        )
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
      p_media_type,
      m.id,
      cc.overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(mc.shared_creator, false)::int
            + 0.15 * coalesce(mc.shared_studio, false)::int
            + 0.5 * coalesce(mc.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
          * crc.realm_mult
          * crc.mem_term
        + case when (select allow_gimmicks from req) then 0.0
               else coalesce(mp.penalty, 0)::double precision end
      )::real,
      coalesce(m.popularity, 0)
    from cand_cos cc
    join public.manga m on m.id = cc.media_id
    join cand_realm_cost crc on crc.media_id = cc.media_id
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
      -- Realm hard exclusion (b): no shared family AND affinity < 0.6.
      and crc.realm_mult is not null
      -- Realm hard exclusion (a): tier distance > 1, missing tier = 'solid'.
      and (
        (select r from seed_tier_rank) is null
        or abs(
             coalesce((
               select case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
               from public.media_realm_tier ct
               where ct.media_type = p_media_type
                 and ct.media_id = m.id
             ), 2)
             - (select r from seed_tier_rank)
           ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000), manga branch.
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(m.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = m.anilist_id
            and cs.blessed = true
        )
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  -- Franchise clusters over gate-passing candidates: connected components of
  -- media_relations (UNION keeps the recursion cycle-safe), labeled by the
  -- lexicographically smallest member key. Titles with no relations are
  -- singleton clusters via the coalesce in the final select.
  fr_nodes as (
    select ranked.mt as media_type, ranked.media_id from ranked
  ),
  fr_edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join fr_nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join fr_nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  fr_adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from fr_edges
    union
    select b_t, b_i, a_t, a_i from fr_edges
  ),
  fr_reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from fr_nodes n
    union
    select r.s_t, r.s_i, a.nt, a.ni
    from fr_reach r
    join fr_adj a on a.t = r.t and a.i = r.i
  ),
  fr_labels as (
    select r.t as media_type, r.i as media_id,
           min(r.s_t || ':' || r.s_i::text) as label
    from fr_reach r
    group by r.t, r.i
  )
  -- <= 1 candidate per franchise cluster: DISTINCT ON keeps the
  -- highest-scoring entry of each cluster (ties: popularity, then media_id).
  select d.media_id, d.overlap_count, d.score
  from (
    select distinct on (coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text))
      ranked.media_id,
      ranked.overlap_count,
      ranked.score,
      ranked.popularity
    from ranked
    left join fr_labels fr
      on fr.media_type = ranked.mt
     and fr.media_id = ranked.media_id
    order by coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text),
             ranked.score desc,
             ranked.popularity desc,
             ranked.media_id desc
  ) d
  order by d.score desc, d.popularity desc, d.media_id desc
  limit (select lim from req);
$function$;

revoke all on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) from public;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon, authenticated;

commit;
