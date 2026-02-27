-- Curated rails (pinned lists):
-- - Fully pinned "Classics" and "Start Here" rails keyed by AniList IDs
-- - Public read access (non-user private)
-- - RPC to fetch cards by rail_id with optional "exclude already in my list"

begin;
create table if not exists public.curated_rails (
  id text primary key,
  title text not null,
  media_type text not null check (media_type in ('ANIME','MANGA','BOTH')),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.curated_rails enable row level security;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'curated_rails_set_updated_at') then
    create trigger curated_rails_set_updated_at
      before update on public.curated_rails
      for each row execute function public.set_updated_at();
  end if;
end $$;
-- Public read: rails are editorial, not user-private.
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='curated_rails' and policyname='curated_rails_select_all'
  ) then
    create policy curated_rails_select_all on public.curated_rails
      for select using (true);
  end if;
end $$;
grant select on public.curated_rails to anon, authenticated;
create table if not exists public.curated_rail_items (
  rail_id text not null references public.curated_rails(id) on delete cascade,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  anilist_id integer not null,
  rank integer not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (rail_id, media_type, anilist_id)
);
create index if not exists idx_curated_rail_items_rail_rank on public.curated_rail_items (rail_id, media_type, rank);
alter table public.curated_rail_items enable row level security;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'curated_rail_items_set_updated_at') then
    create trigger curated_rail_items_set_updated_at
      before update on public.curated_rail_items
      for each row execute function public.set_updated_at();
  end if;
end $$;
-- Public read: items are editorial, not user-private.
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='curated_rail_items' and policyname='curated_rail_items_select_all'
  ) then
    create policy curated_rail_items_select_all on public.curated_rail_items
      for select using (true);
  end if;
end $$;
grant select on public.curated_rail_items to anon, authenticated;
-- Fetch curated rail cards with stable ordering.
-- Uses AniList IDs for linkage to catalog rows (anime.anilist_id / manga.anilist_id).
create or replace function public.curated_rail_cards(
  p_rail_id text,
  p_limit integer default 30,
  p_exclude_seen boolean default true
)
returns table (
  media_type text,
  media_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_medium text,
  average_score integer,
  year integer,
  format text,
  status text,
  site_url text,
  genres text[],
  signals text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select greatest(1, least(coalesce(p_limit, 30), 120))::int as lim
  ),
  flags as (
    select
      (case when p_rail_id ilike 'classics%' then true else false end) as is_classics,
      (case when p_rail_id ilike 'gateway%' or p_rail_id ilike 'start_here%' then true else false end) as is_gateway
  ),
  anime_items as (
    select
      'ANIME'::text as media_type,
      a.id as media_id,
      a.title_english, a.title_romaji, a.title_native,
      a.cover_image_medium,
      a.average_score,
      a.start_date_year as year,
      a.format,
      a.status,
      a.site_url,
      a.genres,
      array_remove(array[
        case when (select is_classics from flags) then 'CLASSIC' else null end,
        case when (select is_gateway from flags) then 'GATEWAY' else null end
      ], null) as signals,
      i.rank as r
    from public.curated_rail_items i
    join public.anime a on a.anilist_id = i.anilist_id
    where i.rail_id = p_rail_id
      and i.media_type = 'ANIME'
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        p_exclude_seen = false
        or auth.uid() is null
        or not exists (
          select 1 from public.user_lists ul
          where ul.user_id = auth.uid()::text
            and ul.media_type = 'anime'
            and ul.media_id = a.id
        )
      )
  ),
  manga_items as (
    select
      'MANGA'::text as media_type,
      m.id as media_id,
      m.title_english, m.title_romaji, m.title_native,
      m.cover_image_medium,
      m.average_score,
      m.start_date_year as year,
      m.format,
      m.status,
      m.site_url,
      m.genres,
      array_remove(array[
        case when (select is_classics from flags) then 'CLASSIC' else null end,
        case when (select is_gateway from flags) then 'GATEWAY' else null end
      ], null) as signals,
      i.rank as r
    from public.curated_rail_items i
    join public.manga m on m.anilist_id = i.anilist_id
    where i.rail_id = p_rail_id
      and i.media_type = 'MANGA'
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        p_exclude_seen = false
        or auth.uid() is null
        or not exists (
          select 1 from public.user_lists ul
          where ul.user_id = auth.uid()::text
            and ul.media_type = 'manga'
            and ul.media_id = m.id
        )
      )
  )
  select
    x.media_type,
    x.media_id,
    x.title_english,
    x.title_romaji,
    x.title_native,
    x.cover_image_medium,
    x.average_score,
    x.year,
    x.format,
    x.status,
    x.site_url,
    x.genres,
    x.signals
  from (
    select * from anime_items
    union all
    select * from manga_items
  ) x, params p
  order by x.r asc, x.media_id asc
  limit (select lim from params);
$$;
grant execute on function public.curated_rail_cards(text, integer, boolean) to anon, authenticated;
commit;
