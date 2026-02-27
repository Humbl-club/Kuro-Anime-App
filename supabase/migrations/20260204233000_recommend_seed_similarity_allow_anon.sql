-- Allow `recommend_ids_similar_to_seeds` to work for unauthenticated browsing.
-- When `auth.uid()` is null, we simply skip the "exclude items already in user list" filter.
-- This keeps Discover/Detail "More like this" usable pre-login while retaining personalization post-login.

begin;
create or replace function public.recommend_ids_similar_to_seeds(
  p_media_type text,
  p_seed_ids integer[],
  p_limit integer default 10,
  p_allow_gimmicks boolean default false
)
returns table (
  media_id integer,
  overlap_count integer,
  score real
)
language sql stable security definer
set search_path = public
as $$
  with req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  seed_tags_anime as (
    select distinct at.tag_id
    from public.anime_tags at
    where p_media_type = 'ANIME'
      and p_seed_ids is not null
      and at.anime_id = any(p_seed_ids)
  ),
  seed_tags_manga as (
    select distinct mt.tag_id
    from public.manga_tags mt
    where p_media_type = 'MANGA'
      and p_seed_ids is not null
      and mt.manga_id = any(p_seed_ids)
  ),
  anime_overlap as (
    select
      at.anime_id as media_id,
      count(*)::int as overlap_count
    from public.anime_tags at
    where p_media_type = 'ANIME'
      and at.tag_id in (select tag_id from seed_tags_anime)
    group by at.anime_id
  ),
  manga_overlap as (
    select
      mt.manga_id as media_id,
      count(*)::int as overlap_count
    from public.manga_tags mt
    where p_media_type = 'MANGA'
      and mt.tag_id in (select tag_id from seed_tags_manga)
    group by mt.manga_id
  ),
  anime_pen as (
    select at.anime_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.anime_tags at
    join public.editorial_penalty_tags p on p.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_pen as (
    select mt.manga_id as media_id, coalesce(sum(p.penalty), 0)::int as penalty
    from public.manga_tags mt
    join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
    group by mt.manga_id
  ),
  anime_boost as (
    select at.anime_id as media_id, coalesce(sum(b.boost), 0)::int as boost
    from public.anime_tags at
    join public.editorial_tag_boosts b on b.tag_id = at.tag_id
    group by at.anime_id
  ),
  manga_boost as (
    select mt.manga_id as media_id, coalesce(sum(b.boost), 0)::int as boost
    from public.manga_tags mt
    join public.editorial_tag_boosts b on b.tag_id = mt.tag_id
    group by mt.manga_id
  )
  select *
  from (
    select
      a.id as media_id,
      coalesce(ao.overlap_count, 0) as overlap_count,
      (
        coalesce(ao.overlap_count, 0) * 9
        + ln(1 + coalesce(a.favourites, 0)) * 2.0
        + ln(1 + coalesce(a.popularity, 0)) * 1.0
        + (coalesce(a.average_score, 0) / 10.0)
        + case
            when a.start_date_year is not null and a.start_date_year <= 2005 then 5
            when a.start_date_year is not null and a.start_date_year <= 2015 then 3
            else 0
          end
        + coalesce(eb.weight, 0)
        + coalesce(ab.boost, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(ap.penalty, 0)
          end
      )::real as score
    from public.anime a
    join anime_overlap ao on ao.media_id = a.id
    left join public.editorial_boosts eb on eb.media_type = 'ANIME' and eb.media_id = a.id
    left join anime_pen ap on ap.media_id = a.id
    left join anime_boost ab on ab.media_id = a.id
    where p_media_type = 'ANIME'
      and p_seed_ids is not null
      and not (a.id = any(p_seed_ids))
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      m.id as media_id,
      coalesce(mo.overlap_count, 0) as overlap_count,
      (
        coalesce(mo.overlap_count, 0) * 9
        + ln(1 + coalesce(m.favourites, 0)) * 2.0
        + ln(1 + coalesce(m.popularity, 0)) * 1.0
        + (coalesce(m.average_score, 0) / 10.0)
        + case
            when m.start_date_year is not null and m.start_date_year <= 2000 then 4
            when m.start_date_year is not null and m.start_date_year <= 2015 then 3
            else 0
          end
        + coalesce(eb.weight, 0)
        + coalesce(mb.boost, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(mp.penalty, 0)
          end
      )::real as score
    from public.manga m
    join manga_overlap mo on mo.media_id = m.id
    left join public.editorial_boosts eb on eb.media_type = 'MANGA' and eb.media_id = m.id
    left join manga_pen mp on mp.media_id = m.id
    left join manga_boost mb on mb.media_id = m.id
    where p_media_type = 'MANGA'
      and p_seed_ids is not null
      and not (m.id = any(p_seed_ids))
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ) ranked
  order by score desc
  limit (select lim from req);
$$;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to authenticated;
commit;
