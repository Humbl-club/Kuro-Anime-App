-- Edges-first serving fork (spec: 2026-08-04-realm-repair-and-critique-plan.md
-- §4 baseline; owner decision 2026-08-05).
--
-- WHY: the §4 gold baseline (100 seeds, 1,839 pooled judgments) measured raw
--   AniList recommendation edges at P@10 0.847 vs the gated tag-projection
--   cosine at 0.512 — edges are the strong retrieval signal (86.8% of judged
--   edge rows relevant), cosine is the weak one. The owner-decided fork:
--   serve same-type edges FIRST (realm-checked), cosine as BACKFILL. The fork
--   lives ENTIRELY in rebuild_media_similar_titles(): RPC read path, store PK,
--   multi-seed sum-blend, per-user exclusion, franchise DISTINCT ON, live
--   fallback, and p_allow_gimmicks routing are ALL byte-unchanged from
--   20260804140000.
--
-- PER-SEED BUILD (replaces only the output-assembly stage of the 20260804140000
-- builder; every scoring/gating CTE before it is byte-identical):
--
--   Stage A — edges. media_rec_edges rows with (from = seed, same media_type),
--   KEEP checks mirroring the cosine scorer's hard gates:
--     * candidate in the existing pool snapshot (_pool_a/_pool_m: exists in
--       catalog, has cover, non-adult, no Hentai/Ecchi genre). NOTE: the
--       current pool has NO format exclusions (MUSIC/SPECIAL/TV_SHORT hiding is
--       a Discover/Search rule, not a similarity-pool rule) — verified against
--       the live 20260804140000 definition, so there is nothing to mirror.
--     * NOT in the seed's own franchise component (media_franchise_components;
--       singletons label as themselves via coalesce — same convention as
--       everywhere else). Stage A is also internally franchise-deduped
--       (one candidate per component, highest rating wins).
--     * tier distance <= 1 vs the seed (missing candidate tier = 'solid',
--       rank 2 — identical to the cosine gate).
--     * canon-seed absolute merit floor stays a HARD check (seed tier canon ->
--       candidate average_score >= 75 or canon_seed-blessed).
--     * editorial penalties are a DEMOTION inside the edge block, not a gate
--       (see formula) — penalized edges sink, they do not vanish.
--
--   Stage B — cosine backfill. The EXISTING scorer output (_scored_a/_scored_m,
--   unchanged logic incl. penalties as additive terms) fills the remaining
--   slots to depth 30, excluding every franchise component already taken by
--   Stage A (component-label anti-join; covers exact-id repeats too, since a
--   title's label equals its component's label).
--
-- EDGE SCORE FORMULA (blend compatibility — the RPC sums scores across seeds):
--     edge_score = greatest(2.6,
--                    3.0 + coalesce((rating - min_r)::float8
--                                     / nullif(max_r - min_r, 0), 0.5)
--                        + penalty)
--   where min_r/max_r are computed PER SEED over the kept, franchise-deduped
--   edge set (so the base lands in [3.0, 4.0]; a seed whose kept edges all
--   share one rating — incl. single-edge seeds — gets 3.5 via the coalesce),
--   and penalty = the candidate's summed editorial_penalty_tags (<= 0; the
--   smallest tag is -3, so ANY penalized edge clamps to the 2.6 floor and
--   ranks below every clean edge — ties there break rating desc). Cosine rows
--   keep their existing scale, which is capped at 2.5 by construction
--   (sim <= 1 x craft/rail cap 2.5 x realm_mult <= 1 x mem_term <= 1 +
--   penalty <= 0), so every edge row outranks every cosine row within a seed
--   and per-contribution in blends. (Sum-blend nuance, documented not changed:
--   a candidate reached by cosine from MORE seeds can still out-sum a
--   candidate reached by an edge from fewer seeds — that is the unchanged
--   multi-seed blend semantics, not a regression of edge priority.)
--
--   Rank layout per seed: edges rn 1..n_e (score desc, rating desc,
--   popularity desc, cand_id desc), cosine n_e+1..30 (score desc, popularity
--   desc, cand_id desc — the pre-fork ordering). n_e <= 25 (max edges/seed in
--   the 103k-row table), so edges are never truncated by the rn <= 30 cap.
--   overlap_count on edge rows = the cosine tag-overlap when the pair exists
--   in _pairs_*, else 0 (reporting column only).
--
-- OBSERVABILITY: media_similar_titles gains `src text not null default
--   'cosine'` ('edge' | 'cosine'). Backward-compatible: the RPC selects named
--   columns and nothing selects * from the store (verified repo-wide).
--
-- ROLLOUT: this migration only changes the builder — served rows change as
--   seeds go stale and rebuild. Do NOT re-stale the full catalog by hand; the
--   nightly 'realm-similar-nightly' re-stale (05:10 UTC) propagates the fork
--   catalog-wide within its normal cadence. (Targeted re-stales for eval seeds
--   are fine and are done operationally, not in this migration.)
--
-- REVERT PATH: restore the 20260804140000 builder body (create or replace
--   function rebuild_media_similar_titles from that file's section 2) and
--   re-stale; the src column is inert under the old builder (defaults to
--   'cosine') and can stay.
--
-- Rating-distribution note (measured 2026-08-05): 103,007 same-type edges over
--   7,220 seeds (median 14/seed, max 25; 354 single-edge seeds); ratings are
--   AniList recommendation vote counts, heavily skewed (p50 4, p95 63,
--   max 6003) — hence per-seed min-max normalization, which preserves
--   within-seed order and bounds cross-seed contributions.
begin;

-- ---------------------------------------------------------------------------
-- 1) src column ('edge' | 'cosine') — idempotent, default keeps existing rows
--    and any old-builder inserts valid.
-- ---------------------------------------------------------------------------

alter table public.media_similar_titles
  add column if not exists src text not null default 'cosine';

comment on column public.media_similar_titles.src is
  'Edges-first fork (20260805120000): which stage produced this row — ''edge'' (media_rec_edges Stage A) or ''cosine'' (tag-projection backfill Stage B).';

-- ---------------------------------------------------------------------------
-- 2) rebuild_media_similar_titles — byte-identical to 20260804140000 except:
--    the _out_a/_out_m stage tables gain src, and the per-seed output assembly
--    becomes Stage A (edges) + Stage B (cosine backfill) per the header.
-- ---------------------------------------------------------------------------

create or replace function public.rebuild_media_similar_titles(p_batch integer default 100)
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _n integer;
  _out_n bigint;
begin
  -- Overlap guard: the 5-min driver can fire while a long batch is still
  -- running (an all-manga batch of 300 is ~300s). Skipping beats stomping
  -- (duplicate batch picks would collide on the PK mid-swap).
  if not pg_try_advisory_xact_lock(hashtext('media_similar_titles_rebuild'), 0) then
    return -1;
  end if;

  -- Local raise for direct service_role/owner invocations; the CRON command
  -- must (and does) raise the session statement_timeout BEFORE calling — a
  -- mid-statement change cannot re-arm the running statement's timer
  -- (20260804120000 mechanics).
  set local statement_timeout = '600s';

  -- -------------------------------------------------------------------------
  -- Seed-universe sync: visible pool = average_score >= 70, non-adult, cover.
  -- -------------------------------------------------------------------------

  delete from public.media_similar_seed_state st
  where (st.seed_media_type = 'ANIME' and not exists (
           select 1 from public.anime a
           where a.id = st.seed_media_id
             and coalesce(a.average_score, 0) >= 70
             and coalesce(a.is_adult, false) = false
             and a.cover_image_large is not null))
     or (st.seed_media_type = 'MANGA' and not exists (
           select 1 from public.manga m
           where m.id = st.seed_media_id
             and coalesce(m.average_score, 0) >= 70
             and coalesce(m.is_adult, false) = false
             and m.cover_image_large is not null));

  delete from public.media_similar_titles t
  where not exists (
    select 1 from public.media_similar_seed_state st
    where st.seed_media_type = t.seed_media_type
      and st.seed_media_id = t.seed_media_id
  );

  insert into public.media_similar_seed_state (seed_media_type, seed_media_id, stale)
  select 'ANIME', a.id, true
  from public.anime a
  where coalesce(a.average_score, 0) >= 70
    and coalesce(a.is_adult, false) = false
    and a.cover_image_large is not null
  union all
  select 'MANGA', m.id, true
  from public.manga m
  where coalesce(m.average_score, 0) >= 70
    and coalesce(m.is_adult, false) = false
    and m.cover_image_large is not null
  on conflict (seed_media_type, seed_media_id) do nothing;

  -- Franchise-component sync (20260804140000): refresh the persistent
  -- media_franchise_components from media_relations (global same-type
  -- connected components, label = min member id). Targeted delete of
  -- stale/relabeled rows + insert-on-conflict — pg_safeupdate-clean. Runs
  -- before the empty-batch early return on purpose: the RPC's blend dedupe
  -- reads this table, so it stays current within one driver cadence as
  -- relations grow even when the similar-titles store is converged
  -- (~1s for 16.6k relation rows).

  drop table if exists pg_temp._frn;
  create temp table _frn on commit drop as
  with recursive edges as (
    select mr.from_media_type as t, mr.from_media_id as i1, mr.to_media_id as i2
    from public.media_relations mr
    where mr.from_media_type = mr.to_media_type
  ),
  adj as (select t, i1 as i, i2 as ni from edges union select t, i2, i1 from edges),
  nodes as (select distinct t, i from adj),
  reach as (
    select n.t, n.i as s, n.i as x from nodes n
    union
    select r.t, r.s, a.ni from reach r join adj a on a.t = r.t and a.i = r.x
  )
  select r.t as media_type, r.x as media_id, min(r.s) as label
  from reach r group by r.t, r.x;

  delete from public.media_franchise_components c
  where not exists (
    select 1 from pg_temp._frn f
    where f.media_type = c.media_type
      and f.media_id = c.media_id
      and f.label = c.component_label
  );

  insert into public.media_franchise_components (media_type, media_id, component_label)
  select f.media_type, f.media_id, f.label
  from pg_temp._frn f
  on conflict (media_type, media_id) do nothing;

  -- -------------------------------------------------------------------------
  -- Batch pick. Empty batch -> cheap no-op (the driver stays scheduled).
  -- -------------------------------------------------------------------------

  drop table if exists pg_temp._smb;
  create temp table _smb on commit drop as
  select st.seed_media_type as mt, st.seed_media_id as sid
  from public.media_similar_seed_state st
  where st.stale
  order by st.seed_media_type, st.seed_media_id
  limit greatest(1, least(coalesce(p_batch, 100), 2000));

  select count(*) into _n from pg_temp._smb;
  if _n = 0 then
    return 0;
  end if;

  -- -------------------------------------------------------------------------
  -- Shared per-invocation snapshots (both media types).
  -- One materialization of the FULL-OUTER-JOIN effective view (~140ms) instead
  -- of the repeated view scans that dominated the live path.
  -- -------------------------------------------------------------------------

  drop table if exists pg_temp._eff;
  create temp table _eff on commit drop as
  select e.media_type, e.media_id, e.realm, e.family, e.weight::double precision as w
  from public.media_realm_membership_effective e;
  create index on pg_temp._eff (media_type, media_id);
  analyze pg_temp._eff;

  drop table if exists pg_temp._aff;
  create temp table _aff on commit drop as
  select f.realm_a, f.realm_b, f.affinity::double precision as aff
  from public.realm_affinity_effective f;

  drop table if exists pg_temp._ctop;
  create temp table _ctop on commit drop as
  select s.media_type, s.media_id, s.realm, s.family from (
    select e.media_type, e.media_id, e.realm, e.family,
           row_number() over (partition by e.media_type, e.media_id order by e.w desc, e.realm asc) as rn
    from pg_temp._eff e) s
  where s.rn = 1;
  create index on pg_temp._ctop (media_type, media_id);

  -- Global same-type franchise components: snapshot of the persistent
  -- media_franchise_components refreshed above (20260804140000 — one source
  -- of truth; formerly recomputed here as a recursive CTE). label = min
  -- member id per component; singletons label via coalesce at use site
  -- (collision-free: a component's min-member id belongs to that component).
  drop table if exists pg_temp._fr;
  create temp table _fr on commit drop as
  select c.media_type, c.media_id, c.component_label as label
  from public.media_franchise_components c;
  create index on pg_temp._fr (media_type, media_id);

  drop table if exists pg_temp._trank;
  create temp table _trank on commit drop as
  select t.media_type, t.media_id,
         case t.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end as r
  from public.media_realm_tier t;
  create index on pg_temp._trank (media_type, media_id);

  -- Output stages (created unconditionally so the final INSERT compiles even
  -- when the batch is single-type). src: 'edge' (Stage A) | 'cosine' (Stage B).
  drop table if exists pg_temp._out_a;
  create temp table _out_a (seed_id integer, cand_id integer, overlap integer, score real, rn bigint, src text) on commit drop;
  drop table if exists pg_temp._out_m;
  create temp table _out_m (seed_id integer, cand_id integer, overlap integer, score real, rn bigint, src text) on commit drop;

  -- =========================================================================
  -- ANIME sub-pipeline (exact 20260804100000 semantics per single seed,
  -- minus the user_lists exclusion).
  -- =========================================================================
  if exists (select 1 from pg_temp._smb b where b.mt = 'ANIME') then

    drop table if exists pg_temp._pool_a;
    create temp table _pool_a on commit drop as
    select a.id as media_id, coalesce(a.genres, '{}'::text[]) as genres,
           coalesce(a.popularity, 0) as popularity, coalesce(a.average_score, 0) as avg_score,
           a.anilist_id
    from public.anime a
    where a.cover_image_large is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])));
    create index on pg_temp._pool_a (media_id);

    drop table if exists pg_temp._pool_genre_a;
    create temp table _pool_genre_a on commit drop as
    select p.media_id, g from pg_temp._pool_a p cross join lateral unnest(p.genres) as g;
    create index on pg_temp._pool_genre_a (media_id, g);
    analyze pg_temp._pool_genre_a;

    drop table if exists pg_temp._pen_a;
    create temp table _pen_a on commit drop as
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id;
    create index on pg_temp._pen_a (media_id);

    drop table if exists pg_temp._bless_a;
    create temp table _bless_a on commit drop as
    select cs.media_id as anilist_id from public.canon_seed cs
    where cs.media_type = 'ANIME' and cs.blessed = true;

    drop table if exists pg_temp._seed_attr_a;
    create temp table _seed_attr_a on commit drop as
    select b.sid as seed_id, t.r as tier_rank, coalesce(a.genres, '{}'::text[]) as genres
    from pg_temp._smb b
    join public.anime a on a.id = b.sid
    left join pg_temp._trank t on t.media_type = 'ANIME' and t.media_id = b.sid
    where b.mt = 'ANIME';

    drop table if exists pg_temp._seed_genre_a;
    create temp table _seed_genre_a on commit drop as
    select s.seed_id, g from pg_temp._seed_attr_a s cross join lateral unnest(s.genres) as g
    group by s.seed_id, g;
    create index on pg_temp._seed_genre_a (seed_id, g);

    drop table if exists pg_temp._seed_need_a;
    create temp table _seed_need_a on commit drop as
    select sg.seed_id, count(*) as n, case when count(*) >= 4 then 2 else 1 end as need
    from pg_temp._seed_genre_a sg group by sg.seed_id;

    drop table if exists pg_temp._seed_realm_a;
    create temp table _seed_realm_a on commit drop as
    select b.sid as seed_id, e.realm, min(e.family) as family, max(e.w) as w
    from pg_temp._smb b
    join pg_temp._eff e on e.media_type = 'ANIME' and e.media_id = b.sid
    where b.mt = 'ANIME'
    group by b.sid, e.realm;
    create index on pg_temp._seed_realm_a (seed_id, realm);

    drop table if exists pg_temp._seed_family_a;
    create temp table _seed_family_a on commit drop as
    select distinct sr.seed_id, sr.family from pg_temp._seed_realm_a sr where sr.family is not null;

    drop table if exists pg_temp._top_adj_a;
    create temp table _top_adj_a on commit drop as
    select sr.seed_id, f.realm_a as realm, max(f.aff) as aff
    from pg_temp._seed_realm_a sr join pg_temp._aff f on f.realm_b = sr.realm
    group by sr.seed_id, f.realm_a;
    create index on pg_temp._top_adj_a (seed_id, realm);

    drop table if exists pg_temp._rail_pair_a;
    create temp table _rail_pair_a on commit drop as
    select distinct sr.seed_id, a3.id as cand_id
    from (
      select b.sid as seed_id, i.rail_id
      from pg_temp._smb b
      join public.anime a2 on a2.id = b.sid
      join public.curated_rail_items i on i.media_type = 'ANIME' and i.anilist_id = a2.anilist_id
      where b.mt = 'ANIME'
    ) sr
    join public.curated_rail_items i2 on i2.rail_id = sr.rail_id and i2.media_type = 'ANIME'
    join public.anime a3 on a3.anilist_id = i2.anilist_id;
    create index on pg_temp._rail_pair_a (seed_id, cand_id);

    drop table if exists pg_temp._dir_pair_a;
    create temp table _dir_pair_a on commit drop as
    select distinct ys.seed_id, xs.anime_id as cand_id
    from (select b.sid as seed_id, s.staff_id from pg_temp._smb b
          join public.anime_staff s on s.anime_id = b.sid and s.role ilike '%director%'
          where b.mt = 'ANIME') ys
    join public.anime_staff xs on xs.staff_id = ys.staff_id and xs.role ilike '%director%';
    create index on pg_temp._dir_pair_a (seed_id, cand_id);

    drop table if exists pg_temp._studio_pair_a;
    create temp table _studio_pair_a on commit drop as
    select distinct ys.seed_id, xs.anime_id as cand_id
    from (select b.sid as seed_id, s.studio_id from pg_temp._smb b
          join public.anime_studios s on s.anime_id = b.sid
          where b.mt = 'ANIME') ys
    join public.anime_studios xs on xs.studio_id = ys.studio_id;
    create index on pg_temp._studio_pair_a (seed_id, cand_id);

    drop table if exists pg_temp._auth_pair_a;
    create temp table _auth_pair_a on commit drop as
    select distinct ys.seed_id, xs.anime_id as cand_id
    from (select b.sid as seed_id, s.staff_id from pg_temp._smb b
          join public.anime_staff s on s.anime_id = b.sid and s.role ilike '%creator%'
          where b.mt = 'ANIME') ys
    join public.anime_staff xs on xs.staff_id = ys.staff_id and xs.role ilike '%creator%';
    create index on pg_temp._auth_pair_a (seed_id, cand_id);

    drop table if exists pg_temp._sv_a;
    create temp table _sv_a on commit drop as
    select v.media_id as seed_id, v.tag_key, v.w::double precision as w
    from public.media_tag_vectors v
    join pg_temp._smb b on b.mt = 'ANIME' and b.sid = v.media_id
    where v.media_type = 'ANIME';
    analyze pg_temp._sv_a;

    -- Live parity: seed norm computed from the vector (single seed: equals its
    -- stored l2_norm); nullif(...,0) there -> similarity NULL -> excluded, so
    -- zero-norm seeds simply produce no rows here.
    drop table if exists pg_temp._snorm_a;
    create temp table _snorm_a on commit drop as
    select sv.seed_id, sqrt(sum(sv.w * sv.w)) as n
    from pg_temp._sv_a sv group by sv.seed_id
    having sqrt(sum(sv.w * sv.w)) > 0;

    drop table if exists pg_temp._pairs_a;
    create temp table _pairs_a on commit drop as
    select sv.seed_id, v.media_id as cand_id,
           count(*)::int as overlap,
           (sum(v.w::double precision * sv.w) / (sn.n * max(v.l2_norm)::double precision)) as sim
    from pg_temp._sv_a sv
    join pg_temp._snorm_a sn on sn.seed_id = sv.seed_id
    join public.media_tag_vectors v
      on v.media_type = 'ANIME' and v.tag_key = sv.tag_key and v.media_id <> sv.seed_id
    group by sv.seed_id, v.media_id, sn.n
    having max(v.l2_norm) > 0;
    create index on pg_temp._pairs_a (seed_id, cand_id);
    analyze pg_temp._pairs_a;

    drop table if exists pg_temp._shared_a;
    create temp table _shared_a on commit drop as
    select p.seed_id, p.cand_id, max(least(sr.w, e.w)) as shared_w
    from pg_temp._pairs_a p
    join pg_temp._eff e on e.media_type = 'ANIME' and e.media_id = p.cand_id
    join pg_temp._seed_realm_a sr on sr.seed_id = p.seed_id and sr.realm = e.realm
    group by p.seed_id, p.cand_id;
    create index on pg_temp._shared_a (seed_id, cand_id);

    drop table if exists pg_temp._famflag_a;
    create temp table _famflag_a on commit drop as
    select distinct p.seed_id, p.cand_id
    from pg_temp._pairs_a p
    join pg_temp._eff e on e.media_type = 'ANIME' and e.media_id = p.cand_id
    join pg_temp._seed_family_a sf on sf.seed_id = p.seed_id and sf.family = e.family;
    create index on pg_temp._famflag_a (seed_id, cand_id);

    drop table if exists pg_temp._gcnt_a;
    create temp table _gcnt_a on commit drop as
    select p.seed_id, p.cand_id, count(*) as c
    from pg_temp._pairs_a p
    join pg_temp._pool_genre_a pg on pg.media_id = p.cand_id
    join pg_temp._seed_genre_a sg on sg.seed_id = p.seed_id and sg.g = pg.g
    group by p.seed_id, p.cand_id;
    create index on pg_temp._gcnt_a (seed_id, cand_id);

    drop table if exists pg_temp._scored_a;
    create temp table _scored_a on commit drop as
    select
      x.seed_id, x.cand_id, x.overlap,
      (x.sim
        * least(2.5,
            least(2.0, 1.0 + 0.5 * x.dir + 0.15 * x.studio + 0.5 * x.author)
            * case when x.rail then 1.25 else 1.0 end)
        * x.realm_mult
        * x.mem_term
        + x.penalty)::real as score,
      x.popularity
    from (
      select
        p.seed_id, p.cand_id, p.overlap, p.sim,
        pl.popularity,
        (dp.cand_id is not null)::int as dir,
        (sp.cand_id is not null)::int as studio,
        (ap.cand_id is not null)::int as author,
        (rp.cand_id is not null) as rail,
        coalesce(pen.penalty, 0)::double precision as penalty,
        case
          when sr_any.seed_id is null then 1.0
          when ct.media_id is null then null
          when st.realm is not null then 1.0
          when coalesce(ta.aff, 0) >= 0.6 then 0.85
          when ff.cand_id is not null then 0.65
          else null
        end::double precision as realm_mult,
        case
          when sr_any.seed_id is null then 1.0
          else 0.5 + 0.5 * least(1.0, coalesce(sh.shared_w, 0) / 0.35)
        end::double precision as mem_term,
        sa.tier_rank as seed_tier_rank,
        coalesce(ctr.r, 2) as cand_tier_rank,
        coalesce(sn.n, 0) as seed_genre_n,
        coalesce(sn.need, 1) as genre_need,
        coalesce(gc.c, 0) as genre_overlap,
        pl.avg_score,
        (bl.anilist_id is not null) as blessed
      from pg_temp._pairs_a p
      join pg_temp._pool_a pl on pl.media_id = p.cand_id
      join pg_temp._seed_attr_a sa on sa.seed_id = p.seed_id
      left join (select distinct sr.seed_id from pg_temp._seed_realm_a sr) sr_any on sr_any.seed_id = p.seed_id
      left join pg_temp._ctop ct on ct.media_type = 'ANIME' and ct.media_id = p.cand_id
      left join pg_temp._seed_realm_a st on st.seed_id = p.seed_id and st.realm = ct.realm
      left join pg_temp._top_adj_a ta on ta.seed_id = p.seed_id and ta.realm = ct.realm
      left join pg_temp._famflag_a ff on ff.seed_id = p.seed_id and ff.cand_id = p.cand_id
      left join pg_temp._shared_a sh on sh.seed_id = p.seed_id and sh.cand_id = p.cand_id
      left join pg_temp._dir_pair_a dp on dp.seed_id = p.seed_id and dp.cand_id = p.cand_id
      left join pg_temp._studio_pair_a sp on sp.seed_id = p.seed_id and sp.cand_id = p.cand_id
      left join pg_temp._auth_pair_a ap on ap.seed_id = p.seed_id and ap.cand_id = p.cand_id
      left join pg_temp._rail_pair_a rp on rp.seed_id = p.seed_id and rp.cand_id = p.cand_id
      left join pg_temp._pen_a pen on pen.media_id = p.cand_id
      left join pg_temp._trank ctr on ctr.media_type = 'ANIME' and ctr.media_id = p.cand_id
      left join pg_temp._gcnt_a gc on gc.seed_id = p.seed_id and gc.cand_id = p.cand_id
      left join pg_temp._seed_need_a sn on sn.seed_id = p.seed_id
      left join pg_temp._bless_a bl on bl.anilist_id = pl.anilist_id
    ) x
    where x.sim is not null
      -- genre-overlap gate
      and (x.seed_genre_n = 0 or x.genre_overlap >= x.genre_need)
      -- realm hard exclusion (b): mult NULL = no shared family and affinity < 0.6
      and x.realm_mult is not null
      -- realm hard exclusion (a): tier distance > 1 (missing cand tier = solid)
      and (x.seed_tier_rank is null or abs(x.cand_tier_rank - x.seed_tier_rank) <= 1)
      -- canon-seed absolute merit floor
      and (coalesce(x.seed_tier_rank, 0) < 4 or x.avg_score >= 75 or x.blessed);

    -- -----------------------------------------------------------------------
    -- Stage A (20260805120000): same-type edges, KEEP-checked (see migration
    -- header). Pool membership via _pool_a; franchise via _fr (candidate must
    -- not share the seed's component, and the stage is internally deduped to
    -- one candidate per component, highest rating first); tier distance <= 1
    -- (missing tier = solid); canon-seed merit floor hard.
    -- -----------------------------------------------------------------------

    drop table if exists pg_temp._edge_keep_a;
    create temp table _edge_keep_a on commit drop as
    select b.sid as seed_id, e.to_media_id as cand_id, e.rating,
           pl.popularity, coalesce(pen.penalty, 0)::double precision as penalty
    from pg_temp._smb b
    join public.media_rec_edges e
      on e.from_media_type = 'ANIME' and e.from_media_id = b.sid and e.to_media_type = 'ANIME'
    join pg_temp._pool_a pl on pl.media_id = e.to_media_id
    join pg_temp._seed_attr_a sa on sa.seed_id = b.sid
    left join pg_temp._fr fs on fs.media_type = 'ANIME' and fs.media_id = b.sid
    left join pg_temp._fr fc on fc.media_type = 'ANIME' and fc.media_id = e.to_media_id
    left join pg_temp._trank ctr on ctr.media_type = 'ANIME' and ctr.media_id = e.to_media_id
    left join pg_temp._pen_a pen on pen.media_id = e.to_media_id
    left join pg_temp._bless_a bl on bl.anilist_id = pl.anilist_id
    where b.mt = 'ANIME'
      and e.to_media_id <> b.sid
      -- not the seed's own franchise (sequels/specials of the seed are out)
      and coalesce(fc.label, e.to_media_id) <> coalesce(fs.label, b.sid)
      -- tier distance <= 1 (missing cand tier = solid, rank 2)
      and (sa.tier_rank is null or abs(coalesce(ctr.r, 2) - sa.tier_rank) <= 1)
      -- canon-seed absolute merit floor (hard, same as the cosine gate)
      and (coalesce(sa.tier_rank, 0) < 4 or pl.avg_score >= 75 or bl.anilist_id is not null);

    -- One candidate per franchise component within the edge stage.
    drop table if exists pg_temp._edge_dedup_a;
    create temp table _edge_dedup_a on commit drop as
    select distinct on (k.seed_id, coalesce(f.label, k.cand_id))
           k.seed_id, k.cand_id, k.rating, k.popularity, k.penalty,
           coalesce(f.label, k.cand_id) as label
    from pg_temp._edge_keep_a k
    left join pg_temp._fr f on f.media_type = 'ANIME' and f.media_id = k.cand_id
    order by k.seed_id, coalesce(f.label, k.cand_id), k.rating desc, k.popularity desc, k.cand_id desc;

    -- Edge scores: 3.0 + per-seed min-max of rating (flat-rating seeds -> 3.5)
    -- + penalty, floored at 2.6 (above every cosine row, which caps at 2.5).
    drop table if exists pg_temp._edge_a;
    create temp table _edge_a on commit drop as
    select s.seed_id, s.cand_id, s.rating, s.label, s.score,
           row_number() over (partition by s.seed_id
                              order by s.score desc, s.rating desc, s.popularity desc, s.cand_id desc) as rn
    from (
      select d.seed_id, d.cand_id, d.rating, d.popularity, d.label,
             greatest(2.6,
               3.0 + coalesce((d.rating - mm.min_r)::double precision
                                / nullif(mm.max_r - mm.min_r, 0), 0.5)
                   + d.penalty)::real as score
      from pg_temp._edge_dedup_a d
      join (select dd.seed_id, min(dd.rating) as min_r, max(dd.rating) as max_r
            from pg_temp._edge_dedup_a dd group by dd.seed_id) mm on mm.seed_id = d.seed_id
    ) s;
    create index on pg_temp._edge_a (seed_id, label);

    insert into pg_temp._out_a (seed_id, cand_id, overlap, score, rn, src)
    select e.seed_id, e.cand_id, coalesce(p.overlap, 0), e.score, e.rn, 'edge'
    from pg_temp._edge_a e
    left join pg_temp._pairs_a p on p.seed_id = e.seed_id and p.cand_id = e.cand_id;

    -- -----------------------------------------------------------------------
    -- Stage B: cosine backfill — the pre-fork output assembly, minus every
    -- franchise component Stage A already took (label anti-join also covers
    -- exact-id repeats), ranked after the seed's edge block.
    -- -----------------------------------------------------------------------

    insert into pg_temp._out_a (seed_id, cand_id, overlap, score, rn, src)
    select c.seed_id, c.cand_id, c.overlap, c.score,
           coalesce(en.n, 0)
             + row_number() over (partition by c.seed_id order by c.score desc, c.popularity desc, c.cand_id desc),
           'cosine'
    from (
      select distinct on (s.seed_id, coalesce(f.label, s.cand_id))
        s.seed_id, s.cand_id, s.overlap, s.score, s.popularity,
        coalesce(f.label, s.cand_id) as label
      from pg_temp._scored_a s
      left join pg_temp._fr f on f.media_type = 'ANIME' and f.media_id = s.cand_id
      order by s.seed_id, coalesce(f.label, s.cand_id), s.score desc, s.popularity desc, s.cand_id desc
    ) c
    left join (select e.seed_id, count(*) as n from pg_temp._edge_a e group by e.seed_id) en
      on en.seed_id = c.seed_id
    where not exists (
      select 1 from pg_temp._edge_a el
      where el.seed_id = c.seed_id and el.label = c.label
    );

  end if;

  -- =========================================================================
  -- MANGA sub-pipeline (craft: story-role creator + any-role author; no studio).
  -- =========================================================================
  if exists (select 1 from pg_temp._smb b where b.mt = 'MANGA') then

    drop table if exists pg_temp._pool_m;
    create temp table _pool_m on commit drop as
    select m.id as media_id, coalesce(m.genres, '{}'::text[]) as genres,
           coalesce(m.popularity, 0) as popularity, coalesce(m.average_score, 0) as avg_score,
           m.anilist_id
    from public.manga m
    where m.cover_image_large is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])));
    create index on pg_temp._pool_m (media_id);

    drop table if exists pg_temp._pool_genre_m;
    create temp table _pool_genre_m on commit drop as
    select p.media_id, g from pg_temp._pool_m p cross join lateral unnest(p.genres) as g;
    create index on pg_temp._pool_genre_m (media_id, g);
    analyze pg_temp._pool_genre_m;

    drop table if exists pg_temp._pen_m;
    create temp table _pen_m on commit drop as
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id;
    create index on pg_temp._pen_m (media_id);

    drop table if exists pg_temp._bless_m;
    create temp table _bless_m on commit drop as
    select cs.media_id as anilist_id from public.canon_seed cs
    where cs.media_type = 'MANGA' and cs.blessed = true;

    drop table if exists pg_temp._seed_attr_m;
    create temp table _seed_attr_m on commit drop as
    select b.sid as seed_id, t.r as tier_rank, coalesce(m.genres, '{}'::text[]) as genres
    from pg_temp._smb b
    join public.manga m on m.id = b.sid
    left join pg_temp._trank t on t.media_type = 'MANGA' and t.media_id = b.sid
    where b.mt = 'MANGA';

    drop table if exists pg_temp._seed_genre_m;
    create temp table _seed_genre_m on commit drop as
    select s.seed_id, g from pg_temp._seed_attr_m s cross join lateral unnest(s.genres) as g
    group by s.seed_id, g;
    create index on pg_temp._seed_genre_m (seed_id, g);

    drop table if exists pg_temp._seed_need_m;
    create temp table _seed_need_m on commit drop as
    select sg.seed_id, count(*) as n, case when count(*) >= 4 then 2 else 1 end as need
    from pg_temp._seed_genre_m sg group by sg.seed_id;

    drop table if exists pg_temp._seed_realm_m;
    create temp table _seed_realm_m on commit drop as
    select b.sid as seed_id, e.realm, min(e.family) as family, max(e.w) as w
    from pg_temp._smb b
    join pg_temp._eff e on e.media_type = 'MANGA' and e.media_id = b.sid
    where b.mt = 'MANGA'
    group by b.sid, e.realm;
    create index on pg_temp._seed_realm_m (seed_id, realm);

    drop table if exists pg_temp._seed_family_m;
    create temp table _seed_family_m on commit drop as
    select distinct sr.seed_id, sr.family from pg_temp._seed_realm_m sr where sr.family is not null;

    drop table if exists pg_temp._top_adj_m;
    create temp table _top_adj_m on commit drop as
    select sr.seed_id, f.realm_a as realm, max(f.aff) as aff
    from pg_temp._seed_realm_m sr join pg_temp._aff f on f.realm_b = sr.realm
    group by sr.seed_id, f.realm_a;
    create index on pg_temp._top_adj_m (seed_id, realm);

    drop table if exists pg_temp._rail_pair_m;
    create temp table _rail_pair_m on commit drop as
    select distinct sr.seed_id, m3.id as cand_id
    from (
      select b.sid as seed_id, i.rail_id
      from pg_temp._smb b
      join public.manga m2 on m2.id = b.sid
      join public.curated_rail_items i on i.media_type = 'MANGA' and i.anilist_id = m2.anilist_id
      where b.mt = 'MANGA'
    ) sr
    join public.curated_rail_items i2 on i2.rail_id = sr.rail_id and i2.media_type = 'MANGA'
    join public.manga m3 on m3.anilist_id = i2.anilist_id;
    create index on pg_temp._rail_pair_m (seed_id, cand_id);

    drop table if exists pg_temp._dir_pair_m;
    create temp table _dir_pair_m on commit drop as
    select distinct ys.seed_id, xs.manga_id as cand_id
    from (select b.sid as seed_id, s.author_id from pg_temp._smb b
          join public.manga_authors s on s.manga_id = b.sid and s.role ilike '%story%'
          where b.mt = 'MANGA') ys
    join public.manga_authors xs on xs.author_id = ys.author_id and xs.role ilike '%story%';
    create index on pg_temp._dir_pair_m (seed_id, cand_id);

    drop table if exists pg_temp._auth_pair_m;
    create temp table _auth_pair_m on commit drop as
    select distinct ys.seed_id, xs.manga_id as cand_id
    from (select b.sid as seed_id, s.author_id from pg_temp._smb b
          join public.manga_authors s on s.manga_id = b.sid
          where b.mt = 'MANGA') ys
    join public.manga_authors xs on xs.author_id = ys.author_id;
    create index on pg_temp._auth_pair_m (seed_id, cand_id);

    drop table if exists pg_temp._sv_m;
    create temp table _sv_m on commit drop as
    select v.media_id as seed_id, v.tag_key, v.w::double precision as w
    from public.media_tag_vectors v
    join pg_temp._smb b on b.mt = 'MANGA' and b.sid = v.media_id
    where v.media_type = 'MANGA';
    analyze pg_temp._sv_m;

    drop table if exists pg_temp._snorm_m;
    create temp table _snorm_m on commit drop as
    select sv.seed_id, sqrt(sum(sv.w * sv.w)) as n
    from pg_temp._sv_m sv group by sv.seed_id
    having sqrt(sum(sv.w * sv.w)) > 0;

    drop table if exists pg_temp._pairs_m;
    create temp table _pairs_m on commit drop as
    select sv.seed_id, v.media_id as cand_id,
           count(*)::int as overlap,
           (sum(v.w::double precision * sv.w) / (sn.n * max(v.l2_norm)::double precision)) as sim
    from pg_temp._sv_m sv
    join pg_temp._snorm_m sn on sn.seed_id = sv.seed_id
    join public.media_tag_vectors v
      on v.media_type = 'MANGA' and v.tag_key = sv.tag_key and v.media_id <> sv.seed_id
    group by sv.seed_id, v.media_id, sn.n
    having max(v.l2_norm) > 0;
    create index on pg_temp._pairs_m (seed_id, cand_id);
    analyze pg_temp._pairs_m;

    drop table if exists pg_temp._shared_m;
    create temp table _shared_m on commit drop as
    select p.seed_id, p.cand_id, max(least(sr.w, e.w)) as shared_w
    from pg_temp._pairs_m p
    join pg_temp._eff e on e.media_type = 'MANGA' and e.media_id = p.cand_id
    join pg_temp._seed_realm_m sr on sr.seed_id = p.seed_id and sr.realm = e.realm
    group by p.seed_id, p.cand_id;
    create index on pg_temp._shared_m (seed_id, cand_id);

    drop table if exists pg_temp._famflag_m;
    create temp table _famflag_m on commit drop as
    select distinct p.seed_id, p.cand_id
    from pg_temp._pairs_m p
    join pg_temp._eff e on e.media_type = 'MANGA' and e.media_id = p.cand_id
    join pg_temp._seed_family_m sf on sf.seed_id = p.seed_id and sf.family = e.family;
    create index on pg_temp._famflag_m (seed_id, cand_id);

    drop table if exists pg_temp._gcnt_m;
    create temp table _gcnt_m on commit drop as
    select p.seed_id, p.cand_id, count(*) as c
    from pg_temp._pairs_m p
    join pg_temp._pool_genre_m pg on pg.media_id = p.cand_id
    join pg_temp._seed_genre_m sg on sg.seed_id = p.seed_id and sg.g = pg.g
    group by p.seed_id, p.cand_id;
    create index on pg_temp._gcnt_m (seed_id, cand_id);

    drop table if exists pg_temp._scored_m;
    create temp table _scored_m on commit drop as
    select
      x.seed_id, x.cand_id, x.overlap,
      (x.sim
        * least(2.5,
            least(2.0, 1.0 + 0.5 * x.dir + 0.15 * x.studio + 0.5 * x.author)
            * case when x.rail then 1.25 else 1.0 end)
        * x.realm_mult
        * x.mem_term
        + x.penalty)::real as score,
      x.popularity
    from (
      select
        p.seed_id, p.cand_id, p.overlap, p.sim,
        pl.popularity,
        (dp.cand_id is not null)::int as dir,
        0 as studio,
        (ap.cand_id is not null)::int as author,
        (rp.cand_id is not null) as rail,
        coalesce(pen.penalty, 0)::double precision as penalty,
        case
          when sr_any.seed_id is null then 1.0
          when ct.media_id is null then null
          when st.realm is not null then 1.0
          when coalesce(ta.aff, 0) >= 0.6 then 0.85
          when ff.cand_id is not null then 0.65
          else null
        end::double precision as realm_mult,
        case
          when sr_any.seed_id is null then 1.0
          else 0.5 + 0.5 * least(1.0, coalesce(sh.shared_w, 0) / 0.35)
        end::double precision as mem_term,
        sa.tier_rank as seed_tier_rank,
        coalesce(ctr.r, 2) as cand_tier_rank,
        coalesce(sn.n, 0) as seed_genre_n,
        coalesce(sn.need, 1) as genre_need,
        coalesce(gc.c, 0) as genre_overlap,
        pl.avg_score,
        (bl.anilist_id is not null) as blessed
      from pg_temp._pairs_m p
      join pg_temp._pool_m pl on pl.media_id = p.cand_id
      join pg_temp._seed_attr_m sa on sa.seed_id = p.seed_id
      left join (select distinct sr.seed_id from pg_temp._seed_realm_m sr) sr_any on sr_any.seed_id = p.seed_id
      left join pg_temp._ctop ct on ct.media_type = 'MANGA' and ct.media_id = p.cand_id
      left join pg_temp._seed_realm_m st on st.seed_id = p.seed_id and st.realm = ct.realm
      left join pg_temp._top_adj_m ta on ta.seed_id = p.seed_id and ta.realm = ct.realm
      left join pg_temp._famflag_m ff on ff.seed_id = p.seed_id and ff.cand_id = p.cand_id
      left join pg_temp._shared_m sh on sh.seed_id = p.seed_id and sh.cand_id = p.cand_id
      left join pg_temp._dir_pair_m dp on dp.seed_id = p.seed_id and dp.cand_id = p.cand_id
      left join pg_temp._auth_pair_m ap on ap.seed_id = p.seed_id and ap.cand_id = p.cand_id
      left join pg_temp._rail_pair_m rp on rp.seed_id = p.seed_id and rp.cand_id = p.cand_id
      left join pg_temp._pen_m pen on pen.media_id = p.cand_id
      left join pg_temp._trank ctr on ctr.media_type = 'MANGA' and ctr.media_id = p.cand_id
      left join pg_temp._gcnt_m gc on gc.seed_id = p.seed_id and gc.cand_id = p.cand_id
      left join pg_temp._seed_need_m sn on sn.seed_id = p.seed_id
      left join pg_temp._bless_m bl on bl.anilist_id = pl.anilist_id
    ) x
    where x.sim is not null
      and (x.seed_genre_n = 0 or x.genre_overlap >= x.genre_need)
      and x.realm_mult is not null
      and (x.seed_tier_rank is null or abs(x.cand_tier_rank - x.seed_tier_rank) <= 1)
      and (coalesce(x.seed_tier_rank, 0) < 4 or x.avg_score >= 75 or x.blessed);

    -- -----------------------------------------------------------------------
    -- Stage A (20260805120000): same-type edges — MANGA mirror of the anime
    -- stage; identical KEEP checks and formula.
    -- -----------------------------------------------------------------------

    drop table if exists pg_temp._edge_keep_m;
    create temp table _edge_keep_m on commit drop as
    select b.sid as seed_id, e.to_media_id as cand_id, e.rating,
           pl.popularity, coalesce(pen.penalty, 0)::double precision as penalty
    from pg_temp._smb b
    join public.media_rec_edges e
      on e.from_media_type = 'MANGA' and e.from_media_id = b.sid and e.to_media_type = 'MANGA'
    join pg_temp._pool_m pl on pl.media_id = e.to_media_id
    join pg_temp._seed_attr_m sa on sa.seed_id = b.sid
    left join pg_temp._fr fs on fs.media_type = 'MANGA' and fs.media_id = b.sid
    left join pg_temp._fr fc on fc.media_type = 'MANGA' and fc.media_id = e.to_media_id
    left join pg_temp._trank ctr on ctr.media_type = 'MANGA' and ctr.media_id = e.to_media_id
    left join pg_temp._pen_m pen on pen.media_id = e.to_media_id
    left join pg_temp._bless_m bl on bl.anilist_id = pl.anilist_id
    where b.mt = 'MANGA'
      and e.to_media_id <> b.sid
      and coalesce(fc.label, e.to_media_id) <> coalesce(fs.label, b.sid)
      and (sa.tier_rank is null or abs(coalesce(ctr.r, 2) - sa.tier_rank) <= 1)
      and (coalesce(sa.tier_rank, 0) < 4 or pl.avg_score >= 75 or bl.anilist_id is not null);

    drop table if exists pg_temp._edge_dedup_m;
    create temp table _edge_dedup_m on commit drop as
    select distinct on (k.seed_id, coalesce(f.label, k.cand_id))
           k.seed_id, k.cand_id, k.rating, k.popularity, k.penalty,
           coalesce(f.label, k.cand_id) as label
    from pg_temp._edge_keep_m k
    left join pg_temp._fr f on f.media_type = 'MANGA' and f.media_id = k.cand_id
    order by k.seed_id, coalesce(f.label, k.cand_id), k.rating desc, k.popularity desc, k.cand_id desc;

    drop table if exists pg_temp._edge_m;
    create temp table _edge_m on commit drop as
    select s.seed_id, s.cand_id, s.rating, s.label, s.score,
           row_number() over (partition by s.seed_id
                              order by s.score desc, s.rating desc, s.popularity desc, s.cand_id desc) as rn
    from (
      select d.seed_id, d.cand_id, d.rating, d.popularity, d.label,
             greatest(2.6,
               3.0 + coalesce((d.rating - mm.min_r)::double precision
                                / nullif(mm.max_r - mm.min_r, 0), 0.5)
                   + d.penalty)::real as score
      from pg_temp._edge_dedup_m d
      join (select dd.seed_id, min(dd.rating) as min_r, max(dd.rating) as max_r
            from pg_temp._edge_dedup_m dd group by dd.seed_id) mm on mm.seed_id = d.seed_id
    ) s;
    create index on pg_temp._edge_m (seed_id, label);

    insert into pg_temp._out_m (seed_id, cand_id, overlap, score, rn, src)
    select e.seed_id, e.cand_id, coalesce(p.overlap, 0), e.score, e.rn, 'edge'
    from pg_temp._edge_m e
    left join pg_temp._pairs_m p on p.seed_id = e.seed_id and p.cand_id = e.cand_id;

    insert into pg_temp._out_m (seed_id, cand_id, overlap, score, rn, src)
    select c.seed_id, c.cand_id, c.overlap, c.score,
           coalesce(en.n, 0)
             + row_number() over (partition by c.seed_id order by c.score desc, c.popularity desc, c.cand_id desc),
           'cosine'
    from (
      select distinct on (s.seed_id, coalesce(f.label, s.cand_id))
        s.seed_id, s.cand_id, s.overlap, s.score, s.popularity,
        coalesce(f.label, s.cand_id) as label
      from pg_temp._scored_m s
      left join pg_temp._fr f on f.media_type = 'MANGA' and f.media_id = s.cand_id
      order by s.seed_id, coalesce(f.label, s.cand_id), s.score desc, s.popularity desc, s.cand_id desc
    ) c
    left join (select e.seed_id, count(*) as n from pg_temp._edge_m e group by e.seed_id) en
      on en.seed_id = c.seed_id
    where not exists (
      select 1 from pg_temp._edge_m el
      where el.seed_id = c.seed_id and el.label = c.label
    );

  end if;

  -- -------------------------------------------------------------------------
  -- Sanity guard (20260804140000, reviewer finding 8): a healthy batch of
  -- >= 50 seeds never legitimately produces ZERO output rows across the WHOLE
  -- batch (individual seeds may be legitimately empty — zero-norm vectors,
  -- all candidates gated). If it happens, something upstream is broken
  -- (vectors/membership/tier wiped) and proceeding would erase served rows
  -- batch-by-batch via the swap below. RAISE rolls this batch back; the
  -- seeds stay stale and the store keeps serving its previous rows.
  -- -------------------------------------------------------------------------

  select (select count(*) from pg_temp._out_a)
       + (select count(*) from pg_temp._out_m)
    into _out_n;
  if _n >= 50 and _out_n = 0 then
    raise exception 'rebuild_media_similar_titles: batch of % seeds produced 0 output rows — refusing to wipe served rows', _n
      using detail = 'STAGE_EMPTY_ANOMALY';
  end if;

  -- -------------------------------------------------------------------------
  -- SWAP for this batch's seeds only (targeted WHERE via the batch temp —
  -- pg_safeupdate). One transaction: readers see old rows or new rows.
  -- -------------------------------------------------------------------------

  delete from public.media_similar_titles t
  using pg_temp._smb b
  where t.seed_media_type = b.mt and t.seed_media_id = b.sid;

  insert into public.media_similar_titles
    (seed_media_type, seed_media_id, rank, media_id, overlap_count, score, built_at, src)
  select 'ANIME', o.seed_id, o.rn, o.cand_id, o.overlap, o.score, now(), o.src
  from pg_temp._out_a o where o.rn <= 30
  union all
  select 'MANGA', o.seed_id, o.rn, o.cand_id, o.overlap, o.score, now(), o.src
  from pg_temp._out_m o where o.rn <= 30;

  update public.media_similar_seed_state st
  set stale = false, built_at = now()
  from pg_temp._smb b
  where st.seed_media_type = b.mt and st.seed_media_id = b.sid;

  return _n;
end;
$$;

revoke all on function public.rebuild_media_similar_titles(integer) from public, anon, authenticated;
grant execute on function public.rebuild_media_similar_titles(integer) to service_role;

comment on function public.rebuild_media_similar_titles(integer) is
  'Realm repair Fix 5 (20260804130000/140000; edges-first fork 20260805120000): batched set-based rebuild of media_similar_titles — syncs the visible seed universe AND media_franchise_components, takes up to p_batch stale seeds (default 100 — Micro-instance sizing), and per seed serves Stage A media_rec_edges (KEEP-checked: pool/franchise/tier-distance/canon merit floor; score 3.0 + per-seed min-max of rating + penalty, floored 2.6) above Stage B cosine backfill (the unchanged 20260804100000 scorer, franchise-anti-joined against Stage A) to depth 30, swapping delete-then-insert. Aborts with DETAIL STAGE_EMPTY_ANOMALY if >= 50 seeds produce 0 total rows. Returns seeds processed, 0 when converged, -1 when the advisory lock is held. service_role-only EXECUTE; crons SET statement_timeout as their own first statement. Revert: restore the 20260804140000 builder body.';

commit;
