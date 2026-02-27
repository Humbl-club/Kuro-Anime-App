-- Phase 5: Cron Cleanup + Operational Hygiene

-- 1. Add cron history cleanup (retain 14 days)
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'cleanup-cron-history';

SELECT cron.schedule(
  'cleanup-cron-history',
  '0 5 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '14 days'$$
);

-- 2. Remove duplicate weekly concierge events cleanup
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'concierge_events_retention';

-- 3. Fix scheduling overlap at 03:00 — move club message pruning to 03:15
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'prune_club_messages';

SELECT cron.schedule('prune_club_messages', '15 3 * * *',
  $$DELETE FROM public.club_messages WHERE created_at < now() - interval '30 days'$$);

-- 4. Update mirror-images cron jobs to include x-import-secret header
-- (Required after adding IMPORT_SECRET auth to mirror-images edge function)
-- NOTE: Jobs are unscheduled by ID and recreated with new names + x-import-secret header.
-- The actual secret and JWT values are hardcoded in cron commands because pg_cron
-- does not support environment variable interpolation.
