-- Realm repair Phase 1, Fixes 3+4 (spec: 2026-08-04-realm-repair-and-critique-plan.md §3.3/§3.4).
--
-- FIX 3 — media_realm_tier rebuilt FROM EFFECTIVE membership (split-brain closed).
--   History: 20260802123000 introduced media_realm_membership_effective (rules
--   matview + LLM deltas, FULL OUTER JOIN) and switched the similarity gates to
--   it — but media_realm_tier stayed a matview built from the RAW rules matview.
--   Result: similarity judged membership on one universe, tier on another
--   (split-brain), and ~2,200 visible titles with effective membership had NO
--   tier row at all (429 of them at weight >= 0.35), so the tier gate silently
--   dropped them from every recommendation.
--   This migration converts media_realm_tier to a plain TABLE (same name, same
--   columns media_type/media_id/realm/tier, same unique index) rebuilt by
--   rebuild_media_realm_tier(), whose tier SELECT reads
--   media_realm_membership_effective for BOTH the top-realm assignment and the
--   percentile basis. All other tier semantics are unchanged byte-for-byte from
--   20260731150000: acclaim percentile within realm (canon >= p97, acclaimed
--   >= p85, solid >= p60, else tail), canon_seed forcing via anilist_id, craft
--   lift (director/author with >= 2 other pre-lift canon works lifts one tier),
--   one row per (media_type, media_id).
--
-- FIX 4 — the refresh actually succeeds on schedule.
--   History: the nightly `realm-tier-refresh` cron (04:50 UTC, 20260731150000)
--   ran `refresh materialized view concurrently public.media_realm_tier;` as
--   role postgres, whose role-level statement_timeout is 2min. It failed 4/4
--   runs (2026-08-01..04), each killed at exactly 120s ("canceling statement
--   due to statement timeout"), so tier data had been frozen at its CREATE-time
--   contents. A `SET statement_timeout` INSIDE a function cannot rescue the
--   statement that is already running (the timeout timer is armed once per
--   top-level statement, at statement start; mid-statement GUC changes do not
--   re-arm it) — so the new cron command raises the timeout as its OWN first
--   statement, then invokes the rebuild as a second statement:
--     set statement_timeout = '600s'; select public.rebuild_media_realm_tier();
--   (pg_cron here runs jobs over libpq/simple protocol — use_background_workers
--   is off — so each statement in the command string gets its own timeout
--   arming, and the session-level SET from statement 1 governs statement 2.)
--   The rebuild is STAGED: the expensive SELECT lands in a temp table with no
--   lock on the live table; the swap is a TRUNCATE + INSERT holding the
--   exclusive lock only for the small final copy (~57k rows, well under the old
--   2-minute ceiling), inside one transaction — readers see either the old or
--   the new contents, never an empty table.
--
-- MIGRATION POPULATION NOTE: the effective-membership build measured > 125s
--   under EXPLAIN ANALYZE and could not be bounded above through the inspection
--   gateway, so this migration does NOT run it in the migration transaction
--   (the exact failure mode that froze the matview). Instead the new table is
--   seeded with the outgoing matview's rows (fast copy) so the RPC and iOS
--   never see a missing/empty media_realm_tier, and the first
--   rebuild_media_realm_tier() run — invoked immediately post-push, then
--   nightly at 04:50 — replaces the seed with effective-membership data.
--
-- Dependents: media_realm_profile (view) is the only pg_depend dependent of the
--   matview; it is dropped and recreated byte-equivalent (same text, comment,
--   and grants as 20260731170000). Functions reading media_realm_tier
--   (recommend_ids_similar_to_seeds, fetch_taste_deck_batch, discover shelf
--   RPCs) resolve by name at call time and keep working unchanged.
--
-- Timeout inside the function is 600s (spec example said 300s): the build's
--   upper bound is unmeasured (> 125s instrumented); 600s buys headroom against
--   catalog growth while still failing fast enough to alarm within the night.

begin;

-- ---------------------------------------------------------------------------
-- 1) New table, seeded from the outgoing matview so it is never empty.
-- ---------------------------------------------------------------------------

create table public.media_realm_tier_next (
  media_type text    not null,
  media_id   integer not null,
  realm      text    not null,
  tier       text    not null
);

insert into public.media_realm_tier_next (media_type, media_id, realm, tier)
select media_type, media_id, realm, tier
from public.media_realm_tier;

-- ---------------------------------------------------------------------------
-- 2) Swap: drop the dependent view + matview, rename the table into place,
--    recreate the same-named indexes (names are freed by the matview drop).
-- ---------------------------------------------------------------------------

drop view public.media_realm_profile;
drop materialized view public.media_realm_tier;

alter table public.media_realm_tier_next rename to media_realm_tier;

create unique index media_realm_tier_uidx
  on public.media_realm_tier (media_type, media_id);
create index media_realm_tier_realm_idx
  on public.media_realm_tier (realm);

comment on table public.media_realm_tier is
  'Realm Graph: each title''s tier (canon/acclaimed/solid/tail) inside its TOP realm, built from media_realm_membership_effective (rules + LLM deltas) by rebuild_media_realm_tier() — plain table since 20260804120000 (the matview refresh timed out nightly). One row per (media_type, media_id).';

-- Plain table needs RLS (matview had none; reads were grant-gated only).
-- SELECT stays open to the same roles that could read the matview; writes are
-- default-deny for client roles (no write policies) — only the SECURITY
-- DEFINER rebuild (owner) touches rows.
alter table public.media_realm_tier enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'media_realm_tier'
      and policyname = 'media_realm_tier_select_all'
  ) then
    create policy media_realm_tier_select_all
      on public.media_realm_tier
      for select using (true);
  end if;
end $$;

-- Preserve the live read surface exactly (anon/authenticated/service_role all
-- held SELECT on the matview via default privileges). Default privileges also
-- hand write bits to anon/authenticated on CREATE TABLE — revoke those; they
-- were unusable on the matview (matviews reject direct DML), so the effective
-- grant surface is unchanged. M4 owns any further posture change.
revoke all on public.media_realm_tier from public, anon, authenticated;
grant select on public.media_realm_tier to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) media_realm_profile recreated byte-equivalent (text, comment, grants as
--    20260731170000; only the underlying relation changed matview -> table).
-- ---------------------------------------------------------------------------

create view public.media_realm_profile as
select
  t.media_type,
  t.media_id,
  case
    when t.media_type = 'ANIME' then coalesce(nullif(a.title_english, ''), a.title_romaji)
    else coalesce(nullif(m.title_english, ''), m.title_romaji)
  end as title,
  t.realm as top_realm,
  t.tier,
  l.realms as llm_realms,
  l.tone as llm_tone,
  l.register as llm_register,
  l.pacing as llm_pacing,
  l.descriptor as llm_descriptor,
  l.confidence as llm_confidence,
  l.model as llm_model,
  l.created_at as llm_at
from public.media_realm_tier t
left join public.anime a
  on t.media_type = 'ANIME' and a.id = t.media_id
left join public.manga m
  on t.media_type = 'MANGA' and m.id = t.media_id
left join public.media_realm_llm l
  on l.media_type = t.media_type and l.media_id = t.media_id;

comment on view public.media_realm_profile is
  'Realm Graph Stage 2b consumer read: one row per tiered title — membership top realm + tier (rules) plus the llm descriptor (realms/tone/register/pacing/descriptor/confidence) when written. Public read.';

revoke all on public.media_realm_profile from public, anon, authenticated;
grant select on public.media_realm_profile to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) rebuild_media_realm_tier(): staged rebuild from EFFECTIVE membership.
--    Tier SELECT = 20260731150000's matview query with media_realm_membership
--    replaced by media_realm_membership_effective in top_realm + realm_members;
--    everything else identical.
--    search_path appends pg_temp LAST (the documented SECURITY DEFINER hardening
--    — prevents temp-schema shadowing of public objects; the stage table is
--    referenced pg_temp-qualified).
--    No auth.role() guard on purpose (unlike recompute_media_realm_llm_deltas):
--    the nightly cron session runs as role postgres with no JWT claims, where
--    auth.role() is NULL and a guard would fail every scheduled run. EXECUTE
--    grants enforce service_role-only for client roles; the owner's implicit
--    EXECUTE is what the cron uses.
-- ---------------------------------------------------------------------------

create or replace function public.rebuild_media_realm_tier()
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _n integer;
begin
  -- Local raise for direct service_role/owner invocations whose session cap is
  -- already high enough to get past this statement's arming; the CRON command
  -- must (and does) raise the session statement_timeout BEFORE calling — a
  -- mid-statement change cannot re-arm the already-running statement's timer.
  set local statement_timeout = '600s';

  drop table if exists pg_temp._realm_tier_stage;

  -- STAGE: the expensive build touches only the temp table — no lock is taken
  -- on public.media_realm_tier while this runs.
  create temp table _realm_tier_stage on commit drop as
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
    -- exactly one row per title: its highest-weight EFFECTIVE membership
    -- (deterministic; same ordering as the 20260731150000 matview build).
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
      from public.media_realm_membership_effective m
    ) s
    where s.rn = 1
  ),
  realm_members as (
    -- the percentile basis: EFFECTIVE members of each realm at weight >= T.
    select
      m.media_type,
      m.media_id,
      m.realm,
      c.score,
      c.favourites
    from public.media_realm_membership_effective m
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

  select count(*) into _n from pg_temp._realm_tier_stage;
  if _n = 0 then
    -- Upstream matview empty/broken: keep serving the existing tier data
    -- rather than swapping in nothing.
    raise exception 'rebuild_media_realm_tier: staged build produced 0 rows; swap aborted'
      using detail = 'EMPTY_STAGE';
  end if;

  -- SWAP: exclusive lock held only for this small copy; the transaction makes
  -- it atomic (readers see old rows or new rows, never none). TRUNCATE, not
  -- bare DELETE (pg_safeupdate posture).
  truncate table public.media_realm_tier;

  insert into public.media_realm_tier (media_type, media_id, realm, tier)
  select media_type, media_id, realm, tier
  from pg_temp._realm_tier_stage;

  return _n;
end;
$$;

revoke all on function public.rebuild_media_realm_tier() from public;
grant execute on function public.rebuild_media_realm_tier() to service_role;

comment on function public.rebuild_media_realm_tier() is
  'Staged rebuild of media_realm_tier from media_realm_membership_effective (split-brain fix, 20260804120000): build into temp table, then TRUNCATE + INSERT swap in one transaction. service_role-only EXECUTE for client roles; nightly cron runs it as owner. Returns row count.';

-- ---------------------------------------------------------------------------
-- 5) Cron: replace the 0/4 failing matview refresh with the staged rebuild,
--    same jobname + schedule. The session-level SET is the load-bearing part
--    (see header). Idempotent: unschedule-if-exists first.
-- ---------------------------------------------------------------------------

select cron.unschedule(jobid)
from cron.job
where jobname = 'realm-tier-refresh';

select cron.schedule(
  'realm-tier-refresh',
  '50 4 * * *',
  $cmd$set statement_timeout = '600s'; select public.rebuild_media_realm_tier();$cmd$
);

commit;
