-- 66_club_realtime_signals.sql  --  F42 server side: scoped revocation / invalidation signals
--
-- Contract under test (prepared, NOT deployed):
--   20261005160000_club_realtime_signals.sql
--   * club_activity_signals (club_id, revision, changed_at): one row per club, bumped by
--     every rail / item / poll / vote / reaction / membership / club change. No user
--     identifiers. SELECT only for current members (is_club_member). Realtime filter:
--     club_id=eq.<club>. It replaces the unfiltered raw-table streams, which after F34
--     only carry the subscriber's OWN rows.
--   * club_membership_signals (user_id, club_id, state, revision, changed_at): one row per
--     (user, club); state member | left | removed | club_deleted. SELECT only for that
--     user. Realtime filter: user_id=eq.<me>. This is the revocation event a removed
--     member receives (club_members itself stays OUT of the publication).
--   * both tables are in supabase_realtime; nobody writes them through the table API.
-- Actual Realtime delivery needs a running Realtime server: BLOCKED below with recovery.
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires table public.club_rails
-- @requires table public.club_rail_items
-- @requires table public.club_rail_item_reactions
-- @requires table public.club_polls
-- @requires table public.club_poll_options
-- @requires table public.club_votes
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.leave_club(uuid)
-- @requires function public.create_club_rail(uuid,text,text)
-- @requires function public.add_club_rail_item(uuid,text,integer,text)
-- @requires function public.create_club_poll(uuid,text,text[],timestamptz)
-- @requires function public.cast_club_vote(uuid,uuid)
-- @requires function public.toggle_club_reaction(uuid,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4);
insert into public.anime (id) values (666666);

-- revision as the superuser (the subject of the bump assertions)
create temp table _rev (club uuid primary key, r bigint) on commit drop;
grant all on _rev to authenticated, service_role;

select tests.as_user(tests.uid(1));
select (public.create_club('Signal club', null, 'status')) ->> 'club_id' as k \gset
select invite_code as k_code from public.clubs where id = :'k' \gset
select tests.reset();
select tests.ok('club creation creates its activity signal row', exists (select 1 from public.club_activity_signals where club_id = :'k'));
select tests.eq('creator''s membership signal is member',
  (select state from public.club_membership_signals where user_id = tests.uid(1) and club_id = :'k'), 'member');

-- helper: did the revision move since the last snapshot?
create or replace function pg_temp.bumped(c uuid) returns boolean language plpgsql as $$
declare cur bigint; prev bigint;
begin
  select revision into cur from public.club_activity_signals where club_id = c;
  select r into prev from _rev where club = c;
  insert into _rev values (c, cur) on conflict (club) do update set r = excluded.r;
  return prev is null or cur > prev;
end $$;
select pg_temp.bumped(:'k');

select tests.as_user(tests.uid(2)); select public.join_club(:'k_code');
select tests.reset(); select tests.ok('join bumps the club revision', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(1));
select (public.create_club_rail(:'k', 'K rail', null)) ->> 'rail_id' as k_rail \gset
select tests.reset(); select tests.ok('rail creation bumps', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(1));
select (public.add_club_rail_item(:'k_rail', 'ANIME', 666666, null)) ->> 'item_id' as k_item \gset
select tests.reset(); select tests.ok('rail item add bumps', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(2));
select (public.create_club_poll(:'k', 'Q?', array['A','B'], null)) ->> 'poll_id' as k_poll \gset
select id as k_opt from public.club_poll_options where poll_id = :'k_poll' order by sort_order limit 1 \gset
select tests.reset(); select tests.ok('poll creation bumps', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(2)); select public.cast_club_vote(:'k_poll', :'k_opt');
select tests.reset(); select tests.ok('a vote bumps (other members learn "something changed", never who voted)', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(2)); select public.toggle_club_reaction(:'k_item', 'fire');
select tests.reset(); select tests.ok('a reaction bumps', pg_temp.bumped(:'k'));
select tests.as_user(tests.uid(1));
select tests.affected(format($q$update public.clubs set description = 'changed' where id = %L$q$, :'k'));
select tests.reset(); select tests.ok('a club settings change bumps', pg_temp.bumped(:'k'));

-- ---- who can read what ----------------------------------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('member reads the club activity signal', (select count(*) from public.club_activity_signals where club_id = :'k'), 1::bigint);
select tests.eq('member reads ONLY their own membership signal rows',
  (select count(*) from public.club_membership_signals where user_id <> auth.uid()), 0::bigint);
select tests.denied('nobody writes activity signals through the table API',
  format($q$update public.club_activity_signals set revision = 0 where club_id = %L$q$, :'k'));
select tests.denied('nobody writes membership signals through the table API',
  format($q$insert into public.club_membership_signals (user_id, club_id, state) values (auth.uid(), %L, 'member')$q$, :'k'));
select tests.as_user(tests.uid(3));
select tests.eq('outsider reads no activity signal', (select count(*) from public.club_activity_signals where club_id = :'k'), 0::bigint);
select tests.as_anon();
select tests.denied('anon has no SELECT on club_activity_signals', $q$select count(*) from public.club_activity_signals$q$);
select tests.denied('anon has no SELECT on club_membership_signals', $q$select count(*) from public.club_membership_signals$q$);

-- ---- revocation: removal, leave, club deletion -----------------------------------
select tests.as_user(tests.uid(3)); select public.join_club(:'k_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'k_code');
select tests.as_user(tests.uid(1));
select public.remove_club_member(:'k', tests.uid(3));
select tests.as_user(tests.uid(3));
select tests.eq('F42: the removed member receives a revocation signal (state removed)',
  (select state from public.club_membership_signals where club_id = :'k'), 'removed');
select tests.eq('F42: ...and immediately loses the club activity signal (RLS)', (select count(*) from public.club_activity_signals where club_id = :'k'), 0::bigint);
select tests.as_user(tests.uid(4));
select tests.eq('leave_club', (public.leave_club(:'k')) ->> 'success', 'true');
select tests.eq('F42: a leaver''s signal is state left', (select state from public.club_membership_signals where club_id = :'k'), 'left');
select tests.as_user(tests.uid(2));
select tests.eq('another member cannot see who was removed or left',
  (select count(*) from public.club_membership_signals where club_id = :'k'), 1::bigint);
select tests.as_user(tests.uid(1));
select tests.affected(format($q$delete from public.clubs where id = %L$q$, :'k'));
select tests.as_user(tests.uid(2));
select tests.eq('F42: club deletion signals every former member (state club_deleted)',
  (select state from public.club_membership_signals where club_id = :'k'), 'club_deleted');
select tests.reset();
select tests.eq('the deleted club''s activity row is gone with it', (select count(*) from public.club_activity_signals where club_id = :'k'), 0::bigint);

-- ---- account deletion: signal rows go with the auth user, deletion is not blocked ----
select tests.as_user(tests.uid(4));
select (public.create_club('Gone with the user', null, 'status')) ->> 'club_id' as g \gset
select tests.reset();
delete from auth.users where id = tests.uid(4);
select tests.eq('membership signal rows of a deleted user are removed by the cascade',
  (select count(*) from public.club_membership_signals where user_id = tests.uid(4)), 0::bigint);

-- ---- publication + payload shape ----------------------------------------------------
select tests.eq('both signal tables are in supabase_realtime',
  (select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
     and schemaname = 'public' and tablename in ('club_activity_signals', 'club_membership_signals')), 2::bigint);
select tests.ok('club_members itself stays OUT of the publication (no global DELETE broadcast of membership row ids)',
  not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'club_members'));
select tests.eq('activity signal payload carries no user identifier',
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
    where table_schema = 'public' and table_name = 'club_activity_signals'), 'club_id,revision,changed_at');
select tests.ok('both signal tables have RLS enabled',
  (select bool_and(relrowsecurity) from pg_class where oid in ('public.club_activity_signals'::regclass, 'public.club_membership_signals'::regclass)));

select tests.requires_live('Realtime delivery of club_activity_signals / club_membership_signals to subscribers',
  'no Realtime server in this fixture (publication membership + per-subscriber RLS are proven here); recovery: local Supabase stack (supabase start, needs Docker) or an approved non-production project, subscribe as two users and run the removal/leave/club-delete steps above');

select tests.reset();
rollback;
