-- W9 tags: privacy, bounds, normalisation, delta semantics, grants, 2,000-title plan, cascade.
-- Disposable local fixture only, never hosted.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;
\ir ../fixtures/library_2000.sql

select tests.ok('ICU collation available', exists (select 1 from pg_collation where collname = 'und-x-icu'));
select tests.ok('server encoding is UTF8 (normalize() is valid)', pg_encoding_to_char(encoding) = 'UTF8')
  from pg_database where datname = current_database();

select tests.make_user(1);
select tests.make_user(2);
set local session_replication_role = replica;
insert into public.anime (id, title_romaji) select n, 'T' || n from generate_series(1, 40) n on conflict (id) do nothing;
insert into public.manga (id, title_romaji) select n, 'M' || n from generate_series(1, 5) n on conflict (id) do nothing;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  select tests.uid(1)::text, n, 'PLANNING', 0 from generate_series(1, 40) n;
insert into public.manga_user_lists (user_id, manga_id, list_type, progress)
  values (tests.uid(1)::text, 2, 'PLANNING', 0);
set local session_replication_role = origin;

-- Privacy ---------------------------------------------------------------------------------------------------------
select tests.as_user(tests.uid(1));
select public.apply_title_organisation_delta_v1('anime', 1, array['comfy'], null, null, null);
select tests.eq('A tagged', (select tags from public.library_tag_index_v1() where media_id = 1 and medium = 'anime'), array['comfy']);

select tests.as_user(tests.uid(2));
select tests.eq('B reads none of A', tests.rowcount('select * from public.library_tags'), 0::bigint);
select tests.eq('B index empty', tests.rowcount('select * from public.library_tag_index_v1()'), 0::bigint);
select tests.denied('B cannot insert', 'insert into public.library_tags(user_id,medium,media_id,tag) values ('''||tests.uid(1)||''',''anime'',1,''x'')');
select tests.denied('B cannot update', 'update public.library_tags set tag = ''y''');
select tests.denied('B cannot delete', 'delete from public.library_tags');
select tests.raises('B cannot tag a title B does not track',
  'select public.apply_title_organisation_delta_v1(''anime'',1,array[''x''],null,null,null)', '%ENTRY_NOT_FOUND%');
select tests.as_user(tests.uid(1));
select tests.eq('A tag unchanged after B attempt', (select tags from public.library_tag_index_v1() where media_id = 1 and medium = 'anime'), array['comfy']);

-- Delta semantics -------------------------------------------------------------------------------------------------
select public.apply_title_organisation_delta_v1('anime', 1, array['Comfy'], null, null, null);
select tests.eq('re-adding by another case is a no-op keeping the stored spelling',
  (select tags from public.library_tag_index_v1() where media_id = 1 and medium = 'anime'), array['comfy']);
select tests.ok('removing an absent tag succeeds', (public.apply_title_organisation_delta_v1('anime', 1, null, array['absent'], null, null)) is not null);
select tests.raises('same key in add and remove', 'select public.apply_title_organisation_delta_v1(''anime'',1,array[''x''],array[''X''],null,null)', '%DELTA_INVALID%');
select tests.raises('invalid medium', 'select public.apply_title_organisation_delta_v1(''film'',1,array[''x''],null,null,null)', '%INVALID_MEDIUM%');
-- resulting-set limit on anime 2: 9 stored tags
select public.apply_title_organisation_delta_v1('anime', 2, (select array_agg('t' || n) from generate_series(1, 9) n), null, null, null);
select tests.raises('adding 2 to 9 passes the limit', 'select public.apply_title_organisation_delta_v1(''anime'',2,array[''a'',''b''],null,null,null)', '%TAG_LIMIT%');
select tests.eq('adding 2 and removing 1 gives exactly 10',
  jsonb_array_length((public.apply_title_organisation_delta_v1('anime', 2, array['a', 'b'], array['t1'], null, null)) -> 'tags'), 10);

-- Orphan removal on its own title
select public.apply_title_organisation_delta_v1('anime', 3, array['old'], null, null, null);
select tests.reset();
delete from public.anime_user_lists where user_id = tests.uid(1)::text and anime_id = 3;
select tests.as_user(tests.uid(1));
select tests.eq('orphan can still lose its tag',
  jsonb_array_length((public.apply_title_organisation_delta_v1('anime', 3, null, array['old'], null, null)) -> 'tags'), 0);
select tests.raises('re-tagging an untracked title', 'select public.apply_title_organisation_delta_v1(''anime'',3,array[''comfy''],null,null,null)', '%ENTRY_NOT_FOUND%');

-- Bounds on a fresh tracked title (anime 4)
select tests.raises('11 distinct tags', 'select public.apply_title_organisation_delta_v1(''anime'',4,(select array_agg(''k''||n) from generate_series(1,11) n),null,null,null)', '%TAG_LIMIT%');
select tests.raises('25 chars', 'select public.apply_title_organisation_delta_v1(''anime'',4,array[repeat(''a'',25)],null,null,null)', '%TAG_TOO_LONG%');
select tests.raises('blank tag', 'select public.apply_title_organisation_delta_v1(''anime'',4,array[''   ''],null,null,null)', '%TAG_EMPTY%');
select tests.eq('10 tags succeed',
  jsonb_array_length((public.apply_title_organisation_delta_v1('anime', 4, (select array_agg('k' || n) from generate_series(1, 10) n), null, null, null)) -> 'tags'), 10);
select tests.eq('24 emoji scalars succeed',
  jsonb_array_length((public.apply_title_organisation_delta_v1('anime', 5, array[repeat('😀', 24)], null, null, null)) -> 'tags'), 1);
select tests.raises('25 emoji scalars rejected', 'select public.apply_title_organisation_delta_v1(''anime'',6,array[repeat(''😀'',25)],null,null,null)', '%TAG_TOO_LONG%');

-- Normalisation
select tests.eq('Comfy/comfy/" comfy " store one tag, first spelling',
  (public.apply_title_organisation_delta_v1('anime', 7, array['Comfy', 'comfy', ' comfy '], null, null, null)) -> 'tags', '["Comfy"]'::jsonb);
select tests.eq('NFC and NFD dedupe to one NFC tag',
  (select jsonb_array_length(r -> 'tags') from (select public.apply_title_organisation_delta_v1('anime', 8, array[U&'cafe\0301', U&'caf\00E9'], null, null, null) r) s), 1);
select tests.ok('stored tag is NFC', (select bool_and(tag = normalize(tag, NFC)) from public.library_tags where media_id = 8));
select tests.eq('non-ASCII case folding works through ICU',
  jsonb_array_length((public.apply_title_organisation_delta_v1('anime', 9, array['Émotion', 'émotion'], null, null, null)) -> 'tags'), 1);

-- Grants and function config --------------------------------------------------------------------------------------
select tests.reset();
select tests.ok('anon cannot execute delta', not has_function_privilege('anon', 'public.apply_title_organisation_delta_v1(text,integer,text[],text[],uuid[],uuid[])', 'execute'));
select tests.ok('anon cannot execute index', not has_function_privilege('anon', 'public.library_tag_index_v1()', 'execute'));
select tests.ok('authenticated can execute both',
  has_function_privilege('authenticated', 'public.apply_title_organisation_delta_v1(text,integer,text[],text[],uuid[],uuid[])', 'execute')
  and has_function_privilege('authenticated', 'public.library_tag_index_v1()', 'execute'));
select tests.ok('no whole-set organisation RPC exists', to_regproc('public.set_title_organisation_v1') is null);
select tests.ok('search_path pinned, SECURITY DEFINER, plpgsql (both)',
  (select bool_and(proconfig @> array['search_path=public, extensions'] and prosecdef
                   and prolang = (select oid from pg_language where lanname = 'plpgsql'))
     from pg_proc where oid in ('public.apply_title_organisation_delta_v1(text,integer,text[],text[],uuid[],uuid[])'::regprocedure,
                                'public.library_tag_index_v1()'::regprocedure)));
select tests.ok('no client write grant on library_tags',
  not has_table_privilege('authenticated', 'public.library_tags', 'insert')
  and not has_table_privilege('authenticated', 'public.library_tags', 'update')
  and not has_table_privilege('authenticated', 'public.library_tags', 'delete')
  and not has_table_privilege('anon', 'public.library_tags', 'select'));

-- Plan at 2,000 titles --------------------------------------------------------------------------------------------
select pg_temp.load_library_2000(tests.uid(1));
set local session_replication_role = replica;
insert into public.library_tags (user_id, medium, media_id, tag)
  select tests.uid(1), 'anime', 9100000 + n, 'bulk' from generate_series(2, 1400, 2) n;
insert into public.library_tags (user_id, medium, media_id, tag)
  select tests.uid(1000 + u), 'anime', 9100000 + a, 'noise'
  from generate_series(1, 400) u, generate_series(2, 150, 2) a;
set local session_replication_role = origin;
analyze public.library_tags;
-- the query text mirrors the body of public.library_tag_index_v1()
select tests.ok('tag index read uses an index (pkey or user_tag_idx) at 2,000 titles',
  pg_temp.plan_uses_index(format('select medium, media_id, array_agg(tag order by tag_key) from public.library_tags where user_id=%L group by medium, media_id', tests.uid(1)), 'library_tags_pkey')
  or pg_temp.plan_uses_index(format('select medium, media_id, array_agg(tag order by tag_key) from public.library_tags where user_id=%L group by medium, media_id', tests.uid(1)), 'library_tags_user_tag_idx'));
alter table public.library_tags drop constraint library_tags_pkey;
drop index public.library_tags_user_tag_idx;
select tests.ok('control: without the index the plan check is false',
  not (pg_temp.plan_uses_index(format('select medium, media_id, array_agg(tag order by tag_key) from public.library_tags where user_id=%L group by medium, media_id', tests.uid(1)), 'library_tags_pkey')
        or pg_temp.plan_uses_index(format('select medium, media_id, array_agg(tag order by tag_key) from public.library_tags where user_id=%L group by medium, media_id', tests.uid(1)), 'library_tags_user_tag_idx')));

rollback;

-- Cascade (own transaction: the plan section dropped the key)
begin;
select tests.make_user(1);
set local session_replication_role = replica;
insert into public.anime (id, title_romaji) values (1, 'T1') on conflict (id) do nothing;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(1)::text, 1, 'PLANNING', 0);
set local session_replication_role = origin;
select tests.as_user(tests.uid(1));
select public.apply_title_organisation_delta_v1('anime', 1, array['comfy'], null, null, null);
select tests.reset();
delete from auth.users where id = tests.uid(1);
select tests.eq('tags cascade', (select count(*) from public.library_tags where user_id = tests.uid(1)), 0::bigint);
rollback;
