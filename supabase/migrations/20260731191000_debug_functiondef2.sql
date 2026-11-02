-- TEMPORARY debug #2: list ALL overloads of recommend_ids_similar_to_seeds.
drop function if exists public.debug_functiondef();
create function public.debug_functiondef()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  return (select jsonb_agg(jsonb_build_object(
            'identity', p.oid::regprocedure::text,
            'body_len', length(pg_get_functiondef(p.oid)),
            'body', pg_get_functiondef(p.oid)))
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public'
            and p.proname = 'recommend_ids_similar_to_seeds');
end;
$$;
revoke all on function public.debug_functiondef() from public;
grant execute on function public.debug_functiondef() to authenticated;
