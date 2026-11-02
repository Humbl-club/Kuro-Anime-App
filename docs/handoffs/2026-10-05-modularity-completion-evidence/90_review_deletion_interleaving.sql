\set ON_ERROR_STOP on
begin;
select tests.make_user(90),tests.make_user(91);
insert into public.anime(id) values(424290),(424291);
-- Request 1: service-role cleanup completes; request 2 can still insert before Auth deletion.
delete from public.anime_user_lists where user_id=tests.uid(90)::text;
select tests.as_user(tests.uid(90));
insert into public.anime_user_lists(user_id,anime_id,list_type) values(tests.uid(90)::text,424290,'WATCHING');
select tests.reset();
delete from auth.users where id=tests.uid(90);
select tests.eq('REPRO: concurrent post-cleanup insert survives auth deletion',
 (select count(*) from public.anime_user_lists where user_id=tests.uid(90)::text),1::bigint);
-- A normal insert after deletion is blocked indirectly by the taste-event FK.
-- A notes-only change does not emit a taste signal, so check the surviving row separately.
select tests.as_user(tests.uid(90));
update public.anime_user_lists set notes='post-deletion note' where user_id=tests.uid(90)::text;
select tests.reset();
select tests.eq('REPRO: surviving TEXT row accepts notes-only update under deleted-user claims',
 (select notes from public.anime_user_lists where user_id=tests.uid(90)::text),'post-deletion note');
-- An orphan is found empty, then a different user joins before the service-role DELETE.
select tests.as_user(tests.uid(91));
select (public.create_club('Review orphan',null,'status'))->>'club_id' as club \gset
select tests.reset();
delete from auth.users where id=tests.uid(91);
select tests.eq('orphan sweep observes zero members',(select count(*) from public.club_members where club_id=:'club'),0::bigint);
select tests.make_user(92);
select invite_code as invite from public.clubs where id=:'club' \gset
select tests.as_user(tests.uid(92));
select public.join_club(:'invite');
select tests.reset();
select tests.eq('different user joined between count and delete',(select count(*) from public.club_members where club_id=:'club'),1::bigint);
delete from public.clubs where id=:'club';
select tests.eq('REPRO: stale orphan decision deletes other user membership',(select count(*) from public.club_members where user_id=tests.uid(92)),0::bigint);
rollback;
