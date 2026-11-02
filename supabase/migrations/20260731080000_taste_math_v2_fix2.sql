-- FIX2 2026-07-31: taste-math v2 verification run 2 (P0 bare UPDATEs, P3 residuals).
-- Apply after 20260731070000. Two recreated functions, nothing else.
--
-- 1) P0 (still down): pg_safeupdate also blocks bare UPDATE. The 070000 deck
--    body had exactly two UPDATEs without WHERE on the session temp table
--    (cluster assign ~line 621, top_tags assign ~line 844; the other ~15
--    UPDATEs all carry WHERE). Both get `where true`; body otherwise identical
--    to 070000. Audit: every SECURITY INVOKER function in 060000+070000 was
--    grepped for bare update/delete (pg_safeupdate only bites invoker paths
--    running as authenticated; SECURITY DEFINER paths run as the owner):
--      _taste_deck_title_tag_keys   invoker, read-only (no DML)
--      _taste_genre_cluster         invoker, read-only (no DML)
--      fetch_taste_deck_batch       invoker, temp-table DML -> 2 fixed here
--      fetch_personalized_new_to_you invoker, no direct DML (definer helpers)
--      fetch_my_taste_profile       invoker, read-only (010000, audited too)
--    Definer functions audited for completeness (not pg_safeupdate-exposed,
--    all their DML already carries WHERE): record_taste_deck_signal,
--    recompute_user_taste_profile, drain_taste_recompute_queue,
--    _taste_deck_apply_tag_stats, _taste_recent_impressed_ids,
--    _taste_stamp_impressions, recommend_ids_similar_to_seeds.
-- 2) P3 residual: stored vector was top-80 by abs and genre keys got cut.
--    New rule: top 60 tag keys by abs + ALL 'genre:' keys with abs(w) > 0.001.
-- 3) P3 residual: loved-yet-avoided artifact. avoided_tags now requires the
--    old floors (>= 2 negative events OR cumulative <= -0.8) AND strictly
--    negative net sentiment (pos_sum + neg_sum < 0).
-- Everything else from 070000 unchanged (symmetric caps, floors, evidence,
-- genre rescue matview, narrowed NTY penalty, revokes).

drop function if exists public.fetch_taste_deck_batch(integer);

create function public.fetch_taste_deck_batch(p_limit integer default 12)
returns table (
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
  volumes integer,
  seasons_count integer,
  has_dub boolean,
  has_sub boolean
)
language plpgsql
volatile
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(2, least(coalesce(p_limit, 12), 40));
  v_half integer;
  v_pool_lim integer;
  v_profile jsonb;
  v_avoided jsonb := '[]'::jsonb;
  v_unorm double precision := 0;
  v_evidence double precision := 0;
  v_explore_ratio double precision;
  v_explore_slots integer;
  v_exploit_slots integer;
  v_cluster_cap integer;
  v_franchise_cap integer;
  v_a_count integer;
  v_m_count integer;
  v_a_take integer;
  v_m_take integer;
  v_pa integer := 0;
  v_pm integer := 0;
  v_picked integer := 0;
  v_explore_target integer;
  v_prog boolean;
  v_clusters text[] := array['action', 'drama', 'fantasy', 'scifi', 'comedy', 'dark'];
  v_strata text[] := array['head', 'mid', 'gems'];
  v_ci integer;
  v_si integer;
  v_min_s double precision;
  v_max_s double precision;
  v_mmr double precision;
  v_best_mmr double precision;
  v_max_ovl double precision;
  v_tags text[];
  v_slot text;
  r record;
  v_best record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  v_half := v_lim / 2;
  -- Deeper than v1 (v_lim per type) so the dealing policy has room to work;
  -- <= 60 rows for the default batch of 12.
  v_pool_lim := greatest(v_lim + 18, 24);
  -- Hard caps, scaled from the spec's <=4/12 cluster and <=2/12 franchise.
  v_cluster_cap := greatest(1, (v_lim * 4) / 12);
  v_franchise_cap := greatest(1, (v_lim * 2) / 12);

  select p.vector into v_profile
  from public.user_taste_profiles p
  where p.user_id = v_uid;

  if v_profile is not null then
    v_evidence := coalesce((v_profile->>'evidence')::double precision, 0);
    v_avoided := coalesce(v_profile->'avoided_tags', '[]'::jsonb);
    select coalesce(sqrt(sum(uv.uval * uv.uval)), 0)
      into v_unorm
    from (
      select value::double precision as uval
      from jsonb_each_text(v_profile->'vector')
    ) uv;
  end if;

  -- Explore/exploit split from evidence mass (new user -> 0.75 -> 9 of 12 explore).
  v_explore_ratio := greatest(0.25, 0.75 * exp(-v_evidence / 50.0));
  v_explore_slots := greatest(0, least(v_lim, round(v_lim * v_explore_ratio)::integer));
  v_exploit_slots := v_lim - v_explore_slots;

  create temporary table if not exists taste_deck_cand (
    media_type text not null,
    media_id integer not null,
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
    volumes integer,
    mirrored boolean,
    popularity integer,
    cluster text,
    stratum text,
    fit double precision default 0,
    ucb double precision default 1,
    slot text,
    slot_raw double precision,
    slot_score double precision,
    franchise text,
    top_tags text[],
    picked boolean not null default false,
    primary key (media_type, media_id)
  ) on commit drop;
  delete from taste_deck_cand where true; -- P0: pg_safeupdate blocks bare DELETE

  -- Selection pool: identical eligibility to v1 (score >= 70, not adult, no
  -- Ecchi/Hentai, ancillary formats excluded, not in lists, no prior deck
  -- signal), mirrored-first pull, just deeper.
  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'ANIME', a.id,
    coalesce(nullif(a.title_english, ''), a.title_romaji),
    a.cover_image_large, a.cover_image_medium, a.cover_image_color,
    a.genres, a.average_score, a.format,
    coalesce(a.season_year, a.start_date_year),
    left(coalesce(a.description_normalized, ''), 300),
    a.episodes, null::integer, null::integer,
    (a.cover_image_large like '%/storage/v1/%'),
    coalesce(a.popularity, 0)
  from public.anime a
  where coalesce(a.is_adult, false) = false
    and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
    and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
    and coalesce(a.average_score, 0) >= 70
    and a.cover_image_large is not null
    and not exists (
      select 1 from public.anime_user_lists ul
      where ul.user_id = v_uid::text
        and ul.anime_id = a.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'ANIME'
        and e.media_id = a.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
    )
  order by (a.cover_image_large like '%/storage/v1/%') desc, coalesce(a.popularity, 0) desc, a.id desc
  limit v_pool_lim;

  insert into taste_deck_cand (
    media_type, media_id, title, cover_image_large, cover_image_medium,
    cover_image_color, genres, average_score, format, year, synopsis,
    episodes, chapters, volumes, mirrored, popularity
  )
  select
    'MANGA', m.id,
    coalesce(nullif(m.title_english, ''), m.title_romaji),
    m.cover_image_large, m.cover_image_medium, m.cover_image_color,
    m.genres, m.average_score, m.format,
    m.start_date_year,
    left(coalesce(m.description_normalized, ''), 300),
    null::integer, m.chapters, m.volumes,
    (m.cover_image_large like '%/storage/v1/%'),
    coalesce(m.popularity, 0)
  from public.manga m
  where coalesce(m.is_adult, false) = false
    and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
    and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
    and coalesce(m.average_score, 0) >= 70
    and m.cover_image_large is not null
    and not exists (
      select 1 from public.manga_user_lists ul
      where ul.user_id = v_uid::text
        and ul.manga_id = m.id
    )
    and not exists (
      select 1 from public.taste_signal_events e
      where e.user_id = v_uid
        and e.media_type = 'MANGA'
        and e.media_id = m.id
        and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
    )
  order by (m.cover_image_large like '%/storage/v1/%') desc, coalesce(m.popularity, 0) desc, m.id desc
  limit v_pool_lim;

  update taste_deck_cand c
  set cluster = public._taste_genre_cluster(c.genres)
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

  -- Popularity strata over the pool (percent_rank ascending by popularity):
  -- head pr >= 0.9; gems pr < 0.4 with average_score >= 75; mid 0.1 <= pr < 0.6;
  -- anything left (bottom decile without the gems score, 0.4-0.6 without mid is
  -- impossible) -> 'tail' (only reachable via exploit or starvation fill).
  with s as (
    select
      c.media_type,
      c.media_id,
      percent_rank() over (order by c.popularity asc, c.media_id asc) as pr
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set stratum = case
    when s.pr >= 0.9 then 'head'
    when s.pr < 0.4 and c.average_score >= 75 then 'gems'
    when s.pr >= 0.1 and s.pr < 0.6 then 'mid'
    else 'tail'
  end
  from s
  where s.media_type = c.media_type
    and s.media_id = c.media_id;

  -- Exploit fit: cosine(user vector, title vector) in the shared space.
  -- The stored user vector is L2-normalized; v_unorm recomputes its true norm
  -- (jsonb rounding) so the cosine stays exact.
  if v_unorm > 0 then
    update taste_deck_cand c
    set fit = f.fit
    from (
      select
        c2.media_type,
        c2.media_id,
        case
          when max(v.l2_norm)::double precision > 0
            then least(greatest(
              coalesce(sum(uv.uval * v.w::double precision), 0.0)
                / (v_unorm * max(v.l2_norm)::double precision),
              -1.0), 1.0)
          else 0.0
        end as fit
      from taste_deck_cand c2
      left join public.media_tag_vectors v
        on v.media_type = c2.media_type
       and v.media_id = c2.media_id
      left join (
        select key, value::double precision as uval
        from jsonb_each_text(v_profile->'vector')
      ) uv on uv.key = v.tag_key
      group by c2.media_type, c2.media_id
    ) f
    where f.media_type = c.media_type
      and f.media_id = c.media_id;
  end if;

  -- Explore UCB: mean over the title's deck-stats keys (rank >= 40 tags plus
  -- 'genre:' keys) of (alpha+1)/(alpha+beta+2) + 0.5/sqrt(alpha+beta+1);
  -- missing stat rows -> alpha = beta = 0 (Beta(1,1) prior baked in).
  update taste_deck_cand c
  set ucb = x.ucb
  from (
    select
      c2.media_type,
      c2.media_id,
      avg(
        (coalesce(s.alpha, 0)::double precision + 1.0)
          / (coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 2.0)
        + 0.5 / sqrt(coalesce(s.alpha, 0)::double precision + coalesce(s.beta, 0)::double precision + 1.0)
      ) as ucb
    from taste_deck_cand c2
    left join lateral (
      select k.tag_key
      from public._taste_deck_title_tag_keys(c2.media_type, c2.media_id) k
    ) keys on true
    left join public.taste_tag_stats s
      on s.user_id = v_uid
     and s.tag_key = keys.tag_key
    group by c2.media_type, c2.media_id
  ) x
  where x.media_type = c.media_type
    and x.media_id = c.media_id;

  -- Slot candidates. Buffers (+6 each side) give MMR and the hard caps room
  -- to skip without starving the batch.
  with ranked as (
    select
      c.media_type,
      c.media_id,
      c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) as es,
      row_number() over (
        order by c.fit * (0.5 + 0.5 * c.average_score::double precision / 100.0) desc,
                 c.popularity desc, c.media_id desc
      ) as rn
    from taste_deck_cand c
  )
  update taste_deck_cand c
  set slot = 'exploit',
      slot_raw = rk.es
  from ranked rk
  where rk.media_type = c.media_type
    and rk.media_id = c.media_id
    and rk.rn <= v_exploit_slots + 6;

  -- Stratified explore: round-robin over 6 clusters x 3 strata, best UCB per
  -- cell, skipping cells that run dry. A title already slotted for exploit is
  -- not double-dealt as explore.
  v_explore_target := v_explore_slots + 6;
  <<explore_loop>>
  while (select count(*) from taste_deck_cand where slot = 'explore') < v_explore_target loop
    v_prog := false;
    for v_ci in 1..6 loop
      for v_si in 1..3 loop
        select c2.media_type, c2.media_id, c2.ucb
          into r
        from taste_deck_cand c2
        where c2.slot is null
          and c2.cluster = v_clusters[v_ci]
          and c2.stratum = v_strata[v_si]
        order by c2.ucb desc, c2.popularity desc, c2.media_id desc
        limit 1;
        if found then
          update taste_deck_cand c
          set slot = 'explore', slot_raw = r.ucb
          where c.media_type = r.media_type
            and c.media_id = r.media_id;
          v_prog := true;
          exit explore_loop when (select count(*) from taste_deck_cand where slot = 'explore') >= v_explore_target;
        end if;
      end loop;
    end loop;
    exit when not v_prog;
  end loop;

  -- Negative-space probe: p = 0.10 per batch, from the *avoided* list only.
  if random() < 0.10 and coalesce(jsonb_array_length(v_avoided), 0) > 0 then
    select c2.media_type, c2.media_id, c2.ucb
      into r
    from taste_deck_cand c2
    where c2.slot is null
      and exists (
        select 1
        from public.anime_tags at
        join public.tags t on t.id = at.tag_id
        where c2.media_type = 'ANIME'
          and at.anime_id = c2.media_id
          and coalesce(at.rank, 0) >= 60
          and v_avoided ? lower(t.name)
        union all
        select 1
        from public.manga_tags mt
        join public.tags t on t.id = mt.tag_id
        where c2.media_type = 'MANGA'
          and mt.manga_id = c2.media_id
          and coalesce(mt.rank, 0) >= 60
          and v_avoided ? lower(t.name)
      )
    order by c2.ucb desc, c2.popularity desc, c2.media_id desc
    limit 1;
    if found then
      -- Drop the weakest explore pick; the probe takes its slot.
      update taste_deck_cand c
      set slot = null, slot_raw = null
      where c.slot = 'explore'
        and (c.media_type, c.media_id) = (
          select c3.media_type, c3.media_id
          from taste_deck_cand c3
          where c3.slot = 'explore'
          order by c3.slot_raw asc, c3.popularity asc, c3.media_id asc
          limit 1
        );
      update taste_deck_cand c
      set slot = 'explore', slot_raw = r.ucb
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
    end if;
  end if;

  -- Franchise labels: connected components over media_relations restricted to
  -- pool titles (same approach as the profile recompute).
  with recursive
  nodes as (
    select c.media_type, c.media_id from taste_deck_cand c
  ),
  edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
  ),
  adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from edges
    union
    select b_t, b_i, a_t, a_i from edges
  ),
  reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from nodes n
    union
    select r2.s_t, r2.s_i, a.nt, a.ni
    from reach r2
    join adj a on a.t = r2.t and a.i = r2.i
  ),
  labels as (
    select r2.t as media_type, r2.i as media_id,
           min(r2.s_t || ':' || r2.s_i::text) as label
    from reach r2
    group by r2.t, r2.i
  )
  update taste_deck_cand c
  set franchise = coalesce(l.label, c.media_type || ':' || c.media_id::text)
  from labels l
  where l.media_type = c.media_type
    and l.media_id = c.media_id;

  update taste_deck_cand c
  set franchise = c.media_type || ':' || c.media_id::text
  where c.franchise is null;

  -- MMR overlap space: each title's top 15 tags by |w|.
  update taste_deck_cand c
  set top_tags = (
    select array_agg(v.tag_key)
    from (
      select v2.tag_key
      from public.media_tag_vectors v2
      where v2.media_type = c.media_type
        and v2.media_id = c.media_id
      order by abs(v2.w) desc
      limit 15
    ) v
  )
  where true; -- fix2 P0: pg_safeupdate blocks bare UPDATE

  -- slot_score: min-max normalize per slot group so UCB (0..~1.5) and cosine
  -- exploit scores (-1..1) compete on a shared 0..1 scale. Degenerate group:
  -- all-equal positives -> 1.0, all-zero -> 0.0.
  for v_slot in select 'exploit' union select 'explore' loop
    select min(c.slot_raw), max(c.slot_raw)
      into v_min_s, v_max_s
    from taste_deck_cand c
    where c.slot = v_slot;
    if v_max_s is null then
      continue;
    elsif v_max_s > v_min_s then
      update taste_deck_cand c
      set slot_score = (c.slot_raw - v_min_s) / (v_max_s - v_min_s)
      where c.slot = v_slot;
    elsif v_max_s > 0 then
      update taste_deck_cand c set slot_score = 1.0 where c.slot = v_slot;
    else
      update taste_deck_cand c set slot_score = 0.0 where c.slot = v_slot;
    end if;
  end loop;

  -- Half anime / half manga with v1 cross-fill on starvation.
  select
    count(*) filter (where c.media_type = 'ANIME'),
    count(*) filter (where c.media_type = 'MANGA')
  into v_a_count, v_m_count
  from taste_deck_cand c;
  v_a_take := least(v_a_count, v_lim - least(v_m_count, v_half));
  v_m_take := least(v_m_count, v_lim - v_a_take);

  -- MMR assembly (lambda = 0.7) with hard caps.
  while v_picked < v_lim loop
    v_best := null;
    v_best_mmr := null;
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.cluster = r.cluster
      ) >= v_cluster_cap;
      continue when (
        select count(*) from taste_deck_cand c2
        where c2.picked and c2.franchise = r.franchise
      ) >= v_franchise_cap;

      v_tags := r.top_tags;
      select coalesce(max(o.ovl), 0.0)
        into v_max_ovl
      from (
        select (
          select count(*)::double precision
          from (select unnest(v_tags) intersect select unnest(p2.top_tags)) i
        ) / nullif((
          select count(*)::double precision
          from (select unnest(v_tags) union select unnest(p2.top_tags)) u
        ), 0) as ovl
        from taste_deck_cand p2
        where p2.picked
      ) o;

      v_mmr := 0.7 * r.slot_score - 0.3 * coalesce(v_max_ovl, 0.0);
      if v_best_mmr is null or v_mmr > v_best_mmr then
        v_best := r;
        v_best_mmr := v_mmr;
      end if;
    end loop;
    exit when v_best is null;

    update taste_deck_cand c
    set picked = true
    where c.media_type = v_best.media_type
      and c.media_id = v_best.media_id;
    if v_best.media_type = 'ANIME' then
      v_pa := v_pa + 1;
    else
      v_pm := v_pm + 1;
    end if;
    v_picked := v_picked + 1;
  end loop;

  -- Starvation fill 1: remaining slotted candidates, caps relaxed, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where c.slot is not null
        and not c.picked
      order by c.slot_score desc, c.slot_raw desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Starvation fill 2: unslotted pool in v1 mirrored-first order, media quota kept.
  if v_picked < v_lim then
    for r in
      select c.*
      from taste_deck_cand c
      where not c.picked
      order by c.mirrored desc, c.popularity desc, c.media_id desc
    loop
      exit when v_picked >= v_lim;
      continue when r.media_type = 'ANIME' and v_pa >= v_a_take;
      continue when r.media_type = 'MANGA' and v_pm >= v_m_take;
      update taste_deck_cand c
      set picked = true
      where c.media_type = r.media_type
        and c.media_id = r.media_id;
      if r.media_type = 'ANIME' then
        v_pa := v_pa + 1;
      else
        v_pm := v_pm + 1;
      end if;
      v_picked := v_picked + 1;
    end loop;
  end if;

  -- Final output keeps v1's mirrored-first ordering and the 050000 meta strip.
  return query
  select
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.cover_image_medium,
    c.cover_image_color,
    c.genres,
    c.average_score,
    c.format,
    c.year,
    c.synopsis,
    c.episodes,
    c.chapters,
    c.volumes,
    case
      when c.media_type = 'ANIME' and c.format = 'TV'
        then public._taste_deck_seasons_count(c.media_id)
      else null
    end as seasons_count,
    avail.has_dub,
    avail.has_sub
  from taste_deck_cand c
  left join lateral (
    select
      bool_or(exists (
        select 1
        from unnest(pa.audio_langs) as lang
        where lower(trim(lang)) not in ('', 'ja', 'jpn', 'japanese', 'unknown')
      )) as has_dub,
      bool_or(coalesce(array_length(pa.subtitle_langs, 1), 0) > 0) as has_sub
    from public.provider_availability pa
    where pa.media_type = c.media_type
      and pa.media_id = c.media_id
  ) avail on true
  where c.picked
  order by c.mirrored desc, c.popularity desc, c.media_id desc;
end;
$$;

revoke all on function public.fetch_taste_deck_batch(integer) from public;
grant execute on function public.fetch_taste_deck_batch(integer) to authenticated, service_role;

drop function if exists public.recompute_user_taste_profile(uuid);

create function public.recompute_user_taste_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_event_count integer;
  v_strong_count integer;
  v_evidence double precision;
  v_confidence real;
  v_vector jsonb;
begin
  if p_user_id is null then
    return;
  end if;

  select
    count(*),
    count(*) filter (where abs(e.event_strength) >= 0.3),
    coalesce(sum(case when abs(e.event_strength) >= 0.3 then 1.0 else 0.5 end), 0)
  into v_event_count, v_strong_count, v_evidence
  from public.taste_signal_events e
  where e.user_id = p_user_id;

  -- Display-tier confidence (contract copy tiers, unchanged).
  v_confidence := case
    when v_strong_count >= 30 then 0.20
    when v_strong_count >= 15 then 0.15
    when v_strong_count >= 5 then 0.10
    else 0.05
  end;

  with recursive
  ev as (
    select
      e.media_type,
      e.media_id,
      e.event_strength::double precision
        * case when e.is_import then 0.25 else 1.0 end          -- import discount x0.25
        * power(0.5, greatest(extract(epoch from (now() - e.created_at)) / 86400.0, 0.0) / 180.0) as w, -- 180-day half-life
      (e.event_strength < 0) as negative_event
    from public.taste_signal_events e
    where e.user_id = p_user_id
  ),
  contrib as (
    -- strength x title_vector, both in the media_tag_vectors space.
    select
      c.media_type,
      c.media_id,
      v.tag_key,
      c.w * v.w::double precision as weight,
      c.negative_event
    from ev c
    join public.media_tag_vectors v
      on v.media_type = c.media_type
     and v.media_id = c.media_id
  ),
  -- Per-title cap (SYMMETRIC, hotfix P3): a title's ABSOLUTE mass may not
  -- exceed 8% of total profile positive mass, and the scale factor applies to
  -- ALL of the title's contributions, positive and negative alike. v2 capped
  -- positive mass only: skipped titles (all-negative) entered unscaled while
  -- loved titles were crushed toward 8%, so small profiles came out
  -- negative-dominated (52/60 negative keys in production).
  title_abs as (
    select media_type, media_id, sum(abs(weight)) as abs_mass
    from contrib
    group by media_type, media_id
  ),
  total_pos as (
    select coalesce(sum(greatest(weight, 0)), 0) as v from contrib
  ),
  title_scale as (
    select
      ta.media_type,
      ta.media_id,
      case
        when ta.abs_mass > 0 and (select v from total_pos) > 0
          then least(1.0, 0.08 * (select v from total_pos) / ta.abs_mass)
        else 1.0
      end as scale
    from title_abs ta
  ),
  capped as (
    select c.tag_key, c.media_type, c.media_id,
           c.weight * ts.scale as weight,
           c.negative_event
    from contrib c
    join title_scale ts
      on ts.media_type = c.media_type
     and ts.media_id = c.media_id
  ),
  -- Franchise family = connected component over media_relations, restricted to
  -- titles this user actually signaled (small subgraph). UNION (not UNION ALL)
  -- makes the recursion cycle-safe. Guard: histories with >2000 distinct titles
  -- skip grouping (each title becomes its own family).
  nodes as (
    select distinct media_type, media_id from ev
  ),
  node_ok as (
    select count(*) <= 2000 as ok from nodes
  ),
  edges as (
    select
      mr.from_media_type as a_t, mr.from_media_id as a_i,
      mr.to_media_type as b_t, mr.to_media_id as b_i
    from public.media_relations mr
    join nodes nf on nf.media_type = mr.from_media_type and nf.media_id = mr.from_media_id
    join nodes nt on nt.media_type = mr.to_media_type and nt.media_id = mr.to_media_id
    where (select ok from node_ok)
  ),
  adj as (
    select a_t as t, a_i as i, b_t as nt, b_i as ni from edges
    union
    select b_t, b_i, a_t, a_i from edges
  ),
  reach as (
    select n.media_type as s_t, n.media_id as s_i, n.media_type as t, n.media_id as i
    from nodes n
    union
    select r.s_t, r.s_i, a.nt, a.ni
    from reach r
    join adj a on a.t = r.t and a.i = r.i
  ),
  family_label as (
    select r.t as media_type, r.i as media_id,
           min(r.s_t || ':' || r.s_i::text) as label
    from reach r
    group by r.t, r.i
  ),
  capped_labeled as (
    select c.tag_key, c.weight, c.negative_event,
           coalesce(fl.label, c.media_type || ':' || c.media_id::text) as family
    from capped c
    left join family_label fl
      on fl.media_type = c.media_type
     and fl.media_id = c.media_id
  ),
  -- Franchise cap (SYMMETRIC): one family's absolute mass <= 15% of profile
  -- positive mass; the scale factor applies to both signs together.
  family_abs as (
    select family,
           sum(abs(weight)) as abs_mass,
           sum(greatest(weight, 0)) as pos_mass
    from capped_labeled
    group by family
  ),
  family_total as (
    select coalesce(sum(pos_mass), 0) as v from family_abs
  ),
  family_scale as (
    select
      fa.family,
      case
        when fa.abs_mass > 0 and (select v from family_total) > 0
          then least(1.0, 0.15 * (select v from family_total) / fa.abs_mass)
        else 1.0
      end as scale
    from family_abs fa
  ),
  final_contrib as (
    select cl.tag_key, cl.weight * fs.scale as weight, cl.negative_event
    from capped_labeled cl
    join family_scale fs on fs.family = cl.family
  ),
  agg as (
    select
      tag_key,
      sum(weight) as weight
    from final_contrib
    group by tag_key
  ),
  floored as (
    select
      tag_key,
      greatest(weight, -1.0) as weight -- per-tag negative mass floor -1.0
    from agg
  ),
  vec_norm as (
    select nullif(sqrt(sum(weight * weight)), 0) as n from floored
  ),
  normalized as (
    select
      f.tag_key,
      case when (select n from vec_norm) is null then 0.0
           else f.weight / (select n from vec_norm) end as weight
    from floored f
  ),
  -- Avoidance basis: per-tag RAW sums (decayed strength x rank/100, import-
  -- discounted; genres at x0.6) BEFORE IDF weighting, caps and L2
  -- normalization. One skip (e.g. -0.45 x 0.80 = -0.36) must never exile a
  -- tag (spec SS4.3); in the IDF space a single rare-tag skip would already
  -- cross the -0.8 cumulative floor, so the floors are evaluated here.
  -- 'genre:*' keys can be avoided too; consumers only match rank-bearing
  -- tags, making genre entries informational.
  avoid_contrib as (
    select c.media_type, c.media_id, lower(t.name) as tag_key,
           c.w * (coalesce(at.rank, 0)::double precision / 100.0) as weight,
           c.negative_event
    from ev c
    join public.anime_tags at on c.media_type = 'ANIME' and at.anime_id = c.media_id
    join public.tags t on t.id = at.tag_id
    union all
    select c.media_type, c.media_id, lower(t.name),
           c.w * (coalesce(mt.rank, 0)::double precision / 100.0),
           c.negative_event
    from ev c
    join public.manga_tags mt on c.media_type = 'MANGA' and mt.manga_id = c.media_id
    join public.tags t on t.id = mt.tag_id
    union all
    select c.media_type, c.media_id, 'genre:' || lower(g),
           c.w * 0.6, c.negative_event
    from ev c
    join public.anime a on c.media_type = 'ANIME' and a.id = c.media_id
    cross join lateral unnest(coalesce(a.genres, '{}'::text[])) as g
    union all
    select c.media_type, c.media_id, 'genre:' || lower(g),
           c.w * 0.6, c.negative_event
    from ev c
    join public.manga m on c.media_type = 'MANGA' and m.id = c.media_id
    cross join lateral unnest(coalesce(m.genres, '{}'::text[])) as g
  ),
  avoid_agg as (
    select
      tag_key,
      count(*) filter (where negative_event) as neg_events,
      sum(weight) filter (where weight < 0) as neg_weight,
      sum(weight) filter (where weight > 0) as pos_weight
    from avoid_contrib
    group by tag_key
  ),
  -- fix2 net-sentiment guard: the event/cumulative floors alone could exile a
  -- register the user mostly LOVES when two skips happen to carry it (live:
  -- genre:drama avoided despite 3 loves + 3 knowns). Avoidance now also
  -- requires the tag's net sentiment to be strictly negative.
  avoided as (
    select tag_key
    from avoid_agg
    where (neg_events >= 2 or coalesce(neg_weight, 0) <= -0.8)
      and (coalesce(pos_weight, 0) + coalesce(neg_weight, 0)) < 0
  ),
  vec_json as (
    select coalesce(jsonb_object_agg(tag_key, w), '{}'::jsonb) as j
    from (
      -- fix2: top 60 TAG keys by abs + ALL 'genre:' keys with abs(w) > 0.001.
      -- Genres are the bounded backbone register (~36 keys); truncating them
      -- by rank loses the persona's most load-bearing signal (verified live:
      -- genre:drama/genre:fantasy cut at ranks 91/104 of 126).
      select tag_key, round(weight::numeric, 4) as w
      from (
        select
          n2.tag_key,
          n2.weight,
          row_number() over (
            partition by (n2.tag_key not like 'genre:%')
            order by abs(n2.weight) desc, n2.tag_key asc
          ) as rn
        from normalized n2
      ) s
      where round(s.weight::numeric, 4) <> 0
        and (
          (s.tag_key like 'genre:%' and abs(s.weight) > 0.001)
          or (s.tag_key not like 'genre:%' and s.rn <= 60)
        )
    ) t
  ),
  avoided_json as (
    select coalesce(jsonb_agg(tag_key order by tag_key), '[]'::jsonb) as j
    from avoided
  )
  select jsonb_build_object(
    'vector', (select j from vec_json),
    'avoided_tags', (select j from avoided_json),
    'evidence', round(v_evidence::numeric, 2),
    'confidence', v_confidence,
    'event_count', v_event_count,
    'computed_at', now()
  )
  into v_vector;

  insert into public.user_taste_profiles as p (user_id, vector, updated_at)
  values (p_user_id, v_vector, now())
  on conflict (user_id) do update
    set vector = excluded.vector,
        updated_at = now();
end;
$$;

revoke all on function public.recompute_user_taste_profile(uuid) from public;
grant execute on function public.recompute_user_taste_profile(uuid) to service_role;

-- Re-enqueue existing profiles so the fix2 rules (genre retention, avoidance net-sentiment guard)
-- are applied on the next drain, even if the 070000 hotfix wave already ran.
insert into public.taste_profile_recompute_queue as q (user_id, reason, requested_at, processed_at)
select p.user_id, 'taste_math_v2_fix2', now(), null
from public.user_taste_profiles p
on conflict (user_id) do update
  set reason = excluded.reason,
      requested_at = excluded.requested_at,
      processed_at = null;
