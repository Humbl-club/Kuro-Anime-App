-- @requires table public.taste_profile_recompute_queue
-- @requires function public.drain_taste_recompute_queue()
-- @requires function public.recompute_user_taste_profile(uuid)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.ok('background taste worker and math run without JIT; source math remains present',
 (select proconfig @> array['jit=off'] and length(prosrc)>1000 from pg_proc where oid='public.recompute_user_taste_profile(uuid)'::regprocedure)
 and (select proconfig @> array['jit=off'] and prosrc like '%limit 5%' and prosrc like '%skip locked%' from pg_proc where oid='public.drain_taste_recompute_queue()'::regprocedure));
select tests.ok('worker remains server-only for anonymous and authenticated callers',
 not has_function_privilege('anon','public.drain_taste_recompute_queue()','EXECUTE')
 and not has_function_privilege('authenticated','public.drain_taste_recompute_queue()','EXECUTE')
 and has_function_privilege('service_role','public.drain_taste_recompute_queue()','EXECUTE'));

-- Controlled recompute stand-in isolates scheduling/poison behavior from the old math fixture gaps.
create or replace function public.recompute_user_taste_profile(p_user_id uuid) returns void
language plpgsql security definer set search_path=public,extensions as $$
begin
 if p_user_id='10300000-0000-0000-0000-000000000002' then raise exception 'controlled poison';end if;
end $$;
insert into auth.users(id) select ('10300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,8) i;
delete from public.taste_profile_recompute_queue;
insert into public.taste_profile_recompute_queue(user_id,requested_at,processed_at)
 select ('10300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,now()-interval '1 hour'+i*interval '1 second',null from generate_series(1,8) i;
select public.drain_taste_recompute_queue();
select tests.eq('one drain processes exactly five eligible accounts',(select count(*) from public.taste_profile_recompute_queue where processed_at is not null),5::bigint);
select tests.eq('FIFO leaves the three newest accounts pending',(select array_agg(right(user_id::text,1) order by requested_at) from public.taste_profile_recompute_queue where processed_at is null),array['6','7','8']::text[]);
select tests.ok('poison account records an error without blocking later accounts',
 (select last_error->>'sqlstate'='P0001' and processed_at is not null from public.taste_profile_recompute_queue where user_id='10300000-0000-0000-0000-000000000002'));
select public.drain_taste_recompute_queue();
select tests.eq('next bounded drain clears the remaining backlog',(select count(*) from public.taste_profile_recompute_queue where processed_at is null),0::bigint);
rollback;
