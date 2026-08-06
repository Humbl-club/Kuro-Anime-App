-- Serving fixes v1 (deep review, 2026-08-06) — three serving-side defects,
-- one migration. All function bodies are recreated from their current live
-- definitions; signatures, return shapes, ordering, and grants are unchanged.
-- Idempotent: CREATE OR REPLACE only, no data writes.
--
-- DEFECT 1 — Tonight's shelf franchise runaway (fetch_tonight_shelf, live def
--   20260802141000): the demo account got 6 of 12 shelf slots from Attack on
--   Titan. Fix: cap <= 2 titles per franchise cluster, labeled by
--   public.media_franchise_components (the single franchise source,
--   20260804140000), read through the new owner-read accessor
--   public._franchise_component_labels() (the components table is
--   client-invisible BY DESIGN — 20260804140000 — and these RPCs are SECURITY
--   INVOKER, the documented 20260805110000 ACL trap; a direct join would fail
--   permission-denied for authenticated callers). The cap is a running one:
--   each cluster keeps its two best entries under the existing shelf ordering
--   (tier_rank, average_score, membership weight, media_id); everything else
--   unchanged.
--
-- DEFECT 2 — Hidden gem argument is scraper text (fetch_realm_hidden_gem,
--   live def 20260802150000): the argument fell back to description_normalized
--   — the LOWERCASED search-normalization column — and served text like
--   "sequel to kuroshitsuji... (source: crunchyroll)". Fix: the same treatment
--   The One Thing got — display-cased description fallback with a non-empty
--   enhanced gate (20260805100000), sentence-trim via
--   public._discover_sentence_trim(..., 320) + capitalize first letter
--   (20260731110000). ALSO tightened selection: candidates whose franchise
--   component already has a member on the user's list OR deck-signalled
--   (deck_love / deck_known in taste_signal_events) are excluded — a gem from
--   a franchise the user already knows is not hidden. The relations walk is
--   the persistent components table via the accessor (cheap: one
--   materialized CTE + indexed user-row lookups), so the stronger
--   franchise-level exclusion is implemented rather than the sequel-only
--   minimum; no part deferred.
--
-- DEFECT 3 — Craft lift over-promotes (rebuild_media_realm_tier, live def
--   20260804120000 + 20260804121000 grants): Vending Machine (average_score
--   63) served as 'acclaimed' purely via canon-director lift. Fix: the lift
--   now requires the candidate's OWN average_score >= 70 (score is threaded
--   through base_tier/forced from cat; coalesce(...,0) means unknown scores
--   never lift). Lineage may elevate a good work, not rescue a poor one. The
--   forced-canon branch (canon_seed) is untouched. NO in-migration rebuild
--   (20260804120000 population note: the build exceeds the migration
--   transaction timeout) — the nightly realm-tier-refresh cron / first manual
--   service_role call applies the new guard.
--
-- SET search_path on every function; security definer helper appends pg_temp
-- LAST (the documented SECURITY DEFINER hardening, 20260804120000).

begin;

-- ---------------------------------------------------------------------------
-- 0) _franchise_component_labels — owner-read accessor for the deliberately
--    client-invisible media_franchise_components (20260804140000: "No client
--    grants on purpose"). SECURITY INVOKER serving RPCs (fetch_tonight_shelf,
--    fetch_realm_hidden_gem — granted to authenticated) cannot join that table
--    directly (20260805110000 documented the same trap for
--    media_realm_membership_effective's override layer); this SECURITY DEFINER
--    setof accessor exposes only catalog-id cluster labels (no user data) so
--    the invoker RPCs can franchise-cap/dedupe set-based.
-- ---------------------------------------------------------------------------

create or replace function public._franchise_component_labels()
returns table (media_type text, media_id integer, component_label integer)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select fc.media_type, fc.media_id, fc.component_label
  from public.media_franchise_components fc;
$$;

revoke all on function public._franchise_component_labels() from public, anon;
grant execute on function public._franchise_component_labels() to authenticated, service_role;

comment on function public._franchise_component_labels() is
  'Serving fixes v1 (20260806010000): owner-read (SECURITY DEFINER) accessor over media_franchise_components so SECURITY INVOKER serving RPCs can use franchise labels without granting clients SELECT on the table itself (20260804140000 posture: no client grants on purpose; 20260805110000 documented the invoker-RPC ACL trap). Labels are min member id per same-type connected component of media_relations; titles with no same-type relations have no row and label as themselves via coalesce at use sites (collision-free).';

-- ---------------------------------------------------------------------------
-- 1) fetch_tonight_shelf — franchise cap. Byte-identical to 20260802141000
--    except the final query gains the `capped` step (row_number per cluster,
--    keep rn <= 2) between `ranked` and the unchanged final select.
-- ---------------------------------------------------------------------------

create or replace function public.fetch_tonight_shelf(p_limit integer default 12)
returns table (
  realm text,
  display_name text,
  blurb text,
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
  volumes integer
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim int := greatest(1, least(coalesce(p_limit, 12), 40));
  v_realm text;
  v_display text;
  v_blurb text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb
    into v_display, v_blurb
  from public.realm_meta rm
  where rm.realm = v_realm;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier,
      case t.tier
        when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1
      end as tier_rank,
      m.weight as mem_weight
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and m.weight >= 0.35
  ),
  anime_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.cover_image_medium,
      a.cover_image_color,
      a.genres,
      a.average_score,
      a.format,
      coalesce(a.season_year, a.start_date_year) as year,
      left(coalesce(a.description_normalized, ''), 300) as synopsis,
      a.episodes,
      null::integer as chapters,
      null::integer as volumes,
      coalesce(a.popularity, 0) as popularity
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )
  ),
  manga_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
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
      m.volumes,
      coalesce(m.popularity, 0)
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  ranked as (
    select * from anime_cards
    union all
    select * from manga_cards
  ),
  capped as (
    -- Franchise runaway cap (20260806010000): <= 2 titles per franchise
    -- cluster on the shelf. Label = media_franchise_components via the
    -- owner-read accessor; singletons label as themselves (collision-free —
    -- 20260804140000: a component's min-member id is itself a member).
    -- media_type is in the partition key because component labels are
    -- per-type integers. Running cap: the cluster's two best entries under
    -- the shelf ordering keep their rank positions; the rest fall out.
    select
      r.*,
      row_number() over (
        partition by r.media_type, coalesce(fc.component_label, r.media_id)
        order by r.tier_rank desc, r.average_score desc nulls last, r.mem_weight desc, r.media_id desc
      ) as franchise_rn
    from ranked r
    left join public._franchise_component_labels() fc
      on fc.media_type = r.media_type
     and fc.media_id = r.media_id
  )
  select
    v_realm,
    v_display,
    v_blurb,
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
    c.volumes
  from capped c
  where c.franchise_rn <= 2
  order by c.tier_rank desc, c.average_score desc nulls last, c.mem_weight desc, c.media_id desc
  limit v_lim;
end;
$$;

revoke all on function public.fetch_tonight_shelf(integer) from public;
grant execute on function public.fetch_tonight_shelf(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fetch_realm_hidden_gem — argument polish + franchise-familiarity
--    exclusion. Byte-identical to 20260802150000 except:
--      * scored.argument: The One Thing treatment (20260805100000) —
--        non-empty gated synopsis_enhanced, else DISPLAY-CASED description
--        (never the lowercased description_normalized); the left(...,280)
--        pre-trim is dropped, the final select now sentence-trims at 320 and
--        capitalizes the first letter (20260731110000), computed once via a
--        lateral.
--      * scored (both branches): NOT EXISTS over known_franchises — the
--        franchise components (via accessor) of any title on the user's list
--        or deck_love/deck_known-signalled. Singleton candidates (no
--        component row) are unaffected; a candidate already on the user's
--        list was and stays excluded by the existing user_lists clause.
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
      case
        when a.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
          then a.synopsis_enhanced
        else a.description
      end as argument,
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
      case
        when m.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
          then m.synopsis_enhanced
        else m.description
      end,
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
-- 3) rebuild_media_realm_tier — craft-lift merit guard. Byte-identical to
--    20260804120000 except: cat score threaded through base_tier/forced, and
--    the lift branch in `lifted` now requires f.score >= 70 — lineage may
--    elevate a good work, not rescue a poor one (live example: Vending
--    Machine, average_score 63, served 'acclaimed' via canon-director lift).
--    Unknown scores (coalesce 0) never lift. Forced-canon branch untouched.
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
      c.score,
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
      bt.score,
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
          -- Merit guard (20260806010000): the craft lift only applies when
          -- the candidate's OWN average_score >= 70 — lineage may elevate a
          -- good work, not rescue a poor one.
          f.score >= 70
          and (
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

revoke all on function public.rebuild_media_realm_tier() from public, anon, authenticated;
grant execute on function public.rebuild_media_realm_tier() to service_role;

comment on function public.rebuild_media_realm_tier() is
  'Staged rebuild of media_realm_tier from media_realm_membership_effective (split-brain fix, 20260804120000; craft-lift merit guard 20260806010000: director/author lineage lift now requires the candidate''s own average_score >= 70 — elevate a good work, not rescue a poor one; forced-canon via canon_seed untouched). Build into temp table, then TRUNCATE + INSERT swap in one transaction. service_role-only EXECUTE for client roles; nightly cron runs it as owner. Returns row count.';

commit;
