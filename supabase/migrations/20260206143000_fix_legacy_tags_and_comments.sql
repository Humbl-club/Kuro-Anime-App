-- Fix legacy schema drift on existing DBs:
-- - public.tags.kitsu_id missing
-- - public.anime_comments.user_id + public.manga_comments.user_id were INTEGER in early schema
--   but policies compare to auth.uid()::text, so convert to TEXT

begin;
-- Add kitsu_id if missing (keep uniqueness for non-null values).
alter table public.tags add column if not exists kitsu_id integer;
create unique index if not exists idx_tags_kitsu_id_unique on public.tags(kitsu_id) where kitsu_id is not null;
-- Convert comments.user_id from integer -> text only if needed.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'anime_comments'
      and column_name = 'user_id'
      and data_type = 'integer'
  ) then
    -- Policies depend on column types. Drop/recreate the policy so ALTER TYPE can run.
    execute format('drop policy if exists %I on public.anime_comments', 'Users can manage their own comments');
    alter table public.anime_comments
      alter column user_id type text using user_id::text;
    execute format(
      'create policy %I on public.anime_comments for all using (auth.uid()::text = user_id) with check (auth.uid()::text = user_id)',
      'Users can manage their own comments'
    );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'manga_comments'
      and column_name = 'user_id'
      and data_type = 'integer'
  ) then
    execute format('drop policy if exists %I on public.manga_comments', 'Users can manage their own comments');
    alter table public.manga_comments
      alter column user_id type text using user_id::text;
    execute format(
      'create policy %I on public.manga_comments for all using (auth.uid()::text = user_id) with check (auth.uid()::text = user_id)',
      'Users can manage their own comments'
    );
  end if;
end $$;
commit;
