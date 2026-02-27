-- Phase 5: Cron Cleanup + Operational Hygiene

-- 1. Add cron history cleanup (retain 14 days)
SELECT cron.schedule(
  'cleanup-cron-history',
  '0 5 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '14 days'$$
);

-- 2. Remove duplicate weekly concierge events cleanup (job 17)
SELECT cron.unschedule('concierge_events_retention');

-- 3. Fix scheduling overlap at 03:00 — move club message pruning to 03:15
SELECT cron.unschedule('prune_club_messages');
SELECT cron.schedule('prune_club_messages', '15 3 * * *',
  $$DELETE FROM public.club_messages WHERE created_at < now() - interval '30 days'$$);

-- 4. Update mirror-images cron jobs to include x-import-secret header

SELECT cron.unschedule(3);
SELECT cron.schedule('mirror-images-anime-manga-0', '0 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

SELECT cron.unschedule(4);
SELECT cron.schedule('mirror-images-anime-manga-200', '15 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":200,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

SELECT cron.unschedule(5);
SELECT cron.schedule('mirror-images-anime-manga-400', '30 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":400,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

SELECT cron.unschedule(6);
SELECT cron.schedule('mirror-images-character', '45 2 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["CHARACTER"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);

SELECT cron.unschedule(7);
SELECT cron.schedule('mirror-images-staff', '0 3 * * *', $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo',
      'x-import-secret', current_setting('app.settings.import_secret', true)
    ),
    body := '{"bucket":"media","mediaTypes":["STAFF"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
$$);;
