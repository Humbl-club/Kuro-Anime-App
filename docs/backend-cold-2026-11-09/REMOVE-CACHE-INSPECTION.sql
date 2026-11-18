-- Only if the exact install receipt proves this experiment created the extension.
-- Save measured state and grants first. No CASCADE; never remove others' dependencies.
begin;
set local search_path=public,extensions;
set local lock_timeout='3s';
set local statement_timeout='30s';
drop extension pg_buffercache restrict;
commit;
