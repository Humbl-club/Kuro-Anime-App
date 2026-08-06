-- ADR 2026-07-31: taste profile recompute + pure-SQL drain.
-- Contract numbers (docs/personalization_execution_contract.md + ADR):
--   import discount x0.25 on is_import events
--   tag weight = event_strength * rank/100 ; genre weight = event_strength * 0.6
--   per-title positive mass cap 8% of profile positive mass
--   per-franchise positive mass cap 15% (media_relations family)
--   avoided tag = >=2 negative events OR cumulative negative weight <= -0.8
--   per-tag/name negative mass floor -1.0
--   confidence by strong events (abs(strength) >= 0.3): 0-4 -> 0.05, 5-14 -> 0.10,
--     15-30 -> 0.15, 30+ -> 0.20 (30 exactly counts as 30+)
-- Drain: pg_cron every 15 min, 50 users/run, per-user error capture, no HTTP/GUC pattern.

-- Error log column for the drain (additive, nullable).
alter table public.taste_profile_recompute_queue
  add column if not exists last_error jsonb;

-- ---------------------------------------------------------------------------
-- 1) Profile recompute for one user (SECURITY DEFINER: runs as owner, user-scoped)
-- ---------------------------------------------------------------------------
create or replace function public.recompute_user_taste_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_event_count integer;
  v_strong_count integer;
  v_confidence real;
  v_vector jsonb;
begin
  if p_user_id is null then
    return;
  end if;

  select
    count(*),
    count(*) filter (where abs(e.event_strength) >= 0.3)
  into v_event_count, v_strong_count
  from public.taste_signal_events e
  where e.user_id = p_user_id;

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
        * case when e.is_import then 0.25 else 1.0 end as w, -- import discount x0.25
      (e.event_strength < 0) as negative_event
    from public.taste_signal_events e
    where e.user_id = p_user_id
  ),
  contrib as (
    -- Tag contributions scaled by tag rank/100.
    select c.media_type, c.media_id, 'tag'::text as kind, t.name as name,
           c.w * (coalesce(at.rank, 0)::double precision / 100.0) as weight,
           c.negative_event
    from ev c
    join public.anime_tags at on c.media_type = 'ANIME' and at.anime_id = c.media_id
    join public.tags t on t.id = at.tag_id
    union all
    select c.media_type, c.media_id, 'tag'::text, t.name,
           c.w * (coalesce(mt.rank, 0)::double precision / 100.0),
           c.negative_event
    from ev c
    join public.manga_tags mt on c.media_type = 'MANGA' and mt.manga_id = c.media_id
    join public.tags t on t.id = mt.tag_id
    union all
    -- Genre contributions: flat 0.6 per genre (genres carry no rank).
    select c.media_type, c.media_id, 'genre'::text, g,
           c.w * 0.6, c.negative_event
    from ev c
    join public.anime a on c.media_type = 'ANIME' and a.id = c.media_id
    cross join lateral unnest(a.genres) as g
    union all
    select c.media_type, c.media_id, 'genre'::text, g,
           c.w * 0.6, c.negative_event
    from ev c
    join public.manga m on c.media_type = 'MANGA' and m.id = c.media_id
    cross join lateral unnest(m.genres) as g
  ),
  -- Per-title cap: one title's positive mass <= 8% of profile positive mass.
  title_pos as (
    select media_type, media_id, sum(greatest(weight, 0)) as pos_mass
    from contrib
    group by media_type, media_id
  ),
  total_pos as (
    select coalesce(sum(pos_mass), 0) as v from title_pos
  ),
  title_scale as (
    select
      tp.media_type,
      tp.media_id,
      case
        when tp.pos_mass > 0 and (select v from total_pos) > 0
          then least(1.0, 0.08 * (select v from total_pos) / tp.pos_mass)
        else 1.0
      end as scale
    from title_pos tp
  ),
  capped as (
    select c.kind, c.name, c.media_type, c.media_id,
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
  -- skip grouping (each title becomes its own family, i.e. franchise cap no-ops
  -- beyond the stricter 8% per-title cap).
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
    select c.kind, c.name, c.weight, c.negative_event,
           coalesce(fl.label, c.media_type || ':' || c.media_id::text) as family
    from capped c
    left join family_label fl
      on fl.media_type = c.media_type
     and fl.media_id = c.media_id
  ),
  -- Franchise cap: one family's positive mass <= 15% of profile positive mass.
  family_pos as (
    select family, sum(greatest(weight, 0)) as pos_mass
    from capped_labeled
    group by family
  ),
  family_total as (
    select coalesce(sum(pos_mass), 0) as v from family_pos
  ),
  family_scale as (
    select
      fp.family,
      case
        when fp.pos_mass > 0 and (select v from family_total) > 0
          then least(1.0, 0.15 * (select v from family_total) / fp.pos_mass)
        else 1.0
      end as scale
    from family_pos fp
  ),
  final_contrib as (
    select cl.kind, cl.name, cl.weight * fs.scale as weight, cl.negative_event
    from capped_labeled cl
    join family_scale fs on fs.family = cl.family
  ),
  agg as (
    select
      kind,
      name,
      sum(weight) as weight,
      count(*) filter (where negative_event) as neg_events,
      sum(weight) filter (where weight < 0) as neg_weight
    from final_contrib
    group by kind, name
  ),
  floored as (
    select
      kind,
      name,
      greatest(weight, -1.0) as weight, -- per-name negative mass floor -1.0
      neg_events,
      neg_weight
    from agg
  ),
  avoided as (
    select name
    from floored
    where kind = 'tag'
      and (neg_events >= 2 or coalesce(neg_weight, 0) <= -0.8)
  ),
  tags_json as (
    select coalesce(jsonb_object_agg(name, w), '{}'::jsonb) as j
    from (
      select name, round(weight::numeric, 3) as w
      from floored
      where kind = 'tag'
        and round(weight::numeric, 3) <> 0
      order by abs(weight) desc, name asc
      limit 40
    ) t
  ),
  genres_json as (
    select coalesce(jsonb_object_agg(name, w), '{}'::jsonb) as j
    from (
      select name, round(weight::numeric, 3) as w
      from floored
      where kind = 'genre'
        and round(weight::numeric, 3) <> 0
      order by abs(weight) desc, name asc
    ) g
  ),
  avoided_json as (
    select coalesce(jsonb_agg(name order by name), '[]'::jsonb) as j
    from avoided
  )
  select jsonb_build_object(
    'genres', (select j from genres_json),
    'tags', (select j from tags_json),
    'avoided_tags', (select j from avoided_json),
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
grant execute on function public.recompute_user_taste_profile(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2) Queue drain: up to 50 users per run, per-user error capture, never aborts
-- ---------------------------------------------------------------------------
create or replace function public.drain_taste_recompute_queue()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select q.user_id
    from public.taste_profile_recompute_queue q
    where q.processed_at is null
    order by q.requested_at asc
    limit 50
  loop
    begin
      perform public.recompute_user_taste_profile(v_user_id);
      update public.taste_profile_recompute_queue
      set processed_at = now(),
          last_error = null
      where user_id = v_user_id;
    exception when others then
      -- Poison rows must not block the batch: stamp processed_at, log the error.
      update public.taste_profile_recompute_queue
      set processed_at = now(),
          last_error = jsonb_build_object(
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'at', now()
          )
      where user_id = v_user_id;
      raise warning 'recompute_user_taste_profile failed for %: %', v_user_id, SQLERRM;
    end;
  end loop;
end;
$$;

revoke all on function public.drain_taste_recompute_queue() from public;
grant execute on function public.drain_taste_recompute_queue() to service_role;

-- ---------------------------------------------------------------------------
-- 3) pg_cron: pure SQL every 15 minutes (no net.http_post, no GUC secrets)
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid)
from cron.job
where jobname = 'taste-profile-drain-15m';

select cron.schedule(
  'taste-profile-drain-15m',
  '*/15 * * * *',
  $cmd$select public.drain_taste_recompute_queue();$cmd$
);
