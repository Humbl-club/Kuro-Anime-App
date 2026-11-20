-- Prepared 2026-11-19 (catalogue consolidation & OOM-proof matching; NOT applied).
--
-- 1. catalogue_find_title_candidates_v1(p_medium, p_titles, p_year_min, p_year_max, p_limit)
--    Bounded, case-insensitive candidate lookup against existing anime/manga rows (including
--    title_synonyms) so `catalogue-intake create` matches against existing AniList-seeded rows
--    in Postgres without loading 42k manga rows into Edge Function memory.
-- 2. catalogue_create_title_v1 whitelist extended with `season` and `season_year` so newly
--    created ANN anime immediately populate Discover's `This season` rail.
--
-- Both functions are SECURITY INVOKER and executable by service_role only.
-- Depends on 20261112100450_catalogue_create_v1.sql.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create or replace function public.catalogue_find_title_candidates_v1(
  p_medium text,
  p_titles text[],
  p_year_min integer default null,
  p_year_max integer default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  _clean text[];
  _lim integer;
  _rows jsonb;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_find_title_candidates_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct lower(btrim(t))), '{}')
    into _clean
    from unnest(coalesce(p_titles, '{}'::text[])) t
   where btrim(t) <> '';
  if coalesce(array_length(_clean, 1), 0) = 0 then
    return '[]'::jsonb;
  end if;
  _lim := least(greatest(coalesce(p_limit, 100), 1), 250);

  if p_medium = 'anime' then
    select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
      into _rows
      from (
        select jsonb_build_object(
                 'id', a.id,
                 'title_english', a.title_english,
                 'title_romaji', a.title_romaji,
                 'title_native', a.title_native,
                 'title_synonyms', a.title_synonyms,
                 'start_date_year', a.start_date_year,
                 'format', a.format
               ) as row_obj
          from public.anime a
         where (
                 lower(btrim(coalesce(a.title_english, ''))) = any (_clean)
                 or lower(btrim(coalesce(a.title_romaji, ''))) = any (_clean)
                 or lower(btrim(coalesce(a.title_native, ''))) = any (_clean)
                 or exists (
                   select 1
                     from unnest(coalesce(a.title_synonyms, '{}'::text[])) s
                    where lower(btrim(s)) = any (_clean)
                 )
               )
           and (p_year_min is null or a.start_date_year is null or a.start_date_year >= p_year_min)
           and (p_year_max is null or a.start_date_year is null or a.start_date_year <= p_year_max)
         order by a.id asc
         limit _lim
      ) sub;
  else
    select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
      into _rows
      from (
        select jsonb_build_object(
                 'id', m.id,
                 'title_english', m.title_english,
                 'title_romaji', m.title_romaji,
                 'title_native', m.title_native,
                 'title_synonyms', m.title_synonyms,
                 'start_date_year', m.start_date_year,
                 'format', m.format,
                 'country_of_origin', m.country_of_origin
               ) as row_obj
          from public.manga m
         where (
                 lower(btrim(coalesce(m.title_english, ''))) = any (_clean)
                 or lower(btrim(coalesce(m.title_romaji, ''))) = any (_clean)
                 or lower(btrim(coalesce(m.title_native, ''))) = any (_clean)
                 or exists (
                   select 1
                     from unnest(coalesce(m.title_synonyms, '{}'::text[])) s
                    where lower(btrim(s)) = any (_clean)
                 )
               )
           and (p_year_min is null or m.start_date_year is null or m.start_date_year >= p_year_min)
           and (p_year_max is null or m.start_date_year is null or m.start_date_year <= p_year_max)
         order by m.id asc
         limit _lim
      ) sub;
  end if;

  return _rows;
end;
$$;

revoke all on function public.catalogue_find_title_candidates_v1(text, text[], integer, integer, integer) from public, anon, authenticated;
grant execute on function public.catalogue_find_title_candidates_v1(text, text[], integer, integer, integer) to service_role;

create or replace function public.catalogue_create_title_v1(
  p_medium text,
  p_row jsonb,
  p_source text,
  p_source_key text,
  p_confidence numeric default 1,
  p_shadow jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path = public, extensions
as $$
declare
  _allowed text[] := array['title_english', 'title_romaji', 'title_native', 'title_synonyms', 'format', 'status',
    'season', 'season_year',
    'start_date_year', 'start_date_month', 'start_date_day', 'end_date_year', 'end_date_month', 'end_date_day',
    'episodes', 'duration', 'chapters', 'volumes', 'country_of_origin', 'is_adult', 'data_sources'];
  _cols text[];
  _id integer;
  _field record;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_create_title_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  if p_source is null or p_source not in ('ann', 'mangaupdates', 'wikidata') or coalesce(btrim(p_source_key), '') = '' then
    raise exception 'catalogue_create_title_v1: a source (ann, mangaupdates, wikidata) and key are required' using errcode = '22023';
  end if;
  if p_row is null or jsonb_typeof(p_row) <> 'object' then
    raise exception 'catalogue_create_title_v1: p_row must be a json object' using errcode = '22023';
  end if;

  select l.kuro_id into _id from public.catalogue_id_links l
   where l.kind = p_medium and l.source = p_source and l.source_key = p_source_key and l.status = 'accepted';
  if _id is not null then
    return jsonb_build_object('id', _id, 'created', false);
  end if;

  select coalesce(array_agg(k), '{}') into _cols from jsonb_object_keys(p_row) k where k = any (_allowed);
  if not (coalesce(p_row ->> 'title_english', p_row ->> 'title_romaji', p_row ->> 'title_native') is not null) then
    raise exception 'catalogue_create_title_v1: a title is required' using errcode = '22023';
  end if;

  begin
    execute format(
      'insert into public.%1$I (%2$s, catalogue_visibility) select %2$s, ''visible'' from jsonb_populate_record(null::public.%1$I, $1) returning id',
      p_medium, (select string_agg(format('%I', c), ', ') from unnest(_cols) c))
      into _id using p_row;

    insert into public.catalogue_id_links (kind, kuro_id, source, source_key, method, confidence, status, decided_at)
    values (p_medium, _id, p_source, p_source_key, 'id_match', p_confidence, 'accepted', now());
  exception when unique_violation then
    select l.kuro_id into _id from public.catalogue_id_links l
     where l.kind = p_medium and l.source = p_source and l.source_key = p_source_key and l.status = 'accepted';
    if _id is null then
      raise;
    end if;
    return jsonb_build_object('id', _id, 'created', false);
  end;

  for _field in select key, value from jsonb_each(coalesce(p_shadow, '{}'::jsonb)) loop
    insert into public.catalogue_shadow_values (medium, media_id, field, value, source)
    values (p_medium, _id, _field.key, _field.value, p_source)
    on conflict (medium, media_id, field) do nothing;
  end loop;

  return jsonb_build_object('id', _id, 'created', true);
end;
$$;

revoke all on function public.catalogue_create_title_v1(text, jsonb, text, text, numeric, jsonb) from public, anon, authenticated;
grant execute on function public.catalogue_create_title_v1(text, jsonb, text, text, numeric, jsonb) to service_role;

notify pgrst, 'reload schema';
commit;
