begin;
create or replace function public._ops_list_import_crons()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, cron
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'jobname', jobname,
      'has_setting_call', command ilike '%current_setting%import_secret%',
      'has_literal_secret', command ~ '''x-import-secret'',\s*''[^'']+'''
        and command not ilike '%current_setting%import_secret%',
      'command_head', left(command, 160)
    ) order by jobid)
    from cron.job
    where command ilike '%import-secret%' or command ilike '%import_secret%'
  ), '[]'::jsonb);
end;
$$;
revoke all on function public._ops_list_import_crons() from public;
revoke all on function public._ops_list_import_crons() from anon, authenticated;
grant execute on function public._ops_list_import_crons() to service_role;
commit;
