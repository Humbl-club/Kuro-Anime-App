-- Read-only; sampled every10seconds during the measured sequence.
select now() as checked_at, (select setting::int from pg_settings where name='max_connections') as max_connections,
 count(*) as connections,count(*) filter(where state='active' and pid<>pg_backend_pid()) as active,
 count(*) filter(where wait_event_type='Lock') as lock_waiters,
 coalesce(max(extract(epoch from(now()-query_start))) filter(where state='active' and pid<>pg_backend_pid()),0) as oldest_active_seconds,
 (select deadlocks from pg_stat_database where datname=current_database()) as deadlocks,
 (select temp_bytes from pg_stat_database where datname=current_database()) as temp_bytes,
 (select blks_read from pg_stat_database where datname=current_database()) as blks_read,
 (select blks_hit from pg_stat_database where datname=current_database()) as blks_hit
 from pg_stat_activity where datname=current_database();
