-- PREPARED: partial unique indexes do not support unqualified parent lookups/deletes.
-- Preserve existing uniqueness, NULL-number rows, RPCs, grants and RLS.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local search_path=public,extensions;
create index idx_episodes_anime_parent_v1 on public.episodes(anime_id);
create index idx_chapters_manga_parent_v1 on public.chapters(manga_id);
commit;
