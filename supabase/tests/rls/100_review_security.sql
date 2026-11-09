-- @requires function public.rate_limit_hit(text,integer)
-- @requires function public.upsert_rec_edges(jsonb)
-- @requires function public.llm_global_budget_reserve(integer,integer,integer)
-- @requires function public.llm_global_budget_finalize(integer,integer)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.make_user(1001);
do $$
declare signature text;
begin
  foreach signature in array array[
    'public.rate_limit_hit(text,integer)', 'public.upsert_rec_edges(jsonb)',
    'public.llm_global_budget_reserve(integer,integer,integer)',
    'public.llm_global_budget_finalize(integer,integer)', 'public.check_email_exists(text)'
  ] loop
    perform tests.ok(signature || ': no client EXECUTE (including inherited PUBLIC)',
      not has_function_privilege('anon', signature, 'execute')
      and not has_function_privilege('authenticated', signature, 'execute')
      and has_function_privilege('service_role', signature, 'execute'));
  end loop;
end $$;
select tests.as_anon();
select tests.denied('anon cannot poison recommendation edges', $q$select public.upsert_rec_edges('[]')$q$);
select tests.denied('anon cannot poison rate buckets', $q$select public.rate_limit_hit('victim',60)$q$);
select tests.denied('anon cannot exhaust global budget', $q$select public.llm_global_budget_reserve(500000,2147483647,2147483647)$q$);
select tests.denied('anon cannot falsify global usage', $q$select public.llm_global_budget_finalize(0,500000)$q$);
select tests.as_user(tests.uid(1001));
select tests.denied('authenticated cannot falsify global usage either', $q$select public.llm_global_budget_finalize(0,500000)$q$);
select tests.reset();
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select tests.eq('service role can still use limiter helper', public.rate_limit_hit('review-fixture',60),1);
select tests.eq('service role still imports edges', public.upsert_rec_edges('[]'),0);
select tests.eq('service role can reserve global accounting',
  public.llm_global_budget_reserve(10,2147483647,2147483647)->>'allowed','true');
select tests.eq('service role can finalize global accounting',public.llm_global_budget_finalize(10,5)->>'success','true');
select tests.reset();
rollback;
