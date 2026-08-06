-- Realm repair Phase 1, Fix 5 (spec: 2026-08-04-realm-repair-and-critique-plan.md §3.5).
--
-- PRECOMPUTE SIMILARITY SERVING.
--   recommend_ids_similar_to_seeds live-computed the gated cosine per call
--   (p50 ~1.9s / p95 ~3.6s Management-API wall-clock post-M1; the pre-M1
--   baseline timed out on 53/100 gold seeds). This migration moves everything
--   user-INdependent into a precomputed store and turns the RPC into an
--   indexed read:
--
--   * public.media_similar_titles — top-30 neighbors per visible seed
--     (seed universe: anime+manga with average_score >= 70, non-adult, has
--     cover — 3,377 anime + 4,160 manga = 7,537 seeds at build time). Baked
--     per seed, EXACTLY the 20260804100000 scorer minus the per-user
--     user_lists exclusion: cosine, realm cost ladder + membership weight
--     term, tier-distance gate, genre-overlap gate, editorial penalties,
--     craft/rail multipliers, canon merit floor, adult/Hentai/Ecchi filter,
--     franchise dedupe. Verified: for seed ANIME/111 the batch pipeline
--     reproduces the live scorer's top-12 byte-for-byte (ids, scores, order).
--   * The per-user user_lists exclusion stays in the RPC at read time (users
--     differ). Top-30 stored so post-exclusion depth survives (the app's rails
--     consume <= 12; concierge asks for 50 and degrades gracefully to the
--     top-30 prefix — noted deviation, see DEVIATIONS below).
--
-- BUILDER: rebuild_media_similar_titles(p_batch) — chunked, set-based.
--   A state table (media_similar_seed_state) tracks staleness; each invocation
--   syncs the seed universe, takes up to p_batch stale seeds, generalizes the
--   scorer CTEs over the whole batch (temp-table pipeline, one snapshot of the
--   FULL-OUTER-JOIN effective-membership view per invocation instead of the
--   per-call rescans that made the live path slow), and swaps that batch's
--   rows delete-then-insert INSIDE the call's transaction (targeted WHERE —
--   pg_safeupdate; served rows are never globally empty). Repeated
--   invocations converge; an advisory xact lock makes overlapping invocations
--   skip (returns -1) instead of stomping each other.
--   MEASURED (Management API, 2026-08-04): 100 anime seeds ~40s wall
--   (1.31M cosine pairs), 100 manga seeds ~100s wall (2.72M pairs — the manga
--   candidate pool is 41k titles vs 19k anime). p_batch therefore defaults to
--   300: worst case (all-manga batch) ~300s — half the 600s cron ceiling.
--
-- TIMEOUT MECHANICS (copied from 20260804120000): the in-function
--   `set local statement_timeout` cannot re-arm the top-level statement that
--   is already running, so the driver cron raises the session timeout as its
--   OWN first statement (pg_cron runs simple-protocol, use_background_workers
--   off — the session SET from statement 1 governs statement 2):
--     set statement_timeout = '600s'; select public.rebuild_media_similar_titles(300);
--
-- CRON CHOICE (documented per plan): the 5-minute driver
--   'realm-similar-drive-5m' stays scheduled PERMANENTLY — when nothing is
--   stale it is a cheap no-op (universe sync + one indexed probe), and it is
--   the self-healing convergence mechanism: newly imported visible titles get
--   rows within minutes, and the nightly full re-stale is drained by the same
--   job. 'realm-similar-nightly' (05:10 UTC) re-marks all seeds stale right
--   after the upstream nightly chain (vectors 03:50, membership 04:30,
--   affinity 04:40, tier 04:50) so the store follows the refreshed graph.
--
-- RPC REWRITE: recommend_ids_similar_to_seeds keeps its exact signature,
--   return shape, and grants (anon, authenticated). Read path: fetch
--   precomputed rows for the given seeds, blend multi-seed by SUMMING score
--   per candidate (dedupe by candidate, keep max overlap_count), exclude the
--   seeds themselves, apply the caller's user_lists exclusion, order by
--   blended score desc / popularity desc / media_id desc, limit. FALLBACK:
--   if NO seed has precomputed rows (obscure/non-visible seeds), the old
--   scorer — preserved verbatim as _recommend_ids_similar_to_seeds_live,
--   EXECUTE locked to service_role (owner postgres keeps implicit EXECUTE;
--   the SECURITY DEFINER RPC calls it as owner) — serves the request, so
--   behavior degrades to the pre-precompute path instead of empty. Mixed
--   case (some seeds precomputed, some not): precomputed only — the hot path
--   never blocks on the live scorer.
--
-- DEVIATIONS from the Fix-5 design brief (each with reason):
--   1. p_batch default 300, not 500 — sized from the measured 100-seed batch
--      cost above so one call stays well under 600s even for all-manga
--      batches (500 manga seeds would be ~490s — too close to the ceiling).
--   2. p_allow_gimmicks = true routes to the live fallback: the baked score
--      already contains the editorial penalty term, and the stored top-30 was
--      selected under penalty ordering, so gimmick calls (penalty term
--      zeroed) cannot be served correctly from the store. Only
--      concierge-recommend's explicit gimmick vibe modes hit this; they keep
--      the post-M1 live-path latency.
--   3. Franchise dedupe uses GLOBAL same-type connected components of
--      media_relations (computed once per builder invocation, ~1s for 16.6k
--      edges, max component 116) instead of the live scorer's per-call
--      components restricted to that call's candidate set. Difference: two
--      candidates bridged only by a same-type relative OUTSIDE the candidate
--      set now dedupe (slightly MORE aggressive franchise collapsing — the
--      intended semantics). Cross-type edges are excluded exactly like the
--      live scorer (fr_nodes is single-type there).
--   4. No separate index on (seed_media_type, seed_media_id): the PK
--      (seed_media_type, seed_media_id, rank) already serves that prefix.
--   5. p_limit > 30 returns at most the stored 30 per seed (minus
--      exclusions) — concierge-recommend passes p_limit 50 as a candidate
--      pool and degrades gracefully to the score-ordered top-30 prefix.
--
-- Grants trap (20260804121000 lesson): default privileges hand EXECUTE on new
-- functions to anon/authenticated — revoked HERE, in the same migration.

begin;

-- ---------------------------------------------------------------------------
-- 1) media_similar_titles — the precomputed store.
--    RLS on, NO policies, NO client grants: the SECURITY DEFINER RPC reads it
--    as owner, service_role bypasses RLS. Keeping anon/authenticated off the
--    table avoids a new advisor finding.
-- ---------------------------------------------------------------------------

create table public.media_similar_titles (
  seed_media_type text        not null,
  seed_media_id   integer     not null,
  rank            integer     not null,
  media_id        integer     not null,
  overlap_count   integer     not null,
  score           real        not null,
  built_at        timestamptz not null default now(),
  primary key (seed_media_type, seed_media_id, rank)
);

comment on table public.media_similar_titles is
  'Realm repair Fix 5 (20260804130000): precomputed top-30 similar titles per visible seed (score >= 70, non-adult, has cover), baked from the repaired recommend_ids_similar_to_seeds scorer minus the per-user exclusion. Rebuilt in batches by rebuild_media_similar_titles(); served by recommend_ids_similar_to_seeds as an indexed read. No client grants on purpose — the SECURITY DEFINER RPC reads it as owner.';

alter table public.media_similar_titles enable row level security;

revoke all on public.media_similar_titles from public, anon, authenticated;
grant all on public.media_similar_titles to service_role;

-- ---------------------------------------------------------------------------
-- 2) media_similar_seed_state — build cursor/staleness tracking.
-- ---------------------------------------------------------------------------

create table public.media_similar_seed_state (
  seed_media_type text        not null,
  seed_media_id   integer     not null,
  stale           boolean     not null default true,
  built_at        timestamptz,
  primary key (seed_media_type, seed_media_id)
);

comment on table public.media_similar_seed_state is
  'Realm repair Fix 5 (20260804130000): per-seed build state for media_similar_titles. stale=true seeds are (re)built by the next rebuild_media_similar_titles() batches; the nightly cron re-marks all seeds stale after the upstream realm refresh chain.';

alter table public.media_similar_seed_state enable row level security;

revoke all on public.media_similar_seed_state from public, anon, authenticated;
grant all on public.media_similar_seed_state to service_role;

create index media_similar_seed_state_stale_idx
  on public.media_similar_seed_state (stale, seed_media_type, seed_media_id);

-- ---------------------------------------------------------------------------
-- 3) rebuild_media_similar_titles(p_batch) — chunked set-based builder.
--    search_path appends pg_temp LAST (SECURITY DEFINER hardening); every
--    temp reference below is pg_temp-qualified.
-- ---------------------------------------------------------------------------

create or replace function public.rebuild_media_similar_titles(p_batch integer default 300)
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _n integer;
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
  -- The pair aggregation hashes ~1-3M groups per 100 seeds; default work_mem
  -- spilled ~128MB to disk in measurement. Applies to this txn only.
  set local work_mem = '256MB';

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

  -- -------------------------------------------------------------------------
  -- Batch pick. Empty batch -> cheap no-op (the driver stays scheduled).
  -- -------------------------------------------------------------------------

  drop table if exists pg_temp._smb;
  create temp table _smb on commit drop as
  select st.seed_media_type as mt, st.seed_media_id as sid
  from public.media_similar_seed_state st
  where st.stale
  order by st.seed_media_type, st.seed_media_id
  limit greatest(1, least(coalesce(p_batch, 300), 2000));

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

  -- Global same-type franchise components (deviation 3 in the header): label =
  -- min member id per component; singletons label via coalesce at use site
  -- (collision-free: a component's min-member id belongs to that component).
  drop table if exists pg_temp._fr;
  create temp table _fr on commit drop as
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
  create index on pg_temp._fr (media_type, media_id);

  drop table if exists pg_temp._trank;
  create temp table _trank on commit drop as
  select t.media_type, t.media_id,
         case t.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end as r
  from public.media_realm_tier t;
  create index on pg_temp._trank (media_type, media_id);

  -- Output stages (created unconditionally so the final INSERT compiles even
  -- when the batch is single-type).
  drop table if exists pg_temp._out_a;
  create temp table _out_a (seed_id integer, cand_id integer, overlap integer, score real, rn bigint) on commit drop;
  drop table if exists pg_temp._out_m;
  create temp table _out_m (seed_id integer, cand_id integer, overlap integer, score real, rn bigint) on commit drop;

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

    insert into pg_temp._out_a (seed_id, cand_id, overlap, score, rn)
    select d.seed_id, d.cand_id, d.overlap, d.score,
           row_number() over (partition by d.seed_id order by d.score desc, d.popularity desc, d.cand_id desc)
    from (
      select distinct on (s.seed_id, coalesce(f.label, s.cand_id))
        s.seed_id, s.cand_id, s.overlap, s.score, s.popularity
      from pg_temp._scored_a s
      left join pg_temp._fr f on f.media_type = 'ANIME' and f.media_id = s.cand_id
      order by s.seed_id, coalesce(f.label, s.cand_id), s.score desc, s.popularity desc, s.cand_id desc
    ) d;

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

    insert into pg_temp._out_m (seed_id, cand_id, overlap, score, rn)
    select d.seed_id, d.cand_id, d.overlap, d.score,
           row_number() over (partition by d.seed_id order by d.score desc, d.popularity desc, d.cand_id desc)
    from (
      select distinct on (s.seed_id, coalesce(f.label, s.cand_id))
        s.seed_id, s.cand_id, s.overlap, s.score, s.popularity
      from pg_temp._scored_m s
      left join pg_temp._fr f on f.media_type = 'MANGA' and f.media_id = s.cand_id
      order by s.seed_id, coalesce(f.label, s.cand_id), s.score desc, s.popularity desc, s.cand_id desc
    ) d;

  end if;

  -- -------------------------------------------------------------------------
  -- SWAP for this batch's seeds only (targeted WHERE via the batch temp —
  -- pg_safeupdate). One transaction: readers see old rows or new rows.
  -- -------------------------------------------------------------------------

  delete from public.media_similar_titles t
  using pg_temp._smb b
  where t.seed_media_type = b.mt and t.seed_media_id = b.sid;

  insert into public.media_similar_titles
    (seed_media_type, seed_media_id, rank, media_id, overlap_count, score, built_at)
  select 'ANIME', o.seed_id, o.rn, o.cand_id, o.overlap, o.score, now()
  from pg_temp._out_a o where o.rn <= 30
  union all
  select 'MANGA', o.seed_id, o.rn, o.cand_id, o.overlap, o.score, now()
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
  'Realm repair Fix 5 (20260804130000): batched set-based rebuild of media_similar_titles — syncs the visible seed universe, takes up to p_batch stale seeds (default 300, measured ~1s anime / ~3s manga per 3 seeds), bakes the full 20260804100000 scorer minus per-user exclusion, swaps that batch delete-then-insert. Returns seeds processed, 0 when converged, -1 when another invocation holds the advisory lock. service_role-only EXECUTE; the crons run it as owner. Cron must SET statement_timeout as its own first statement.';

-- ---------------------------------------------------------------------------
-- 4) _recommend_ids_similar_to_seeds_live — the 20260804100000 scorer body,
--    preserved verbatim as the fallback for seeds without precomputed rows
--    and for p_allow_gimmicks = true. EXECUTE locked to service_role; the
--    SECURITY DEFINER RPC (owner postgres) calls it via implicit owner
--    EXECUTE.
-- ---------------------------------------------------------------------------

create or replace function public._recommend_ids_similar_to_seeds_live(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
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

revoke all on function public._recommend_ids_similar_to_seeds_live(text, integer[], integer, boolean) from public, anon, authenticated;
grant execute on function public._recommend_ids_similar_to_seeds_live(text, integer[], integer, boolean) to service_role;

comment on function public._recommend_ids_similar_to_seeds_live(text, integer[], integer, boolean) is
  'Realm repair Fix 5 (20260804130000): the 20260804100000 live scorer, preserved verbatim as fallback for recommend_ids_similar_to_seeds — used when no seed has precomputed rows (obscure/non-visible seeds) or p_allow_gimmicks = true (baked scores include the penalty term). Not client-callable; the public RPC (same owner) invokes it.';

-- ---------------------------------------------------------------------------
-- 5) recommend_ids_similar_to_seeds — precomputed read + blend + fallback.
--    Signature, return shape, and grants unchanged (iOS + fetch_because_you_rail
--    + concierge-recommend depend on the shape).
-- ---------------------------------------------------------------------------

create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_has_pre boolean;
begin
  -- Gimmick calls: the baked score already contains the penalty term and the
  -- stored top-30 was selected under penalty ordering — serve them live.
  if coalesce(p_allow_gimmicks, false) then
    return query
    select l.media_id, l.overlap_count, l.score
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l;
    return;
  end if;

  select exists (
    select 1 from public.media_similar_titles s
    where s.seed_media_type = p_media_type
      and p_seed_ids is not null
      and s.seed_media_id = any(p_seed_ids)
  ) into v_has_pre;

  -- No precomputed seed at all -> degrade to the old live scorer (never empty
  -- just because the store hasn't met this seed). Mixed seeds: precomputed
  -- only — the hot path never blocks on the live scorer.
  if not v_has_pre then
    return query
    select l.media_id, l.overlap_count, l.score
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l;
    return;
  end if;

  return query
  with req as (
    select greatest(1, least(coalesce(p_limit, 10), 50))::int as lim
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  hits as (
    select s.media_id as cand_id, s.overlap_count as oc, s.score as sc
    from public.media_similar_titles s
    where s.seed_media_type = p_media_type
      and s.seed_media_id = any(p_seed_ids)
      and not (s.media_id = any(p_seed_ids))
  ),
  blended as (
    -- Multi-seed blend: sum score per candidate (a title near several seeds
    -- rises), keep max overlap_count for the reporting column.
    select h.cand_id, max(h.oc)::integer as oc, sum(h.sc)::real as sc
    from hits h
    group by h.cand_id
  )
  select b.cand_id, b.oc, b.sc
  from blended b
  left join public.anime a on p_media_type = 'ANIME' and a.id = b.cand_id
  left join public.manga m on p_media_type = 'MANGA' and m.id = b.cand_id
  where not exists (
    select 1 from public.user_lists ul
    where (select me.user_id from me) is not null
      and ul.user_id = (select me.user_id from me)
      and ul.media_type = case when p_media_type = 'ANIME' then 'anime' else 'manga' end
      and ul.media_id = b.cand_id
  )
  order by b.sc desc, coalesce(a.popularity, m.popularity, 0) desc, b.cand_id desc
  limit (select req.lim from req);
end;
$$;

revoke all on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) from public;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon, authenticated;

comment on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) is
  'Realm repair Fix 5 (20260804130000): serves similar titles from the precomputed media_similar_titles store (indexed read + multi-seed sum-blend + per-user user_lists exclusion). Falls back to _recommend_ids_similar_to_seeds_live when no seed has precomputed rows or p_allow_gimmicks = true. Same signature/shape/grants as before.';

-- ---------------------------------------------------------------------------
-- 6) Crons. Driver stays scheduled permanently (self-healing convergence,
--    cheap no-op when nothing stale); nightly re-stale runs at 05:10 UTC,
--    after the realm refresh chain ends with tier at 04:50. SET-first is the
--    load-bearing timeout mechanic (see header). Idempotent scheduling.
-- ---------------------------------------------------------------------------

select cron.unschedule(jobid)
from cron.job
where jobname = 'realm-similar-drive-5m';

select cron.schedule(
  'realm-similar-drive-5m',
  '*/5 * * * *',
  $cmd$set statement_timeout = '600s'; select public.rebuild_media_similar_titles(300);$cmd$
);

select cron.unschedule(jobid)
from cron.job
where jobname = 'realm-similar-nightly';

select cron.schedule(
  'realm-similar-nightly',
  '10 5 * * *',
  $cmd$update public.media_similar_seed_state set stale = true where stale = false;$cmd$
);

commit;
