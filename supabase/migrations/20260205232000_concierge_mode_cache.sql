-- Concierge mode routing cache:
-- - Per-user cache to keep LLM router calls rare and cheap

begin;
create table if not exists public.concierge_mode_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  prompt_norm text not null,
  primary_mode_id text not null,
  secondary_mode_id text not null,
  used_llm boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, prompt_norm)
);
create index if not exists idx_concierge_mode_cache_user_updated on public.concierge_mode_cache (user_id, updated_at desc);
alter table public.concierge_mode_cache enable row level security;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'concierge_mode_cache_set_updated_at') then
    create trigger concierge_mode_cache_set_updated_at
      before update on public.concierge_mode_cache
      for each row execute function public.set_updated_at();
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='concierge_mode_cache' and policyname='concierge_mode_cache_own_all'
  ) then
    create policy concierge_mode_cache_own_all on public.concierge_mode_cache
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;
commit;
