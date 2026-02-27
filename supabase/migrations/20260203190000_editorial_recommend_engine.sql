-- Editorial weighting for premium recommendations.
-- Goal: push classics/masterpieces up front; softly de-emphasize gimmick isekai/reincarnation/harem,
-- while still keeping everything searchable and accessible.

begin;
create table if not exists public.editorial_boosts (
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  weight integer not null default 0,
  label text not null default '',
  created_at timestamptz not null default now(),
  primary key (media_type, media_id)
);
create table if not exists public.editorial_penalty_tags (
  tag_id integer primary key references public.tags(id) on delete cascade,
  penalty integer not null default 0,
  reason text,
  created_at timestamptz not null default now()
);
-- Seed: core classics/masterpieces (internal ids, not AniList ids).
insert into public.editorial_boosts (media_type, media_id, weight, label) values
  ('MANGA', 14, 25, 'classic'),   -- Vagabond
  ('MANGA', 97, 22, 'classic'),   -- Kingdom
  ('MANGA', 30, 25, 'classic'),   -- 20th Century Boys
  ('MANGA', 29, 22, 'classic'),   -- Monster
  ('MANGA', 5, 25, 'classic'),    -- Berserk
  ('MANGA', 16, 18, 'classic'),   -- Vinland Saga
  ('MANGA', 11, 18, 'classic'),   -- Oyasumi Punpun
  ('MANGA', 98, 18, 'classic'),   -- Slam Dunk
  ('MANGA', 162, 16, 'classic'),  -- Real
  ('MANGA', 116, 14, 'classic'),  -- The Climber
  ('MANGA', 169, 18, 'classic'),  -- Akira
  ('ANIME', 12, 16, 'classic'),   -- Fullmetal Alchemist: Brotherhood
  ('ANIME', 29, 14, 'classic'),   -- Steins;Gate
  ('ANIME', 117, 12, 'classic'),  -- Cowboy Bebop
  ('ANIME', 1072, 14, 'classic')  -- Legend of the Galactic Heroes
on conflict (media_type, media_id) do update
  set weight = excluded.weight, label = excluded.label;
-- Seed: de-emphasize gimmick clusters by default (not a ban).
insert into public.editorial_penalty_tags (tag_id, penalty, reason) values
  (350, -12, 'Isekai'),
  (1023, -10, 'Reincarnation'),
  (358, -6, 'Female Harem'),
  (9154, -6, 'Male Harem'),
  (18064, -6, 'Mixed Gender Harem')
on conflict (tag_id) do update
  set penalty = excluded.penalty, reason = excluded.reason;
create or replace function public.recommend_ids_premium(
  p_media_type text,
  p_categories text[] default null,
  p_limit integer default 10,
  p_allow_gimmicks boolean default false
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
      p_categories as cats,
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
  )
  select *
  from (
    select
      a.id as media_id,
      coalesce(am.match_count, 0) as match_count,
      (
        -- Tag fit (dominant when the user gives a vibe)
        coalesce(am.match_count, 0) * 8
        -- Quality (multi-signal, not rating-only)
        + ln(1 + coalesce(a.favourites, 0)) * 2.0
        + ln(1 + coalesce(a.popularity, 0)) * 1.0
        + (coalesce(a.average_score, 0) / 10.0)
        -- Classic bias
        + case
            when a.start_date_year is not null and a.start_date_year <= 2005 then 7
            when a.start_date_year is not null and a.start_date_year <= 2015 then 4
            else 0
          end
        -- Editorial boost
        + coalesce(eb.weight, 0)
        -- Soft penalties (unless user asks for gimmicks)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(ap.penalty, 0)
          end
      )::real as score
    from public.anime a
    left join anime_match am on am.media_id = a.id
    left join public.editorial_boosts eb on eb.media_type = 'ANIME' and eb.media_id = a.id
    left join anime_pen ap on ap.media_id = a.id
    where p_media_type = 'ANIME'
      and (select user_id from me) is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
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
        + ln(1 + coalesce(m.favourites, 0)) * 2.0
        + ln(1 + coalesce(m.popularity, 0)) * 1.0
        + (coalesce(m.average_score, 0) / 10.0)
        + case
            when m.start_date_year is not null and m.start_date_year <= 2000 then 6
            when m.start_date_year is not null and m.start_date_year <= 2015 then 4
            else 0
          end
        + coalesce(eb.weight, 0)
        + case
            when (select allow_gimmicks from req) then 0
            else coalesce(mp.penalty, 0)
          end
      )::real as score
    from public.manga m
    left join manga_match mm on mm.media_id = m.id
    left join public.editorial_boosts eb on eb.media_type = 'MANGA' and eb.media_id = m.id
    left join manga_pen mp on mp.media_id = m.id
    where p_media_type = 'MANGA'
      and (select user_id from me) is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
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
grant execute on function public.recommend_ids_premium(text, text[], integer, boolean) to authenticated;
commit;
