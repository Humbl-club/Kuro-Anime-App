-- Promote clubs trust-pack flags to 100% so migration history matches live DB.
--
-- Context: 20260731040000 inserted clubs_realtime_v1 / clubs_pace_sync_v1 /
-- clubs_notifications_v1 at enabled=true, rollout_percentage=0 with
-- ON CONFLICT DO NOTHING. Live feature_flags were later raised to 100% outside
-- that insert path. This migration makes repo history authoritative again.

UPDATE public.feature_flags
SET
  enabled = true,
  rollout_percentage = 100,
  target_markets = ARRAY['*']::text[],
  description = CASE flag_name
    WHEN 'clubs_realtime_v1' THEN 'Club realtime refresh (live)'
    WHEN 'clubs_pace_sync_v1' THEN 'Club pace sync milestones and banners (live)'
    WHEN 'clubs_notifications_v1' THEN 'Club activity notifications (live)'
    ELSE description
  END
WHERE flag_name IN (
  'clubs_realtime_v1',
  'clubs_pace_sync_v1',
  'clubs_notifications_v1'
);
