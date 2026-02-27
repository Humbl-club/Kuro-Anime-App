begin;
-- Collection paging (keyset) so large libraries stay snappy.
-- Uses list tables' updated_at + id for stable ordering.

create index if not exists idx_anime_user_lists_user_updated_id
  on public.anime_user_lists (user_id, updated_at desc, id desc);
create index if not exists idx_manga_user_lists_user_updated_id
  on public.manga_user_lists (user_id, updated_at desc, id desc);
drop function if exists public.collection_anime_page(integer, timestamptz, integer, text);
create function public.collection_anime_page(
  p_limit integer default 80,
  p_cursor_updated_at timestamptz default null,
  p_cursor_row_id integer default null,
  p_list_type text default null
)
returns table (
  list_updated_at timestamptz,
  list_row_id integer,
  id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_large text,
  cover_image_medium text,
  banner_image text,
  format text,
  status text,
  episode_count integer,
  season_year integer,
  start_date_year integer,
  average_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with uid as (
    select auth.uid()::text as user_id
  ),
  params as (
    select greatest(1, least(coalesce(p_limit, 80), 120))::int as lim
  )
  select
    l.updated_at as list_updated_at,
    l.id as list_row_id,
    a.id,
    a.title_english,
    a.title_romaji,
    a.title_native,
    a.cover_image_large,
    a.cover_image_medium,
    a.banner_image,
    a.format,
    a.status,
    a.episodes as episode_count,
    a.season_year,
    a.start_date_year,
    a.average_score,
    a.popularity,
    a.trending,
    a.favourites,
    a.genres,
    a.created_at
  from public.anime_user_lists l
  join public.anime a on a.id = l.anime_id
  where
    l.user_id = (select user_id from uid)
    and (p_list_type is null or l.list_type = p_list_type)
    and (
      p_cursor_updated_at is null
      or l.updated_at < p_cursor_updated_at
      or (l.updated_at = p_cursor_updated_at and l.id < coalesce(p_cursor_row_id, 2147483647))
    )
  order by l.updated_at desc, l.id desc
  limit (select lim from params);
$$;
drop function if exists public.collection_manga_page(integer, timestamptz, integer, text);
create function public.collection_manga_page(
  p_limit integer default 80,
  p_cursor_updated_at timestamptz default null,
  p_cursor_row_id integer default null,
  p_list_type text default null
)
returns table (
  list_updated_at timestamptz,
  list_row_id integer,
  id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_large text,
  cover_image_medium text,
  format text,
  status text,
  chapter_count integer,
  start_date_year integer,
  average_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with uid as (
    select auth.uid()::text as user_id
  ),
  params as (
    select greatest(1, least(coalesce(p_limit, 80), 120))::int as lim
  )
  select
    l.updated_at as list_updated_at,
    l.id as list_row_id,
    m.id,
    m.title_english,
    m.title_romaji,
    m.title_native,
    m.cover_image_large,
    m.cover_image_medium,
    m.format,
    m.status,
    m.chapters as chapter_count,
    m.start_date_year,
    m.average_score,
    m.popularity,
    m.trending,
    m.favourites,
    m.genres,
    m.created_at
  from public.manga_user_lists l
  join public.manga m on m.id = l.manga_id
  where
    l.user_id = (select user_id from uid)
    and (p_list_type is null or l.list_type = p_list_type)
    and (
      p_cursor_updated_at is null
      or l.updated_at < p_cursor_updated_at
      or (l.updated_at = p_cursor_updated_at and l.id < coalesce(p_cursor_row_id, 2147483647))
    )
  order by l.updated_at desc, l.id desc
  limit (select lim from params);
$$;
grant execute on function public.collection_anime_page(integer, timestamptz, integer, text) to anon, authenticated;
grant execute on function public.collection_manga_page(integer, timestamptz, integer, text) to anon, authenticated;
commit;
