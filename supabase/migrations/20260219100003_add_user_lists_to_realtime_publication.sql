-- Add user list tables to Realtime publication
-- Fixes silent failure where SupabaseService subscribes to changes
-- but never receives events because tables aren't in the publication
do $$
begin
  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'anime_user_lists'
  ) then
    alter publication supabase_realtime add table public.anime_user_lists;
  end if;

  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'manga_user_lists'
  ) then
    alter publication supabase_realtime add table public.manga_user_lists;
  end if;
end $$;
