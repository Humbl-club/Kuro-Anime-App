alter table public.anime_user_lists
  add column if not exists verdict text;

alter table public.manga_user_lists
  add column if not exists verdict text;

alter table public.anime_user_lists
  drop constraint if exists anime_user_lists_verdict_check;
alter table public.anime_user_lists
  add constraint anime_user_lists_verdict_check
  check (verdict is null or verdict in ('MASTERPIECE', 'OKAY', 'BAD'));

alter table public.manga_user_lists
  drop constraint if exists manga_user_lists_verdict_check;
alter table public.manga_user_lists
  add constraint manga_user_lists_verdict_check
  check (verdict is null or verdict in ('MASTERPIECE', 'OKAY', 'BAD'));
