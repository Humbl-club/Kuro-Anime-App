-- W9: account deletion removes tags, custom lists and list items (FK cascade), and leaves other accounts alone.
-- Disposable local fixture only, never hosted.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;

select tests.make_user(1);
select tests.make_user(2);
set local session_replication_role = replica;
insert into public.anime (id, title_romaji) values (1, 'T1') on conflict (id) do nothing;
insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  values (tests.uid(1)::text, 1, 'PLANNING', 0), (tests.uid(2)::text, 1, 'PLANNING', 0);
set local session_replication_role = origin;

select tests.as_user(tests.uid(1));
select (public.create_custom_list_v1('Mine')) ->> 'id' as la \gset
select public.apply_title_organisation_delta_v1('anime', 1, array['comfy'], null, array[:'la'::uuid], null);
select tests.as_user(tests.uid(2));
select (public.create_custom_list_v1('Theirs')) ->> 'id' as lb \gset
select public.apply_title_organisation_delta_v1('anime', 1, array['keep'], null, array[:'lb'::uuid], null);

select tests.reset();
select tests.eq('A holds a tag, a list and an item before deletion',
  (select count(*) from public.library_tags where user_id = tests.uid(1))
  + (select count(*) from public.custom_lists where user_id = tests.uid(1))
  + (select count(*) from public.custom_list_items where user_id = tests.uid(1)), 3::bigint);
delete from auth.users where id = tests.uid(1);
select tests.eq('A tags gone', (select count(*) from public.library_tags where user_id = tests.uid(1)), 0::bigint);
select tests.eq('A lists gone', (select count(*) from public.custom_lists where user_id = tests.uid(1)), 0::bigint);
select tests.eq('A list items gone', (select count(*) from public.custom_list_items where user_id = tests.uid(1)), 0::bigint);
select tests.eq('B rows intact',
  (select count(*) from public.library_tags where user_id = tests.uid(2))
  + (select count(*) from public.custom_lists where user_id = tests.uid(2))
  + (select count(*) from public.custom_list_items where user_id = tests.uid(2)), 3::bigint);
rollback;
