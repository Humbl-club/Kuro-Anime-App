-- W9 custom lists: privacy, bounds, mixed media, one-row guarded move, rebalance, seed, orphans, grants, plan.
-- Disposable local fixture only, never hosted.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;
\ir ../fixtures/library_2000.sql

select tests.make_user(1);
select tests.make_user(2);
set local session_replication_role = replica;
insert into public.anime (id, title_romaji) select n, 'T' || n from generate_series(1, 10) n on conflict (id) do nothing;
insert into public.manga (id, title_romaji) select n, 'M' || n from generate_series(1, 5) n on conflict (id) do nothing;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  select tests.uid(1)::text, n, 'PLANNING', 0 from generate_series(1, 4) n;
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values (tests.uid(1)::text, 2, 'PLANNING', 0);
set local session_replication_role = origin;

-- Mixed medium and privacy ----------------------------------------------------------------------------------------
select tests.as_user(tests.uid(1));
select (public.create_custom_list_v1('Winter picks')) ->> 'id' as wp \gset
select public.apply_title_organisation_delta_v1('anime', 1, null, null, array[:'wp'::uuid], null);
select public.apply_title_organisation_delta_v1('manga', 2, null, null, array[:'wp'::uuid], null);
select tests.eq('both media in one list',
  (select jsonb_array_length(l -> 'items') from jsonb_array_elements(public.custom_lists_v1()) l), 2);
select tests.eq('two membership changes bump the revision twice',
  (select (l ->> 'revision')::bigint from jsonb_array_elements(public.custom_lists_v1()) l), 2::bigint);

select tests.as_user(tests.uid(2));
select tests.eq('B sees no lists', jsonb_array_length(public.custom_lists_v1()), 0);
select tests.eq('B sees no list rows', tests.rowcount('select * from public.custom_lists'), 0::bigint);
select tests.eq('B sees no item rows', tests.rowcount('select * from public.custom_list_items'), 0::bigint);
select tests.raises('B cannot rename A''s list', format('select public.rename_custom_list_v1(%L, ''x'')', :'wp'), '%LIST_NOT_FOUND%');
select tests.raises('B cannot delete A''s list', format('select public.delete_custom_list_v1(%L)', :'wp'), '%LIST_NOT_FOUND%');
select tests.raises('B cannot add to A''s list', format('select public.apply_title_organisation_delta_v1(''anime'',1,null,null,array[%L::uuid],null)', :'wp'), '%LIST_NOT_FOUND%');
select tests.denied('B direct insert list', 'insert into public.custom_lists(user_id,name) values (''' || tests.uid(1) || ''',''x'')');
select tests.denied('B direct update list', 'update public.custom_lists set name = ''y''');
select tests.denied('B direct delete list', 'delete from public.custom_lists');
select tests.denied('B direct insert item', format('insert into public.custom_list_items(list_id,user_id,medium,media_id,position) values (%L,%L,''anime'',1,1)', :'wp', tests.uid(1)::text));
select tests.denied('B direct update item', 'update public.custom_list_items set position = 1');
select tests.denied('B direct delete item', 'delete from public.custom_list_items');

-- Rename ---------------------------------------------------------------------------------------------------------
select tests.as_user(tests.uid(1));
select tests.eq('rename keeps the revision',
  (public.rename_custom_list_v1(:'wp'::uuid, 'Winter picks 2')) ->> 'revision', '2');
select public.rename_custom_list_v1(:'wp'::uuid, 'Winter picks');

-- Limits ---------------------------------------------------------------------------------------------------------
select public.create_custom_list_v1('L' || n) from generate_series(2, 50) n;
select tests.eq('50 lists', jsonb_array_length(public.custom_lists_v1()), 50);
select tests.raises('51st list', 'select public.create_custom_list_v1(''L51'')', '%LIST_LIMIT%');
select tests.raises('case-insensitive duplicate name', 'select public.create_custom_list_v1(''winter PICKS'')', '%LIST_NAME_TAKEN%');
select tests.raises('name too long', 'select public.create_custom_list_v1(repeat(''x'',61))', '%LIST_NAME_INVALID%');
select tests.raises('blank name', 'select public.create_custom_list_v1(''  '')', '%LIST_NAME_INVALID%');
select tests.raises('rename onto another list''s name', format('select public.rename_custom_list_v1(%L, ''l2'')', :'wp'), '%LIST_NAME_TAKEN%');

-- Supported maximum: a list of 2,000 items refuses one more
select id as l2 from public.custom_lists where name = 'L2' \gset
select tests.reset();
set local session_replication_role = replica;
insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
  select :'l2'::uuid, tests.uid(1), 'anime', 100000 + n, 1024 * n from generate_series(1, 2000) n;
set local session_replication_role = origin;
select tests.as_user(tests.uid(1));
select tests.raises('LIST_FULL at 2,000 items',
  format('select public.apply_title_organisation_delta_v1(''anime'',1,null,null,array[%L::uuid],null)', :'l2'), '%LIST_FULL%');
select (l ->> 'revision')::bigint as l2rev from jsonb_array_elements(public.custom_lists_v1()) l where l ->> 'name' = 'L2' \gset
select tests.eq('rebalance of the 2,000-item list succeeds with all ids',
  jsonb_array_length((public.rebalance_custom_list_v1(:'l2'::uuid,
    (select array_agg(id order by position, id) from public.custom_list_items where list_id = :'l2'::uuid), :l2rev)) -> 'items'), 2000);

-- One-row move with the revision guard ----------------------------------------------------------------------------
select id as l3 from public.custom_lists where name = 'L3' \gset
select tests.reset();
set local session_replication_role = replica;
insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
  select :'l3'::uuid, tests.uid(1), 'anime', 200000 + n, 1024 * n from generate_series(1, 200) n;
set local session_replication_role = origin;
select tests.as_user(tests.uid(1));
select (l ->> 'revision')::bigint as r from jsonb_array_elements(public.custom_lists_v1()) l where l ->> 'name' = 'L3' \gset
create temp table _snap as select id, ctid as c from public.custom_list_items where list_id = :'l3'::uuid;
select id as item150 from public.custom_list_items where list_id = :'l3'::uuid and media_id = 200150 \gset
select tests.eq('move returns the midpoint',
  ((public.move_custom_list_item_v1(:'l3'::uuid, :'item150'::uuid, 2048, 3072, :r)) ->> 'position')::float8, 2560::float8);
select tests.eq('a move writes one item row',
  (select count(*) from public.custom_list_items i join _snap s using (id) where i.ctid <> s.c), 1::bigint);
select tests.eq('the move bumps the list revision once',
  (select revision from public.custom_lists where id = :'l3'::uuid), (:r + 1)::bigint);
select tests.eq('item 150 is now third',
  (select media_id from public.custom_list_items where list_id = :'l3'::uuid order by position, id offset 2 limit 1), 200150);
select tests.raises('the old revision is stale', format('select public.move_custom_list_item_v1(%L,%L,2048,3072,%s)', :'l3', :'item150', :r), '%STALE_LIST%');
select tests.eq('stale move wrote nothing',
  (select count(*) from public.custom_list_items i join _snap s using (id) where i.ctid <> s.c), 1::bigint);
select tests.raises('NaN position', format('select public.move_custom_list_item_v1(%L,%L,''NaN''::float8,3072,%s)', :'l3', :'item150', :r + 1), '%POSITION_INVALID%');
select tests.raises('Infinity position', format('select public.move_custom_list_item_v1(%L,%L,''Infinity''::float8,3072,%s)', :'l3', :'item150', :r + 1), '%POSITION_INVALID%');
select tests.raises('no neighbours', format('select public.move_custom_list_item_v1(%L,%L,null,null,%s)', :'l3', :'item150', :r + 1), '%POSITION_INVALID%');
select tests.raises('no room', format('select public.move_custom_list_item_v1(%L,%L,1,1,%s)', :'l3', :'item150', :r + 1), '%POSITION_INVALID%');
select tests.raises('item not in the list', format('select public.move_custom_list_item_v1(%L,%L,1,5,%s)', :'l3', :'wp', :r + 1), '%ITEM_NOT_FOUND%');
select tests.eq('head move uses before - 1024',
  ((public.move_custom_list_item_v1(:'l3'::uuid, :'item150'::uuid, null, 1024, :r + 1)) ->> 'position')::float8, 0::float8);

-- Rebalance
select tests.raises('rebalance with a stale id set',
  format('select public.rebalance_custom_list_v1(%L, array[%L::uuid], %s)', :'l3', :'item150', :r + 2), '%STALE_LIST%');
select tests.raises('rebalance with a stale revision',
  format('select public.rebalance_custom_list_v1(%L, (select array_agg(id) from public.custom_list_items where list_id = %L), %s)', :'l3', :'l3', :r), '%STALE_LIST%');
select tests.raises('rebalance with more than 2000 ids is capped before any lookup',
  format('select public.rebalance_custom_list_v1(%L, (select array_agg(gen_random_uuid()) from generate_series(1,2001)), %s)', :'l3', :r + 2), '%DELTA_INVALID%');
select tests.raises('seed with more than 10000 items in total is invalid',
  'select public.seed_custom_lists_v1((select jsonb_agg(jsonb_build_object(''name'', ''S'' || n, ''items'', (select jsonb_agg(jsonb_build_object(''medium'',''anime'',''media_id'',1)) from generate_series(1,1000)))) from generate_series(1,11) n))', '%SEED_INVALID%');
select (public.rebalance_custom_list_v1(:'l3'::uuid, (select array_agg(id order by position, id) from public.custom_list_items where list_id = :'l3'::uuid), :r + 2))::text as rb \gset
select tests.eq('rebalance renumbers 1024*i',
  (select array_agg(p) from (select (e ->> 'position')::float8 p from jsonb_array_elements(:'rb'::jsonb -> 'items') e order by 1 limit 3) q),
  array[1024, 2048, 3072]::float8[]);
select tests.eq('rebalance bumped the revision', (select revision from public.custom_lists where id = :'l3'::uuid), (:r + 3)::bigint);

-- Delete (frees room for the seed below)
select public.delete_custom_list_v1(id) from public.custom_lists where name in ('L40','L41','L42','L43','L44','L45','L46','L47','L48','L49','L50');
select tests.eq('deleted lists are gone', jsonb_array_length(public.custom_lists_v1()), 39);
select tests.raises('deleting a missing list', 'select public.delete_custom_list_v1(''00000000-0000-4000-8000-000000000000'')', '%LIST_NOT_FOUND%');

-- Seed ------------------------------------------------------------------------------------------------------------
select tests.eq('seed creates both lists, adds tracked titles only',
  (public.seed_custom_lists_v1('[{"name":"Favourites","items":[{"medium":"anime","media_id":1}]},{"name":"To rewatch","items":[{"medium":"manga","media_id":2},{"medium":"anime","media_id":999999}]}]'::jsonb)) - 'skipped' - 'reused',
  '{"created":["Favourites","To rewatch"],"added":2}'::jsonb);
select tests.eq('second identical seed creates nothing and adds nothing',
  (public.seed_custom_lists_v1('[{"name":"favourites","items":[{"medium":"anime","media_id":1}]},{"name":"To rewatch","items":[{"medium":"manga","media_id":2}]}]'::jsonb)),
  '{"created":[],"reused":["Favourites","To rewatch"],"skipped":[],"added":0}'::jsonb);
select tests.raises('malformed seed', 'select public.seed_custom_lists_v1(''[{"name":"x","items":[{"medium":"film","media_id":1}]}]''::jsonb)', '%SEED_INVALID%');
select tests.raises('seed must be an array', 'select public.seed_custom_lists_v1(''{}''::jsonb)', '%SEED_INVALID%');

-- Orphans (anime 3) -----------------------------------------------------------------------------------------------
select public.apply_title_organisation_delta_v1('anime', 3, null, null, array[:'wp'::uuid], null);
select tests.reset();
delete from public.anime_user_lists where user_id = tests.uid(1)::text and anime_id = 3;
select tests.as_user(tests.uid(1));
select tests.eq('the list item survives library removal',
  (select count(*) from public.custom_list_items where list_id = :'wp'::uuid and medium = 'anime' and media_id = 3), 1::bigint);
select tests.ok('custom_lists_v1 still lists it',
  exists (select 1 from jsonb_array_elements(public.custom_lists_v1()) l, jsonb_array_elements(l -> 'items') i
           where l ->> 'id' = :'wp' and (i ->> 'media_id')::int = 3));
select public.apply_title_organisation_delta_v1('anime', 3, null, null, null, array[:'wp'::uuid]);
select tests.eq('the orphan left the list',
  (select count(*) from public.custom_list_items where list_id = :'wp'::uuid and medium = 'anime' and media_id = 3), 0::bigint);
select tests.raises('re-adding an untracked title',
  format('select public.apply_title_organisation_delta_v1(''anime'',3,null,null,array[%L::uuid],null)', :'wp'), '%ENTRY_NOT_FOUND%');

-- Delta list semantics --------------------------------------------------------------------------------------------
select (public.create_custom_list_v1('Gone soon')) ->> 'id' as gone \gset
select public.delete_custom_list_v1(:'gone'::uuid);
select tests.ok('remove from a deleted list is a no-op',
  (public.apply_title_organisation_delta_v1('anime', 1, null, null, null, array[:'gone'::uuid])) is not null);
select tests.raises('add to a deleted list',
  format('select public.apply_title_organisation_delta_v1(''anime'',1,null,null,array[%L::uuid],null)', :'gone'), '%LIST_NOT_FOUND%');
select (l ->> 'revision')::bigint as wprev from jsonb_array_elements(public.custom_lists_v1()) l where l ->> 'id' = :'wp' \gset
select public.apply_title_organisation_delta_v1('anime', 1, null, null, array[:'wp'::uuid], null);
select tests.eq('adding an existing membership does not bump the revision',
  (select (l ->> 'revision')::bigint from jsonb_array_elements(public.custom_lists_v1()) l where l ->> 'id' = :'wp'), :wprev::bigint);
select tests.eq('delta result names the changed list with before/after',
  (select (e ->> 'revision')::bigint - (e ->> 'revision_before')::bigint from jsonb_array_elements(
    (public.apply_title_organisation_delta_v1('anime', 4, null, null, array[:'wp'::uuid], null)) -> 'lists') e), 1::bigint);

-- Grants and function config --------------------------------------------------------------------------------------
select tests.reset();
select tests.ok('anon has no EXECUTE on the seven list RPCs, authenticated has',
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('custom_lists_v1','create_custom_list_v1','rename_custom_list_v1','delete_custom_list_v1',
                        'move_custom_list_item_v1','rebalance_custom_list_v1','seed_custom_lists_v1')));
select tests.eq('seven list RPCs exist', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('custom_lists_v1','create_custom_list_v1','rename_custom_list_v1','delete_custom_list_v1',
                        'move_custom_list_item_v1','rebalance_custom_list_v1','seed_custom_lists_v1')), 7::bigint);
select tests.ok('search_path pinned, SECURITY DEFINER, plpgsql',
  (select bool_and(proconfig @> array['search_path=public, extensions'] and prosecdef
                   and prolang = (select oid from pg_language where lanname = 'plpgsql'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('custom_lists_v1','create_custom_list_v1','rename_custom_list_v1','delete_custom_list_v1',
                        'move_custom_list_item_v1','rebalance_custom_list_v1','seed_custom_lists_v1')));
select tests.ok('no LIST_ORDER_STALE anywhere', not exists (select 1 from pg_proc where prosrc like '%LIST_ORDER_STALE%'));
select tests.ok('no client write grants on the list tables',
  not has_table_privilege('authenticated', 'public.custom_lists', 'insert')
  and not has_table_privilege('authenticated', 'public.custom_list_items', 'update')
  and not has_table_privilege('anon', 'public.custom_lists', 'select'));

-- Plan at 2,000 titles --------------------------------------------------------------------------------------------
select pg_temp.load_library_2000(tests.uid(1));
set local session_replication_role = replica;
insert into public.custom_lists (user_id, name)
  select tests.uid(1000 + u), 'plan-' || n from generate_series(1, 400) u, generate_series(1, 20) n;
insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
  select l.id, l.user_id, 'anime', 9100000 + i, 1024 * i
  from public.custom_lists l, generate_series(1, 25) i where l.name like 'plan-%';
insert into public.custom_lists (user_id, name) select tests.uid(1), 'planu-' || n from generate_series(1, 20) n;
insert into public.custom_list_items (list_id, user_id, medium, media_id, position)
  select l.id, l.user_id, 'anime', 9100000 + i, 1024 * i
  from public.custom_lists l, generate_series(1, 100) i where l.user_id = tests.uid(1) and l.name like 'planu-%';
set local session_replication_role = origin;
analyze public.custom_lists;
analyze public.custom_list_items;
-- the query text mirrors the items read of public.custom_lists_v1()
select tests.ok('list items read uses custom_list_items_user_idx',
  pg_temp.plan_uses_index(format('select list_id, id, medium, media_id, position from public.custom_list_items where user_id=%L order by list_id, position, id', tests.uid(1)), 'custom_list_items_user_idx'));
drop index public.custom_list_items_user_idx;
select tests.ok('control: without the index the plan check is false',
  not pg_temp.plan_uses_index(format('select list_id, id, medium, media_id, position from public.custom_list_items where user_id=%L order by list_id, position, id', tests.uid(1)), 'custom_list_items_user_idx'));
rollback;
