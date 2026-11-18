-- @requires function public.catalog_intake_payload_v1(text,boolean,timestamptz)
-- @requires function public.configure_catalog_intake_jobs_v1()
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.ok('light jobs cover every intake strategy in four hours',
  (select count(distinct public.catalog_intake_payload_v1('anime',false,'2026-11-08 00:00Z'::timestamptz + make_interval(hours=>h))->>'trackPreset') = 4
   from generate_series(0,3) h));
select tests.ok('heavy jobs refresh cast even when upstream updatedAt is unchanged',
  (public.catalog_intake_payload_v1('anime',true)->>'includeVoiceActors')::boolean
  and (public.catalog_intake_payload_v1('anime',true)->>'forceRefresh')::boolean);
select tests.eq('manga never requests voice actors', public.catalog_intake_payload_v1('manga',true)->>'includeVoiceActors','false');
select tests.eq('light jobs bounded to fifty titles',
  (public.catalog_intake_payload_v1('anime',false)->>'perPage')::integer *
  (public.catalog_intake_payload_v1('anime',false)->>'pagesPerBatch')::integer,50);
select tests.eq('heavy jobs bounded to ten titles',
  (public.catalog_intake_payload_v1('anime',true)->>'perPage')::integer,10);
select tests.ok('light and heavy runs never share a cursor',
  public.catalog_intake_payload_v1('anime',false)->>'trackKey' <> public.catalog_intake_payload_v1('anime',true)->>'trackKey');

delete from cron.job where jobname in ('kuro-import-anime-hourly','kuro-import-anime-weekly','kuro-import-manga-hourly','kuro-import-manga-weekly');
insert into cron.job(jobname,schedule,command)
select name,'5 * * * *', $cmd$select net.http_post(url := 'https://fixture.invalid/import',headers := '{"x-import-secret":"fixture-only"}',body := '{"perPage":25}'::jsonb);$cmd$
from unnest(array['kuro-import-anime-hourly','kuro-import-anime-weekly','kuro-import-manga-hourly','kuro-import-manga-weekly']) name;
select tests.eq('all four existing jobs are upgraded', public.configure_catalog_intake_jobs_v1(),4);
select tests.eq('schedule upgrade is idempotent', public.configure_catalog_intake_jobs_v1(),0);
select tests.eq('credentials and timing survive the upgrade',
  (select count(*) from cron.job where jobname like 'kuro-import-%' and schedule='5 * * * *'
    and position('fixture-only' in command)>0 and position('body := public.catalog_intake_payload_v1(' in command)>0),4::bigint);
select tests.as_anon();
select tests.denied('anon cannot reconfigure intake', $q$select public.configure_catalog_intake_jobs_v1()$q$);
select tests.reset();
rollback;
