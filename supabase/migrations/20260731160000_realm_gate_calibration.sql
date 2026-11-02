-- Realm Gate Calibration (production verification, 2026-08-01).
--
-- INCIDENT: Spirited Away (canon tier; realms supernatural-yokai/auteur-cinema/
-- grand-adventure) admitted "Reborn as a Vending Machine" (acclaimed within
-- isekai-reincarnation at average_score 63 — the within-realm percentile
-- inflates trash-tier isekai) in its similar list. Two independent holes:
--   (a) isekai<->auteur-cinema affinity measured 0.72 vs the 0.25 gate
--       constant. Live affinity distribution (1560 pairs, top-1000 sample):
--       p50 0.142 / p90 0.974 / p95 1.278 / max 1.93 — the 0.25 constant
--       passed ~half of all pairs. A highway.
--   (b) "canon admits canon+acclaimed" tier compatibility had no absolute
--       merit floor, so within-realm inflation crossed legend gates.
--
-- FIX (this file):
--   1) Affinity gate constant 0.25 -> 0.9 in recommend_ids_similar_to_seeds
--      (recreated from 20260731150000; no other logic changes). 0.9 ~= top
--      ~10% of measured live pairs; specific adjacencies belong in
--      realm_affinity_overrides, not a loose global constant.
--   2) Editorial overrides seeded below (both directions, ON CONFLICT DO
--      NOTHING) at 0.95. Four clearly-correct adjacencies, checked against
--      the verification fixture (fixture-measured value in each reason):
--        dark-fantasy<->horror-dread            0.47   (below gate -> pin)
--        psychological-thriller<->mystery-detective 0.13 -> 1.35 across
--          fixture iterations — UNSTABLE around the gate; pinned so the
--          adjacency cannot flap below 0.9 on refresh noise (determinism)
--        romance-slow-burn<->romantic-comedy    0.89   (just below -> pin)
--        grand-adventure<->historical-epic      0.00   (signature gap -> pin)
--      quiet-melancholy<->slice-of-life-iyashikei measured 0.93-0.94 >= 0.9
--      in the fixture, so no override is seeded for it (the gate keeps it
--      open); if production measures it under 0.9 it is a one-row follow-up.
--   3) Canon-seed absolute floor: when the seed set's max tier = 'canon',
--      candidates must additionally satisfy
--      (average_score >= 75 OR exists in canon_seed for that media).
--      Within-realm tier measures *good for its kind*; cross-realm gates to
--      legend-tier require absolute merit. Tier compatibility is unchanged
--      for non-canon seeds (no floor).
--
-- Idempotent: drop+create for the function, ON CONFLICT DO NOTHING for seeds.

-- ---------------------------------------------------------------------------
-- 1) recommend_ids_similar_to_seeds v4.1 — 150000 form with:
--      realm-affinity gate 0.25 -> 0.9 (both media branches)
--      + canon-seed absolute merit floor (both media branches)
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
            and e.affinity >= 0.9
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
            and e.affinity >= 0.9
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
      and (
        -- Canon-seed absolute merit floor (20260731160000), manga branch.
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(m.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = m.anilist_id
        )
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
-- 2) Editorial affinity overrides (both directions) at 0.95 for the four
--    clearly-correct adjacencies whose fixture measurements fall under the
--    new 0.9 gate. Directed table: both (a,b) and (b,a) inserted.
-- ---------------------------------------------------------------------------
insert into public.realm_affinity_overrides (realm_a, realm_b, affinity, reason) values
  ('dark-fantasy', 'horror-dread', 0.95,
   'Berserk/Claymore readers cross straight into Junji Ito/Higurashi — dread is the shared register (fixture-measured 0.47; pinned editorially after the 0.9 gate raise)'),
  ('horror-dread', 'dark-fantasy', 0.95,
   'Berserk/Claymore readers cross straight into Junji Ito/Higurashi — dread is the shared register (fixture-measured 0.47; pinned editorially after the 0.9 gate raise)'),
  ('psychological-thriller', 'mystery-detective', 0.95,
   'The crime-procedure continuum (Monster/Psycho-Pass <-> Erased/Hyouka) — one neighborhood split by a genre boundary (fixture measurement unstable 0.13 -> 1.35; pinned so the adjacency cannot flap below the 0.9 gate on refresh noise)'),
  ('mystery-detective', 'psychological-thriller', 0.95,
   'The crime-procedure continuum (Monster/Psycho-Pass <-> Erased/Hyouka) — one neighborhood split by a genre boundary (fixture measurement unstable 0.13 -> 1.35; pinned so the adjacency cannot flap below the 0.9 gate on refresh noise)'),
  ('romance-slow-burn', 'romantic-comedy', 0.95,
   'Same readers, different register (Your Lie in April <-> Kaguya-sama) — editorially inseparable (fixture-measured 0.89, just under the gate)'),
  ('romantic-comedy', 'romance-slow-burn', 0.95,
   'Same readers, different register (Your Lie in April <-> Kaguya-sama) — editorially inseparable (fixture-measured 0.89, just under the gate)'),
  ('grand-adventure', 'historical-epic', 0.95,
   'Vinland Saga/Kingdom/Golden Kamuy straddle both realms by definition (fixture-measured 0.0000 — pure signature-vocabulary gap, not a taste boundary)'),
  ('historical-epic', 'grand-adventure', 0.95,
   'Vinland Saga/Kingdom/Golden Kamuy straddle both realms by definition (fixture-measured 0.0000 — pure signature-vocabulary gap, not a taste boundary)')
on conflict (realm_a, realm_b) do nothing;
