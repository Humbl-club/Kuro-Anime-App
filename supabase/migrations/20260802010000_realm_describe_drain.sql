-- Realm Graph Stage 2b — drain helper + temporary cron for realm-describe.
-- Spec: docs/superpowers/specs/2026-08-02-realm-descriptor-groq-pipeline-design.md
--
-- enqueue_realm_describe_batch: service_role-only; fires pg_net HTTP POST to
-- the realm-describe edge function using app.settings.import_secret (same
-- pattern as manga-chapter-enrich / mirror-images crons).
--
-- Cron realm-describe-drain-2m: every 2 minutes, batch of 12 pending titles.
-- Unschedule once media_realm_llm_pending is drained (ops), or leave as a
-- low-cost catch-up for newly eligible visible-pool titles.

begin;

create or replace function public.enqueue_realm_describe_batch(p_limit integer default 10)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  _limit integer := least(greatest(coalesce(p_limit, 10), 1), 25);
  _url text;
  _anon text;
  _secret text;
  _request_id bigint;
begin
  _secret := nullif(current_setting('app.settings.import_secret', true), '');
  if _secret is null or length(_secret) = 0 then
    raise exception 'IMPORT_SECRET_NOT_CONFIGURED'
      using errcode = 'P0001',
            detail = 'app.settings.import_secret is empty';
  end if;

  _url := coalesce(
    nullif(current_setting('app.settings.supabase_url', true), ''),
    'https://bkdifromsqxkndnllmdj.supabase.co'
  ) || '/functions/v1/realm-describe';

  _anon := coalesce(
    nullif(current_setting('app.settings.supabase_anon_key', true), ''),
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrZGlmcm9tc3F4a25kbmxsbWRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1OTg2NjMsImV4cCI6MjA2ODE3NDY2M30.xWtSNgApX5jMZqdWJLjsqNlsXbwubFwW39Hs3x9hOoo'
  );

  select net.http_post(
    url := _url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _anon,
      'apikey', _anon,
      'x-import-secret', _secret
    ),
    body := jsonb_build_object('batch', true, 'limit', _limit)
  ) into _request_id;

  return _request_id;
end;
$$;

comment on function public.enqueue_realm_describe_batch(integer) is
  'Ops: enqueue one realm-describe batch (1..25) via pg_net. service_role only.';

revoke all on function public.enqueue_realm_describe_batch(integer) from public;
revoke all on function public.enqueue_realm_describe_batch(integer) from anon, authenticated;
grant execute on function public.enqueue_realm_describe_batch(integer) to service_role;

-- Temporary peek for local worker bootstrap (service_role only). Drop after
-- the initial drain if desired; harmless if left (not granted to clients).
create or replace function public._ops_peek_import_secret()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return nullif(current_setting('app.settings.import_secret', true), '');
end;
$$;

revoke all on function public._ops_peek_import_secret() from public;
revoke all on function public._ops_peek_import_secret() from anon, authenticated;
grant execute on function public._ops_peek_import_secret() to service_role;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'realm-describe-drain-2m';
exception
  when undefined_table then null;
  when others then null;
end $$;

select cron.schedule(
  'realm-describe-drain-2m',
  '*/2 * * * *',
  $job$
    select public.enqueue_realm_describe_batch(12);
  $job$
);

commit;
