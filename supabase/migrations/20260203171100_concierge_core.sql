-- Concierge core schema (production-grade foundation)
-- - Title search index for multilingual fuzzy matching
-- - Import sessions/items for staging + undo
-- - Concierge runs for observability
-- - Taste profiles for non-LLM personalization

begin;

-- Extensions used for fast fuzzy search.
create extension if not exists pg_trgm;

-- 1) Profiles (identity metadata)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  adult_opt_in boolean not null default false
);

alter table public.profiles enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_select_own'
  ) then
    create policy profiles_select_own on public.profiles
      for select using (auth.uid() = id);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_update_own'
  ) then
    create policy profiles_update_own on public.profiles
      for update using (auth.uid() = id) with check (auth.uid() = id);
  end if;
end $$;

-- Helper: keep updated_at fresh on update.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'profiles_set_updated_at') then
    create trigger profiles_set_updated_at
      before update on public.profiles
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- 2) Title normalization + search index
create or replace function public.normalize_title(p text)
returns text language sql immutable as $$
  select trim(regexp_replace(lower(coalesce(p, '')), '[^[:alnum:][:space:]]+', ' ', 'g'));
$$;

create table if not exists public.title_search (
  id bigserial primary key,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  variant_type text not null, -- english|romaji|native|synonym|alias|user_alias
  title_raw text not null,
  title_norm text not null,
  lang text,
  popularity integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_title_search_media on public.title_search (media_type, media_id);
create index if not exists idx_title_search_title_norm_trgm on public.title_search using gin (title_norm gin_trgm_ops);

-- Public read (derived from public catalog).
alter table public.title_search enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='title_search' and policyname='title_search_select_all'
  ) then
    create policy title_search_select_all on public.title_search
      for select using (true);
  end if;
end $$;

grant select on public.title_search to anon, authenticated;

-- RPC: fast fuzzy search against title_search
create or replace function public.search_titles(
  p_query text,
  p_media_type text default null,
  p_limit integer default 12
)
returns table (
  media_type text,
  media_id integer,
  variant_type text,
  title_raw text,
  score real
)
language sql stable as $$
  with q as (
    select public.normalize_title(p_query) as qn
  )
  select
    ts.media_type,
    ts.media_id,
    ts.variant_type,
    ts.title_raw,
    similarity(ts.title_norm, (select qn from q))::real as score
  from public.title_search ts, q
  where (p_media_type is null or ts.media_type = p_media_type)
    and ts.title_norm % (select qn from q)
  order by score desc, ts.popularity desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;

grant execute on function public.search_titles(text, text, integer) to anon, authenticated;

-- 3) Concierge import sessions (staging + undo)
create table if not exists public.import_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft','applied','failed','cancelled')),
  source text not null default 'chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_import_sessions_user_created on public.import_sessions (user_id, created_at desc);

alter table public.import_sessions enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='import_sessions' and policyname='import_sessions_own_all'
  ) then
    create policy import_sessions_own_all on public.import_sessions
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'import_sessions_set_updated_at') then
    create trigger import_sessions_set_updated_at
      before update on public.import_sessions
      for each row execute function public.set_updated_at();
  end if;
end $$;

create table if not exists public.import_session_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.import_sessions(id) on delete cascade,
  raw text not null,
  parsed jsonb not null default '{}'::jsonb,
  candidates jsonb not null default '[]'::jsonb,
  chosen jsonb,
  action jsonb,
  confidence real not null default 0,
  state text not null default 'needs_choice' check (state in ('needs_choice','ready','applied','error','skipped')),
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_import_session_items_session on public.import_session_items (session_id, created_at asc);

alter table public.import_session_items enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='import_session_items' and policyname='import_session_items_own_all'
  ) then
    create policy import_session_items_own_all on public.import_session_items
      for all using (
        exists (
          select 1 from public.import_sessions s
          where s.id = import_session_items.session_id
            and s.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.import_sessions s
          where s.id = import_session_items.session_id
            and s.user_id = auth.uid()
        )
      );
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'import_session_items_set_updated_at') then
    create trigger import_session_items_set_updated_at
      before update on public.import_session_items
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- 4) Concierge runs (observability)
create table if not exists public.concierge_runs (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  kind text not null, -- parse|recommend|apply|llm_router|llm_resolve
  status text not null default 'success' check (status in ('success','error','skipped')),
  input_chars integer,
  items_count integer,
  latency_ms integer,
  token_in integer,
  token_out integer,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists idx_concierge_runs_user_created on public.concierge_runs (user_id, created_at desc);

alter table public.concierge_runs enable row level security;
-- Default: deny for anon/authenticated. Service role can still write.

-- Service-side logging helper (Edge Functions using anon+JWT cannot write by default).
-- This RPC is SECURITY DEFINER so it can insert run logs while still attributing to auth.uid().
create or replace function public.log_concierge_run(
  p_kind text,
  p_status text default 'success',
  p_input_chars integer default null,
  p_items_count integer default null,
  p_latency_ms integer default null,
  p_token_in integer default null,
  p_token_out integer default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.concierge_runs (
    user_id, kind, status, input_chars, items_count, latency_ms, token_in, token_out, error
  ) values (
    auth.uid(), p_kind, coalesce(p_status,'success'), p_input_chars, p_items_count, p_latency_ms, p_token_in, p_token_out, p_error
  );
end;
$$;

revoke all on function public.log_concierge_run(text, text, integer, integer, integer, integer, integer, text) from public;
grant execute on function public.log_concierge_run(text, text, integer, integer, integer, integer, integer, text) to authenticated;

-- 5) Taste profile
create table if not exists public.user_taste_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  vector jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_taste_profiles enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='user_taste_profiles' and policyname='taste_profiles_own_all'
  ) then
    create policy taste_profiles_own_all on public.user_taste_profiles
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

commit;
