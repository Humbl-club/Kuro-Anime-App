-- Improve premium recommendations:
-- - Boost story-first signals (Seinen + narrative-heavy tags)
-- - Add a few more soft penalties for gimmick clusters
-- - Add lightweight title-based penalties for "reborn / another world / slime" phrasing

begin;

create table if not exists public.editorial_tag_boosts (
  tag_id integer primary key references public.tags(id) on delete cascade,
  boost integer not null default 0,
  reason text,
  created_at timestamptz not null default now()
);

-- Story-first boosts (small but meaningful; not a hard filter).
insert into public.editorial_tag_boosts (tag_id, boost, reason) values
  (170, 6, 'Seinen'),
  (3, 2, 'Tragedy'),
  (22, 2, 'Coming of Age'),
  (59, 2, 'Crime'),
  (154, 1, 'Politics'),
  (245, 1, 'War'),
  (65, 1, 'Philosophy'),
  (49, 1, 'Historical')
on conflict (tag_id) do update
  set boost = excluded.boost, reason = excluded.reason;

-- A couple more soft penalties for default recommendations (still searchable).
insert into public.editorial_penalty_tags (tag_id, penalty, reason) values
  (19294, -8, 'Reverse Isekai'),
  (156, -3, 'Video Games'),
  (848, -3, 'Dungeon')
on conflict (tag_id) do update
  set penalty = excluded.penalty, reason = excluded.reason;

create or replace function public.recommend_ids_premium(
  p_media_type text,
  p_categories text[] default null,
  p_limit integer default 10,
  p_allow_gimmicks boolean default false,
  p_focus_tag_ids integer[] default null
)
returns table (
  media_id integer,
  match_count integer,
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
  ),
  anime_match as (
    select
      at.anime_id as media_id,
      count(*)::int as match_count
    from public.anime_tags at
    join public.tags t on t.id = at.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by at.anime_id
  ),
  manga_match as (
    select
      mt.manga_id as media_id,
      count(*)::int as match_count
    from public.manga_tags mt
    join public.tags t on t.id = mt.tag_id
    where p_categories is not null
      and t.category = any(p_categories)
      and coalesce(t.is_adult, false) = false
      and coalesce(t.category, '') <> 'Sexual Content'
    group by mt.manga_id
  ),
  anime_focus as (
    select
      at.anime_id as media_id,
      count(*)::int as focus_count
    from public.anime_tags at
    where p_focus_tag_ids is not null
      and at.tag_id = any(p_focus_tag_ids)
    group by at.anime_id
  ),
  manga_focus as (
    select
      mt.manga_id as media_id,
      count(*)::int as focus_count
    from public.manga_tags mt
    where p_focus_tag_ids is not null
      and mt.tag_id = any(p_focus_tag_ids)
    group by mt.manga_id
  )
  select *
  from (
    select
      a.id as media_id,
      coalesce(am.match_count, 0) as match_count,
      (
        coalesce(am.match_count, 0) * 8
        + coalesce(af.focus_count, 0) * 18
        + ln(1 + coalesce(a.favourites, 0)) * 2.0
        + ln(1 + coalesce(a.popularity, 0)) * 1.0
        + (coalesce(a.average_score, 0) / 10.0)
        + case
            when a.start_date_year is not null and a.start_date_year <= 2005 then 7
            when a.start_date_year is not null and a.start_date_year <= 2015 then 4
            else 0
          end
        + coalesce(eb.weight, 0)
        + coalesce(ab.boost, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(ap.penalty, 0)
          end
        + case
            when (select allow_gimmicks from req) then 0
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%reincarnat%' then -8
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%tensei%' then -8
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%reborn%' then -8
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%slime%' then -8
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%another world%' then -6
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%in another world%' then -6
            when lower(coalesce(a.title_english, a.title_romaji, a.title_native, '')) like '%isekai%' then -6
            else 0
          end
        + case
            when (select allow_gimmicks from req) then 0
            when coalesce(a.average_score, 0) < 70 and coalesce(a.favourites, 0) < 2000 then -6
            else 0
          end
      )::real as score
    from public.anime a
    left join anime_match am on am.media_id = a.id
    left join anime_focus af on af.media_id = a.id
    left join public.editorial_boosts eb on eb.media_type = 'ANIME' and eb.media_id = a.id
    left join anime_pen ap on ap.media_id = a.id
    left join anime_boost ab on ab.media_id = a.id
    where p_media_type = 'ANIME'
      and (select user_id from me) is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (p_focus_tag_ids is null or af.focus_count is not null)
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      m.id as media_id,
      coalesce(mm.match_count, 0) as match_count,
      (
        coalesce(mm.match_count, 0) * 8
        + coalesce(mf.focus_count, 0) * 18
        + ln(1 + coalesce(m.favourites, 0)) * 2.0
        + ln(1 + coalesce(m.popularity, 0)) * 1.0
        + (coalesce(m.average_score, 0) / 10.0)
        + case
            when m.start_date_year is not null and m.start_date_year <= 2000 then 6
            when m.start_date_year is not null and m.start_date_year <= 2015 then 4
            else 0
          end
        + coalesce(eb.weight, 0)
        + coalesce(mb.boost, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(mp.penalty, 0)
          end
        + case
            when (select allow_gimmicks from req) then 0
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%reincarnat%' then -8
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%tensei%' then -8
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%reborn%' then -8
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%slime%' then -8
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%another world%' then -6
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%in another world%' then -6
            when lower(coalesce(m.title_english, m.title_romaji, m.title_native, '')) like '%isekai%' then -6
            else 0
          end
        + case
            when (select allow_gimmicks from req) then 0
            when coalesce(m.average_score, 0) < 70 and coalesce(m.favourites, 0) < 2000 then -6
            else 0
          end
      )::real as score
    from public.manga m
    left join manga_match mm on mm.media_id = m.id
    left join manga_focus mf on mf.media_id = m.id
    left join public.editorial_boosts eb on eb.media_type = 'MANGA' and eb.media_id = m.id
    left join manga_pen mp on mp.media_id = m.id
    left join manga_boost mb on mb.media_id = m.id
    where p_media_type = 'MANGA'
      and (select user_id from me) is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (p_focus_tag_ids is null or mf.focus_count is not null)
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ) ranked
  order by score desc
  limit (select lim from req);
$$;

grant execute on function public.recommend_ids_premium(text, text[], integer, boolean, integer[]) to authenticated;

commit;

