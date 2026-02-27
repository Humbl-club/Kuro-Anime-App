-- Allow authenticated users to create their own `profiles` row.
-- Without this, client-side bootstrap can't insert on first login.

begin;
alter table public.profiles enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='profiles'
      and policyname='profiles_insert_own'
  ) then
    create policy profiles_insert_own on public.profiles
      for insert
      with check (auth.uid() = id);
  end if;
end $$;
commit;
