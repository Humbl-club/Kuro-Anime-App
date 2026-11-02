-- Serving hardening v1 (2026-08-06) — second wave of deep-review fixes.
-- Functions are recreated from their CURRENT repo definitions (newest
-- 202608xx files + 20260806010000); signatures, OUT shapes, ordering, and
-- grants unchanged. Idempotent: CREATE OR REPLACE / INSERT ... ON CONFLICT /
-- targeted DELETE+UPDATE with WHERE / unschedule-then-schedule. SET
-- search_path on every function. No bare DELETE/UPDATE without WHERE.
--
-- 1) Own-franchise exclusion at the serving read path
--    (recommend_ids_similar_to_seeds; live def 20260804130000, re-finalized
--    20260804140000 — the 20260805120000/140000/150000 forks touched only the
--    builder, so 140000 IS the newest RPC body). Live store probe: seed 134
--    (AoT Final P2) served media_id 20 (same component_label 2), 2163
--    (Chronicle — orphan singleton), 12941 (Crimson Bow — orphan recap
--    component 2452). Fix: candidates sharing a media_franchise_components
--    label with ANY seed are filtered at read time on ALL THREE paths (both
--    _recommend_ids_similar_to_seeds_live fallbacks and the store `visible`
--    CTE — store rows carry no stage marker, so edge AND cosine rows are
--    covered with no store rebuild). The RPC is SECURITY DEFINER, so it
--    reads the client-invisible components table as owner directly.
--
-- 2) Compilation bridges (data). AniList carries NO same-type edge between
--    the recap/compilation movies and their parent series (the recap
--    components float free, defeating the entry-point mapping and the
--    franchise caps). Editorial bridges, source = 'editorial' — the
--    Danganronpa-bridge pattern (20260805140000): the relations worker
--    deletes only source = 'anilist' rows per refresh, and the table's
--    unique key includes source, so bridges survive and never collide.
--    relation_type = 'SIDE_STORY': COMPILATION is not a legal value (the
--    importer's SUPPORTED_RELATIONS = SOURCE/ADAPTATION/PREQUEL/SEQUEL/
--    SIDE_STORY/SPIN_OFF — scripts/media_relations_worker.js); SIDE_STORY
--    is the closest legal type for a recap/compilation. Both directions are
--    stored (SIDE_STORY is symmetric), mirroring the importer convention.
--    Bridges (kuro internal ids, verified against the live catalog
--    2026-08-06):
--      AoT S1 (2)          -> 12941 (Part I: Crimson Bow and Arrow, S1 recap)
--      AoT S1 (2)          -> 2452  (Part II: Wings of Freedom, S1 recap)
--      AoT S2 (10)         -> 22396 (The Roar of Awakening, S2 recap)
--      AoT S1 (2)          -> 2163  (~Chronicle~, series compilation; 2 is the
--                                  chain root 2->10->17->27->20->134->298 and
--                                  the franchise entry point — most central)
--      Haikyuu S1 (30)     -> 2549  (The End and the Beginning, S1 recap)
--      Haikyuu S1 (30)     -> 13155 (The Winner and the Loser, S1 recap)
--      Haikyuu S3 (156)    -> 15790 (Talent and Sense, S3 recap)
--      Haikyuu S3 (156)    -> 12928 (Battle of Concepts, S3 recap)
--      Mob Psycho 100 (22) -> 2047  (REIGEN, S1 recap OVA)
--    Then: media_franchise_components refreshed IN THIS MIGRATION (no
--    standalone rebuild function exists — the refresh lives inside
--    rebuild_media_similar_titles' universe sync; the byte-identical CTE +
--    targeted delete + insert-on-conflict is the 20260805140000 §0b
--    pattern), and every seed in the touched (post-merge) components is
--    re-staled so the builder re-runs entry-point mapping on them.
--
-- 3) Hidden gem argument HTML (fetch_realm_hidden_gem; live def
--    20260806010000). The argument now falls back to display-cased
--    description, which still carries AniList markup (<i>, <br>) and
--    "(Source: ...)" scraper tails. New immutable helper
--    public._discover_sanitize_synopsis mirrors TextNormalization's
--    sanitizeMediaDescription (Kuro/Services/TextNormalization.swift) for
--    one-line display — strip tags, decode the common entities, drop
--    "(source: ...)" tails, collapse whitespace — applied at selection time
--    in both scored branches, BEFORE the 320-char sentence trim (a trim must
--    never cut mid-tag). No pre-existing SQL helper; the Swift one is
--    client-side only.
--
-- 4) Edge-floor asymmetry (rebuild_media_similar_titles; live def
--    20260805150000). The edge floor greatest(2.6, ...) sat above the cosine
--    cap 2.5, so a penalized edge could never fall below a clean cosine row.
--    Floor 2.6 -> 2.4 (both stage expressions + comments): penalized edges
--    may sink into the cosine band. NOTHING else in the builder changes.
--
-- 5) Cron timeout guards: realm-membership-refresh (30 4 * * *) and
--    realm-affinity-refresh (40 4 * * *) rescheduled with the SET-first
--    command pattern realm-tier-refresh got in 20260804120000/121000 —
--    schedules and refresh commands byte-identical to 20260731150000, only
--    the leading `set statement_timeout = '600s';` is new (pg_cron here runs
--    over libpq/simple protocol: each statement in the command string gets
--    its own timeout arming). Uses cron.unschedule(jobid)+cron.schedule(...)
--    only — no direct cron.job DML (not permitted to the migration role).
--
-- 6) GDPR orphan: discover_rail_impressions (user_id TEXT, 20260326221000)
--    survived account deletion. The delete-account edge function delegates
--    DB deletion to delete_user_concierge_data(p_user_id) (called with the
--    user's own JWT; SECURITY DEFINER, caller = auth.uid() self-check) — so
--    the fix belongs in the helper and NO edge-function edit is needed:
--    impressions rows leave in the same RPC call as the rest. Helper
--    recreated byte-identical from its newest def (20260305153000) plus the
--    impressions DELETE (text compare against p_user_id) and its count in
--    the returned jsonb.

begin;

-- ---------------------------------------------------------------------------
-- 3a) _discover_sanitize_synopsis — the sanitizer helper (used by item 3).
-- ---------------------------------------------------------------------------

create or replace function public._discover_sanitize_synopsis(p_text text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  -- Mirrors TextNormalization.sanitizeMediaDescription for one-line display:
  -- <br>/</p> become spaces (one-line card), every other tag vanishes WITHOUT
  -- a space (inline markup: "Kuroshitsuji</i>:" -> "Kuroshitsuji:"), then
  -- "(Source: ...)" scraper tails, entity decode, whitespace collapse.
  -- &amp; decodes LAST so a literal "&amp;lt;" becomes "&lt;" text, not a
  -- "<" character. Empty -> null so callers' nullif/coalesce fallbacks work.
  with s0 as (select coalesce(p_text, '') as t),
  s1 as (select regexp_replace(t, '<br\s*/?>', ' ', 'gi') as t from s0),
  s2 as (select regexp_replace(t, '</p\s*>', ' ', 'gi') as t from s1),
  s3 as (select regexp_replace(t, '<[^>]+>', '', 'gi') as t from s2),
  s4 as (select regexp_replace(t, '\s*\(source:[^)]*\)', '', 'gi') as t from s3),
  s5 as (select replace(t, '&nbsp;', ' ') as t from s4),
  s6 as (select replace(t, '&quot;', '"') as t from s5),
  s7 as (select replace(t, '&#39;', '''') as t from s6),
  s8 as (select replace(t, '&#x27;', '''') as t from s7),
  s9 as (select replace(t, '&lt;', '<') as t from s8),
  s10 as (select replace(t, '&gt;', '>') as t from s9),
  s11 as (select replace(t, '&amp;', '&') as t from s10),
  sa as (select regexp_replace(t, '\s+', ' ', 'g') as t from s11)
  select nullif(btrim(t), '') from sa;
$$;

revoke all on function public._discover_sanitize_synopsis(text) from public;
grant execute on function public._discover_sanitize_synopsis(text) to authenticated, service_role;

comment on function public._discover_sanitize_synopsis(text) is
  'Serving hardening v1 (20260806020000): SQL mirror of TextNormalization.sanitizeMediaDescription (Kuro/Services/TextNormalization.swift) for one-line serving text — strips AniList HTML tags and "(Source: ...)" scraper tails, decodes common entities, collapses whitespace; empty collapses to null. Used by fetch_realm_hidden_gem at selection time, before _discover_sentence_trim.';

-- ---------------------------------------------------------------------------
-- 1) recommend_ids_similar_to_seeds — own-franchise exclusion at read time.
-- ---------------------------------------------------------------------------

create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_has_pre boolean;
begin
  -- Gimmick calls: the baked score already contains the penalty term and the
  -- stored top-30 was selected under penalty ordering — serve them live.
  if coalesce(p_allow_gimmicks, false) then
    return query
    select l.media_id, l.overlap_count, l.score
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l
    where not exists (
      -- Own-franchise exclusion (20260806020000): never serve a member of a
      -- seed's OWN franchise component (sequel-in-rail / recap-in-rail).
      -- Singleton candidates (no component row) share a cluster with no seed.
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = l.media_id
        and ss.media_id = any(p_seed_ids)
    );
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
    from public._recommend_ids_similar_to_seeds_live(p_media_type, p_seed_ids, p_limit, p_allow_gimmicks) l
    where not exists (
      -- Own-franchise exclusion (20260806020000): never serve a member of a
      -- seed's OWN franchise component (sequel-in-rail / recap-in-rail).
      -- Singleton candidates (no component row) share a cluster with no seed.
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = l.media_id
        and ss.media_id = any(p_seed_ids)
    );
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
  ),
  visible as (
    -- Per-user exclusion BEFORE franchise dedupe (live-scorer order: the
    -- user_lists filter sits inside `ranked`, franchise DISTINCT ON after),
    -- so an excluded best member yields its franchise slot to the next-best
    -- member instead of erasing the franchise from the results.
    select b.cand_id, b.oc, b.sc,
           coalesce(a.popularity, m.popularity, 0) as pop
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
    -- Own-franchise exclusion (20260806020000): the read-time filter that
    -- kills sequel-in-rail and recap-in-rail for all seeds WITHOUT a store
    -- rebuild — store rows carry no stage marker, so this covers Stage A
    -- edge rows and Stage B cosine rows alike. A candidate sharing a
    -- franchise component with ANY seed is dropped; singleton candidates
    -- (no component row) are kept: they share a cluster with no seed, and
    -- seeds themselves are already excluded in `hits`.
    and not exists (
      select 1
      from public.media_franchise_components cc
      join public.media_franchise_components ss
        on ss.media_type = cc.media_type
       and ss.component_label = cc.component_label
      where cc.media_type = p_media_type
        and cc.media_id = b.cand_id
        and ss.media_id = any(p_seed_ids)
    )
  ),
  franchise_deduped as (
    -- 20260804140000 (finding 3): each per-seed store is franchise-deduped at
    -- build time, but a multi-seed blend could still carry two members of the
    -- same franchise (each seed contributed its own best member). Keep only
    -- the highest-blended entry per component; singletons label as themselves
    -- (collision-free: a component's min-member label is itself a member).
    -- Single-seed calls collapse nothing here — the store already deduped.
    select distinct on (coalesce(fc.component_label, v.cand_id))
      v.cand_id, v.oc, v.sc, v.pop
    from visible v
    left join public.media_franchise_components fc
      on fc.media_type = p_media_type and fc.media_id = v.cand_id
    order by coalesce(fc.component_label, v.cand_id),
             v.sc desc, v.pop desc, v.cand_id desc
  )
  select d.cand_id, d.oc, d.sc
  from franchise_deduped d
  order by d.sc desc, d.pop desc, d.cand_id desc
  limit (select req.lim from req);
end;
$$;

revoke all on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) from public;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon, authenticated;

comment on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) is
  'Realm repair Fix 5 (20260804130000, loop-2 20260804140000): serves similar titles from the precomputed media_similar_titles store (indexed read + multi-seed sum-blend + per-user user_lists exclusion + franchise dedupe over the blended set via media_franchise_components). Falls back to _recommend_ids_similar_to_seeds_live when no seed has precomputed rows or p_allow_gimmicks = true. Same signature/shape/grants as before. 20260806020000: own-franchise exclusion on all three paths — candidates sharing a media_franchise_components label with ANY seed are filtered at read time (covers edge and cosine store rows; no rebuild needed).';

-- ---------------------------------------------------------------------------
-- 2) Compilation bridges + components refresh + re-stale.
-- ---------------------------------------------------------------------------

insert into public.media_relations
  (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
values
  ('ANIME', 2,   'SIDE_STORY', 'ANIME', 12941, 'editorial'),
  ('ANIME', 12941, 'SIDE_STORY', 'ANIME', 2,   'editorial'),
  ('ANIME', 2,   'SIDE_STORY', 'ANIME', 2452,  'editorial'),
  ('ANIME', 2452,  'SIDE_STORY', 'ANIME', 2,   'editorial'),
  ('ANIME', 10,  'SIDE_STORY', 'ANIME', 22396, 'editorial'),
  ('ANIME', 22396, 'SIDE_STORY', 'ANIME', 10,  'editorial'),
  ('ANIME', 2,   'SIDE_STORY', 'ANIME', 2163,  'editorial'),
  ('ANIME', 2163,  'SIDE_STORY', 'ANIME', 2,   'editorial'),
  ('ANIME', 30,  'SIDE_STORY', 'ANIME', 2549,  'editorial'),
  ('ANIME', 2549,  'SIDE_STORY', 'ANIME', 30,  'editorial'),
  ('ANIME', 30,  'SIDE_STORY', 'ANIME', 13155, 'editorial'),
  ('ANIME', 13155, 'SIDE_STORY', 'ANIME', 30,  'editorial'),
  ('ANIME', 156, 'SIDE_STORY', 'ANIME', 15790, 'editorial'),
  ('ANIME', 15790, 'SIDE_STORY', 'ANIME', 156, 'editorial'),
  ('ANIME', 156, 'SIDE_STORY', 'ANIME', 12928, 'editorial'),
  ('ANIME', 12928, 'SIDE_STORY', 'ANIME', 156, 'editorial'),
  ('ANIME', 22,  'SIDE_STORY', 'ANIME', 2047,  'editorial'),
  ('ANIME', 2047,  'SIDE_STORY', 'ANIME', 22,  'editorial')
on conflict (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
do nothing;

-- Components refresh NOW (byte-identical CTE to the builder's universe-sync
-- refresh; 20260804140000 populate / 20260805140000 §0b pattern) so the
-- re-stale below and the next serving reads compute on the BRIDGED
-- components at commit time instead of waiting one driver cadence.

drop table if exists pg_temp._mfc_now;
create temp table _mfc_now on commit drop as
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
  select 1 from pg_temp._mfc_now f
  where f.media_type = c.media_type
    and f.media_id = c.media_id
    and f.label = c.component_label
);

insert into public.media_franchise_components (media_type, media_id, component_label)
select f.media_type, f.media_id, f.label
from pg_temp._mfc_now f
on conflict (media_type, media_id) do nothing;

-- Re-stale every seed whose component membership changed: all seeds in the
-- touched (post-merge) components — the AoT main/recap components, the
-- Haikyuu TV/recap components, and the Mob Psycho component. Their stored
-- rails are also handled at read time by item 1, but the rebuild re-runs
-- Stage-A franchise anti-joins and entry-point mapping on the merged
-- components (the recaps stop being their own entry points).
update public.media_similar_seed_state st
set stale = true
where exists (
  select 1
  from public.media_franchise_components fc
  join public.media_franchise_components touched
    on touched.media_type = fc.media_type
   and touched.component_label = fc.component_label
  where fc.media_type = st.seed_media_type
    and fc.media_id = st.seed_media_id
    and touched.media_type = 'ANIME'
    and touched.media_id in (2, 10, 12941, 2452, 22396, 2163,
                             30, 156, 2549, 13155, 15790, 12928,
                             22, 2047)
);

-- ---------------------------------------------------------------------------
-- 3) fetch_realm_hidden_gem — sanitize markup + scraper tails at selection.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_realm_hidden_gem()
returns table (
  realm text,
  display_name text,
  blurb text,
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
  v_realm text;
  v_display text;
  v_blurb text;
  v_week int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb into v_display, v_blurb
  from public.realm_meta rm where rm.realm = v_realm;

  v_week := (extract(epoch from date_trunc('week', now() at time zone 'utc')) / 86400)::int;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and t.tier in ('canon', 'acclaimed')
      and m.weight >= 0.35
  ),
  fr_labels as (
    -- One materialization of the franchise labels (referenced by
    -- known_franchises and both scored branches).
    select fc.media_type, fc.media_id, fc.component_label
    from public._franchise_component_labels() fc
  ),
  known_franchises as (
    -- Franchise-familiarity (20260806010000): components containing any title
    -- the user already knows — on their list, or deck-signalled love/known
    -- (deck_skip is disinterest in that title, not franchise familiarity).
    -- Driven from the user's own rows (small) joined to labels, never a
    -- full components scan per candidate.
    select distinct fc.media_type, fc.component_label
    from (
      select
        case when ul.media_type = 'anime' then 'ANIME' else 'MANGA' end as mt,
        ul.media_id as mid
      from public.user_lists ul
      where ul.user_id = v_uid::text
      union
      select e.media_type, e.media_id
      from public.taste_signal_events e
      where e.user_id = v_uid
        and e.event_type in ('deck_love', 'deck_known')
    ) k
    join fr_labels fc
      on fc.media_type = k.mt
     and fc.media_id = k.mid
  ),
  scored as (
    select
      p.media_type,
      p.media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.banner_image,
      a.genres,
      a.average_score as score,
      coalesce(a.season_year, a.start_date_year) as year,
      a.format,
      coalesce(a.popularity, 0) as popularity,
      public._discover_sanitize_synopsis(
        case
          when a.synopsis_enhanced_state = 'ready'
           and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
            then a.synopsis_enhanced
          else a.description
        end
      ) as argument,
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      ) as has_seasonal
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    left join fr_labels fc
      on fc.media_type = p.media_type
     and fc.media_id = p.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
      and coalesce(a.average_score, 0) >= 75
      and coalesce(a.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'anime' and ul.media_id = a.id
      )
      and not exists (
        select 1 from known_franchises kf
        where kf.media_type = p.media_type
          and kf.component_label = fc.component_label
      )

    union all

    select
      p.media_type,
      p.media_id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      coalesce(m.popularity, 0),
      public._discover_sanitize_synopsis(
        case
          when m.synopsis_enhanced_state = 'ready'
           and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
            then m.synopsis_enhanced
          else m.description
        end
      ),
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      )
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    left join fr_labels fc
      on fc.media_type = p.media_type
     and fc.media_id = p.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
      and coalesce(m.average_score, 0) >= 75
      and coalesce(m.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'manga' and ul.media_id = m.id
      )
      and not exists (
        select 1 from known_franchises kf
        where kf.media_type = p.media_type
          and kf.component_label = fc.component_label
      )
  ),
  cut as (
    select s.*,
           percent_rank() over (order by s.popularity asc) as pop_pct,
           row_number() over (
             order by
               (case when s.has_seasonal then 0 else 1 end),
               (hashtext(s.media_type || ':' || s.media_id::text || ':' || v_week::text))
           ) as rn
    from scored s
  )
  select
    v_realm,
    v_display,
    v_blurb,
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.banner_image,
    c.genres,
    c.score,
    c.year,
    c.format,
    -- The One Thing treatment (20260731110000): sentence-trim at 320,
    -- capitalize the first letter; empty collapses to null.
    nullif(
      upper(left(t.argument, 1)) || substring(t.argument from 2),
    '') as argument
  from cut c
  cross join lateral (
    select public._discover_sentence_trim(
      coalesce(nullif(c.argument, ''), v_blurb),
      320
    ) as argument
  ) t
  where c.pop_pct <= 0.55 or c.has_seasonal
  order by c.rn
  limit 1;
end;
$$;

revoke all on function public.fetch_realm_hidden_gem() from public;
grant execute on function public.fetch_realm_hidden_gem() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) rebuild_media_similar_titles — edge floor 2.6 -> 2.4 (only change).
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

  -- Entry-point sync (20260805140000): refresh media_franchise_entry_points
  -- from the just-refreshed components. Entry = the member a newcomer should
  -- start with: format preference (ANIME: TV first; MANGA: MANGA first), then
  -- earliest start_date_year (nulls last), then lowest id; the member must be
  -- non-adult and have a cover. Components where NO member passes visibility
  -- get no row (the mapping then keeps the original candidate). Same targeted
  -- delete + insert-on-conflict pattern as the component refresh above
  -- (pg_safeupdate-clean; ~10k member rows joined by PK — trivial per fire).

  drop table if exists pg_temp._epn;
  create temp table _epn on commit drop as
  select x.media_type, x.component_label, x.media_id as entry_media_id
  from (
    select c.media_type, c.component_label, c.media_id,
           row_number() over (
             partition by c.media_type, c.component_label
             order by case when a.format = 'TV' then 0 else 1 end,
                      a.start_date_year asc nulls last,
                      c.media_id asc) as rn
    from public.media_franchise_components c
    join public.anime a on c.media_type = 'ANIME' and a.id = c.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
    union all
    select c.media_type, c.component_label, c.media_id,
           row_number() over (
             partition by c.media_type, c.component_label
             order by case when m.format = 'MANGA' then 0 else 1 end,
                      m.start_date_year asc nulls last,
                      c.media_id asc) as rn
    from public.media_franchise_components c
    join public.manga m on c.media_type = 'MANGA' and m.id = c.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
  ) x
  where x.rn = 1;

  delete from public.media_franchise_entry_points e
  where not exists (
    select 1 from pg_temp._epn f
    where f.media_type = e.media_type
      and f.component_label = e.component_label
      and f.entry_media_id = e.entry_media_id
  );

  insert into public.media_franchise_entry_points (media_type, component_label, entry_media_id)
  select f.media_type, f.component_label, f.entry_media_id
  from pg_temp._epn f
  on conflict (media_type, component_label) do nothing;

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

  -- Entry-point snapshot (20260805140000): per-component natural entry, read
  -- by the Stage A/B candidate->entry mapping in both sub-pipelines.
  drop table if exists pg_temp._ep;
  create temp table _ep on commit drop as
  select e.media_type, e.component_label, e.entry_media_id
  from public.media_franchise_entry_points e;
  create index on pg_temp._ep (media_type, component_label);

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
    select b.sid as seed_id,
           -- Entry-point canonicalization (20260805140000): a rail recommends
           -- a FRANCHISE via its entry point. If the edge candidate is a
           -- mid-franchise member and its component's entry passes this
           -- stage's gates (pool = non-adult/cover/no-Hentai-Ecchi; tier:
           -- within seed distance 1 OR an upward/equal-tier substitution —
           -- 20260805150000; canon-seed merit floor), serve the entry instead,
           -- carrying the candidate's rating/penalty/popularity unchanged.
           -- If the entry fails a gate, keep the original candidate.
           case
             when ep.entry_media_id is not null
              and pe.media_id is not null
              and (sa.tier_rank is null
                   or abs(coalesce(etr.r, 2) - sa.tier_rank) <= 1
                   or coalesce(etr.r, 2) >= coalesce(ctr.r, 2))
              and (coalesce(sa.tier_rank, 0) < 4 or pe.avg_score >= 75 or ebl.anilist_id is not null)
             then ep.entry_media_id
             else e.to_media_id
           end as cand_id,
           e.rating,
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
    left join pg_temp._ep ep
      on ep.media_type = 'ANIME' and ep.component_label = fc.label
     and ep.entry_media_id <> e.to_media_id
    left join pg_temp._pool_a pe on pe.media_id = ep.entry_media_id
    left join pg_temp._trank etr on etr.media_type = 'ANIME' and etr.media_id = ep.entry_media_id
    left join pg_temp._bless_a ebl on ebl.anilist_id = pe.anilist_id
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
    -- + penalty, floored at 2.4 (20260806020000: was 2.6 — the floor sat above
    -- the cosine cap 2.5, so a penalized edge could never sink below a clean
    -- cosine row; 2.4 lets penalized edges fall into the cosine band).
    drop table if exists pg_temp._edge_a;
    create temp table _edge_a on commit drop as
    select s.seed_id, s.cand_id, s.rating, s.label, s.score,
           row_number() over (partition by s.seed_id
                              order by s.score desc, s.rating desc, s.popularity desc, s.cand_id desc) as rn
    from (
      select d.seed_id, d.cand_id, d.rating, d.popularity, d.label,
             greatest(2.4,
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
        s.seed_id,
        -- Entry-point canonicalization (20260805140000): same mapping as
        -- Stage A (gates: pool; tier within seed distance 1 OR upward/equal
        -- substitution — 20260805150000; canon merit floor), carrying
        -- the winning candidate's score; the label is component-invariant so
        -- the DISTINCT ON dedupe and the Stage-A label anti-join below are
        -- unaffected. The ep join skips the seed's OWN component (those rows
        -- keep pre-fork behavior — never remapped toward the seed itself).
        case
          when ep.entry_media_id is not null
           and pe.media_id is not null
           and (sa.tier_rank is null
                or abs(coalesce(etr.r, 2) - sa.tier_rank) <= 1
                or coalesce(etr.r, 2) >= coalesce(ctr.r, 2))
           and (coalesce(sa.tier_rank, 0) < 4 or pe.avg_score >= 75 or ebl.anilist_id is not null)
          then ep.entry_media_id
          else s.cand_id
        end as cand_id,
        s.overlap, s.score, s.popularity,
        coalesce(f.label, s.cand_id) as label
      from pg_temp._scored_a s
      join pg_temp._seed_attr_a sa on sa.seed_id = s.seed_id
      left join pg_temp._fr f on f.media_type = 'ANIME' and f.media_id = s.cand_id
      left join pg_temp._fr fs on fs.media_type = 'ANIME' and fs.media_id = s.seed_id
      left join pg_temp._trank ctr on ctr.media_type = 'ANIME' and ctr.media_id = s.cand_id
      left join pg_temp._ep ep
        on ep.media_type = 'ANIME' and ep.component_label = f.label
       and ep.entry_media_id <> s.cand_id
       and coalesce(f.label, s.cand_id) <> coalesce(fs.label, s.seed_id)
      left join pg_temp._pool_a pe on pe.media_id = ep.entry_media_id
      left join pg_temp._trank etr on etr.media_type = 'ANIME' and etr.media_id = ep.entry_media_id
      left join pg_temp._bless_a ebl on ebl.anilist_id = pe.anilist_id
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
    select b.sid as seed_id,
           -- Entry-point canonicalization (20260805140000): a rail recommends
           -- a FRANCHISE via its entry point. If the edge candidate is a
           -- mid-franchise member and its component's entry passes this
           -- stage's gates (pool = non-adult/cover/no-Hentai-Ecchi; tier:
           -- within seed distance 1 OR an upward/equal-tier substitution —
           -- 20260805150000; canon-seed merit floor), serve the entry instead,
           -- carrying the candidate's rating/penalty/popularity unchanged.
           -- If the entry fails a gate, keep the original candidate.
           case
             when ep.entry_media_id is not null
              and pe.media_id is not null
              and (sa.tier_rank is null
                   or abs(coalesce(etr.r, 2) - sa.tier_rank) <= 1
                   or coalesce(etr.r, 2) >= coalesce(ctr.r, 2))
              and (coalesce(sa.tier_rank, 0) < 4 or pe.avg_score >= 75 or ebl.anilist_id is not null)
             then ep.entry_media_id
             else e.to_media_id
           end as cand_id,
           e.rating,
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
    left join pg_temp._ep ep
      on ep.media_type = 'MANGA' and ep.component_label = fc.label
     and ep.entry_media_id <> e.to_media_id
    left join pg_temp._pool_m pe on pe.media_id = ep.entry_media_id
    left join pg_temp._trank etr on etr.media_type = 'MANGA' and etr.media_id = ep.entry_media_id
    left join pg_temp._bless_m ebl on ebl.anilist_id = pe.anilist_id
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
             greatest(2.4,
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
        s.seed_id,
        -- Entry-point canonicalization (20260805140000): same mapping as
        -- Stage A (gates: pool; tier within seed distance 1 OR upward/equal
        -- substitution — 20260805150000; canon merit floor), carrying
        -- the winning candidate's score; the label is component-invariant so
        -- the DISTINCT ON dedupe and the Stage-A label anti-join below are
        -- unaffected. The ep join skips the seed's OWN component (those rows
        -- keep pre-fork behavior — never remapped toward the seed itself).
        case
          when ep.entry_media_id is not null
           and pe.media_id is not null
           and (sa.tier_rank is null
                or abs(coalesce(etr.r, 2) - sa.tier_rank) <= 1
                or coalesce(etr.r, 2) >= coalesce(ctr.r, 2))
           and (coalesce(sa.tier_rank, 0) < 4 or pe.avg_score >= 75 or ebl.anilist_id is not null)
          then ep.entry_media_id
          else s.cand_id
        end as cand_id,
        s.overlap, s.score, s.popularity,
        coalesce(f.label, s.cand_id) as label
      from pg_temp._scored_m s
      join pg_temp._seed_attr_m sa on sa.seed_id = s.seed_id
      left join pg_temp._fr f on f.media_type = 'MANGA' and f.media_id = s.cand_id
      left join pg_temp._fr fs on fs.media_type = 'MANGA' and fs.media_id = s.seed_id
      left join pg_temp._trank ctr on ctr.media_type = 'MANGA' and ctr.media_id = s.cand_id
      left join pg_temp._ep ep
        on ep.media_type = 'MANGA' and ep.component_label = f.label
       and ep.entry_media_id <> s.cand_id
       and coalesce(f.label, s.cand_id) <> coalesce(fs.label, s.seed_id)
      left join pg_temp._pool_m pe on pe.media_id = ep.entry_media_id
      left join pg_temp._trank etr on etr.media_type = 'MANGA' and etr.media_id = ep.entry_media_id
      left join pg_temp._bless_m ebl on ebl.anilist_id = pe.anilist_id
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
  'Realm repair Fix 5 (20260804130000/140000; edges-first fork 20260805120000; entry-point canonicalization 20260805140000/150000): batched set-based rebuild of media_similar_titles — syncs the visible seed universe, media_franchise_components AND media_franchise_entry_points, takes up to p_batch stale seeds (default 100 — Micro-instance sizing), and per seed serves Stage A media_rec_edges (KEEP-checked; score 3.0 + per-seed min-max of rating + penalty, floored 2.4 since 20260806020000 — penalized edges may sink into the cosine band) above Stage B cosine backfill to depth 30, mapping each candidate to its franchise component''s entry point when the entry passes the gates (pool; tier within seed distance 1 OR upward/equal-tier substitution; canon merit floor — original candidate kept otherwise), swapping delete-then-insert. Aborts with DETAIL STAGE_EMPTY_ANOMALY if >= 50 seeds produce 0 total rows. Returns seeds processed, 0 when converged, -1 when the advisory lock is held. service_role-only EXECUTE; crons SET statement_timeout as their own first statement. Revert: restore the 20260805140000 builder body.';

-- ---------------------------------------------------------------------------
-- 5) Cron timeout guards — same jobs/schedules as 20260731150000, SET-first
--    commands (the realm-tier-refresh pattern, 20260804120000).
-- ---------------------------------------------------------------------------

select cron.unschedule(jobid)
from cron.job
where jobname in ('realm-membership-refresh', 'realm-affinity-refresh');

select cron.schedule(
  'realm-membership-refresh',
  '30 4 * * *',
  $cmd$set statement_timeout = '600s'; refresh materialized view concurrently public.media_realm_membership;$cmd$
);

select cron.schedule(
  'realm-affinity-refresh',
  '40 4 * * *',
  $cmd$set statement_timeout = '600s'; refresh materialized view concurrently public.realm_affinity;$cmd$
);

-- ---------------------------------------------------------------------------
-- 6) GDPR: delete_user_concierge_data gains discover_rail_impressions.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_user_concierge_data(p_user_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  caller uuid;
  deleted_counts jsonb := '{}'::jsonb;
  cnt integer;
BEGIN
  caller := auth.uid();
  IF caller IS NULL THEN
    RETURN jsonb_build_object('error', 'unauthenticated');
  END IF;

  IF caller::text <> p_user_id THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  BEGIN
    uid := p_user_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('error', 'invalid_user_id');
  END;

  -- text-keyed telemetry/feedback tables
  DELETE FROM public.concierge_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_events', cnt);

  DELETE FROM public.rag_retrieval_feedback WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('rag_retrieval_feedback', cnt);

  -- uuid-keyed concierge core tables
  DELETE FROM public.concierge_parse_feedback WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_parse_feedback', cnt);

  DELETE FROM public.concierge_runs WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_runs', cnt);

  DELETE FROM public.concierge_mode_cache WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_mode_cache', cnt);

  DELETE FROM public.title_aliases WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_aliases', cnt);

  -- import tables (import_sessions.user_id is uuid)
  DELETE FROM public.import_session_items i
  USING public.import_sessions s
  WHERE i.session_id = s.id AND s.user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_session_items', cnt);

  DELETE FROM public.import_sessions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_sessions', cnt);

  -- usage/profile tables
  DELETE FROM public.llm_daily_usage WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('llm_daily_usage', cnt);

  DELETE FROM public.user_taste_profiles WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_taste_profiles', cnt);

  -- social + club tables
  DELETE FROM public.club_analytics WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_analytics', cnt);

  DELETE FROM public.title_comment_reactions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comment_reactions', cnt);

  DELETE FROM public.title_comments WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comments', cnt);

  -- streaming preferences
  DELETE FROM public.user_streaming_services WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_streaming_services', cnt);

  -- discover rail impressions (20260806020000 GDPR orphan fix; user_id is
  -- TEXT on this table, 20260326221000 — compare against p_user_id, not uid)
  DELETE FROM public.discover_rail_impressions WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('discover_rail_impressions', cnt);

  RETURN jsonb_build_object('success', true, 'deleted', deleted_counts);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_concierge_data(text) TO authenticated;

commit;
