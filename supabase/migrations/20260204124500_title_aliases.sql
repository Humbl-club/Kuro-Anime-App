-- User-specific title aliases for "magic" parsing.
-- Stores previously-confirmed mappings from noisy user input -> canonical media id.

begin;
create table if not exists public.title_aliases (
  user_id uuid not null references auth.users(id) on delete cascade,
  alias_norm text not null,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  title_raw text,
  hits integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, alias_norm, media_type)
);
create index if not exists idx_title_aliases_user_updated on public.title_aliases (user_id, updated_at desc);
create index if not exists idx_title_aliases_user_alias on public.title_aliases (user_id, alias_norm);
alter table public.title_aliases enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='title_aliases' and policyname='title_aliases_own_all'
  ) then
    create policy title_aliases_own_all on public.title_aliases
      for all
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'title_aliases_set_updated_at') then
    create trigger title_aliases_set_updated_at
      before update on public.title_aliases
      for each row execute function public.set_updated_at();
  end if;
end $$;
commit;
