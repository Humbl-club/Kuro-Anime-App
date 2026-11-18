-- W10 "Up next in your series": library_up_next_v1(p_medium, p_limit).
-- PREPARED, NOT DEPLOYED. Owner approval is required before this is applied.
-- Depends on 20261007040000 (series tables, live) and 20260307120000 (media_relations, live).
-- SECURITY INVOKER: every relation read is readable by `authenticated` under RLS.
create or replace function public.library_up_next_v1(p_medium text, p_limit integer default 30)
returns table(media_type text, media_id integer, title text, cover_image text, format text, status text,
              start_year integer, total_units integer, after_media_id integer, after_title text, link text)
language plpgsql stable security invoker
set search_path = public, extensions
set jit = off
as $fn$
declare
  v_limit integer;
  v_uid uuid;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM: %', coalesce(p_medium, '<null>') using errcode = '22023';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 30), 1), 30);
  v_uid := auth.uid();
  if v_uid is null then
    return;
  end if;

  -- The dollar-quote tags of the two EXECUTE bodies below are a contract: the EXPLAIN test extracts the SQL between them.
  -- (Never write the tag names in a comment: the test splits on the first occurrence.)
  -- $1 = acting user (auth.uid()), $2 = limit. A reviewed link (series continuity 'verified', grouping
  -- 'approved', section 'approved', same medium) wins over an AniList SEQUEL edge.
  if p_medium = 'anime' then
    return query execute $anime_query$
      with done as (
        select l.anime_id as id, l.updated_at as done_at
        from public.anime_user_lists l
        where l.user_id = $1::text and l.list_type = 'COMPLETED'),
      cand as (
        select mr.to_media_id as id, d.id as after_id, d.done_at, 1 as pri, 'sequel'::text as link
        from done d
        join public.media_relations mr
          on mr.from_media_type = 'ANIME' and mr.from_media_id = d.id
         and mr.relation_type = 'SEQUEL' and mr.to_media_type = 'ANIME'
        union all
        select nxt.anime_id, d.id, d.done_at, 0, 'reviewed'::text
        from done d
        join public.series_entry_spans sp on sp.anime_id = d.id
        join public.series s on s.id = sp.series_id and s.continuity = 'verified'
                            and s.grouping_state = 'approved' and s.medium = sp.medium
        join public.series_sections sec on sec.id = sp.section_id and sec.state = 'approved'
        join lateral (
          select sp2.anime_id
          from public.series_entry_spans sp2
          join public.series_sections sec2 on sec2.id = sp2.section_id and sec2.state = 'approved'
          where sp2.series_id = sp.series_id and sp2.anime_id is not null and sec2.sort_order > sec.sort_order
          order by sec2.sort_order, sp2.id
          limit 1) nxt on true),
      best as (
        select distinct on (c.id) c.*
        from cand c
        where c.id <> c.after_id
        order by c.id, c.pri, c.done_at desc, c.after_id)
      select 'anime'::text, a.id, coalesce(nullif(a.title_english, ''), a.title_romaji), a.cover_image_large,
             a.format, a.status, coalesce(a.season_year, a.start_date_year), a.episodes,
             p.id, coalesce(nullif(p.title_english, ''), p.title_romaji), b.link
      from best b
      join public.anime a on a.id = b.id
      join public.anime p on p.id = b.after_id
      where coalesce(a.is_adult, false) = false
        and not ('Hentai' = any(coalesce(a.genres, '{}')))
        and not ('Ecchi' = any(coalesce(a.genres, '{}')))
        and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
        and coalesce(a.status, '') <> 'CANCELLED'
        and not exists (select 1 from public.anime_user_lists o where o.user_id = $1::text and o.anime_id = b.id)
        and not exists (select 1 from public.taste_signal_events e
                        where e.user_id = $1 and e.media_type = 'ANIME' and e.media_id = b.id
                          and e.event_type in ('deck_skip', 'deck_known')
                          and e.created_at >= now() - interval '365 days')
      order by b.done_at desc, b.id
      limit $2
    $anime_query$ using v_uid, v_limit;
  else
    return query execute $manga_query$
      with done as (
        select l.manga_id as id, l.updated_at as done_at
        from public.manga_user_lists l
        where l.user_id = $1::text and l.list_type = 'COMPLETED'),
      cand as (
        select mr.to_media_id as id, d.id as after_id, d.done_at, 1 as pri, 'sequel'::text as link
        from done d
        join public.media_relations mr
          on mr.from_media_type = 'MANGA' and mr.from_media_id = d.id
         and mr.relation_type = 'SEQUEL' and mr.to_media_type = 'MANGA'
        union all
        select nxt.manga_id, d.id, d.done_at, 0, 'reviewed'::text
        from done d
        join public.series_entry_spans sp on sp.manga_id = d.id
        join public.series s on s.id = sp.series_id and s.continuity = 'verified'
                            and s.grouping_state = 'approved' and s.medium = sp.medium
        join public.series_sections sec on sec.id = sp.section_id and sec.state = 'approved'
        join lateral (
          select sp2.manga_id
          from public.series_entry_spans sp2
          join public.series_sections sec2 on sec2.id = sp2.section_id and sec2.state = 'approved'
          where sp2.series_id = sp.series_id and sp2.manga_id is not null and sec2.sort_order > sec.sort_order
          order by sec2.sort_order, sp2.id
          limit 1) nxt on true),
      best as (
        select distinct on (c.id) c.*
        from cand c
        where c.id <> c.after_id
        order by c.id, c.pri, c.done_at desc, c.after_id)
      select 'manga'::text, a.id, coalesce(nullif(a.title_english, ''), a.title_romaji), a.cover_image_large,
             a.format, a.status, a.start_date_year, a.chapters,
             p.id, coalesce(nullif(p.title_english, ''), p.title_romaji), b.link
      from best b
      join public.manga a on a.id = b.id
      join public.manga p on p.id = b.after_id
      where coalesce(a.is_adult, false) = false
        and not ('Hentai' = any(coalesce(a.genres, '{}')))
        and not ('Ecchi' = any(coalesce(a.genres, '{}')))
        and coalesce(a.status, '') <> 'CANCELLED'
        and not exists (select 1 from public.manga_user_lists o where o.user_id = $1::text and o.manga_id = b.id)
        and not exists (select 1 from public.taste_signal_events e
                        where e.user_id = $1 and e.media_type = 'MANGA' and e.media_id = b.id
                          and e.event_type in ('deck_skip', 'deck_known')
                          and e.created_at >= now() - interval '365 days')
      order by b.done_at desc, b.id
      limit $2
    $manga_query$ using v_uid, v_limit;
  end if;
end;
$fn$;

revoke all on function public.library_up_next_v1(text, integer) from public, anon;
grant execute on function public.library_up_next_v1(text, integer) to authenticated;

comment on function public.library_up_next_v1(text, integer) is
  'W10: sequels / reviewed next sections of the caller''s COMPLETED titles that are not in the library. INVOKER; account from auth.uid().';
