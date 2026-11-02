-- TEMP ops: extract literal x-import-secret from kuro-import-* cron commands
-- (app.settings.import_secret GUC is empty in this project; hourly import crons
-- embed the secret as a jsonb string literal). service_role only.
begin;

create or replace function public._ops_import_secret_from_cron()
returns text
language plpgsql
security definer
set search_path = public, extensions, cron
as $$
declare
  cmd text;
  m text[];
begin
  m := array[nullif(current_setting('app.settings.import_secret', true), '')];
  if m[1] is not null then
    return m[1];
  end if;

  select j.command into cmd
  from cron.job j
  where j.jobname like 'kuro-import-%'
    and j.command ilike '%x-import-secret%'
  order by j.jobid
  limit 1;

  if cmd is null then
    return null;
  end if;

  -- jsonb_build_object( ...'x-import-secret', '<value>' ... )
  m := regexp_match(cmd, '''x-import-secret''\s*,\s*''([^'']+)''');
  if m is null then
    m := regexp_match(cmd, '"x-import-secret"\s*,\s*"([^"]+)"');
  end if;
  if m is null then
    return null;
  end if;
  return m[1];
end;
$$;

revoke all on function public._ops_import_secret_from_cron() from public;
revoke all on function public._ops_import_secret_from_cron() from anon, authenticated;
grant execute on function public._ops_import_secret_from_cron() to service_role;

-- Also fix enqueue to fall back to the same extraction when GUC empty.
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
  _secret := public._ops_import_secret_from_cron();
  if _secret is null or length(_secret) = 0 then
    raise exception 'IMPORT_SECRET_NOT_CONFIGURED'
      using errcode = 'P0001',
            detail = 'could not resolve import secret from GUC or cron literals';
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

revoke all on function public.enqueue_realm_describe_batch(integer) from public;
revoke all on function public.enqueue_realm_describe_batch(integer) from anon, authenticated;
grant execute on function public.enqueue_realm_describe_batch(integer) to service_role;

commit;
