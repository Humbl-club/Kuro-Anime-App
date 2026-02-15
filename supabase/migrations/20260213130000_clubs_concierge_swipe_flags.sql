-- Add rollout flags for clubs interactions, concierge perf pass, and swipe/tap guard.

insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
values
  ('clubs_interaction_v2', false, 0, '{}', 'Optimistic club interactions + add-to-rail reliability pass'),
  ('concierge_perf_v2', false, 0, '{}', 'Concierge perceived-performance optimizations (prefetch/timing tuning)'),
  ('swipe_tap_guard_v1', false, 0, '{}', 'Suppress accidental card taps while horizontal page swipe is active')
on conflict (flag_name) do update
set
  enabled = excluded.enabled,
  rollout_percentage = excluded.rollout_percentage,
  target_markets = excluded.target_markets,
  description = excluded.description;
