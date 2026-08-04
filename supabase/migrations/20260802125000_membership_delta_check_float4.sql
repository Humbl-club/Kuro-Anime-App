-- float4 cannot represent 0.2 exactly; CHECK (delta <= 0.2) rejects clamped 0.2.
-- Keep the editorial ±0.2 contract with a tiny float-epsilon envelope.

alter table public.media_realm_membership_delta
  drop constraint if exists media_realm_membership_delta_delta_check;

alter table public.media_realm_membership_delta
  add constraint media_realm_membership_delta_delta_check
  check (delta >= -0.2001 and delta <= 0.2001);
