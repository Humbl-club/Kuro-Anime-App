-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 8). NOT applied.
--
-- Comparator RPC for the catalogue shadow: catalogue_shadow_report_v1(p_medium, p_sample) reads
-- catalogue_shadow_values (written by catalogue-intake `compose`) next to today's published columns and
-- returns coverage and agreement per field group and tier as jsonb. Read-only; service role only.
-- Depends on 20261112100000_catalogue_sources_v1.sql (shadow, link and review tables).
--
-- Tiers: top1k / top5k (popularity rank, nulls last, id tie-break), in_lists (any user list row),
-- curated (curated_rail_items joined on anilist_id), all. Cells per group and tier:
--   total (titles in the tier), covered (shadow has a value), compared (both sides have a value),
--   agreed (equal under the spec section 6 rule), disagree_sample (up to p_sample {id, today, shadow}).
-- Groups: identity (covered = an accepted non-AniList link), titles (display title; compared on
-- title_english with the normaliser), titles_native, facts_start_year, facts_format, facts_status,
-- facts_episodes (FINISHED anime only), adult. Shadow values hold Kuro-vocabulary values (the mappers
-- already map ANN/MangaUpdates types), so format and status compare exactly.
-- The title normaliser is catalogue_norm_title: lower, Latin accents/macrons folded by translate()
-- (unaccent is not relied on), punctuation to spaces, whitespace collapsed.
-- The function is SECURITY DEFINER because the tables it reads are service-only and user_lists are
-- RLS-protected; EXECUTE is revoked from public/anon/authenticated. It scans each table once per call
-- (about 64k titles), meant for an operator run, not a request path.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.catalogue_norm_title(p_text text)
returns text
language plpgsql
immutable
set search_path = public, extensions
as $$
begin
  if p_text is null then
    return null;
  end if;
  return btrim(regexp_replace(
    translate(lower(p_text), 'áàâäãåāéèêëēíìîïīóòôöõōøúùûüūñçýÿ', 'aaaaaaaeeeeeiiiiiooooooouuuuuncyy'),
    '[^[:alnum:]]+', ' ', 'g'));
end;
$$;

-- Safe casts for shadow values (jsonb ->> text). A value that is not a plain integer / boolean returns
-- null, so one bad shadow row counts as a disagreement (and is counted as invalid) instead of
-- aborting the whole report.
create or replace function public.catalogue_try_int(p_text text)
returns integer
language plpgsql
immutable
set search_path = public, extensions
as $$
begin
  if p_text ~ '^-?[0-9]{1,9}$' then
    return p_text::integer;
  end if;
  return null;
end;
$$;

create or replace function public.catalogue_try_bool(p_text text)
returns boolean
language plpgsql
immutable
set search_path = public, extensions
as $$
begin
  if p_text in ('true', 'false') then
    return p_text::boolean;
  end if;
  return null;
end;
$$;

create or replace function public.catalogue_shadow_report_v1(p_medium text, p_sample integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
set statement_timeout = '60s'
as $$
declare
  _sample integer;
  _episodes_expr text;
  _sql text;
  _out jsonb;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_shadow_report_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  _sample := greatest(0, least(coalesce(p_sample, 20), 100));
  _episodes_expr := case when p_medium = 'anime' then 'm.episodes' else 'null::integer' end;

  _sql := format($q$
    with ranked as (
      select m.id, m.title_english, m.title_romaji, m.format, m.status, m.start_date_year, m.is_adult,
             %1$s as episodes,
             row_number() over (order by m.popularity desc nulls last, m.id) as rn
      from public.%2$I m
    ),
    sv as (
      select media_id, jsonb_object_agg(field, value) as j
      from public.catalogue_shadow_values
      where medium = $1
      group by media_id
    ),
    lists as (select distinct %3$I as id from public.%4$I),
    cur as (
      select distinct a.id
      from public.curated_rail_items c
      join public.%2$I a on a.anilist_id = c.anilist_id
      where c.media_type = upper($1)
    ),
    acc as (
      select kuro_id as id
      from public.catalogue_id_links
      where kind = $1 and status = 'accepted' and source in ('wikidata', 'ann', 'mangaupdates')
      group by kuro_id
    ),
    b as (
      select r.*, sv.j,
             (r.rn <= 1000) as t1, (r.rn <= 5000) as t5,
             (l.id is not null) as tl, (c.id is not null) as tc, (a.id is not null) as linked
      from ranked r
      left join sv on sv.media_id = r.id
      left join lists l on l.id = r.id
      left join cur c on c.id = r.id
      left join acc a on a.id = r.id
    ),
    cells as (
      select 'identity'::text as grp, id, t1, t5, tl, tc,
             linked as covered, false as compared, false as agreed,
             null::jsonb as today, null::jsonb as shadow
      from b
      union all
      select 'titles', id, t1, t5, tl, tc,
             (j->>'title_english') is not null or (j->>'title_romaji') is not null,
             title_english is not null and (j->>'title_english') is not null,
             coalesce(public.catalogue_norm_title(title_english) = public.catalogue_norm_title(j->>'title_english'), false),
             to_jsonb(title_english), j->'title_english'
      from b
      union all
      select 'titles_native', id, t1, t5, tl, tc, (j->>'title_native') is not null, false, false, null, null
      from b
      union all
      select 'facts_start_year', id, t1, t5, tl, tc,
             (j->>'start_date_year') is not null,
             start_date_year is not null and (j->>'start_date_year') is not null,
             coalesce(public.catalogue_try_int(j->>'start_date_year') = start_date_year, false),
             to_jsonb(start_date_year), j->'start_date_year'
      from b
      union all
      select 'facts_format', id, t1, t5, tl, tc,
             (j->>'format') is not null,
             format is not null and (j->>'format') is not null,
             coalesce((j->>'format') = format, false),
             to_jsonb(format), j->'format'
      from b
      union all
      select 'facts_status', id, t1, t5, tl, tc,
             (j->>'status') is not null,
             status is not null and (j->>'status') is not null,
             coalesce((j->>'status') = status, false),
             to_jsonb(status), j->'status'
      from b
      union all
      select 'facts_episodes', id, t1, t5, tl, tc,
             (j->>'episodes') is not null,
             status = 'FINISHED' and episodes is not null and (j->>'episodes') is not null,
             coalesce(public.catalogue_try_int(j->>'episodes') = episodes, false),
             to_jsonb(episodes), j->'episodes'
      from b
      union all
      select 'adult', id, t1, t5, tl, tc,
             (j->>'is_adult') is not null,
             (j->>'is_adult') is not null,
             coalesce(public.catalogue_try_bool(j->>'is_adult') = is_adult, false),
             to_jsonb(is_adult), j->'is_adult'
      from b
    ),
    tiered as (
      select c.grp, t.tier, c.id, c.covered, c.compared, c.agreed, c.today, c.shadow
      from cells c
      cross join lateral (values ('top1k', c.t1), ('top5k', c.t5), ('in_lists', c.tl), ('curated', c.tc), ('all', true)) t(tier, inn)
      where t.inn
    ),
    agg as (
      select grp, tier, count(*) as total,
             count(*) filter (where covered) as covered,
             count(*) filter (where compared) as compared,
             count(*) filter (where compared and agreed) as agreed
      from tiered
      group by grp, tier
    ),
    samples as (
      select grp, tier,
             jsonb_agg(jsonb_build_object('id', id, 'today', today, 'shadow', shadow) order by id) as s
      from (
        select grp, tier, id, today, shadow,
               row_number() over (partition by grp, tier order by id) as rn_s
        from tiered
        where compared and not agreed
      ) d
      where rn_s <= $2
      group by grp, tier
    ),
    grid as (
      select g.grp, t.tier
      from (values ('identity'), ('titles'), ('titles_native'), ('facts_start_year'), ('facts_format'),
                   ('facts_status'), ('facts_episodes'), ('adult')) g(grp)
      cross join (values ('top1k'), ('top5k'), ('in_lists'), ('curated'), ('all')) t(tier)
    ),
    groups as (
      select grid.grp,
             jsonb_object_agg(grid.tier, jsonb_build_object(
               'total', coalesce(agg.total, 0),
               'covered', coalesce(agg.covered, 0),
               'compared', coalesce(agg.compared, 0),
               'agreed', coalesce(agg.agreed, 0),
               'disagree_sample', coalesce(samples.s, '[]'::jsonb))) as t
      from grid
      left join agg on agg.grp = grid.grp and agg.tier = grid.tier
      left join samples on samples.grp = grid.grp and samples.tier = grid.tier
      group by grid.grp
    )
    select jsonb_build_object(
      'medium', $1,
      'generated_at', now(),
      'sample', $2,
      'tiers', (select jsonb_build_object(
          'top1k', count(*) filter (where t1), 'top5k', count(*) filter (where t5),
          'in_lists', count(*) filter (where tl), 'curated', count(*) filter (where tc),
          'all', count(*)) from b),
      'groups', (select jsonb_object_agg(grp, t) from groups),
      'identity_gate', jsonb_build_object(
        'accepted_links', (select count(*) from public.catalogue_id_links
                            where kind = $1 and status = 'accepted' and source in ('wikidata', 'ann', 'mangaupdates')),
        'proposed_links', (select count(*) from public.catalogue_id_links where kind = $1 and status = 'proposed'),
        -- Gates that can fail (key kept for scripts/catalogue_shadow_report.js): the same Kuro title holding two accepted links for one source (the
        -- partial unique index forbids it; a nonzero count means the index is missing or bypassed),
        -- and accepted links whose target title no longer exists (the existence trigger forbids it).
        'duplicate_accepted_links', (select count(*) from (
                            select 1 from public.catalogue_id_links
                            where kind = $1 and status = 'accepted'
                            group by kuro_id, source having count(*) > 1) d),
        'orphan_accepted_links', (select count(*) from public.catalogue_id_links l
                            where l.kind = $1 and l.status = 'accepted'
                              and not exists (select 1 from ranked r where r.id = l.kuro_id)),
        'proposed_only_titles', (select count(distinct p.kuro_id) from public.catalogue_id_links p
                            where p.kind = $1 and p.status = 'proposed'
                              and not exists (select 1 from acc where acc.id = p.kuro_id))),
      'invalid_shadow_values', (select count(*) from public.catalogue_shadow_values
                            where medium = $1 and value is not null and jsonb_typeof(value) <> 'null'
                              and ((field in ('start_date_year', 'episodes') and public.catalogue_try_int(value #>> '{}') is null)
                                or (field = 'is_adult' and public.catalogue_try_bool(value #>> '{}') is null))),
      'adult', jsonb_build_object(
        'review_size', (select count(*) from public.catalogue_shadow_values where medium = $1 and field = 'review:adult'),
        'becomes_non_adult', (select count(*) from b where public.catalogue_try_bool(j->>'is_adult') = false and is_adult),
        'newly_adult', (select count(*) from b where public.catalogue_try_bool(j->>'is_adult') = true and not is_adult))
    )
  $q$, _episodes_expr, p_medium, p_medium || '_id', p_medium || '_user_lists');

  execute _sql into _out using p_medium, _sample;
  return _out;
end;
$$;

revoke all on function public.catalogue_norm_title(text) from public, anon, authenticated;
revoke all on function public.catalogue_try_int(text) from public, anon, authenticated;
revoke all on function public.catalogue_try_bool(text) from public, anon, authenticated;
revoke all on function public.catalogue_shadow_report_v1(text, integer) from public, anon, authenticated;
grant execute on function public.catalogue_norm_title(text) to service_role;
grant execute on function public.catalogue_try_int(text) to service_role;
grant execute on function public.catalogue_try_bool(text) to service_role;
grant execute on function public.catalogue_shadow_report_v1(text, integer) to service_role;

notify pgrst, 'reload schema';
commit;
