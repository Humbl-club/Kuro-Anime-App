-- PREPARED ONLY. Deploy the recommend/resolve service-budget clients BEFORE this migration.
-- No data is deleted, no credentials are rotated, no read RPCs lose their intended grants.
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

do $$
declare signature text;
begin
  foreach signature in array array[
    'public.upsert_rec_edges(jsonb)',
    'public.rate_limit_hit(text,integer)',
    'public.llm_global_budget_reserve(integer,integer,integer)',
    'public.llm_global_budget_finalize(integer,integer)',
    'public.check_email_exists(text)'
  ] loop
    if to_regprocedure(signature) is null then
      raise exception 'Missing required function: %', signature;
    end if;
    execute format('revoke all on function %s from public, anon, authenticated', signature);
    execute format('grant execute on function %s to service_role', signature);
    if has_function_privilege('anon', signature, 'execute')
       or has_function_privilege('authenticated', signature, 'execute') then
      raise exception 'Client EXECUTE remains on %', signature;
    end if;
  end loop;
end $$;
commit;
