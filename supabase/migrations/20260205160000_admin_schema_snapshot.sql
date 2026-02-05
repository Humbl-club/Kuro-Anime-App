-- Admin-only schema snapshot RPC for documentation and drift detection.
-- This is intended to be callable only with the Supabase service role key.
--
-- Why:
-- - The repo schema (migrations) is the primary source of truth, but production/dev DB can drift.
-- - This RPC provides a safe way to fetch *metadata* (not data) for auditing and docs generation.
--
-- Safety:
-- - SECURITY DEFINER so it can read catalogs (and cron schema if present).
-- - EXECUTE is granted ONLY to service_role; revoked from PUBLIC.

create or replace function public.admin_schema_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog, information_schema
as $$
declare
  cron_exists boolean := (to_regclass('cron.job') is not null);
  out jsonb;
begin
  out := jsonb_build_object(
    'generated_at', now(),
    'schemas', jsonb_build_object(
      'included', jsonb_build_array('public', 'auth', 'storage', 'cron')
    ),
    'extensions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'name', extname,
        'schema', nspname,
        'version', extversion
      ) order by extname), '[]'::jsonb)
      from pg_extension e
      join pg_namespace n on n.oid = e.extnamespace
    ),
    'tables', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', table_schema,
        'name', table_name,
        'type', table_type
      ) order by table_schema, table_name), '[]'::jsonb)
      from information_schema.tables
      where table_schema in ('public', 'auth', 'storage', 'cron')
        and table_type in ('BASE TABLE', 'VIEW')
    ),
    'columns', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', table_schema,
        'table', table_name,
        'column', column_name,
        'ordinal', ordinal_position,
        'data_type', data_type,
        'udt_name', udt_name,
        'is_nullable', is_nullable,
        'column_default', column_default
      ) order by table_schema, table_name, ordinal_position), '[]'::jsonb)
      from information_schema.columns
      where table_schema in ('public', 'auth', 'storage', 'cron')
    ),
    'functions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', n.nspname,
        'name', p.proname,
        'args', pg_get_function_identity_arguments(p.oid),
        'returns', pg_get_function_result(p.oid),
        'security_definer', p.prosecdef,
        'language', l.lanname
      ) order by n.nspname, p.proname), '[]'::jsonb)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
      where n.nspname in ('public')
        and p.proname not like 'pg_%'
    ),
    'policies', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'schema', schemaname,
        'table', tablename,
        'name', policyname,
        'roles', roles,
        'cmd', cmd,
        'permissive', permissive,
        'qual', qual,
        'with_check', with_check
      ) order by schemaname, tablename, policyname), '[]'::jsonb)
      from pg_policies
      where schemaname in ('public')
    ),
    'cron_jobs', (
      case
        when cron_exists then (
          select coalesce(jsonb_agg(jsonb_build_object(
            'jobid', jobid,
            'schedule', schedule,
            'command', command,
            'nodename', nodename,
            'nodeport', nodeport,
            'database', database,
            'username', username,
            'active', active
          ) order by jobid), '[]'::jsonb)
          from cron.job
        )
        else jsonb_build_object('note', 'cron.job not present (pg_cron not installed or schema not exposed)')
      end
    )
  );

  return out;
end;
$$;

revoke all on function public.admin_schema_snapshot() from public;
grant execute on function public.admin_schema_snapshot() to service_role;

