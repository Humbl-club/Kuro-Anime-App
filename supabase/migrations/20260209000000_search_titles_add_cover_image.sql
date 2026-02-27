-- Add cover_image_medium to search_titles() so concierge import cards show posters.
-- Backwards-compatible: same function name/args, one new nullable column appended.

drop function if exists public.search_titles(text, text, integer);
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
  score real,
  year integer,
  format text,
  cover_image_medium text
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
    similarity(ts.title_norm, (select qn from q))::real as score,
    coalesce(a.start_date_year, m.start_date_year) as year,
    coalesce(a.format, m.format) as format,
    coalesce(a.cover_image_medium, m.cover_image_medium) as cover_image_medium
  from public.title_search ts
  cross join q
  left join public.anime a
    on ts.media_type = 'ANIME' and a.id = ts.media_id
  left join public.manga m
    on ts.media_type = 'MANGA' and m.id = ts.media_id
  where (p_media_type is null or ts.media_type = p_media_type)
    and ts.title_norm % (select qn from q)
  order by score desc, ts.popularity desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;
grant execute on function public.search_titles(text, text, integer) to anon, authenticated;
