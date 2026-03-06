-- Feature flag for characters, staff, studios, and authors on detail pages
INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES ('credits_cast_v1', true, 100, '{}', 'Characters, staff, studios, and authors on detail pages')
ON CONFLICT (flag_name) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  rollout_percentage = EXCLUDED.rollout_percentage,
  description = EXCLUDED.description;
