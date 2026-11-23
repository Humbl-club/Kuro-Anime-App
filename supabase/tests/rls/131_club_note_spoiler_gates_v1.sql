-- 131_club_note_spoiler_gates_v1.sql
-- Prepared 20261121120000_club_note_spoiler_gates_v1.sql (NOT deployed):
-- Covers: club_rail_items spoiler metadata columns & constraints,
-- set_club_rail_item_spoiler_v1(uuid, boolean, integer) authorization/grants,
-- fetch_club_bundle(uuid) projection of is_spoiler and spoiler_through_unit,
-- and title_story_tags_v1(text, integer) safe/spoiler separation & safety filters.
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires table public.club_rails
-- @requires table public.club_rail_items
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.tags
-- @requires table public.anime_tags
-- @requires table public.manga_tags
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.create_club_rail(uuid,text,text)
-- @requires function public.add_club_rail_item(uuid,text,integer,text)
-- @requires function public.fetch_club_bundle(uuid)
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

select tests.ok('club_rail_items carries is_spoiler and spoiler_through_unit',
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'club_rail_items' and column_name = 'is_spoiler' and is_nullable = 'NO')
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'club_rail_items' and column_name = 'spoiler_through_unit'));

select tests.ok('set_club_rail_item_spoiler_v1 is SECURITY DEFINER with search_path = public, extensions and locked grants',
  to_regprocedure('public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)') is not null
  and (select prosecdef and proconfig @> array['search_path=public, extensions']
         from pg_proc where oid = 'public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)'::regprocedure)
  and not has_function_privilege('anon', 'public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)', 'execute')
  and has_function_privilege('service_role', 'public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)', 'execute')
  and not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
    where p.oid = 'public.set_club_rail_item_spoiler_v1(uuid,boolean,integer)'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ));

select tests.make_user(1311), tests.make_user(1312), tests.make_user(1313), tests.make_user(1314);
insert into public.anime (id) values (131001) on conflict do nothing;

select tests.as_user(tests.uid(1311));
select (public.create_club('Spoiler Gate Club', null, 'status')) ->> 'club_id' as sg_club \gset
select invite_code as sg_code from public.clubs where id = :'sg_club' \gset
select (public.create_club_rail(:'sg_club', 'Spoilers', null)) ->> 'rail_id' as sg_rail \gset

select tests.as_user(tests.uid(1312));
select public.join_club(:'sg_code');
select (public.add_club_rail_item(:'sg_rail', 'ANIME', 131001, '[ep:12] Big reveal')) ->> 'item_id' as sg_item \gset

select tests.as_user(tests.uid(1313));
select public.join_club(:'sg_code');

select tests.as_anon();
select tests.denied('anon cannot call set_club_rail_item_spoiler_v1',
  format($q$select public.set_club_rail_item_spoiler_v1(%L, true, 12)$q$, :'sg_item'));

select tests.as_user(tests.uid(1314));
select tests.raises('outsider cannot set spoiler metadata',
  format($q$select public.set_club_rail_item_spoiler_v1(%L, true, 12)$q$, :'sg_item'), '%FORBIDDEN%');

select tests.as_user(tests.uid(1313));
select tests.raises('other member cannot set spoiler metadata on someone else item',
  format($q$select public.set_club_rail_item_spoiler_v1(%L, true, 12)$q$, :'sg_item'), '%FORBIDDEN%');

select tests.as_user(tests.uid(1312));
select tests.raises('negative spoiler unit raises INVALID_SPOILER_UNIT',
  format($q$select public.set_club_rail_item_spoiler_v1(%L, true, -1)$q$, :'sg_item'), '%INVALID_SPOILER_UNIT%');

select tests.eq('author sets is_spoiler = true and spoiler_through_unit = 12',
  public.set_club_rail_item_spoiler_v1(:'sg_item', true, 12) ->> 'ok', 'true');

select tests.as_user(tests.uid(1311));
select tests.eq('owner overrides spoiler metadata',
  public.set_club_rail_item_spoiler_v1(:'sg_item', true, 24) ->> 'spoiler_through_unit', '24');

select tests.eq('fetch_club_bundle exposes is_spoiler',
  (public.fetch_club_bundle(:'sg_club')) #>> '{rails,0,items,0,is_spoiler}', 'true');
select tests.eq('fetch_club_bundle exposes spoiler_through_unit',
  (public.fetch_club_bundle(:'sg_club')) #>> '{rails,0,items,0,spoiler_through_unit}', '24');

select tests.reset();
select tests.raises('direct negative spoiler_through_unit violates check constraint',
  format($q$update public.club_rail_items set spoiler_through_unit = -5 where id = %L$q$, :'sg_item'),
  '%club_rail_items_spoiler_unit_nonneg_check%');

select tests.ok('anime_tags and manga_tags carry is_spoiler column',
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'anime_tags' and column_name = 'is_spoiler' and is_nullable = 'NO')
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'manga_tags' and column_name = 'is_spoiler' and is_nullable = 'NO'));

select tests.ok('title_story_tags_v1 is SECURITY DEFINER with search_path = public, extensions and explicit grants without PUBLIC or anon',
  to_regprocedure('public.title_story_tags_v1(text,integer)') is not null
  and (select prosecdef and proconfig @> array['search_path=public, extensions']
         from pg_proc where oid = 'public.title_story_tags_v1(text,integer)'::regprocedure)
  and not has_function_privilege('anon', 'public.title_story_tags_v1(text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.title_story_tags_v1(text,integer)', 'execute')
  and has_function_privilege('service_role', 'public.title_story_tags_v1(text,integer)', 'execute')
  and not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
    where p.oid = 'public.title_story_tags_v1(text,integer)'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ));

set local session_replication_role = replica;
insert into public.anime (id, title_romaji, is_adult, safety_blocked)
values (131101, 'Story Tag Visible Anime', false, false),
       (131102, 'Story Tag Adult Anime', true, false),
       (131103, 'Story Tag Blocked Anime', false, true)
on conflict (id) do nothing;

insert into public.manga (id, title_romaji, is_adult, safety_blocked)
values (131201, 'Story Tag Visible Manga', false, false)
on conflict (id) do nothing;

insert into public.tags (id, name, category, is_general_spoiler, is_media_spoiler, is_adult)
values (131301, 'Test Safe Theme 131', 'Theme', false, false, false),
       (131302, 'Test Edge Spoiler Theme 131', 'Theme', false, false, false),
       (131303, 'Test General Spoiler 131', 'Plot', true, false, false),
       (131304, 'Test Media Spoiler 131', 'Plot', false, true, false),
       (131305, 'Test Adult Tag 131', 'Cast', false, false, true)
on conflict (id) do nothing;

insert into public.anime_tags (anime_id, tag_id, rank, is_spoiler)
values (131101, 131301, 80, false),
       (131101, 131302, 85, true),
       (131101, 131303, 90, false),
       (131101, 131304, 70, false),
       (131101, 131305, 95, false),
       (131102, 131301, 80, false),
       (131103, 131301, 80, false);

insert into public.manga_tags (manga_id, tag_id, rank, is_spoiler)
values (131201, 131301, 88, false),
       (131201, 131302, 75, true);
set local session_replication_role = origin;

select tests.eq('title_story_tags_v1 separates safe vs spoiler anime tags and filters adult tags',
  (select coalesce(array_agg(name || ':' || is_spoiler::text order by is_spoiler asc, rank desc, name asc), '{}'::text[])
     from public.title_story_tags_v1('anime', 131101)),
  array[
    'Test Safe Theme 131:false',
    'Test General Spoiler 131:true',
    'Test Edge Spoiler Theme 131:true',
    'Test Media Spoiler 131:true'
  ]);

select tests.eq('title_story_tags_v1 hides adult anime titles',
  (select count(*) from public.title_story_tags_v1('ANIME', 131102)), 0::bigint);

select tests.eq('title_story_tags_v1 hides safety-blocked anime titles',
  (select count(*) from public.title_story_tags_v1('ANIME', 131103)), 0::bigint);

select tests.eq('title_story_tags_v1 returns manga safe and spoiler tags',
  (select coalesce(array_agg(name || ':' || is_spoiler::text order by is_spoiler asc, rank desc, name asc), '{}'::text[])
     from public.title_story_tags_v1('MANGA', 131201)),
  array[
    'Test Safe Theme 131:false',
    'Test Edge Spoiler Theme 131:true'
  ]);

rollback;
