-- Read-only metadata observation only. No catalogue row reads and NO cache eviction.
begin read only;
set local search_path=public,extensions;
set local statement_timeout='5s';
with targets as (
 select oid from pg_class where relnamespace='public'::regnamespace and relkind in ('r','m','i')
 union select reltoastrelid from pg_class where relnamespace='public'::regnamespace and reltoastrelid<>0
 union select i.indexrelid from pg_class c join pg_index i on i.indrelid=c.reltoastrelid where c.relnamespace='public'::regnamespace
), buffers as (
 select c.relname,c.relkind,count(*) as cached_blocks,count(*) filter(where b.isdirty) as dirty_blocks
 from extensions.pg_buffercache b join pg_class c on pg_relation_filenode(c.oid)=b.relfilenode
 where b.reldatabase=(select oid from pg_database where datname=current_database())
   and c.oid in(select oid from targets)
 group by c.relname,c.relkind
)
select jsonb_build_object('checked_at',clock_timestamp(),'postmaster_started_at',pg_postmaster_start_time(),
 'public_cached_blocks',coalesce((select sum(cached_blocks) from buffers),0),
 'public_relation_buffers',coalesce((select jsonb_agg(to_jsonb(x) order by relname) from buffers x),'[]'::jsonb)) as cold_state;
rollback;
