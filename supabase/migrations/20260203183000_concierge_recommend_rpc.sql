-- Deterministic recommendation primitives (no LLM).
-- Uses tags + join tables to produce "new to you" premium-ish candidates.

begin;
create or replace function public.recommend_ids_by_tag_categories(
  p_media_type text,
  p_categories text[],
  p_limit integer default 10
)
returns table (
  media_type text,
  media_id integer,
  match_count integer
)
language sql stable as $$
  select media_type, media_id, match_count from (
    select
      'ANIME'::text as media_type,
      at.anime_id as media_id,
      count(*)::int as match_count,
      max(a.average_score) as avg_score,
      max(a.popularity) as pop
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    join public.anime a on a.id = at.anime_id
    where p_media_type = 'ANIME'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'anime'
          and ul.media_id = at.anime_id
      )
    group by at.anime_id

    union all

    select
      'MANGA'::text as media_type,
      mt.manga_id as media_id,
      count(*)::int as match_count,
      max(m.average_score) as avg_score,
      max(m.popularity) as pop
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    join public.manga m on m.id = mt.manga_id
    where p_media_type = 'MANGA'
      and auth.uid() is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1
        from public.user_lists ul
        where ul.user_id = auth.uid()::text
          and ul.media_type = 'manga'
          and ul.media_id = mt.manga_id
      )
    group by mt.manga_id
  ) ranked
  order by match_count desc, avg_score desc nulls last, pop desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;
grant execute on function public.recommend_ids_by_tag_categories(text, text[], integer) to authenticated;
commit;
