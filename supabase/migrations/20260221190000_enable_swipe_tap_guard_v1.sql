-- Enable gesture guard rollout for reliable swipe/tap behavior.

insert into public.feature_flags (
  flag_name,
  enabled,
  rollout_percentage,
  target_markets,
  description
)
values (
  'swipe_tap_guard_v1',
  true,
  100,
  '{}',
  'Suppress accidental card taps while horizontal page swipe is active'
)
on conflict (flag_name) do update
set
  enabled = excluded.enabled,
  rollout_percentage = excluded.rollout_percentage,
  target_markets = excluded.target_markets,
  description = excluded.description;
