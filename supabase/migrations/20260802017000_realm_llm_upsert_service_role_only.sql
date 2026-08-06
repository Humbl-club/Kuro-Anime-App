-- Security: revoke authenticated write on upsert_media_realm_llm.
-- Descriptors are world-readable editorial data; writers must be service_role
-- (realm-describe edge function) only. Swarm pass window is over.
-- Also drop temporary ops secret-peek helpers that scrape cron.job literals.

begin;

revoke execute on function public.upsert_media_realm_llm(jsonb) from authenticated;
revoke execute on function public.upsert_media_realm_llm(jsonb) from anon, public;
grant execute on function public.upsert_media_realm_llm(jsonb) to service_role;

-- Pending queue stays readable by authenticated (worker listing) + service_role.
-- Secret helpers: drop now that realm-describe + enqueue resolve secrets
-- via cron literal only inside SECURITY DEFINER enqueue (kept) / env for workers.

drop function if exists public._ops_peek_import_secret();
drop function if exists public._ops_list_import_crons();

-- Keep _ops_import_secret_from_cron for enqueue_realm_describe_batch only
-- (service_role / SECURITY DEFINER internal). Do not grant to clients — already
-- service_role-only. Document: replace with app.settings.import_secret GUC ASAP.

commit;
