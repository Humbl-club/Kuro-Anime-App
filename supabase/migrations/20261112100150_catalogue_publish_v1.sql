-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 15). NOT applied.
--
-- Single writer per field group. `catalogue-intake publish` is the only writer of a group whose
-- catalogue_cutover mode is 'new'; the AniList-path writers skip that group (Task 15, TypeScript).
-- This file holds the transactional half of publish and restore, plus one reader change:
--
--   catalogue_publish_batch_v1(medium, group, media_ids[], columns[], with_data_sources)
--     For up to 500 titles of one group whose mode is 'new':
--       1. snapshot (first publish of a title in the group, plus first replacement of each linked
--          table): the main-row columns and the linked rows it is about to replace go to
--          catalogue_rollback_snapshots (the snapshot is never overwritten while it exists);
--       2. replace main-row columns from catalogue_shadow_values. A shadow value that is null or
--          absent never blanks a column (the date month/day parts of a triple whose year has a shadow
--          value are the one exception: a triple comes from one source as a unit). is_adult never goes
--          true -> false here (spec section 3: the adult flag does not clear without review);
--       3. replace linked rows (credits tables, media_relations source='kuro') for titles whose shadow
--          carries the list, in the same transaction (a plpgsql function body is one transaction).
--          Unchanged lists write nothing. media_relations rows of source 'anilist' and 'editorial'
--          are never touched.
--   catalogue_restore_batch_v1(medium, group, limit)
--     Writes the snapshot back (columns exactly, linked rows with their ids) for up to `limit` titles
--     (max 500), deletes the restored snapshot rows and reports how many remain. Refuses to run while
--     the group is still 'new'. Makes no AniList request (it is SQL only).
--   catalogue_relation_source_v1()
--     'kuro' once the relations group is 'new', else 'anilist'. get_media_ladder (the client reader of
--     media_relations) hides the OTHER writer's rows, so a title never shows both lists.
--
-- Both batch functions are SECURITY INVOKER: the caller is the service role, which holds the table
-- grants. EXECUTE is revoked from public/anon/authenticated and granted to service_role only.
-- Remaining media_relations readers (taste/realm/franchise-component builders and
-- recommend_ids_similar_to_seeds) are internal graph walks that treat the relation set as undirected
-- edges; they read the union of both writers' rows until the owner decides (see the task report).
-- Depends on 20261112100000_catalogue_sources_v1.sql.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '120s';

create or replace function public.catalogue_relation_source_v1()
returns text
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  _mode text;
begin
  select mode into _mode from public.catalogue_cutover where field_group = 'relations';
  return case when _mode = 'new' then 'kuro' else 'anilist' end;
end;
$$;

-- Linked-table specs of a group: table, title column, entity column, shadow field.
-- Credits tables hold (id, <title>_id, <entity>_id, role, role_notes, created_at).
create or replace function public.catalogue_publish_batch_v1(
  p_medium text,
  p_group text,
  p_media_ids integer[],
  p_columns text[] default '{}',
  p_with_data_sources boolean default false
)
returns jsonb
language plpgsql
set search_path = public, extensions
as $$
declare
  _table text;
  _mode text;
  _ids integer[];
  _cols text[];
  _snapcols text[];
  _c text;
  _n bigint;
  _updated bigint := 0;
  _snapshotted bigint := 0;
  _replaced bigint := 0;
  _spec record;
  _prefix text;
  _upper text;
  _expr text;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_publish_batch_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  _table := p_medium;
  _upper := upper(p_medium);
  select mode into _mode from public.catalogue_cutover where field_group = p_group;
  if _mode is null then
    raise exception 'catalogue_publish_batch_v1: unknown group %', p_group using errcode = '22023';
  end if;
  if _mode <> 'new' then
    raise exception 'catalogue_publish_batch_v1: group % is %, not new', p_group, _mode using errcode = '55000';
  end if;
  if p_media_ids is null or coalesce(array_length(p_media_ids, 1), 0) = 0 then
    return jsonb_build_object('titles', 0, 'snapshotted', 0, 'columns_updated', 0, 'tables_replaced', 0);
  end if;
  if array_length(p_media_ids, 1) > 500 then
    raise exception 'catalogue_publish_batch_v1: at most 500 titles per call' using errcode = '22023';
  end if;

  _cols := coalesce(p_columns, '{}');
  foreach _c in array _cols loop
    if _c in ('id', 'anilist_id') or not exists (
      select 1 from pg_attribute a
      where a.attrelid = ('public.' || _table)::regclass and a.attname = _c and a.attnum > 0 and not a.attisdropped
    ) then
      raise exception 'catalogue_publish_batch_v1: % is not a publishable column of %', _c, _table using errcode = '22023';
    end if;
  end loop;
  _snapcols := _cols || case when p_with_data_sources then array['data_sources'] else '{}'::text[] end;

  execute format('select coalesce(array_agg(id), ''{}'') from public.%I where id = any ($1)', _table)
    into _ids using p_media_ids;
  if coalesce(array_length(_ids, 1), 0) = 0 then
    return jsonb_build_object('titles', 0, 'snapshotted', 0, 'columns_updated', 0, 'tables_replaced', 0);
  end if;

  -- 1a. snapshot the main-row columns of titles with no snapshot yet (first publish of the group)
  execute format($q$
    insert into public.catalogue_rollback_snapshots (field_group, medium, media_id, payload, taken_at)
    select $1, $2, t.id,
           jsonb_build_object(
             'columns', (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
                           from jsonb_each(to_jsonb(t)) e where e.key = any ($3)),
             'tables', '{}'::jsonb),
           now()
      from public.%I t
     where t.id = any ($4)
    on conflict (field_group, medium, media_id) do nothing
  $q$, _table) using p_group, p_medium, _snapcols, _ids;
  get diagnostics _snapshotted = row_count;

  -- 2. main-row columns from shadow values (never blank a column)
  foreach _c in array _cols loop
    if _c ~ '^(start|end)_date_(month|day)$' then
      -- Part of a date triple: follows the year. A shadow year makes a missing part null.
      _prefix := regexp_replace(_c, '_(month|day)$', '');
      _expr := format($q$
        update public.%1$I t
           set %2$I = nv.v
          from (select y.media_id,
                       (jsonb_populate_record(null::public.%1$I,
                          jsonb_build_object(%2$L, coalesce(sv.value, 'null'::jsonb)))).%2$I as v
                  from public.catalogue_shadow_values y
                  left join public.catalogue_shadow_values sv
                    on sv.medium = y.medium and sv.media_id = y.media_id and sv.field = %2$L
                 where y.medium = $1 and y.field = %3$L and y.media_id = any ($2)
                   and y.value is not null and y.value <> 'null'::jsonb) nv
         where t.id = nv.media_id and t.%2$I is distinct from nv.v
      $q$, _table, _c, _prefix || '_year');
    else
      _expr := format($q$
        update public.%1$I t
           set %2$I = nv.v
          from (select sv.media_id,
                       (jsonb_populate_record(null::public.%1$I, jsonb_build_object(%2$L, sv.value))).%2$I as v
                  from public.catalogue_shadow_values sv
                 where sv.medium = $1 and sv.field = %2$L and sv.media_id = any ($2)
                   and sv.value is not null and sv.value <> 'null'::jsonb) nv
         where t.id = nv.media_id and t.%2$I is distinct from nv.v
           %3$s
      $q$, _table, _c,
        case when _c = 'is_adult' then 'and not (t.is_adult is true and nv.v is not true)' else '' end);
    end if;
    execute _expr using p_medium, _ids;
    get diagnostics _n = row_count;
    _updated := _updated + _n;
  end loop;

  -- 2b. data_sources is copied as an ancillary column of the first group published
  if p_with_data_sources then
    execute format($q$
      update public.%1$I t
         set data_sources = nv.v
        from (select sv.media_id,
                     array(select jsonb_array_elements_text(sv.value)) as v
                from public.catalogue_shadow_values sv
               where sv.medium = $1 and sv.field = 'data_sources' and sv.media_id = any ($2)
                 and jsonb_typeof(sv.value) = 'array') nv
       where t.id = nv.media_id and t.data_sources is distinct from nv.v
    $q$, _table) using p_medium, _ids;
    get diagnostics _n = row_count;
    _updated := _updated + _n;
  end if;

  -- 3. linked rows
  if p_group = 'relations' then
    -- shadow 'relations' = [{type, kind, target_id, sources, status}]; only accepted ones publish.
    -- Titles whose shadow carries the field and whose kuro rows differ get their kuro rows replaced.
    create temp table if not exists _catalogue_pub_ids (id integer primary key) on commit drop;
    truncate _catalogue_pub_ids;
    insert into _catalogue_pub_ids
      select sv.media_id from public.catalogue_shadow_values sv
       where sv.medium = p_medium and sv.field = 'relations' and sv.media_id = any (_ids)
         and jsonb_typeof(sv.value) = 'array';

    create temp table if not exists _catalogue_pub_rel (
      from_id integer, relation_type text, to_type text, to_id integer
    ) on commit drop;
    truncate _catalogue_pub_rel;
    insert into _catalogue_pub_rel
      select distinct sv.media_id, r.elem ->> 'type', upper(r.elem ->> 'kind'), (r.elem ->> 'target_id')::integer
        from public.catalogue_shadow_values sv
        join _catalogue_pub_ids p on p.id = sv.media_id
        cross join lateral jsonb_array_elements(sv.value) r(elem)
       where sv.medium = p_medium and sv.field = 'relations'
         and coalesce(r.elem ->> 'status', 'accepted') = 'accepted'
         and (r.elem ->> 'target_id')::integer is distinct from sv.media_id;

    -- changed = the kuro row set differs from the shadow list
    create temp table if not exists _catalogue_pub_changed (id integer primary key) on commit drop;
    truncate _catalogue_pub_changed;
    insert into _catalogue_pub_changed
      select p.id from _catalogue_pub_ids p
       where coalesce((select md5(string_agg(x.k, '|' order by x.k)) from (
                 select mr.relation_type || ':' || upper(mr.to_media_type) || ':' || mr.to_media_id as k
                   from public.media_relations mr
                  where mr.from_media_type = _upper and mr.from_media_id = p.id and mr.source = 'kuro') x), '')
          is distinct from
             coalesce((select md5(string_agg(x.k, '|' order by x.k)) from (
                 select r.relation_type || ':' || r.to_type || ':' || r.to_id as k
                   from _catalogue_pub_rel r where r.from_id = p.id) x), '');

    update public.catalogue_rollback_snapshots s
       set payload = jsonb_set(s.payload, '{tables,media_relations}',
             coalesce((select jsonb_agg(to_jsonb(mr) order by mr.id) from public.media_relations mr
                        where mr.from_media_type = _upper and mr.from_media_id = s.media_id and mr.source = 'kuro'),
                      '[]'::jsonb))
     where s.field_group = p_group and s.medium = p_medium
       and s.media_id in (select id from _catalogue_pub_changed)
       and not (s.payload -> 'tables') ? 'media_relations';

    delete from public.media_relations mr
     where mr.from_media_type = _upper and mr.source = 'kuro'
       and mr.from_media_id in (select id from _catalogue_pub_changed);
    insert into public.media_relations (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
      select _upper, r.from_id, r.relation_type, r.to_type, r.to_id, 'kuro'
        from _catalogue_pub_rel r
       where r.from_id in (select id from _catalogue_pub_changed)
      on conflict do nothing;
    select count(*) into _n from _catalogue_pub_changed;
    _replaced := _replaced + _n;
  end if;

  for _spec in
    select * from (values
      ('anime', 'credits', 'anime_staff',      'anime_id', 'staff_id',     'credits:staff'),
      ('anime', 'credits', 'anime_studios',    'anime_id', 'studio_id',    'credits:studios'),
      ('anime', 'credits', 'anime_characters', 'anime_id', 'character_id', 'credits:characters'),
      ('manga', 'credits', 'manga_authors',    'manga_id', 'author_id',    'credits:authors')
    ) v(medium, grp, tbl, title_col, entity_col, field)
    where v.medium = p_medium and v.grp = p_group
  loop
    create temp table if not exists _catalogue_pub_credit (title_id integer, entity_id integer, role text) on commit drop;
    truncate _catalogue_pub_credit;
    -- the first credit per (title, entity) wins: the tables are unique on (title, entity)
    insert into _catalogue_pub_credit
      select distinct on (sv.media_id, (c.elem ->> 'kuro_id')::integer)
             sv.media_id, (c.elem ->> 'kuro_id')::integer, nullif(c.elem ->> 'role', '')
        from public.catalogue_shadow_values sv
        cross join lateral jsonb_array_elements(sv.value) with ordinality c(elem, ord)
       where sv.medium = p_medium and sv.field = _spec.field and sv.media_id = any (_ids)
         and jsonb_typeof(sv.value) = 'array' and (c.elem ->> 'kuro_id') is not null
       order by sv.media_id, (c.elem ->> 'kuro_id')::integer, c.ord;

    create temp table if not exists _catalogue_pub_changed (id integer primary key) on commit drop;
    truncate _catalogue_pub_changed;
    execute format($q$
      insert into _catalogue_pub_changed
        select sv.media_id from public.catalogue_shadow_values sv
         where sv.medium = $1 and sv.field = $2 and sv.media_id = any ($3) and jsonb_typeof(sv.value) = 'array'
           and coalesce((select md5(string_agg(x.k, '|' order by x.k)) from (
                   select t.%2$I::text || ':' || coalesce(t.role, '') as k from public.%1$I t
                    where t.%3$I = sv.media_id) x), '')
               is distinct from
               coalesce((select md5(string_agg(x.k, '|' order by x.k)) from (
                   select c.entity_id::text || ':' || coalesce(c.role, '') as k from _catalogue_pub_credit c
                    where c.title_id = sv.media_id
                      and exists (select 1 from public.%4$I e where e.id = c.entity_id)) x), '')
    $q$, _spec.tbl, _spec.entity_col, _spec.title_col,
      case _spec.entity_col when 'staff_id' then 'staff' when 'studio_id' then 'studios'
                            when 'character_id' then 'characters' else 'authors' end)
      using p_medium, _spec.field, _ids;

    -- snapshot the table's current rows once per title, before the first replacement
    execute format($q$
      update public.catalogue_rollback_snapshots s
         set payload = jsonb_set(s.payload, array['tables', %2$L],
               coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.%1$I t where t.%3$I = s.media_id), '[]'::jsonb))
       where s.field_group = $1 and s.medium = $2
         and s.media_id in (select id from _catalogue_pub_changed)
         and not (s.payload -> 'tables') ? %2$L
    $q$, _spec.tbl, _spec.tbl, _spec.title_col) using p_group, p_medium;

    execute format('delete from public.%I where %I in (select id from _catalogue_pub_changed)', _spec.tbl, _spec.title_col);
    execute format($q$
      insert into public.%1$I (%2$I, %3$I, role)
        select c.title_id, c.entity_id, c.role from _catalogue_pub_credit c
         where c.title_id in (select id from _catalogue_pub_changed)
           and exists (select 1 from public.%4$I e where e.id = c.entity_id)
        on conflict do nothing
    $q$, _spec.tbl, _spec.title_col, _spec.entity_col,
      case _spec.entity_col when 'staff_id' then 'staff' when 'studio_id' then 'studios'
                            when 'character_id' then 'characters' else 'authors' end);
    select count(*) into _n from _catalogue_pub_changed;
    _replaced := _replaced + _n;
  end loop;

  return jsonb_build_object('titles', array_length(_ids, 1), 'snapshotted', _snapshotted,
                            'columns_updated', _updated, 'tables_replaced', _replaced);
end;
$$;

create or replace function public.catalogue_restore_batch_v1(
  p_medium text,
  p_group text,
  p_limit integer default 500
)
returns jsonb
language plpgsql
set search_path = public, extensions
as $$
declare
  _table text;
  _upper text;
  _mode text;
  _ids integer[];
  _c text;
  _tbl text;
  _title_col text;
  _restored integer;
  _remaining bigint;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'catalogue_restore_batch_v1: medium must be anime or manga' using errcode = '22023';
  end if;
  _table := p_medium;
  _upper := upper(p_medium);
  select mode into _mode from public.catalogue_cutover where field_group = p_group;
  if _mode is null then
    raise exception 'catalogue_restore_batch_v1: unknown group %', p_group using errcode = '22023';
  end if;
  if _mode = 'new' then
    raise exception 'catalogue_restore_batch_v1: group % is still new; switch it back first', p_group using errcode = '55000';
  end if;
  p_limit := greatest(1, least(coalesce(p_limit, 500), 500));

  select coalesce(array_agg(media_id), '{}') into _ids from (
    select media_id from public.catalogue_rollback_snapshots
     where field_group = p_group and medium = p_medium order by media_id limit p_limit) x;

  -- main-row columns: exactly the snapshot (null stays null: that was the pre-switch state)
  for _c in
    select distinct k from public.catalogue_rollback_snapshots s, jsonb_object_keys(s.payload -> 'columns') k
     where s.field_group = p_group and s.medium = p_medium and s.media_id = any (_ids)
  loop
    execute format($q$
      update public.%1$I t
         set %2$I = (jsonb_populate_record(null::public.%1$I, jsonb_build_object(%2$L, s.payload -> 'columns' -> %2$L))).%2$I
        from public.catalogue_rollback_snapshots s
       where s.field_group = $1 and s.medium = $2 and s.media_id = any ($3)
         and (s.payload -> 'columns') ? %2$L and t.id = s.media_id
    $q$, _table, _c) using p_group, p_medium, _ids;
  end loop;

  -- linked rows: delete the title's rows in the table (relations: only source 'kuro'), put the snapshot back with ids
  for _tbl in
    select distinct k from public.catalogue_rollback_snapshots s, jsonb_object_keys(s.payload -> 'tables') k
     where s.field_group = p_group and s.medium = p_medium and s.media_id = any (_ids)
  loop
    if _tbl = 'media_relations' then
      delete from public.media_relations mr
       where mr.from_media_type = _upper and mr.source = 'kuro' and mr.from_media_id = any (_ids)
         and mr.from_media_id in (select media_id from public.catalogue_rollback_snapshots s
                                   where s.field_group = p_group and s.medium = p_medium and (s.payload -> 'tables') ? 'media_relations');
      insert into public.media_relations
        select r.* from public.catalogue_rollback_snapshots s,
             lateral jsonb_populate_recordset(null::public.media_relations, s.payload -> 'tables' -> 'media_relations') r
         where s.field_group = p_group and s.medium = p_medium and s.media_id = any (_ids)
           and (s.payload -> 'tables') ? 'media_relations';
    elsif _tbl in ('anime_staff', 'anime_studios', 'anime_characters', 'manga_authors') then
      _title_col := case when _tbl like 'anime_%' then 'anime_id' else 'manga_id' end;
      execute format($q$
        delete from public.%1$I t where t.%2$I = any ($3)
           and t.%2$I in (select media_id from public.catalogue_rollback_snapshots s
                           where s.field_group = $1 and s.medium = $2 and (s.payload -> 'tables') ? %1$L)
      $q$, _tbl, _title_col) using p_group, p_medium, _ids;
      execute format($q$
        insert into public.%1$I
          select r.* from public.catalogue_rollback_snapshots s,
               lateral jsonb_populate_recordset(null::public.%1$I, s.payload -> 'tables' -> %1$L) r
           where s.field_group = $1 and s.medium = $2 and s.media_id = any ($3) and (s.payload -> 'tables') ? %1$L
      $q$, _tbl) using p_group, p_medium, _ids;
    else
      raise exception 'catalogue_restore_batch_v1: snapshot holds an unknown table %', _tbl using errcode = '22023';
    end if;
  end loop;

  delete from public.catalogue_rollback_snapshots
   where field_group = p_group and medium = p_medium and media_id = any (_ids);
  get diagnostics _restored = row_count;
  select count(*) into _remaining from public.catalogue_rollback_snapshots
   where field_group = p_group and medium = p_medium;
  return jsonb_build_object('restored', _restored, 'remaining', _remaining);
end;
$$;

-- get_media_ladder: body of 20260311100000_ladder_source_author.sql plus the source filter.
CREATE OR REPLACE FUNCTION public.get_media_ladder(
  p_media_type text,
  p_media_id int
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  normalized_media_type text := upper(trim(COALESCE(p_media_type, '')));
  -- Catalogue cutover (20261112100150): hide the writer that no longer owns the relations group.
  hidden_relation_source text := CASE WHEN public.catalogue_relation_source_v1() = 'kuro' THEN 'anilist' ELSE 'kuro' END;
BEGIN
  IF normalized_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION 'Unsupported media type for ladder: %', p_media_type
      USING ERRCODE = '22023';
  END IF;

  RETURN (
    WITH relation_rows AS (
      SELECT
        upper(mr.relation_type) AS relation_type,
        upper(mr.to_media_type) AS media_type,
        mr.to_media_id AS media_id,
        COALESCE(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') AS title,
        COALESCE(a.cover_image_large, m.cover_image_large) AS cover_image,
        COALESCE(a.season_year, m.start_date_year) AS year,
        COALESCE(a.format, m.format) AS format,
        CASE
          WHEN COALESCE(a.average_score, m.average_score) IS NULL THEN NULL
          ELSE round((COALESCE(a.average_score, m.average_score)::numeric) / 10.0, 1)
        END AS rating,
        COALESCE(a.popularity, m.popularity, 0) AS popularity,
        CASE COALESCE(a.format, m.format, '')
          WHEN 'TV' THEN 0
          WHEN 'MOVIE' THEN 1
          WHEN 'ONA' THEN 2
          WHEN 'OVA' THEN 3
          WHEN 'TV_SHORT' THEN 4
          WHEN 'SPECIAL' THEN 6
          WHEN 'MUSIC' THEN 7
          ELSE 5
        END AS format_priority
      FROM public.media_relations mr
      LEFT JOIN public.anime a
        ON upper(mr.to_media_type) = 'ANIME'
       AND a.id = mr.to_media_id
      LEFT JOIN public.manga m
        ON upper(mr.to_media_type) = 'MANGA'
       AND m.id = mr.to_media_id
      WHERE upper(mr.from_media_type) = normalized_media_type
        AND mr.from_media_id = p_media_id
        AND mr.source <> hidden_relation_source
        AND upper(mr.relation_type) IN ('SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF')
        AND (
          (
            upper(mr.to_media_type) = 'ANIME'
            AND a.id IS NOT NULL
            AND COALESCE(a.is_adult, false) = false
            AND NOT COALESCE('Hentai' = ANY(a.genres), false)
            AND NOT COALESCE('Ecchi' = ANY(a.genres), false)
          )
          OR
          (
            upper(mr.to_media_type) = 'MANGA'
            AND m.id IS NOT NULL
            AND COALESCE(m.is_adult, false) = false
            AND NOT COALESCE('Hentai' = ANY(m.genres), false)
            AND NOT COALESCE('Ecchi' = ANY(m.genres), false)
          )
        )
    ),
    source_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SOURCE'
      ORDER BY COALESCE(rating, 0) DESC, popularity DESC, year DESC NULLS LAST, media_id ASC
    ),
    adaptation_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'ADAPTATION'
      ORDER BY format_priority ASC, COALESCE(rating, 0) DESC, popularity DESC, year DESC NULLS LAST, media_id ASC
    ),
    prequel_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'PREQUEL'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    sequel_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SEQUEL'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    side_story_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SIDE_STORY'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    spin_off_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SPIN_OFF'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    curated AS (
      SELECT
        EXISTS (SELECT 1 FROM source_rows) AS has_source,
        EXISTS (SELECT 1 FROM adaptation_rows) AS has_adaptation,
        EXISTS (SELECT 1 FROM prequel_rows) OR EXISTS (SELECT 1 FROM sequel_rows) AS has_chronology,
        EXISTS (SELECT 1 FROM side_story_rows) OR EXISTS (SELECT 1 FROM spin_off_rows) AS has_companions
    ),
    primary_source AS (
      SELECT
        media_type, media_id, title, cover_image, year, format, rating,
        'Original source'::text AS reason_label
      FROM source_rows
      LIMIT 1
    ),
    -- Resolve author name for the primary source when it lives in the manga table
    -- (covers both MANGA and NOVEL formats since light novels are stored as manga).
    source_author AS (
      SELECT au.name_full
      FROM primary_source ps
      JOIN public.manga_authors ma ON ma.manga_id = ps.media_id
      JOIN public.authors au ON au.id = ma.author_id
      WHERE ps.media_type = 'MANGA'
      ORDER BY
        CASE WHEN lower(COALESCE(ma.role, '')) IN ('story', 'original creator', 'story & art', 'original story') THEN 0 ELSE 1 END,
        ma.author_id ASC
      LIMIT 1
    ),
    primary_adaptation AS (
      SELECT
        media_type, media_id, title, cover_image, year, format, rating,
        'Most relevant adaptation'::text AS reason_label
      FROM adaptation_rows
      LIMIT 1
    ),
    entry_point AS (
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 1 AS priority
        FROM prequel_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 2 AS priority
        FROM source_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 3 AS priority
        FROM adaptation_rows
        LIMIT 1
      ) q
      ORDER BY priority
      LIMIT 1
    ),
    next_step AS (
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Direct continuation'::text AS reason_label, 1 AS priority
        FROM sequel_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT pa.media_type, pa.media_id, pa.title, pa.cover_image, pa.year, pa.format, pa.rating, pa.reason_label, 2 AS priority
        FROM primary_adaptation pa
        WHERE NOT EXISTS (
          SELECT 1 FROM entry_point ep
          WHERE ep.media_type = pa.media_type AND ep.media_id = pa.media_id
        )
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT ps.media_type, ps.media_id, ps.title, ps.cover_image, ps.year, ps.format, ps.rating, ps.reason_label, 3 AS priority
        FROM primary_source ps
        WHERE NOT EXISTS (
          SELECT 1 FROM entry_point ep
          WHERE ep.media_type = ps.media_type AND ep.media_id = ps.media_id
        )
      ) q
      ORDER BY priority
      LIMIT 1
    ),
    -- First adaptation that is NOT the current item, for prose summary
    alt_adaptation AS (
      SELECT year, format
      FROM adaptation_rows
      WHERE NOT (media_type = normalized_media_type AND media_id = p_media_id)
      LIMIT 1
    )
    SELECT jsonb_build_object(
      'source_material',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM source_rows rr
      ), '[]'::jsonb),
      'adaptations',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM adaptation_rows rr
      ), '[]'::jsonb),
      'prequels',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM prequel_rows rr
      ), '[]'::jsonb),
      'sequels',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM sequel_rows rr
      ), '[]'::jsonb),
      'side_stories',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM side_story_rows rr
      ), '[]'::jsonb),
      'spin_offs',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM spin_off_rows rr
      ), '[]'::jsonb),
      'entry_point', (SELECT to_jsonb(ep) - 'priority' FROM entry_point ep),
      'next_step', (SELECT to_jsonb(ns) - 'priority' FROM next_step ns),
      'primary_source', (
        SELECT to_jsonb(ps) || jsonb_build_object(
          'source_author_name', (SELECT sa.name_full FROM source_author sa)
        )
        FROM primary_source ps
      ),
      'primary_adaptation', (SELECT to_jsonb(pa) FROM primary_adaptation pa),
      'coverage_status', (
        SELECT CASE
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 THEN 'strong'
          WHEN has_source OR has_adaptation OR has_chronology THEN 'partial'
          WHEN has_companions THEN 'minimal'
          ELSE 'minimal'
        END
        FROM curated
      ),
      'franchise_note', (
        SELECT CASE
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 AND has_source THEN 'Start with the source, then follow the main adaptation path.'
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 AND has_adaptation THEN 'Kuro found the clearest adaptation path for this title.'
          WHEN has_source OR has_adaptation OR has_chronology OR has_companions THEN 'Kuro found a partial path through this franchise.'
          ELSE NULL
        END
        FROM curated
      ),
      'total_franchise_count', (
        SELECT (SELECT count(*) FROM relation_rows) + 1
      ),
      'alternate_adaptation_summary', (
        SELECT
          CASE
            WHEN aa.year IS NOT NULL AND aa.format IS NOT NULL THEN
              aa.year::text || ' ' || lower(aa.format) || ' series'
            WHEN aa.year IS NOT NULL THEN
              aa.year::text || ' adaptation'
            WHEN aa.format IS NOT NULL THEN
              lower(aa.format) || ' series'
            ELSE NULL
          END
        FROM alt_adaptation aa
      )
    )
  );
END;
$$;

revoke all on function public.get_media_ladder(text, int) from public;
grant execute on function public.get_media_ladder(text, int) to anon, authenticated, service_role;
revoke all on function public.catalogue_relation_source_v1() from public, anon, authenticated;
revoke all on function public.catalogue_publish_batch_v1(text, text, integer[], text[], boolean) from public, anon, authenticated;
revoke all on function public.catalogue_restore_batch_v1(text, text, integer) from public, anon, authenticated;
grant execute on function public.catalogue_relation_source_v1() to service_role;
grant execute on function public.catalogue_publish_batch_v1(text, text, integer[], text[], boolean) to service_role;
grant execute on function public.catalogue_restore_batch_v1(text, text, integer) to service_role;

notify pgrst, 'reload schema';
commit;
