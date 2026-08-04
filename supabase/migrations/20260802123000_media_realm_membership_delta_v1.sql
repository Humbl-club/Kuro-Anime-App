-- Realm Graph Stage 2 — LLM membership delta overlay (±0.2).
-- Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §3 / §6
--
-- Rules membership stays in matview media_realm_membership (inspectable).
-- LLM pass may nudge each (title, realm) by at most ±0.2 with a logged reason.
-- Consumers that need adjusted weights read media_realm_membership_effective.
-- Similarity gates (recommend_ids_similar_to_seeds) switch to the effective view.
--
-- Objects:
--   1) media_realm_membership_delta     — logged overlays (service_role write)
--   2) media_realm_membership_effective — rules ∪ deltas, weight clamped [0,1]
--   3) recompute_media_realm_llm_deltas — rebuild deltas from media_realm_llm
--   4) recommend_ids_similar_to_seeds   — seed/candidate realm gates use effective

begin;

-- ---------------------------------------------------------------------------
-- 1) Delta table
-- ---------------------------------------------------------------------------

create table if not exists public.media_realm_membership_delta (
  media_type text        not null check (media_type in ('ANIME', 'MANGA')),
  media_id   integer     not null,
  realm      text        not null references public.realm_meta(realm),
  delta      real        not null check (delta >= -0.2 and delta <= 0.2),
  reason     text        not null check (char_length(reason) between 1 and 240),
  model      text        not null,
  created_at timestamptz not null default now(),
  primary key (media_type, media_id, realm)
);

comment on table public.media_realm_membership_delta is
  'Realm Graph Stage 2: LLM membership overlays. delta ∈ [-0.2, 0.2] applied on top of rules media_realm_membership; reasons logged for inspectability. Written by recompute_media_realm_llm_deltas (service_role).';

alter table public.media_realm_membership_delta enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'media_realm_membership_delta'
      and policyname = 'media_realm_membership_delta_select_all'
  ) then
    create policy media_realm_membership_delta_select_all
      on public.media_realm_membership_delta
      for select using (true);
  end if;
end $$;

grant select on public.media_realm_membership_delta to anon, authenticated, service_role;
-- No INSERT/UPDATE/DELETE policies: RLS default-deny for client roles.
-- Writes only via SECURITY DEFINER recompute_media_realm_llm_deltas.

create index if not exists media_realm_membership_delta_media_idx
  on public.media_realm_membership_delta (media_type, media_id);

-- ---------------------------------------------------------------------------
-- 2) Effective membership view
--    - Rules rows with applied delta (clamped)
--    - Delta-only rows (LLM introduced a realm absent from rules top-N)
--    family comes from realm_meta when the rules row is absent.
-- ---------------------------------------------------------------------------

create or replace view public.media_realm_membership_effective
with (security_invoker = true)
as
with base as (
  select
    coalesce(m.media_type, d.media_type) as media_type,
    coalesce(m.media_id, d.media_id) as media_id,
    coalesce(m.realm, d.realm) as realm,
    coalesce(m.family, rm.family) as family,
    coalesce(m.weight, 0::real) as rules_weight,
    coalesce(d.delta, 0::real) as delta
  from public.media_realm_membership m
  full outer join public.media_realm_membership_delta d
    on d.media_type = m.media_type
   and d.media_id = m.media_id
   and d.realm = m.realm
  left join public.realm_meta rm
    on rm.realm = coalesce(m.realm, d.realm)
)
select
  media_type,
  media_id,
  realm,
  family,
  least(1.0, greatest(0.0, rules_weight + delta))::real as weight,
  rules_weight,
  delta
from base
where least(1.0, greatest(0.0, rules_weight + delta)) > 0;

comment on view public.media_realm_membership_effective is
  'Rules media_realm_membership + media_realm_membership_delta (±0.2), weight clamped to [0,1]. Similarity gates read this; rules matview stays inspectable.';

grant select on public.media_realm_membership_effective to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Recompute deltas from media_realm_llm
--    For each LLM realm confirmation:
--      rules_w = membership weight or 0
--      raw = llm_weight - rules_w
--      delta = clamp(raw, -0.2, 0.2)
--    Skip |delta| < 0.02 (noise). Skip confidence < 0.5 (QA first).
--    Full replace of source='llm-recompute' rows each run (model tags the pass).
-- ---------------------------------------------------------------------------

create or replace function public.recompute_media_realm_llm_deltas(
  p_min_confidence real default 0.5,
  p_model text default 'llm-delta-recompute-2026-08'
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  _n int;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'recompute_media_realm_llm_deltas requires service_role'
      using detail = 'FORBIDDEN';
  end if;

  if p_min_confidence is null or p_min_confidence < 0 or p_min_confidence > 1 then
    raise exception 'p_min_confidence must be in [0,1]' using detail = 'INVALID_ARG';
  end if;
  if p_model is null or length(trim(p_model)) = 0 then
    raise exception 'p_model required' using detail = 'INVALID_ARG';
  end if;

  -- Drop previous auto-recompute overlays (manual editorial deltas keep other models).
  delete from public.media_realm_membership_delta
  where model like 'llm-delta-recompute%';

  with llm_realms as (
    select
      l.media_type,
      l.media_id,
      r.realm,
      least(1.0, greatest(0.0, (r.weight)::real)) as llm_weight,
      l.confidence,
      l.model as llm_model
    from public.media_realm_llm l
    cross join lateral jsonb_to_recordset(l.realms) as r(realm text, weight double precision)
    where l.confidence >= p_min_confidence
      and r.realm is not null
      and exists (select 1 from public.realm_meta rm where rm.realm = r.realm)
  ),
  computed as (
    select
      lr.media_type,
      lr.media_id,
      lr.realm,
      greatest(-0.2, least(0.2, lr.llm_weight - coalesce(m.weight, 0::real)))::real as delta,
      (
        'llm confirm ' || lr.realm
        || ' w=' || round(lr.llm_weight::numeric, 2)::text
        || ' rules=' || round(coalesce(m.weight, 0)::numeric, 2)::text
        || ' conf=' || round(lr.confidence::numeric, 2)::text
        || ' via ' || left(lr.llm_model, 40)
      )::text as reason,
      p_model as model
    from llm_realms lr
    left join public.media_realm_membership m
      on m.media_type = lr.media_type
     and m.media_id = lr.media_id
     and m.realm = lr.realm
  )
  insert into public.media_realm_membership_delta (
    media_type, media_id, realm, delta, reason, model
  )
  select media_type, media_id, realm, delta, left(reason, 240), model
  from computed
  where abs(delta) >= 0.02
  on conflict (media_type, media_id, realm) do update
    set delta = excluded.delta,
        reason = excluded.reason,
        model = excluded.model,
        created_at = now();

  get diagnostics _n = row_count;
  return _n;
end;
$$;

revoke all on function public.recompute_media_realm_llm_deltas(real, text) from public;
grant execute on function public.recompute_media_realm_llm_deltas(real, text) to service_role;

comment on function public.recompute_media_realm_llm_deltas(real, text) is
  'Rebuild media_realm_membership_delta from media_realm_llm realm confirmations (clamp ±0.2). service_role only.';

-- ---------------------------------------------------------------------------
-- 4) Similarity: use effective membership for seed + candidate realm gates
--    (body identical to 20260731200000 except media_realm_membership → effective)
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
  seed_realms as (
    -- S: realms where any seed holds membership at weight >= T (effective).
    select distinct m.realm
    from public.media_realm_membership_effective m
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
          from public.media_realm_membership_effective cm
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
          from public.media_realm_membership_effective cm
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

commit;
