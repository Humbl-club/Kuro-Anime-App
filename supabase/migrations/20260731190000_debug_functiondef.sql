-- TEMPORARY debug utility: return the live body of recommend_ids_similar_to_seeds
-- (chasing an out-of-repo scoring band). Will be dropped by the next migration.
create or replace function public.debug_functiondef()
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  return (select pg_get_functiondef(p.oid)
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public'
            and p.proname = 'recommend_ids_similar_to_seeds'
          limit 1);
end;
$$;
revoke all on function public.debug_functiondef() from public;
grant execute on function public.debug_functiondef() to authenticated;
