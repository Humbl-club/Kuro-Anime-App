-- Only the throwaway local cluster. Reading metadata does not pre-read catalogue relations.
\set ON_ERROR_STOP on
do $$declare n int;begin
select count(*) into n from extensions.pg_buffercache b join pg_class c on c.relfilenode=b.relfilenode
where b.reldatabase=(select oid from pg_database where datname=current_database())
and c.relnamespace='public'::regnamespace and (c.relname in ('anime','manga','media_realm_membership') or c.relname like 'mv_%' or c.relname like 'idx_%');
assert n=0,'Local catalogue buffers must be empty before the first measured query';
raise notice 'LOCAL_BUFFER_COLD verified: catalogue pages=%, postmaster=%',n,pg_postmaster_start_time();
end$$;
