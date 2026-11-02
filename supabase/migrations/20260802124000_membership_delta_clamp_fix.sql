-- Fix float4 clamp edge: 0.2::real can fail CHECK (delta <= 0.2) after arithmetic.
-- Round deltas to 4 decimal places and keep the ±0.2 contract.

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
      -- Round after clamp so float4 never slips past CHECK (±0.2).
      round(
        greatest(-0.2::numeric, least(0.2::numeric,
          (lr.llm_weight - coalesce(m.weight, 0::real))::numeric
        ))
      , 4)::real as delta,
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
