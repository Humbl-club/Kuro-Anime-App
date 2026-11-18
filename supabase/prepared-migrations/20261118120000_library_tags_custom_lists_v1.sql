-- PREPARED ONLY (W9): owner approval required to apply. Not applied, not deployed.
-- W9 tags, custom lists with manual order (tracker gaps). Depends on 20261007040000 (live: <medium>_user_lists
-- with TEXT user_id). Rollback = drop the 9 functions, then the 3 tables (custom_list_items, custom_lists, library_tags).
--
-- Three per-user tables (UUID user_id, auth.users FK ON DELETE CASCADE: account deletion needs no barrier trigger),
-- RLS select-own, NO client write grants. All writes go through plpgsql SECURITY DEFINER RPCs that derive the actor from
-- auth.uid() (never a client-supplied id), take one per-account advisory lock, and never touch <medium>_user_lists, so
-- server_revision of the library is never advanced.
-- Conflict contract: no whole-set replacement. Membership changes are deltas (apply_title_organisation_delta_v1); every
-- list carries a revision bumped by each membership/order change; move/rebalance take the expected revision and raise
-- STALE_LIST otherwise. Error codes are the exception MESSAGE.
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

-- ---------------------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.library_tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null check (media_id > 0),
  tag text not null check (tag = btrim(tag) and tag = normalize(tag, NFC) and char_length(tag) between 1 and 24),
  -- Unicode case folding through ICU, independent of the cluster's lc_ctype.
  tag_key text generated always as (lower(tag collate "und-x-icu")) stored,
  created_at timestamptz not null default now(),
  primary key (user_id, medium, media_id, tag_key)
);
create index library_tags_user_tag_idx on public.library_tags (user_id, tag_key);

create table public.custom_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (name = btrim(name) and name = normalize(name, NFC) and char_length(name) between 1 and 60),
  name_key text generated always as (lower(name collate "und-x-icu")) stored,
  revision bigint not null default 0 check (revision >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name_key),
  unique (id, user_id)
);

create table public.custom_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  medium text not null check (medium in ('anime', 'manga')),
  media_id integer not null check (media_id > 0),
  position double precision not null check (position > '-Infinity'::float8 and position < 'Infinity'::float8),
  added_at timestamptz not null default now(),
  foreign key (list_id, user_id) references public.custom_lists(id, user_id) on delete cascade,
  unique (list_id, medium, media_id)
);
-- No FK to <medium>_user_lists: an item survives its title's removal from the library.
create index custom_list_items_order_idx on public.custom_list_items (list_id, position, id);
create index custom_list_items_user_idx on public.custom_list_items (user_id, list_id);

alter table public.library_tags enable row level security;
alter table public.custom_lists enable row level security;
alter table public.custom_list_items enable row level security;
create policy library_tags_select_own on public.library_tags for select to authenticated
  using ((select auth.uid()) = user_id);
create policy custom_lists_select_own on public.custom_lists for select to authenticated
  using ((select auth.uid()) = user_id);
create policy custom_list_items_select_own on public.custom_list_items for select to authenticated
  using ((select auth.uid()) = user_id);
revoke all on public.library_tags, public.custom_lists, public.custom_list_items from public, anon, authenticated;
grant select on public.library_tags, public.custom_lists, public.custom_list_items to authenticated;
grant all on public.library_tags, public.custom_lists, public.custom_list_items to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- Tag index read
-- ---------------------------------------------------------------------------------------------------------------------
create function public.library_tag_index_v1()
returns table(medium text, media_id integer, tags text[])
language plpgsql stable security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;
  end if;
  -- The EXPLAIN check in 107_library_tags.sql mirrors this query text.
  return query
    select t.medium, t.media_id, array_agg(t.tag order by t.tag_key)
    from public.library_tags t
    where t.user_id = v_uid
    group by t.medium, t.media_id
    order by t.medium, t.media_id;
end
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Atomic organisation delta (tags and list membership of ONE title)
-- ---------------------------------------------------------------------------------------------------------------------
create function public.apply_title_organisation_delta_v1(
  p_medium text, p_media_id integer, p_add_tags text[], p_remove_tags text[],
  p_add_list_ids uuid[], p_remove_list_ids uuid[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_t text;
  v_k text;
  v_add text[] := '{}';
  v_add_keys text[] := '{}';
  v_rem_keys text[] := '{}';
  v_add_lists uuid[];
  v_rem_lists uuid[];
  v_new_tags text[] := '{}';
  v_new_lists uuid[] := '{}';
  v_hit uuid[];
  v_tracked boolean;
  v_have integer;
  v_acct_items integer;
  v_list uuid;
  v_rev bigint;
  v_pos double precision;
  v_changed jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  if p_media_id is null or p_media_id <= 0 then
    raise exception 'ENTRY_NOT_FOUND';
  end if;

  foreach v_t in array coalesce(p_add_tags, '{}'::text[]) loop
    v_t := normalize(btrim(coalesce(v_t, ''), E' \t\r\n'), NFC);
    if v_t = '' then
      raise exception 'TAG_EMPTY';
    end if;
    if char_length(v_t) > 24 then
      raise exception 'TAG_TOO_LONG';
    end if;
    v_k := lower(v_t collate "und-x-icu");
    if not (v_k = any (v_add_keys)) then
      v_add := v_add || v_t;
      v_add_keys := v_add_keys || v_k;
    end if;
  end loop;
  foreach v_t in array coalesce(p_remove_tags, '{}'::text[]) loop
    v_t := normalize(btrim(coalesce(v_t, ''), E' \t\r\n'), NFC);
    if v_t <> '' then
      v_rem_keys := v_rem_keys || lower(v_t collate "und-x-icu");
    end if;
  end loop;
  v_add_lists := array(select distinct x from unnest(coalesce(p_add_list_ids, '{}'::uuid[])) x where x is not null);
  v_rem_lists := array(select distinct x from unnest(coalesce(p_remove_list_ids, '{}'::uuid[])) x where x is not null);
  if v_add_keys && v_rem_keys or v_add_lists && v_rem_lists then
    raise exception 'DELTA_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));

  -- Removes first (absent = no-op).
  if cardinality(v_rem_keys) > 0 then
    delete from public.library_tags t
     where t.user_id = v_uid and t.medium = p_medium and t.media_id = p_media_id and t.tag_key = any (v_rem_keys);
  end if;
  if cardinality(v_rem_lists) > 0 then
    with d as (
      delete from public.custom_list_items i
       where i.user_id = v_uid and i.medium = p_medium and i.media_id = p_media_id and i.list_id = any (v_rem_lists)
      returning i.list_id)
    select coalesce(array_agg(d.list_id), '{}'::uuid[]) into v_hit from d;
    foreach v_list in array v_hit loop
      update public.custom_lists l set revision = l.revision + 1, updated_at = now()
       where l.id = v_list and l.user_id = v_uid
      returning l.revision into v_rev;
      v_changed := v_changed || jsonb_build_object('list_id', v_list, 'revision_before', v_rev - 1, 'revision', v_rev);
    end loop;
  end if;

  -- Adds. A list that is missing or foreign cannot be added to.
  foreach v_list in array v_add_lists loop
    if not exists (select 1 from public.custom_lists l where l.id = v_list and l.user_id = v_uid) then
      raise exception 'LIST_NOT_FOUND';
    end if;
  end loop;
  foreach v_t in array v_add loop
    if not exists (select 1 from public.library_tags t
                    where t.user_id = v_uid and t.medium = p_medium and t.media_id = p_media_id
                      and t.tag_key = lower(v_t collate "und-x-icu")) then
      v_new_tags := v_new_tags || v_t;
    end if;
  end loop;
  foreach v_list in array v_add_lists loop
    if not exists (select 1 from public.custom_list_items i
                    where i.list_id = v_list and i.user_id = v_uid and i.medium = p_medium and i.media_id = p_media_id) then
      v_new_lists := v_new_lists || v_list;
    end if;
  end loop;

  if cardinality(v_new_tags) > 0 or cardinality(v_new_lists) > 0 then
    if p_medium = 'anime' then
      select exists (select 1 from public.anime_user_lists u where u.user_id = v_uid::text and u.anime_id = p_media_id)
        into v_tracked;
    else
      select exists (select 1 from public.manga_user_lists u where u.user_id = v_uid::text and u.manga_id = p_media_id)
        into v_tracked;
    end if;
    if not v_tracked then
      raise exception 'ENTRY_NOT_FOUND';
    end if;
  end if;

  if cardinality(v_new_tags) > 0 then
    select count(*) into v_have from public.library_tags t
     where t.user_id = v_uid and t.medium = p_medium and t.media_id = p_media_id;
    if v_have + cardinality(v_new_tags) > 10 then
      raise exception 'TAG_LIMIT';
    end if;
    foreach v_t in array v_new_tags loop
      insert into public.library_tags (user_id, medium, media_id, tag) values (v_uid, p_medium, p_media_id, v_t);
    end loop;
  end if;

  if cardinality(v_new_lists) > 0 then
    select count(*) into v_acct_items from public.custom_list_items i where i.user_id = v_uid;
    foreach v_list in array v_new_lists loop
      select count(*) into v_have from public.custom_list_items i where i.list_id = v_list;
      if v_have >= 2000 then
        raise exception 'LIST_FULL';
      end if;
      if v_acct_items >= 10000 then
        raise exception 'LIST_ITEMS_LIMIT';
      end if;
      select coalesce(max(i.position), 0) + 1024 into v_pos from public.custom_list_items i where i.list_id = v_list;
      insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
      values (v_list, v_uid, p_medium, p_media_id, v_pos);
      v_acct_items := v_acct_items + 1;
      update public.custom_lists l set revision = l.revision + 1, updated_at = now()
       where l.id = v_list and l.user_id = v_uid
      returning l.revision into v_rev;
      v_changed := v_changed || jsonb_build_object('list_id', v_list, 'revision_before', v_rev - 1, 'revision', v_rev);
    end loop;
  end if;

  return jsonb_build_object(
    'tags', coalesce((select jsonb_agg(t.tag order by t.tag_key) from public.library_tags t
                       where t.user_id = v_uid and t.medium = p_medium and t.media_id = p_media_id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('list_id', i.list_id, 'item_id', i.id, 'position', i.position)
                                         order by i.list_id, i.position, i.id)
                         from public.custom_list_items i
                        where i.user_id = v_uid and i.medium = p_medium and i.media_id = p_media_id), '[]'::jsonb),
    'lists', v_changed);
end
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Custom lists
-- ---------------------------------------------------------------------------------------------------------------------
create function public.custom_lists_v1()
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return '[]'::jsonb;
  end if;
  -- The EXPLAIN check in 108_custom_lists.sql mirrors the items query (grouped per list below).
  return coalesce((
    with its as (
      select i.list_id,
             jsonb_agg(jsonb_build_object('item_id', i.id, 'medium', i.medium, 'media_id', i.media_id,
                                          'position', i.position) order by i.position, i.id) as items
      from public.custom_list_items i
      where i.user_id = v_uid
      group by i.list_id)
    select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'created_at', l.created_at,
                                        'updated_at', l.updated_at, 'revision', l.revision,
                                        'items', coalesce(its.items, '[]'::jsonb)) order by l.name_key)
    from public.custom_lists l
    left join its on its.list_id = l.id
    where l.user_id = v_uid), '[]'::jsonb);
end
$fn$;

create function public.create_custom_list_v1(p_name text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_row public.custom_lists;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  v_name := normalize(btrim(coalesce(p_name, ''), E' \t\r\n'), NFC);
  if v_name = '' or char_length(v_name) > 60 then
    raise exception 'LIST_NAME_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));
  if exists (select 1 from public.custom_lists l
              where l.user_id = v_uid and l.name_key = lower(v_name collate "und-x-icu")) then
    raise exception 'LIST_NAME_TAKEN';
  end if;
  if (select count(*) from public.custom_lists l where l.user_id = v_uid) >= 50 then
    raise exception 'LIST_LIMIT';
  end if;
  insert into public.custom_lists (user_id, name) values (v_uid, v_name) returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'name', v_row.name, 'created_at', v_row.created_at, 'revision', v_row.revision);
end
$fn$;

create function public.rename_custom_list_v1(p_list_id uuid, p_name text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_row public.custom_lists;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  v_name := normalize(btrim(coalesce(p_name, ''), E' \t\r\n'), NFC);
  if v_name = '' or char_length(v_name) > 60 then
    raise exception 'LIST_NAME_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));
  if not exists (select 1 from public.custom_lists l where l.id = p_list_id and l.user_id = v_uid) then
    raise exception 'LIST_NOT_FOUND';
  end if;
  if exists (select 1 from public.custom_lists l
              where l.user_id = v_uid and l.id <> p_list_id and l.name_key = lower(v_name collate "und-x-icu")) then
    raise exception 'LIST_NAME_TAKEN';
  end if;
  update public.custom_lists l set name = v_name, updated_at = now()
   where l.id = p_list_id and l.user_id = v_uid
  returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'name', v_row.name, 'created_at', v_row.created_at, 'revision', v_row.revision);
end
$fn$;

create function public.delete_custom_list_v1(p_list_id uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_n integer;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));
  delete from public.custom_lists l where l.id = p_list_id and l.user_id = v_uid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'LIST_NOT_FOUND';
  end if;
end
$fn$;

create function public.move_custom_list_item_v1(
  p_list_id uuid, p_item_id uuid, p_after_position double precision,
  p_before_position double precision, p_expected_list_revision bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_rev bigint;
  v_new double precision;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));
  -- Read after the lock: under READ COMMITTED the second of two concurrent moves sees the first commit.
  select l.revision into v_rev from public.custom_lists l where l.id = p_list_id and l.user_id = v_uid;
  if not found then
    raise exception 'LIST_NOT_FOUND';
  end if;
  if p_expected_list_revision is null or v_rev <> p_expected_list_revision then
    raise exception 'STALE_LIST';
  end if;
  if not exists (select 1 from public.custom_list_items i where i.id = p_item_id and i.list_id = p_list_id) then
    raise exception 'ITEM_NOT_FOUND';
  end if;
  if p_after_position is null and p_before_position is null then
    raise exception 'POSITION_INVALID';
  elsif p_after_position is null then
    v_new := p_before_position - 1024;
  elsif p_before_position is null then
    v_new := p_after_position + 1024;
  else
    v_new := (p_after_position + p_before_position) / 2;
  end if;
  if v_new = 'NaN'::float8 or v_new in ('Infinity'::float8, '-Infinity'::float8)
     or (p_after_position is not null and not (v_new > p_after_position))
     or (p_before_position is not null and not (v_new < p_before_position)) then
    raise exception 'POSITION_INVALID';
  end if;
  update public.custom_list_items i set position = v_new where i.id = p_item_id and i.list_id = p_list_id;
  update public.custom_lists l set revision = l.revision + 1, updated_at = now()
   where l.id = p_list_id and l.user_id = v_uid
  returning l.revision into v_rev;
  return jsonb_build_object('item_id', p_item_id, 'position', v_new, 'revision', v_rev);
end
$fn$;

create function public.rebalance_custom_list_v1(p_list_id uuid, p_item_ids uuid[], p_expected_list_revision bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_rev bigint;
  v_ids uuid[] := coalesce(p_item_ids, '{}'::uuid[]);
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));
  select l.revision into v_rev from public.custom_lists l where l.id = p_list_id and l.user_id = v_uid;
  if not found then
    raise exception 'LIST_NOT_FOUND';
  end if;
  if p_expected_list_revision is null or v_rev <> p_expected_list_revision then
    raise exception 'STALE_LIST';
  end if;
  -- The id set must be exactly the list's items (no duplicates, nothing missing, nothing foreign).
  if (select count(*) from public.custom_list_items i where i.list_id = p_list_id) <> cardinality(v_ids)
     or (select count(distinct x) from unnest(v_ids) x) <> cardinality(v_ids)
     or exists (select 1 from unnest(v_ids) x
                 where not exists (select 1 from public.custom_list_items i where i.id = x and i.list_id = p_list_id)) then
    raise exception 'STALE_LIST';
  end if;
  update public.custom_list_items i set position = 1024.0 * u.ord
    from unnest(v_ids) with ordinality as u(id, ord)
   where i.id = u.id and i.list_id = p_list_id;
  update public.custom_lists l set revision = l.revision + 1, updated_at = now()
   where l.id = p_list_id and l.user_id = v_uid
  returning l.revision into v_rev;
  return jsonb_build_object('revision', v_rev,
    'items', coalesce((select jsonb_agg(jsonb_build_object('item_id', i.id, 'position', i.position)
                                         order by i.position, i.id)
                         from public.custom_list_items i where i.list_id = p_list_id), '[]'::jsonb));
end
$fn$;

create function public.seed_custom_lists_v1(p_lists jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $fn$
declare
  v_uid uuid := auth.uid();
  v_entry jsonb;
  v_name text;
  v_list public.custom_lists;
  v_created jsonb := '[]'::jsonb;
  v_reused jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_added integer := 0;
  v_n integer;
  v_have integer;
  v_acct integer;
  v_room integer;
  v_base double precision;
  v_el jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  if p_lists is null or jsonb_typeof(p_lists) <> 'array' or jsonb_array_length(p_lists) > 60 then
    raise exception 'SEED_INVALID';
  end if;
  for v_entry in select e from jsonb_array_elements(p_lists) e loop
    if jsonb_typeof(v_entry) <> 'object' or jsonb_typeof(v_entry -> 'name') is distinct from 'string'
       or jsonb_typeof(v_entry -> 'items') is distinct from 'array' or jsonb_array_length(v_entry -> 'items') > 2000 then
      raise exception 'SEED_INVALID';
    end if;
    for v_el in select e from jsonb_array_elements(v_entry -> 'items') e loop
      if jsonb_typeof(v_el) <> 'object' or (v_el ->> 'medium') is null or (v_el ->> 'medium') not in ('anime', 'manga')
         or jsonb_typeof(v_el -> 'media_id') is distinct from 'number'
         or (v_el ->> 'media_id') !~ '^[1-9][0-9]{0,8}$' then
        raise exception 'SEED_INVALID';
      end if;
    end loop;
  end loop;

  perform pg_advisory_xact_lock(hashtextextended('kuro.library.organise:' || v_uid::text, 0));

  for v_entry in select e from jsonb_array_elements(p_lists) e loop
    v_name := normalize(btrim(v_entry ->> 'name', E' \t\r\n'), NFC);
    if v_name = '' or char_length(v_name) > 60 then
      v_skipped := v_skipped || jsonb_build_object('name', v_entry ->> 'name', 'reason', 'LIST_NAME_INVALID');
      continue;
    end if;
    select * into v_list from public.custom_lists l
     where l.user_id = v_uid and l.name_key = lower(v_name collate "und-x-icu");
    if found then
      v_reused := v_reused || to_jsonb(v_list.name);
    else
      if (select count(*) from public.custom_lists l where l.user_id = v_uid) >= 50 then
        v_skipped := v_skipped || jsonb_build_object('name', v_name, 'reason', 'LIST_LIMIT');
        continue;
      end if;
      insert into public.custom_lists (user_id, name) values (v_uid, v_name) returning * into v_list;
      v_created := v_created || to_jsonb(v_list.name);
    end if;

    select count(*) into v_have from public.custom_list_items i where i.list_id = v_list.id;
    select count(*) into v_acct from public.custom_list_items i where i.user_id = v_uid;
    v_room := greatest(0, least(2000 - v_have, 10000 - v_acct));
    select coalesce(max(i.position), 0) into v_base from public.custom_list_items i where i.list_id = v_list.id;
    with src as (
      select distinct on (x.medium, x.media_id) x.medium, x.media_id, x.ord
      from jsonb_to_recordset(v_entry -> 'items') with ordinality as x(medium text, media_id integer, ord bigint)
      order by x.medium, x.media_id, x.ord),
    ok as (
      select s.medium, s.media_id, s.ord
      from src s
      where (s.medium = 'anime' and exists (select 1 from public.anime_user_lists u
                                             where u.user_id = v_uid::text and u.anime_id = s.media_id))
         or (s.medium = 'manga' and exists (select 1 from public.manga_user_lists u
                                             where u.user_id = v_uid::text and u.manga_id = s.media_id))),
    fresh as (
      select o.medium, o.media_id, o.ord
      from ok o
      where not exists (select 1 from public.custom_list_items i
                         where i.list_id = v_list.id and i.medium = o.medium and i.media_id = o.media_id)
      order by o.ord
      limit v_room)
    insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
    select v_list.id, v_uid, f.medium, f.media_id, v_base + 1024.0 * row_number() over (order by f.ord)
    from fresh f;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      update public.custom_lists l set revision = l.revision + 1, updated_at = now() where l.id = v_list.id;
      v_added := v_added + v_n;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'reused', v_reused, 'skipped', v_skipped, 'added', v_added);
end
$fn$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Privileges: SECURITY DEFINER functions are executable by signed-in users and the service role only.
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function public.library_tag_index_v1() from public, anon;
revoke all on function public.apply_title_organisation_delta_v1(text, integer, text[], text[], uuid[], uuid[]) from public, anon;
revoke all on function public.custom_lists_v1() from public, anon;
revoke all on function public.create_custom_list_v1(text) from public, anon;
revoke all on function public.rename_custom_list_v1(uuid, text) from public, anon;
revoke all on function public.delete_custom_list_v1(uuid) from public, anon;
revoke all on function public.move_custom_list_item_v1(uuid, uuid, double precision, double precision, bigint) from public, anon;
revoke all on function public.rebalance_custom_list_v1(uuid, uuid[], bigint) from public, anon;
revoke all on function public.seed_custom_lists_v1(jsonb) from public, anon;
grant execute on function public.library_tag_index_v1() to authenticated, service_role;
grant execute on function public.apply_title_organisation_delta_v1(text, integer, text[], text[], uuid[], uuid[]) to authenticated, service_role;
grant execute on function public.custom_lists_v1() to authenticated, service_role;
grant execute on function public.create_custom_list_v1(text) to authenticated, service_role;
grant execute on function public.rename_custom_list_v1(uuid, text) to authenticated, service_role;
grant execute on function public.delete_custom_list_v1(uuid) to authenticated, service_role;
grant execute on function public.move_custom_list_item_v1(uuid, uuid, double precision, double precision, bigint) to authenticated, service_role;
grant execute on function public.rebalance_custom_list_v1(uuid, uuid[], bigint) to authenticated, service_role;
grant execute on function public.seed_custom_lists_v1(jsonb) to authenticated, service_role;

commit;
