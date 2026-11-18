-- Production: run only under approval for the reviewed cold-start experiment.
-- Temporary observation, not an application dependency. Stop if it already exists.
begin;
set local search_path=public,extensions;
set local lock_timeout='3s';
set local statement_timeout='30s';
do $install$
begin
 if exists(select 1 from pg_extension where extname='pg_buffercache') then
  raise exception 'Cache inspector already exists; preserve its owner and grants, stop for reconciliation';
 end if;
end;
$install$;
create extension pg_buffercache with schema extensions version '1.4';
do $no_eviction$ begin
 if to_regprocedure('extensions.pg_buffercache_evict(integer)') is not null then
  raise exception 'Metadata-only inspector must not expose an eviction function';
 end if;
end $no_eviction$;
-- Managed-platform adaptation:1.4 contains only metadata inspection, with no eviction function.
-- Preserve full effective client denial; never grant owner membership or weaken ACL checks.
do $privileges$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_depend d on d.classid='pg_proc'::regclass and d.objid=p.oid join pg_extension e on e.oid=d.refobjid where e.extname='pg_buffercache' and d.deptype='e' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
 revoke all on extensions.pg_buffercache from public,anon,authenticated;
 if has_table_privilege('anon','extensions.pg_buffercache','select') or
    has_table_privilege('authenticated','extensions.pg_buffercache','select') then
  raise exception 'Cache inspection view must remain inaccessible to clients';
 end if;
 if exists(select 1 from pg_proc p join pg_depend d on d.classid='pg_proc'::regclass and d.objid=p.oid join pg_extension e on e.oid=d.refobjid where e.extname='pg_buffercache' and d.deptype='e' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
  raise exception 'Cache inspection must remain inaccessible to clients';
 end if;
end;
$privileges$;
commit;
