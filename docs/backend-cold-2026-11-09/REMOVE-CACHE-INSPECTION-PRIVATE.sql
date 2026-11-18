-- Only with the creation receipt proving both objects belong to this experiment.
-- No CASCADE. Do not remove others' dependencies.
begin;
set local search_path=public,extensions;
set local lock_timeout='3s';
set local statement_timeout='30s';
drop extension pg_buffercache restrict;
drop schema kuro_cold_inspection restrict;
commit;
