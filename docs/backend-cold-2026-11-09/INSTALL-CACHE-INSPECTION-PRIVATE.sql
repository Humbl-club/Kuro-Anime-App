-- Managed-platform adaptation: put the temporary inspector in an unexposed private namespace.
-- No owner-role escalation. Supabase owns extension functions and retains PUBLIC EXECUTE
-- on its superuser-only eviction function; schema isolation denies all client access to it.
-- No eviction call is ever issued by this experiment.
begin;
set local search_path=public,extensions;
set local lock_timeout='3s';
set local statement_timeout='30s';
do $absent$ begin
 if exists(select 1 from pg_extension where extname='pg_buffercache') or to_regnamespace('kuro_cold_inspection') is not null then
  raise exception 'Inspector or private namespace already exists; preserve it and reconcile';
 end if;
end $absent$;
create schema kuro_cold_inspection;
revoke all on schema kuro_cold_inspection from public,anon,authenticated;
create extension pg_buffercache with schema kuro_cold_inspection version '1.5';
do $guard$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_depend d on d.classid='pg_proc'::regclass and d.objid=p.oid join pg_extension e on e.oid=d.refobjid where e.extname='pg_buffercache' and d.deptype='e' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
 revoke all on kuro_cold_inspection.pg_buffercache from public,anon,authenticated;
 if has_schema_privilege('anon','kuro_cold_inspection','usage') or has_schema_privilege('authenticated','kuro_cold_inspection','usage') or has_schema_privilege('anon','kuro_cold_inspection','create') or has_schema_privilege('authenticated','kuro_cold_inspection','create') then
  raise exception 'Clients must have neither USAGE nor CREATE on private inspector namespace';
 end if;
 if has_table_privilege('anon','kuro_cold_inspection.pg_buffercache','select') or has_table_privilege('authenticated','kuro_cold_inspection.pg_buffercache','select') then
  raise exception 'Inspector view must remain inaccessible to clients';
 end if;
 if exists(select 1 from pg_proc p join pg_depend d on d.classid='pg_proc'::regclass and d.objid=p.oid join pg_extension e on e.oid=d.refobjid where e.extname='pg_buffercache' and d.deptype='e' and p.proname<>'pg_buffercache_evict' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
  raise exception 'Inspection read functions must deny client EXECUTE';
 end if;
 if not exists(select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pg_buffercache' and e.extversion='1.5' and n.nspname='kuro_cold_inspection') then
  raise exception 'Unexpected extension version or namespace';
 end if;
end $guard$;
commit;
