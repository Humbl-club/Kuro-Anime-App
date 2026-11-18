-- Read-only postflight. Run with an administrative read-only connection.
select p.oid::regprocedure as function,
       has_function_privilege('anon',p.oid,'execute') as anon_execute,
       has_function_privilege('authenticated',p.oid,'execute') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'execute') as service_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'upsert_rec_edges','rate_limit_hit','llm_global_budget_reserve',
  'llm_global_budget_finalize','check_email_exists');
-- Expected on every row: false / false / true.

select version,name from supabase_migrations.schema_migrations
where version in ('20261108120159','20261108120211');

select jobname,schedule,active,
       position('body := public.catalog_intake_payload_v1(' in command)>0 as uses_rotating_payload
from cron.job where jobname in (
  'kuro-import-anime-hourly','kuro-import-anime-weekly',
  'kuro-import-manga-hourly','kuro-import-manga-weekly');
-- Four original schedules, all active, uses_rotating_payload true. Never print commands/headers.

select media_type,run_type,status,started_at,
       results->>'identityConflicts' as identity_conflicts,
       results->>'unknownMedia' as unknown_airing_titles,
       results->>'voiceActors' as voice_actors,
       results->>'errors' as item_errors
from public.import_runs where started_at>now()-interval '24 hours'
order by started_at desc limit 40;

select count(*) as voice_links,max(updated_at) as last_cast_refresh from public.character_voice_actors;
