-- Temporary zero-row chapter crunch selector.
-- Adds p_zero_row_only so enrichment workers can target only manga without chapter rows.

begin;

drop function if exists public.get_manga_chapter_enrich_candidates(integer, integer);

create or replace function public.get_manga_chapter_enrich_candidates(
  p_limit integer default 20,
  p_force_manga_id integer default null,
  p_zero_row_only boolean default false
)
returns table (
  id integer,
  anilist_id integer,
  mal_id integer,
  title_english text,
  title_romaji text,
  title_native text,
  title_synonyms text[],
  status text,
  chapters integer,
  last_synced_at timestamptz,
  chapter_row_count integer,
  priority_class integer
)
language sql
security definer
set search_path = public
as $$
  with chapter_counts as (
    select c.manga_id, count(*)::integer as chapter_row_count
    from public.chapters c
    group by c.manga_id
  ),
  active_mappings as (
    select
      msl.manga_id,
      min(msl.next_verify_at) as next_verify_at
    from public.manga_source_links msl
    where msl.provider = 'mangadex'
      and msl.status = 'active'
    group by msl.manga_id
  ),
  review_due as (
    select
      r.manga_id,
      min(coalesce(r.next_retry_at, r.created_at)) as due_at
    from public.manga_source_link_review r
    where r.status = 'pending'
      and r.manga_id is not null
    group by r.manga_id
  ),
  prioritized as (
    select
      m.id,
      m.anilist_id,
      m.mal_id,
      m.title_english,
      m.title_romaji,
      m.title_native,
      m.title_synonyms,
      m.status,
      m.chapters,
      m.last_synced_at,
      coalesce(cc.chapter_row_count, 0) as chapter_row_count,
      case
        when p_force_manga_id is not null and m.id = p_force_manga_id then 0
        when coalesce(cc.chapter_row_count, 0) = 0 then 1
        when m.status = 'RELEASING'
          and (m.last_synced_at is null or m.last_synced_at < now() - interval '24 hours') then 2
        when m.chapters is not null and coalesce(cc.chapter_row_count, 0) < m.chapters then 3
        when am.next_verify_at is not null and am.next_verify_at <= now() then 4
        when rd.due_at is not null and rd.due_at <= now() then 5
        else 99
      end as priority_class
    from public.manga m
    left join chapter_counts cc on cc.manga_id = m.id
    left join active_mappings am on am.manga_id = m.id
    left join review_due rd on rd.manga_id = m.id
    where (p_force_manga_id is null or m.id = p_force_manga_id)
      and (not p_zero_row_only or coalesce(cc.chapter_row_count, 0) = 0)
  )
  select
    p.id,
    p.anilist_id,
    p.mal_id,
    p.title_english,
    p.title_romaji,
    p.title_native,
    p.title_synonyms,
    p.status,
    p.chapters,
    p.last_synced_at,
    p.chapter_row_count,
    p.priority_class
  from prioritized p
  where p.priority_class < 99
  order by
    p.priority_class asc,
    coalesce(p.last_synced_at, to_timestamp(0)) asc,
    p.id asc
  limit greatest(1, least(coalesce(p_limit, 20), 200));
$$;

revoke all on function public.get_manga_chapter_enrich_candidates(integer, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.get_manga_chapter_enrich_candidates(integer, integer, boolean)
  to service_role;

commit;
