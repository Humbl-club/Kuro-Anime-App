-- Realm Graph Tracks A+C:
--   1) canon_seed.blessed — owner veto without deleting citation rows (default true).
--   2) Discover Stage 4: The Shelf (tonight's realm) + Hidden Gem (high-tier/low-pop).
-- Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §5 / §8 Stage 4.
-- Flag discover_realm_rails_v1 @ 0% (same posture as personalized_new_to_you_v1).

begin;

-- ---------------------------------------------------------------------------
-- 1) Canon blessing
-- ---------------------------------------------------------------------------

alter table public.canon_seed
  add column if not exists blessed boolean not null default true;

comment on column public.canon_seed.blessed is
  'Owner blessing for Stage 2/3. Unblessed rows stay for citations but do not force tier=canon or merit-floor passes. All current seed rows default true; set false to veto.';

-- Tier force-canon: only blessed rows
-- Patch the matview definition by recreating from 150000 with blessed filter.
-- media_realm_profile depends on media_realm_tier — drop view first (170000 note).

-- Tier matview still uses all canon_seed rows; blessing is enforced at the
-- merit-floor helper below. Owner can unbless without a matview rebuild.

create or replace function public._is_blessed_canon(p_media_type text, p_anilist_id integer)
returns boolean
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.canon_seed cs
    where cs.media_type = p_media_type
      and cs.media_id = p_anilist_id
      and cs.blessed = true
  );
$$;

revoke all on function public._is_blessed_canon(text, integer) from public;
grant execute on function public._is_blessed_canon(text, integer) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Feature flag
-- ---------------------------------------------------------------------------

insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
values (
  'discover_realm_rails_v1',
  true,
  0,
  '{}',
  'Discover Stage 4: The Shelf (tonight''s realm) + Hidden Gem per realm'
)
on conflict (flag_name) do nothing;

-- ---------------------------------------------------------------------------
-- 3) Tonight's realm picker (shared)
-- ---------------------------------------------------------------------------

create or replace function public._tonight_realm(p_uid uuid)
returns text
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_realms text[];
  v_n int;
  v_doy int := extract(doy from (now() at time zone 'utc'))::int;
  v_realm text;
  v_meta_n int;
begin
  select array_agg(x.realm order by x.ord)
  into v_realms
  from (
    select (e->>'realm') as realm, ord::int as ord
    from public.user_taste_profiles p
    cross join lateral jsonb_array_elements(coalesce(p.vector->'realms', '[]'::jsonb))
      with ordinality as t(e, ord)
    where p.user_id = p_uid
      and nullif(e->>'realm', '') is not null
    order by ord
    limit 6
  ) x;

  v_n := coalesce(array_length(v_realms, 1), 0);
  if v_n > 0 then
    return v_realms[((v_doy - 1) % v_n) + 1];
  end if;

  select count(*)::int into v_meta_n from public.realm_meta;
  if coalesce(v_meta_n, 0) = 0 then
    return null;
  end if;

  select rm.realm into v_realm
  from public.realm_meta rm
  order by rm.sort
  offset ((v_doy - 1) % v_meta_n)
  limit 1;

  return v_realm;
end;
$$;

revoke all on function public._tonight_realm(uuid) from public;
grant execute on function public._tonight_realm(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) fetch_tonight_shelf
-- ---------------------------------------------------------------------------

create or replace function public.fetch_tonight_shelf(p_limit integer default 12)
returns table (
  realm text,
  display_name text,
  blurb text,
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim int := greatest(1, least(coalesce(p_limit, 12), 40));
  v_realm text;
  v_display text;
  v_blurb text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb
    into v_display, v_blurb
  from public.realm_meta rm
  where rm.realm = v_realm;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier,
      case t.tier
        when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1
      end as tier_rank,
      m.weight as mem_weight
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and m.weight >= 0.35
  ),
  anime_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.cover_image_medium,
      a.cover_image_color,
      a.genres,
      a.average_score,
      a.format,
      coalesce(a.season_year, a.start_date_year) as year,
      left(coalesce(a.description_normalized, ''), 300) as synopsis,
      a.episodes,
      null::integer as chapters,
      null::integer as volumes,
      coalesce(a.popularity, 0) as popularity
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )
  ),
  manga_cards as (
    select
      p.media_type,
      p.media_id,
      p.tier_rank,
      p.mem_weight,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.cover_image_medium,
      m.cover_image_color,
      m.genres,
      m.average_score,
      m.format,
      m.start_date_year,
      left(coalesce(m.description_normalized, ''), 300),
      null::integer,
      m.chapters,
      m.volumes,
      coalesce(m.popularity, 0)
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  ranked as (
    select * from anime_cards
    union all
    select * from manga_cards
  )
  select
    v_realm,
    v_display,
    v_blurb,
    r.media_type,
    r.media_id,
    r.title,
    r.cover_image_large,
    r.cover_image_medium,
    r.cover_image_color,
    r.genres,
    r.average_score,
    r.format,
    r.year,
    r.synopsis,
    r.episodes,
    r.chapters,
    r.volumes
  from ranked r
  order by r.tier_rank desc, r.average_score desc nulls last, r.mem_weight desc, r.media_id desc
  limit v_lim;
end;
$$;

revoke all on function public.fetch_tonight_shelf(integer) from public;
grant execute on function public.fetch_tonight_shelf(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) fetch_realm_hidden_gem — one weekly pick in tonight's realm
-- ---------------------------------------------------------------------------

create or replace function public.fetch_realm_hidden_gem()
returns table (
  realm text,
  display_name text,
  blurb text,
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  banner_image text,
  genres text[],
  score integer,
  year integer,
  format text,
  argument text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_realm text;
  v_display text;
  v_blurb text;
  v_week int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb into v_display, v_blurb
  from public.realm_meta rm where rm.realm = v_realm;

  v_week := (extract(epoch from date_trunc('week', now() at time zone 'utc')) / 86400)::int;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and t.tier in ('canon', 'acclaimed')
      and m.weight >= 0.35
  ),
  scored as (
    select
      p.media_type,
      p.media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.banner_image,
      a.genres,
      a.average_score as score,
      coalesce(a.season_year, a.start_date_year) as year,
      a.format,
      coalesce(a.popularity, 0) as popularity,
      left(coalesce(
        case when a.synopsis_enhanced_state = 'ready' then a.synopsis_enhanced end,
        a.description_normalized, ''
      ), 280) as argument
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
      and coalesce(a.average_score, 0) >= 75
      and coalesce(a.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'anime' and ul.media_id = a.id
      )

    union all

    select
      p.media_type,
      p.media_id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      coalesce(m.popularity, 0),
      left(coalesce(
        case when m.synopsis_enhanced_state = 'ready' then m.synopsis_enhanced end,
        m.description_normalized, ''
      ), 280)
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
      and coalesce(m.average_score, 0) >= 75
      and coalesce(m.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'manga' and ul.media_id = m.id
      )
  ),
  cut as (
    -- Low popularity among high-tier realm members: bottom half by popularity,
    -- then best score. Week-stable pick via hash.
    select s.*,
           percent_rank() over (order by s.popularity asc) as pop_pct,
           row_number() over (
             order by (hashtext(s.media_type || ':' || s.media_id::text || ':' || v_week::text))
           ) as rn
    from scored s
  )
  select
    v_realm,
    v_display,
    v_blurb,
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.banner_image,
    c.genres,
    c.score,
    c.year,
    c.format,
    public._discover_sentence_trim(
      coalesce(nullif(c.argument, ''), v_blurb),
      280
    )
  from cut c
  where c.pop_pct <= 0.55
  order by c.rn
  limit 1;
end;
$$;

revoke all on function public.fetch_realm_hidden_gem() from public;
grant execute on function public.fetch_realm_hidden_gem() to authenticated, service_role;


-- Merit floor honors blessed
create or replace function public.recommend_ids_similar_to_seeds(p_media_type text, p_seed_ids integer[], p_limit integer default 10, p_allow_gimmicks boolean default false)
returns table(media_id integer, overlap_count integer, score real)
language sql
stable
security definer
set search_path = public, extensions
as $function$
  with recursive req as (
    select
      greatest(1, least(coalesce(p_limit, 10), 50))::int as lim,
      p_allow_gimmicks as allow_gimmicks
  ),
  me as (
    select auth.uid()::text as user_id
  ),
  seed_vec as (
    -- Seed set vector = element-wise average of the seed title vectors.
    select v.tag_key, avg(v.w)::double precision as w
    from public.media_tag_vectors v
    where v.media_type = p_media_type
      and p_seed_ids is not null
      and v.media_id = any(p_seed_ids)
    group by v.tag_key
  ),
  seed_norm as (
    select nullif(sqrt(sum(sv.w * sv.w)), 0)::double precision as n
    from seed_vec sv
  ),
  seed_tier_rank as (
    -- Highest tier among seeds (canon 4 / acclaimed 3 / solid 2 / tail 1).
    select max(case t.tier
                 when 'canon' then 4
                 when 'acclaimed' then 3
                 when 'solid' then 2
                 else 1
               end) as r
    from public.media_realm_tier t
    where t.media_type = p_media_type
      and p_seed_ids is not null
      and t.media_id = any(p_seed_ids)
  ),
  seed_realms as (
    -- S: membership >= T. Canon seeds use 0.35 (spec top-realm floor) so
    -- weak secondary realms (e.g. Spirited Away grand-adventure @ 0.28)
    -- cannot open the gate to LN/shounen via shared-realm.
    select distinct m.realm
    from public.media_realm_membership_effective m
    where m.media_type = p_media_type
      and p_seed_ids is not null
      and m.media_id = any(p_seed_ids)
      and m.weight >= case
            when coalesce((select r from seed_tier_rank), 0) >= 4 then 0.35
            else public._realm_membership_threshold()
          end
  ),
  seed_rails as (
    -- curated_rails rails containing any seed (items key on AniList ids).
    select distinct i.rail_id
    from public.curated_rail_items i
    where p_seed_ids is not null
      and (
        (p_media_type = 'ANIME' and i.media_type = 'ANIME' and i.anilist_id in (
          select a2.anilist_id from public.anime a2 where a2.id = any(p_seed_ids)))
        or
        (p_media_type = 'MANGA' and i.media_type = 'MANGA' and i.anilist_id in (
          select m2.anilist_id from public.manga m2 where m2.id = any(p_seed_ids)))
      )
  ),
  rail_cands_anime as (
    select distinct a3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.anime a3 on a3.anilist_id = i.anilist_id
    where i.media_type = 'ANIME'
      and p_media_type = 'ANIME'
  ),
  rail_cands_manga as (
    select distinct m3.id as media_id
    from public.curated_rail_items i
    join seed_rails sr on sr.rail_id = i.rail_id
    join public.manga m3 on m3.anilist_id = i.anilist_id
    where i.media_type = 'MANGA'
      and p_media_type = 'MANGA'
  ),
  seed_genres_anime as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.anime a
    cross join unnest(coalesce(a.genres, '{}'::text[])) as g
    where p_media_type = 'ANIME'
      and p_seed_ids is not null
      and a.id = any(p_seed_ids)
  ),
  seed_genres_manga as (
    select array_remove(array_agg(distinct g), null)::text[] as genres
    from public.manga m
    cross join unnest(coalesce(m.genres, '{}'::text[])) as g
    where p_media_type = 'MANGA'
      and p_seed_ids is not null
      and m.id = any(p_seed_ids)
  ),
  cand_cos as (
    -- Full cosine over the shared vector space. No popularity/score/recency.
    select
      v.media_id,
      count(*)::integer as overlap_count,
      sum(v.w::double precision * sv.w)
        / ((select n from seed_norm) * max(v.l2_norm)::double precision) as similarity
    from public.media_tag_vectors v
    join seed_vec sv on sv.tag_key = v.tag_key
    where v.media_type = p_media_type
      and not (v.media_id = any(p_seed_ids))
    group by v.media_id
    having max(v.l2_norm) > 0
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
  anime_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%director%'
          and ys.role ilike '%director%'
      ) as shared_creator,
      exists (
        select 1
        from public.anime_studios xs
        join public.anime_studios ys
          on ys.studio_id = xs.studio_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
      ) as shared_studio,
      exists (
        select 1
        from public.anime_staff xs
        join public.anime_staff ys
          on ys.staff_id = xs.staff_id
         and ys.anime_id = any(p_seed_ids)
        where xs.anime_id = cc.media_id
          and xs.role ilike '%creator%'
          and ys.role ilike '%creator%'
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'ANIME'
  ),
  manga_craft as (
    select
      cc.media_id,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
          and xs.role ilike '%story%'
          and ys.role ilike '%story%'
      ) as shared_creator,
      false as shared_studio,
      exists (
        select 1
        from public.manga_authors xs
        join public.manga_authors ys
          on ys.author_id = xs.author_id
         and ys.manga_id = any(p_seed_ids)
        where xs.manga_id = cc.media_id
      ) as shared_author
    from cand_cos cc
    where p_media_type = 'MANGA'
  ),
  ranked as (
    select
      p_media_type as mt,
      a.id as media_id,
      cc.overlap_count as overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(ac.shared_creator, false)::int
            + 0.15 * coalesce(ac.shared_studio, false)::int
            + 0.5 * coalesce(ac.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
        - case when (select allow_gimmicks from req) then 0.0
               else greatest(0, coalesce(ap.penalty, 0))::double precision end
      )::real as score,
      coalesce(a.popularity, 0) as popularity
    from cand_cos cc
    join public.anime a on a.id = cc.media_id
    left join anime_craft ac on ac.media_id = cc.media_id
    left join anime_pen ap on ap.media_id = cc.media_id
    left join rail_cands_anime rc on rc.media_id = cc.media_id
    where p_media_type = 'ANIME'
      and cc.similarity is not null
      and a.cover_image_large is not null
      and coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_anime), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(a.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_anime)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_anime), 0) >= 4 then 2
              else 1
            end
      )
      and (
        not exists (select 1 from seed_realms)
        or exists (
          select 1
          from public.media_realm_membership_effective cm
          join seed_realms sr on sr.realm = cm.realm
          where cm.media_type = p_media_type
            and cm.media_id = a.id
            and cm.weight >= case
                  when coalesce((select r from seed_tier_rank), 0) >= 4 then 0.35
                  else public._realm_membership_threshold()
                end
            -- Canon seeds: shared secondary realm is not enough; candidate
            -- top realm must itself sit in S (blocks JJK via yokai alone).
            and (
              coalesce((select r from seed_tier_rank), 0) < 4
              or exists (
                select 1 from public.media_realm_tier ct2
                where ct2.media_type = p_media_type
                  and ct2.media_id = a.id
                  and ct2.realm in (select realm from seed_realms)
              )
            )
        )
        or exists (
          select 1
          from public.media_realm_tier ct
          join public.realm_affinity_effective e on e.realm_a = ct.realm
          join seed_realms sr on sr.realm = e.realm_b
          where ct.media_type = p_media_type
            and ct.media_id = a.id
            and e.affinity >= 0.9
        )
      )
      and (
        (select r from seed_tier_rank) is null
        or (
          select abs(
            case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
            - (select r from seed_tier_rank)
          )
          from public.media_realm_tier ct
          where ct.media_type = p_media_type
            and ct.media_id = a.id
        ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000): within-realm tier
        -- measures *good for its kind*; cross-realm gates to legend-tier
        -- require absolute merit. Non-canon seeds: no floor (tier
        -- compatibility alone). canon_seed.media_id = AniList id (150000).
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(a.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = a.anilist_id
            and cs.blessed = true
        )
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'anime'
          and ul.media_id = a.id
      )

    union all

    select
      p_media_type,
      m.id,
      cc.overlap_count,
      (
        cc.similarity * least(2.5,
          least(2.0, 1.0
            + 0.5 * coalesce(mc.shared_creator, false)::int
            + 0.15 * coalesce(mc.shared_studio, false)::int
            + 0.5 * coalesce(mc.shared_author, false)::int)
          * case when rc.media_id is not null then 1.25 else 1.0 end)
        - case when (select allow_gimmicks from req) then 0.0
               else greatest(0, coalesce(mp.penalty, 0))::double precision end
      )::real,
      coalesce(m.popularity, 0)
    from cand_cos cc
    join public.manga m on m.id = cc.media_id
    left join manga_craft mc on mc.media_id = cc.media_id
    left join manga_pen mp on mp.media_id = cc.media_id
    left join rail_cands_manga rc on rc.media_id = cc.media_id
    where p_media_type = 'MANGA'
      and cc.similarity is not null
      and m.cover_image_large is not null
      and coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and (
        coalesce((select array_length(genres, 1) from seed_genres_manga), 0) = 0
        or (
          select count(*)::int
          from unnest(coalesce(m.genres, '{}'::text[])) g
          where g in (select unnest(genres) from seed_genres_manga)
        ) >= case
              when coalesce((select array_length(genres, 1) from seed_genres_manga), 0) >= 4 then 2
              else 1
            end
      )
      and (
        not exists (select 1 from seed_realms)
        or exists (
          select 1
          from public.media_realm_membership_effective cm
          join seed_realms sr on sr.realm = cm.realm
          where cm.media_type = p_media_type
            and cm.media_id = m.id
            and cm.weight >= case
                  when coalesce((select r from seed_tier_rank), 0) >= 4 then 0.35
                  else public._realm_membership_threshold()
                end
            -- Canon seeds: shared secondary realm is not enough; candidate
            -- top realm must itself sit in S (blocks JJK via yokai alone).
            and (
              coalesce((select r from seed_tier_rank), 0) < 4
              or exists (
                select 1 from public.media_realm_tier ct2
                where ct2.media_type = p_media_type
                  and ct2.media_id = m.id
                  and ct2.realm in (select realm from seed_realms)
              )
            )
        )
        or exists (
          select 1
          from public.media_realm_tier ct
          join public.realm_affinity_effective e on e.realm_a = ct.realm
          join seed_realms sr on sr.realm = e.realm_b
          where ct.media_type = p_media_type
            and ct.media_id = m.id
            and e.affinity >= 0.9
        )
      )
      and (
        (select r from seed_tier_rank) is null
        or (
          select abs(
            case ct.tier when 'canon' then 4 when 'acclaimed' then 3 when 'solid' then 2 else 1 end
            - (select r from seed_tier_rank)
          )
          from public.media_realm_tier ct
          where ct.media_type = p_media_type
            and ct.media_id = m.id
        ) <= 1
      )
      and (
        -- Canon-seed absolute merit floor (20260731160000), manga branch.
        coalesce((select r from seed_tier_rank), 0) < 4
        or coalesce(m.average_score, 0) >= 75
        or exists (
          select 1 from public.canon_seed cs
          where cs.media_type = p_media_type
            and cs.media_id = m.anilist_id
            and cs.blessed = true
        )
      )
      and not exists (
        select 1 from public.user_lists ul
        where (select user_id from me) is not null
          and ul.user_id = (select user_id from me)
          and ul.media_type = 'manga'
          and ul.media_id = m.id
      )
  ),
  -- Franchise clusters over gate-passing candidates: connected components of
  -- media_relations (UNION keeps the recursion cycle-safe), labeled by the
  -- lexicographically smallest member key. Titles with no relations are
  -- singleton clusters via the coalesce in the final select.
  fr_nodes as (
    select ranked.mt as media_type, ranked.media_id from ranked
  ),
  fr_edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join fr_nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join fr_nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  fr_adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from fr_edges
    union
    select b_t, b_i, a_t, a_i from fr_edges
  ),
  fr_reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from fr_nodes n
    union
    select r.s_t, r.s_i, a.nt, a.ni
    from fr_reach r
    join fr_adj a on a.t = r.t and a.i = r.i
  ),
  fr_labels as (
    select r.t as media_type, r.i as media_id,
           min(r.s_t || ':' || r.s_i::text) as label
    from fr_reach r
    group by r.t, r.i
  )
  -- <= 1 candidate per franchise cluster: DISTINCT ON keeps the
  -- highest-scoring entry of each cluster (ties: popularity, then media_id).
  select d.media_id, d.overlap_count, d.score
  from (
    select distinct on (coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text))
      ranked.media_id,
      ranked.overlap_count,
      ranked.score,
      ranked.popularity
    from ranked
    left join fr_labels fr
      on fr.media_type = ranked.mt
     and fr.media_id = ranked.media_id
    order by coalesce(fr.label, ranked.mt || ':' || ranked.media_id::text),
             ranked.score desc,
             ranked.popularity desc,
             ranked.media_id desc
  ) d
  order by d.score desc, d.popularity desc, d.media_id desc
  limit (select lim from req);
$function$;



revoke all on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) from public;
grant execute on function public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean) to anon, authenticated;

commit;
