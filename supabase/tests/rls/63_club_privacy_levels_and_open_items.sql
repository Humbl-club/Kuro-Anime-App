-- 63_club_privacy_levels_and_open_items.sql
--
-- (a) Legitimate club flows through the RPCs (polls / votes / reactions) and what
--     fetch_club_bundle returns per privacy level, as far as this fixture can show.
-- (b) R4 RESOLVED (policy P2-R1, prepared 20261005150000): raw per-user rows are
--     own-row only, and the bundles are authorized SECURITY DEFINER aggregates. The
--     former savepoint probes are replaced by assertions of the implemented state:
--     counts intact, private gating intact, raw rows hidden, status/progress members'
--     statuses visible per their effective level (finding 3 resolved deliberately).
-- (c) R5 RESOLVED: voluntary leave keeps the rejoin-with-a-valid-invite behavior (the
--     leave dialog copy must say so; Swift, lane L1) and the departed member's vote is
--     excluded from current counts. Owner/admin removal is covered in 65_...sql.
-- Default fixture (pending migrations included) -> PASS; --exclude-pending -> FAILS at
-- the first R4 assertion (deployed-chain behavior).
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
-- @requires function public.fetch_club_bundle(uuid)
-- @requires function public.create_club_rail(uuid,text,text)
-- @requires function public.add_club_rail_item(uuid,text,integer,text)
-- @requires function public.create_club_poll(uuid,text,text[],timestamptz)
-- @requires function public.cast_club_vote(uuid,uuid)
-- @requires function public.toggle_club_reaction(uuid,text)
-- @requires table public.anime_user_lists
-- @requires function public.fetch_club_bundle_loading(uuid)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4), tests.make_user(5);
insert into public.anime (id) values (737373);

-- ---- private club P: owner 1, members 2,3,4 (all via RPC) -----------------------
select tests.as_user(tests.uid(1));
select (public.create_club('Private P', null, 'private')) ->> 'club_id' as p_club \gset
select invite_code as p_code from public.clubs where id = :'p_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'p_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'p_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'p_code');

select tests.as_user(tests.uid(1));
select (public.create_club_rail(:'p_club', 'P rail', null)) ->> 'rail_id' as p_rail \gset
select (public.add_club_rail_item(:'p_rail', 'ANIME', 737373, null)) ->> 'item_id' as p_item \gset
select tests.as_user(tests.uid(2));
select (public.create_club_poll(:'p_club', 'Next?', array['A','B'], null)) ->> 'poll_id' as p_poll \gset
select id as p_opt_a from public.club_poll_options where poll_id = :'p_poll' and label = 'A' \gset
select id as p_opt_b from public.club_poll_options where poll_id = :'p_poll' and label = 'B' \gset
select tests.eq('legit: any member creates a poll via create_club_poll', (select count(*) from public.club_poll_options where poll_id = :'p_poll'), 2::bigint);

select tests.as_user(tests.uid(1)); select public.cast_club_vote(:'p_poll', :'p_opt_a'); select public.toggle_club_reaction(:'p_item', 'fire');
select tests.as_user(tests.uid(3)); select public.cast_club_vote(:'p_poll', :'p_opt_b'); select public.toggle_club_reaction(:'p_item', 'heart');
select tests.as_user(tests.uid(2));
select tests.eq('legit: member votes via cast_club_vote', (public.cast_club_vote(:'p_poll', :'p_opt_b')) ->> 'success', 'true');
select tests.eq('legit: member re-votes (single choice, replaces own vote)', (public.cast_club_vote(:'p_poll', :'p_opt_a')) ->> 'success', 'true');
select tests.eq('legit: member reacts via toggle_club_reaction', (public.toggle_club_reaction(:'p_item', 'fire')) ->> 'action', 'added');
select tests.eq('legit: toggling the same emoji again removes it', (public.toggle_club_reaction(:'p_item', 'fire')) ->> 'action', 'removed');
select public.toggle_club_reaction(:'p_item', 'fire');

-- what the bundle promises for 'private' (member 2's view)
select public.fetch_club_bundle(:'p_club')::text as p_bundle \gset
select tests.eq('private bundle: members list contains ONLY the caller', jsonb_array_length((:'p_bundle')::jsonb -> 'members'), 1);
select tests.eq('private bundle: ...and it is the caller', (:'p_bundle')::jsonb #>> '{members,0,user_id}', tests.uid(2)::text);
select tests.eq('private bundle: member_count is the full count (aggregate)', ((:'p_bundle')::jsonb ->> 'member_count')::int, 4);
select tests.eq('private bundle: poll vote counts aggregate all 3 voters',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((:'p_bundle')::jsonb #> '{polls,0,options}') o)::int, 3);
select tests.eq('private bundle: my_vote_option_id is the caller''s (re-)vote', (:'p_bundle')::jsonb #>> '{polls,0,my_vote_option_id}', :'p_opt_a');
select tests.eq('private bundle: reactions are anonymous aggregate counts', (:'p_bundle')::jsonb #> '{rails,0,items,0,reactions}', '{"fire": 2, "heart": 1}'::jsonb);
select tests.eq('private bundle: my_reactions lists only the caller''s', (:'p_bundle')::jsonb #> '{rails,0,items,0,my_reactions}', '["fire"]'::jsonb);
select tests.ok('private bundle: plain member does not get the invite code', (:'p_bundle')::jsonb #>> '{club,invite_code}' is null);

-- R4 RESOLVED: the table API returns only the caller's own per-user rows
select tests.eq('R4: in the PRIVATE club a member reads only their own vote row directly',
  (select count(*) from public.club_votes where poll_id = :'p_poll'), 1::bigint);
select tests.eq('R4: ...only their own reaction row',
  (select count(*) from public.club_rail_item_reactions where rail_item_id = :'p_item'), 1::bigint);
select tests.eq('R4: ...and only their own membership row (the bundle shows only the caller as well)',
  (select count(*) from public.club_members where club_id = :'p_club'), 1::bigint);

-- ---- progress club G (4 members; 3 track the item) and small club T (2 members) ----
select tests.as_user(tests.uid(1));
select (public.create_club('Progress G', null, 'progress')) ->> 'club_id' as g_club \gset
select invite_code as g_code from public.clubs where id = :'g_club' \gset
select (public.create_club_rail(:'g_club', 'G rail', null)) ->> 'rail_id' as g_rail \gset
select (public.add_club_rail_item(:'g_rail', 'ANIME', 737373, null)) ->> 'item_id' as g_item \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'g_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'g_code');
select tests.as_user(tests.uid(5)); select public.join_club(:'g_code');
select tests.reset();
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values
  (tests.uid(1)::text, 737373, 'WATCHING', 3), (tests.uid(2)::text, 737373, 'COMPLETED', 12), (tests.uid(3)::text, 737373, 'WATCHING', 7);

select tests.as_user(tests.uid(2));
select tests.eq('progress bundle (4 members): members list contains all 4', jsonb_array_length((public.fetch_club_bundle(:'g_club')) -> 'members'), 4);
select tests.eq('R4/finding 3: progress club member_statuses expose the 3 tracking members (deliberate, per sharing level)',
  jsonb_array_length((public.fetch_club_bundle(:'g_club')) #> '{rails,0,items,0,member_statuses}'), 3);

select tests.as_user(tests.uid(4));
select (public.create_club('Small T', null, 'progress')) ->> 'club_id' as t_club \gset
select invite_code as t_code from public.clubs where id = :'t_club' \gset
select tests.as_user(tests.uid(5)); select public.join_club(:'t_code');
select tests.eq('small club (<3 members): bundle members list contains only the caller even at progress level',
  jsonb_array_length((public.fetch_club_bundle(:'t_club')) -> 'members'), 1);

-- ==========================================================================
-- R4 implemented state (replaces the two rolled-back decision probes)
-- ==========================================================================
select tests.as_user(tests.uid(2));
select tests.eq('R4: fetch_club_bundle_loading member_count is the full count (4)',
  ((public.fetch_club_bundle_loading(:'p_club')) ->> 'member_count')::int, 4);
select tests.reset();
select tests.ok('R4: fetch_club_bundle is SECURITY DEFINER (authorized aggregate)',
  (select prosecdef from pg_proc where oid = 'public.fetch_club_bundle(uuid)'::regprocedure));
select tests.eq('R4: the member-wide SELECT policies are gone',
  (select count(*) from pg_policies where schemaname = 'public'
     and policyname in ('club_votes_select_member', 'club_reactions_select_member', 'club_members_select_member')), 0::bigint);

-- ==========================================================================
-- R5: voluntary leave + rejoin with the SAME valid code; departed vote excluded
-- ==========================================================================
select tests.as_user(tests.uid(3));
select tests.eq('R5: member 3 leaves via leave_club', (public.leave_club(:'p_club')) ->> 'success', 'true');
select tests.as_user(tests.uid(2));
select tests.eq('R5: the departed member''s vote is excluded from the bundle counts (3 -> 2)',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((public.fetch_club_bundle(:'p_club')) #> '{polls,0,options}') o)::int, 2);
select tests.as_user(tests.uid(3));
select tests.eq('R5: a voluntary leaver re-joins with the still-valid club invite code (leave dialog copy must say so)',
  (public.join_club(:'p_code')) ->> 'club_id', :'p_club');
select tests.as_user(tests.uid(2));
select tests.eq('R5: after rejoining, their earlier vote counts again (it was kept, not deleted)',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((public.fetch_club_bundle(:'p_club')) #> '{polls,0,options}') o)::int, 3);

select tests.reset();
rollback;
