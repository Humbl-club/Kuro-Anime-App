-- 122_catalogue_link_target_race.sql -- the link existence trigger versus a concurrent delete of the
-- target row, with TWO real database sessions (prepared 20261112100000_catalogue_sources_v1.sql).
--
-- catalogue_id_links.kuro_id has no foreign key; a BEFORE INSERT trigger checks the target exists and
-- AFTER DELETE triggers remove the links of a deleted row. Without a row lock the check can pass, the
-- row can then be deleted and cleaned, and the link commit afterwards: an orphan link. The check takes
-- FOR KEY SHARE on the target row, so the delete WAITS for the inserting transaction and its cleanup
-- then removes the freshly committed link.
-- Actors: both run as service_role (the importers' role).
-- @requires extension dblink
-- @requires table public.anime
\set ON_ERROR_STOP on
\o /dev/null

insert into public.anime (id, anilist_id, title_romaji) values (1220001, 1220001, 'Race target');

select tests.actor_open('writer', :'conn') as writer_pid \gset
select tests.actor_open('deleter', :'conn') as deleter_pid \gset
select tests.actor_exec('writer', 'set role service_role');
select tests.actor_exec('deleter', 'set role service_role');

select tests.actor_exec('writer', 'begin');
select tests.actor_exec('writer', $$insert into public.catalogue_id_links (kind, kuro_id, source, source_key, method, status) values ('anime', 1220001, 'ann', '1220001', 'title_match', 'proposed') returning 1$$);
select tests.actor_exec('deleter', 'begin');
select tests.actor_send('deleter', 'delete from public.anime where id = 1220001 returning 1');
select tests.ok('the delete WAITS for the in-flight link insert (row lock held by the existence check)',
  tests.wait_lock_wait(:deleter_pid) in ('transactionid', 'tuple'));
select tests.eq('the writer commits', tests.actor_exec('writer', 'commit'), 'COMMIT');
select tests.actor_result('deleter');
select tests.eq('the deleter commits', tests.actor_exec('deleter', 'commit'), 'COMMIT');
select tests.eq('the anime is gone', (select count(*) from public.anime where id = 1220001), 0::bigint);
select tests.eq('no orphan link survives: the cleanup removed the link the writer committed',
  (select count(*) from public.catalogue_id_links where kind = 'anime' and kuro_id = 1220001), 0::bigint);

select tests.actor_close('writer');
select tests.actor_close('deleter');
