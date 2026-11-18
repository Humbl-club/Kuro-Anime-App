-- Catalogue-intake cron jobs. PREPARED, NOT APPLIED (catalogue Task 15 Step 7; spec section 3.1).
-- Generated from supabase/functions/catalogue-intake/cron_schedule.ts: edit that file, then regenerate with
--   deno run supabase/functions/catalogue-intake/cron_schedule.ts > docs/catalogue-sources-2026-11/cron-prepared.sql
-- Applying this file is a hosted change and needs the owner's explicit approval, after catalogue-intake is deployed.
-- pg_cron runs in UTC. Run it with psql variables copied from an existing import job's command (never committed):
--   \set project_url '...' \set import_secret '...' \set service_jwt '...'
-- Schedule only after the matching migrations are applied and the function is deployed (--no-verify-jwt).
-- A job name that already exists is replaced by cron.schedule(name, ...).

-- wikidata anime
select cron.schedule('catalogue-intake-wikidata-anime', '0,30 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"wikidata","medium":"anime"}'));

-- wikidata manga
select cron.schedule('catalogue-intake-wikidata-manga', '15,45 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"wikidata","medium":"manga"}'));

-- ann anime
select cron.schedule('catalogue-intake-ann-anime', '10,40 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"ann","medium":"anime"}'));

-- mangaupdates manga
select cron.schedule('catalogue-intake-mangaupdates-a', '*/2 0-2,5-23 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates","medium":"manga"}'));

-- mangaupdates manga
select cron.schedule('catalogue-intake-mangaupdates-b', '0-28/2 3 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates","medium":"manga"}'));

-- mangaupdates manga
select cron.schedule('catalogue-intake-mangaupdates-c', '22-58/2 4 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates","medium":"manga"}'));

-- mangaupdates_new manga
select cron.schedule('catalogue-intake-mangaupdates-new-a', '7,37 0-2,5-23 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates_new","medium":"manga"}'));

-- mangaupdates_new manga
select cron.schedule('catalogue-intake-mangaupdates-new-b', '7 3 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates_new","medium":"manga"}'));

-- mangaupdates_new manga
select cron.schedule('catalogue-intake-mangaupdates-new-c', '37 4 * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"mangaupdates_new","medium":"manga"}'));

-- create manga
select cron.schedule('catalogue-intake-create-manga', '20 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"create","medium":"manga"}'));

-- pageviews anime (initial)
select cron.schedule('catalogue-intake-pageviews-anime-initial', '0-50/10 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"pageviews","medium":"anime"}'));

-- pageviews manga (initial)
select cron.schedule('catalogue-intake-pageviews-manga-initial', '5-55/10 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"pageviews","medium":"manga"}'));

-- pageviews anime (refresh)
select cron.schedule('catalogue-intake-pageviews-anime-weekly', '0-50/10 0-11 * * 0', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"pageviews","medium":"anime"}'));

-- pageviews manga (refresh)
select cron.schedule('catalogue-intake-pageviews-manga-weekly', '5-55/10 0-11 * * 0', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"pageviews","medium":"manga"}'));

-- compose anime
select cron.schedule('catalogue-intake-compose-anime', '55 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"compose","medium":"anime"}'));

-- compose manga
select cron.schedule('catalogue-intake-compose-manga', '56 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"compose","medium":"manga"}'));

-- publish anime
select cron.schedule('catalogue-intake-publish-anime', '58 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"publish","medium":"anime"}'));

-- publish manga
select cron.schedule('catalogue-intake-publish-manga', '59 * * * *', format(
  $cmd$select net.http_post(url := %L || '/functions/v1/catalogue-intake',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || %L, 'x-import-secret', %L),
    body := %L::jsonb)$cmd$,
  :'project_url', :'service_jwt', :'import_secret', '{"handler":"publish","medium":"manga"}'));

-- After the initial pageviews pass has covered every title (spec 3.1: about 12 h), drop the initial jobs:
--   select cron.unschedule('catalogue-intake-pageviews-anime-initial');
--   select cron.unschedule('catalogue-intake-pageviews-manga-initial');

