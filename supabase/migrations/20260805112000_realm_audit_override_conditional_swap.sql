-- Realm audit overrides — architecture-review correction to 20260805110000:
-- the override layer is a CONDITIONAL ordering assertion, not an unconditional
-- weight swap.
--
-- SEMANTICS ("promote must rank strictly above demote", evaluated at read time
-- against the layer-1+2 effective weights w_d = w(demote), w_p = w(promote)):
--   * w_p > w_d            -> NO-OP. Upstream already satisfies the assertion
--     (e.g. a later signature regrade lifts the correct realm naturally); the
--     override must never invert a now-correct ordering. This also yields the
--     absorption metric: overrides in this branch are fully absorbed upstream
--     and safe to delete after the Phase-5 regrade —
--       select count(*) from realm_audit_overrides o
--       where <w_p of o> > <w_d of o>;   -- no-op / absorbed
--   * 0 < w_p < w_d        -> swap: promote takes w_d, demote takes w_p.
--   * w_p = w_d (tie)      -> promote takes w_d, demote keeps 0.6 * w_d (a
--     bare swap would keep the tie and the top-realm tiebreak could still pick
--     the demoted realm alphabetically; the assertion demands STRICT order).
--   * promote row missing or clamped to 0 -> promote takes w_d (row CREATED
--     when absent from layers 1+2: rules_weight = 0, delta = 0, family from
--     realm_meta); demote keeps 0.6 * w_d — demotes RANK, not membership.
--   * demote row absent/zero -> override inert (assertion trivially holds).
--
-- The 20260805110000 least/greatest formulation was already output-identical
-- on today's data (its greatest/least arms no-op when w_p > w_d; live data has
-- 0 such rows and 0 ties) — this redefinition changes NO current row and
-- exists to encode the intent explicitly so the no-op branches are legible
-- and the absorption query has a textual anchor. Everything else (table, ACL,
-- seed, column contract, security_invoker) is unchanged from 20260805110000.

begin;

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
),
ov as materialized (
  -- Active overrides + their layer-1+2 weights, via indexed point lookups
  -- (media_realm_membership_uidx / media_realm_membership_delta_pkey) so this
  -- stays O(overrides), not O(view). Inert when the demote realm holds no
  -- positive layer-1+2 weight (the ordering assertion trivially holds).
  select
    o.media_type,
    o.media_id,
    o.demote_realm,
    o.promote_realm,
    dw.w as w_demote_old,
    pw.w as w_promote_old,
    pw.found as promote_row_exists
  from public.realm_audit_overrides o
  cross join lateral (
    select least(1.0, greatest(0.0,
             coalesce((select dm.weight from public.media_realm_membership dm
                       where dm.media_type = o.media_type
                         and dm.media_id = o.media_id
                         and dm.realm = o.demote_realm), 0::real)
           + coalesce((select dd.delta from public.media_realm_membership_delta dd
                       where dd.media_type = o.media_type
                         and dd.media_id = o.media_id
                         and dd.realm = o.demote_realm), 0::real)
          ))::real as w
  ) dw
  cross join lateral (
    select
      least(1.0, greatest(0.0, coalesce(pm.weight, 0::real) + coalesce(pd.delta, 0::real)))::real as w,
      (pm.media_id is not null or pd.media_id is not null) as found
    from (select 1) one
    left join public.media_realm_membership pm
      on pm.media_type = o.media_type
     and pm.media_id = o.media_id
     and pm.realm = o.promote_realm
    left join public.media_realm_membership_delta pd
      on pd.media_type = o.media_type
     and pd.media_id = o.media_id
     and pd.realm = o.promote_realm
  ) pw
  where dw.w > 0
)
select z.media_type, z.media_id, z.realm, z.family, z.weight, z.rules_weight, z.delta
from (
  select
    s.media_type,
    s.media_id,
    s.realm,
    s.family,
    (case
       -- demote row of an active override (conditional ordering assertion):
       when od.media_id is not null then
         case
           -- upstream already ranks promote strictly above: NO-OP (absorbed).
           when od.w_promote_old > od.w_demote_old then s.weight
           -- live lower promote weight: swap down to it.
           when od.w_promote_old > 0 and od.w_promote_old < od.w_demote_old
             then od.w_promote_old
           -- tie, or no live promote weight to swap with: keep 60%.
           else 0.6 * od.w_demote_old
         end
       -- promote row of an active override:
       when op.media_id is not null then
         case
           -- upstream already ranks it strictly above: NO-OP (absorbed).
           when op.w_promote_old > op.w_demote_old then s.weight
           -- otherwise lift to the demoted realm's old weight.
           else op.w_demote_old
         end
       -- everyone else: layer-1+2 weight, untouched.
       else s.weight
     end)::real as weight,
    s.rules_weight,
    s.delta
  from (
    select
      b.media_type, b.media_id, b.realm, b.family,
      least(1.0, greatest(0.0, b.rules_weight + b.delta))::real as weight,
      b.rules_weight, b.delta
    from base b
  ) s
  left join ov od
    on od.media_type = s.media_type
   and od.media_id = s.media_id
   and od.demote_realm = s.realm
  left join ov op
    on op.media_type = s.media_type
   and op.media_id = s.media_id
   and op.promote_realm = s.realm
) z
where z.weight > 0

union all

-- Promote rows absent from layers 1+2 entirely: created with the demoted
-- realm's old weight; family from realm_meta; rules_weight/delta report 0
-- (same convention as delta-only rows in 20260802123000). 84 such pure-fiat
-- memberships at ship time.
select
  o.media_type,
  o.media_id,
  o.promote_realm as realm,
  rm.family,
  o.w_demote_old as weight,
  0::real as rules_weight,
  0::real as delta
from ov o
left join public.realm_meta rm
  on rm.realm = o.promote_realm
where not o.promote_row_exists;

comment on view public.media_realm_membership_effective is
  'Three layers since 20260805110000: rules media_realm_membership + media_realm_membership_delta (±0.2, clamped [0,1]) + realm_audit_overrides as a CONDITIONAL ordering assertion (20260805112000: promote must rank strictly above demote; no-op once upstream weights already satisfy it — no-op overrides are absorbed and deletable post-regrade). Similarity gates, tier rebuild, and deck stratification read this; the rules matview stays inspectable.';

comment on table public.realm_audit_overrides is
  'Realm audit F1+F2 (2026-08-05): double-judged top-realm corrections applied as a CONDITIONAL ordering assertion inside media_realm_membership_effective (layer 3): swap/lift only while layers 1+2 rank demote_realm at or above promote_realm; no-op (absorbed) once upstream heals. One override per title. Seeded from reports/realm-audit/apply_set.jsonl (393 rows; 3 held for regrade; 84 required creating a promote-realm row). Read-open like media_realm_membership_delta (security_invoker view + invoker RPCs need client SELECT); writes service_role-only.';

commit;
