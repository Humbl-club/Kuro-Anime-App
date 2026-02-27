-- Ensure manga chapter enrichment cron always sends x-import-secret.
-- Uses app.settings.import_secret when configured and falls back to the
-- currently deployed IMPORT_SECRET value used by existing import jobs.

begin;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'manga-chapter-enrich-15m';
exception
  when undefined_table then
    null;
end $$;

select cron.schedule(
  'manga-chapter-enrich-15m',
  '*/15 * * * *',
  $job$
    select net.http_post(
      url := coalesce(
        nullif(current_setting('app.settings.supabase_url', true), ''),
        'https://bkdifromsqxkndnllmdj.supabase.co'
      ) || '/functions/v1/manga-chapter-enrich',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(
          nullif(current_setting('app.settings.supabase_anon_key', true), ''),
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
        ),
        'x-import-secret', current_setting('app.settings.import_secret', true)
      ),
      body := jsonb_build_object(
        'limit', 20,
        'scheduleSafe', true,
        'timeBudgetMs', 45000,
        'languages', jsonb_build_array('en', 'de'),
        'includeFallbackAllLanguages', true,
        'forceMangaId', null,
        'lockTtlSeconds', 900
      )
    ) as request_id;
  $job$
);

commit;
