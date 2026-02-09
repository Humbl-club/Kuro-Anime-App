-- P1-16: Fix mirror-images cron contention (58% skip rate)
--
-- Root cause: All 5 mirror jobs shared one lock key ('mirror-images') with a
-- 30-minute TTL. Jobs staggered 10 min apart meant jobs 2-4 always found the
-- lock held by job 1 and were skipped.
--
-- Fix (Part A): Spread jobs further apart (15-min gaps) and reduce batch size
-- from 500 to 200 so each run finishes well within its window. The edge
-- function (Part B) now derives per-batch lock keys so separate batches never
-- block each other, and the lock TTL is reduced from 1800s to 120s.

-- Job 3: ANIME/MANGA offset 0 — keep at 02:00
SELECT cron.alter_job(
  3,
  schedule := '0 2 * * *',
  command := $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
  $$
);

-- Job 4: ANIME/MANGA offset 200 — move to 02:15 (was 02:10, offset was 500)
SELECT cron.alter_job(
  4,
  schedule := '15 2 * * *',
  command := $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":200,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
  $$
);

-- Job 5: ANIME/MANGA offset 400 — move to 02:30 (was 02:20, offset was 1000)
SELECT cron.alter_job(
  5,
  schedule := '30 2 * * *',
  command := $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
    ),
    body := '{"bucket":"media","mediaTypes":["ANIME","MANGA"],"limit":200,"offset":400,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
  $$
);

-- Job 6: CHARACTER — move to 02:45 (was 02:30), reduce limit to 200
SELECT cron.alter_job(
  6,
  schedule := '45 2 * * *',
  command := $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
    ),
    body := '{"bucket":"media","mediaTypes":["CHARACTER"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
  $$
);

-- Job 7: STAFF — move to 03:00 (was 02:40), reduce limit to 200
SELECT cron.alter_job(
  7,
  schedule := '0 3 * * *',
  command := $$
  SELECT net.http_post(
    url := 'https://bkdifromsqxkndnllmdj.supabase.co/functions/v1/mirror-images',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
    ),
    body := '{"bucket":"media","mediaTypes":["STAFF"],"limit":200,"offset":0,"overwrite":false,"skipIfMirrored":true,"timeBudgetMs":55000,"lockTtlSeconds":120}'::jsonb
  ) AS request_id;
  $$
);

-- Clean up stale lock rows from the old shared key
DELETE FROM public.import_locks WHERE lock_key = 'mirror-images';
