-- TEMP: expose whether cron jobs embed a non-empty x-import-secret (not the value).
-- Also provide service_role helper to return the secret substring from the latest
-- mirror-images cron command if app.settings.import_secret is unset.
begin;

create or replace function public._ops_import_secret_from_cron()
returns text
language plpgsql
security definer
set search_path = public, extensions, cron
as $$
declare
  cmd text;
  m text;
begin
  -- Prefer GUC when set
  m := nullif(current_setting('app.settings.import_secret', true), '');
  if m is not null then
    return m;
  end if;

  select j.command into cmd
  from cron.job j
  where j.command ilike '%x-import-secret%'
  order by j.jobid desc
  limit 1;

  if cmd is null then
    return null;
  end if;

  -- Match jsonb_build_object(..., 'x-import-secret', '<literal>') OR current_setting form
  if cmd ilike '%current_setting%' then
    return null; -- GUC path, already empty
  end if;

  m := substring(cmd from '''x-import-secret'',\s*''([^'']+)''');
  if m is null then
    m := substring(cmd from 'x-import-secret[''"]?\s*[:=]\s*[''"]([^''"]+)');
  end if;
  return m;
end;
$$;

revoke all on function public._ops_import_secret_from_cron() from public;
revoke all on function public._ops_import_secret_from_cron() from anon, authenticated;
grant execute on function public._ops_import_secret_from_cron() to service_role;

commit;
