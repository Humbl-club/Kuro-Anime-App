-- 2026-07-31: Clamp editorial_penalty_tags to >= 0 in recommend_ids_similar_to_seeds.
-- Root cause of the "integer band": 20260203201000_editorial_story_boosts.sql seeded
-- NEGATIVE penalties (e.g. Reverse Isekai -8) as a hidden popularity-boost channel.
-- score = similarity x multipliers - penalty, so negative penalties ADDED up to +28,
-- burying Ghibli-class works under seasonal franchises. Penalties now only subtract.
-- Also drops all temporary debug functions from tonight's diagnosis.
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
        - case when (select allow_gimmicks from req) then 0.0
               else greatest(0, coalesce(ap.penalty, 0))::double precision end
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
        - case when (select allow_gimmicks from req) then 0.0
               else greatest(0, coalesce(mp.penalty, 0))::double precision end
      )::real,
      coalesce(m.popularity, 0)
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

drop function if exists public.debug_functiondef();
drop function if exists public.debug_sim_pair(integer, integer);
drop function if exists public.debug_ranked_pair(integer, integer);
drop function if exists public.recommend_ids_similar_to_seeds_v42(text, integer[], integer, boolean);
