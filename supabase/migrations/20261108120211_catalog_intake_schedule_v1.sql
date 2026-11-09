-- PREPARED ONLY. Four existing cron slots, unchanged credentials/schedules/request count.
-- Light jobs rotate new titles / updates / airing / popularity; heavy jobs rotate full
-- backfill / updates / airing. Every track has its own cursor and fixed page size.
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

create or replace function public.catalog_intake_payload_v1(
  p_medium text, p_heavy boolean, p_at timestamptz default now()
) returns jsonb language plpgsql stable security invoker
set search_path = public, extensions
as $$
declare
  medium text := lower(p_medium);
  hour integer := extract(hour from p_at at time zone 'UTC')::integer;
  preset text;
begin
  if medium is null or medium not in ('anime', 'manga') or p_heavy is null or p_at is null then
    raise exception 'Invalid catalogue intake arguments' using detail = 'INVALID_ARG';
  end if;
  preset := case when p_heavy then
    (array['catalog_backfill', 'recent_updates', 'airing_or_releasing'])[1 + hour % 3]
  else
    (array['new_titles', 'recent_updates', 'airing_or_releasing', 'popularity_core'])[1 + hour % 4]
  end;
  return jsonb_build_object(
    'trackPreset', preset, 'trackKey', medium || ':scheduled:' || case when p_heavy then 'heavy:' else 'light:' end || preset,
    'useCursor', true, 'scheduleSafe', true, 'lightweight', not p_heavy,
    'runToEnd', false, 'pagesPerBatch', case when p_heavy then 1 else 2 end,
    'maxPagesPerRun', case when p_heavy then 1 else 2 end,
    'perPage', case when p_heavy then 10 else 25 end,
    'timeBudgetMs', 55000, 'delayMs', 0, 'retries', 2,
    'includeRelations', p_heavy, 'includeEpisodes', p_heavy and medium = 'anime',
    'includeChapters', false, 'includeVolumes', false,
    'includeVoiceActors', p_heavy and medium = 'anime', 'forceRefresh', p_heavy
  );
end $$;
revoke all on function public.catalog_intake_payload_v1(text,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.catalog_intake_payload_v1(text,boolean,timestamptz) to service_role;

create or replace function public.configure_catalog_intake_jobs_v1()
returns integer language plpgsql security invoker
set search_path = public, extensions
as $$
declare
  job record; expected integer; changed integer := 0; expression text; updated text;
  pattern constant text := $re$body\s*:=\s*'[^']*'::jsonb$re$;
begin
  select count(*) into expected from cron.job where jobname in (
    'kuro-import-anime-hourly', 'kuro-import-anime-weekly',
    'kuro-import-manga-hourly', 'kuro-import-manga-weekly');
  if expected <> 4 then raise exception 'Expected exactly four existing intake jobs; found %', expected; end if;
  for job in select jobid,jobname,command from cron.job where jobname in (
    'kuro-import-anime-hourly', 'kuro-import-anime-weekly',
    'kuro-import-manga-hourly', 'kuro-import-manga-weekly') loop
    if position('public.catalog_intake_payload_v1(' in job.command) > 0 then continue; end if;
    if (select count(*) from regexp_matches(job.command, pattern, 'g')) <> 1 then
      raise exception 'Unexpected request-body shape for job %', job.jobname;
    end if;
    expression := format('body := public.catalog_intake_payload_v1(%L, %s)',
      case when job.jobname like '%-anime-%' then 'anime' else 'manga' end,
      case when job.jobname like '%-weekly' then 'true' else 'false' end);
    updated := regexp_replace(job.command, pattern, expression);
    perform cron.alter_job(job.jobid, command := updated);
    changed := changed + 1;
  end loop;
  return changed;
end $$;
revoke all on function public.configure_catalog_intake_jobs_v1() from public, anon, authenticated;
grant execute on function public.configure_catalog_intake_jobs_v1() to service_role;

-- Empty local fixtures have no hosted scheduler. A partially configured host fails closed.
do $$
begin
  if exists (select 1 from cron.job where jobname in (
    'kuro-import-anime-hourly','kuro-import-anime-weekly','kuro-import-manga-hourly','kuro-import-manga-weekly')) then
    perform public.configure_catalog_intake_jobs_v1();
  else
    raise notice 'No hosted intake jobs: schedule change not exercised here';
  end if;
end $$;
commit;
