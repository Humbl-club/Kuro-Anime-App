-- Concierge editorial visual delta rollout flag.

insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
values
  ('concierge_editorial_v1', false, 0, '{}', 'Concierge editorial visual shell (light-only, premium UX layout)')
on conflict (flag_name) do update
set
  enabled = excluded.enabled,
  rollout_percentage = excluded.rollout_percentage,
  target_markets = excluded.target_markets,
  description = excluded.description;
