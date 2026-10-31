-- 20_clubs.sql  --  (b) club tables for owner / member / outsider / REVOKED member
--
-- Everything user-visible runs as role `authenticated` through the real RPCs and
-- direct table access (the PostgREST surface).  Membership is created ONLY via the
-- public RPCs (create_club / join_club); revocation is done both ways the product
-- allows: an owner removing a member row (club_members_delete_self_or_admin) and a
-- member calling leave_club.
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
-- @requires table public.club_messages
-- @requires table public.anime_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4), tests.make_user(5), tests.make_user(6);
insert into public.anime (id) values (424242);
insert into public.manga (id) values (424242);

-- ---- build the club through the real RPCs -----------------------------------
select tests.as_user(tests.uid(1));
select (public.create_club('Club A', 'desc', 'progress')) ->> 'club_id' as a_club \gset
select invite_code as a_code from public.clubs where id = :'a_club' \gset

select tests.as_user(tests.uid(2)); select public.join_club(:'a_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'a_code');
select tests.as_user(tests.uid(5)); select public.join_club(:'a_code');

select tests.as_user(tests.uid(1));
select (public.create_club_rail(:'a_club', 'Rail One', null)) ->> 'rail_id' as a_rail \gset
select (public.add_club_rail_item(:'a_rail', 'ANIME', 424242, 'note'))  ->> 'item_id' as a_item \gset
select (public.create_club_poll(:'a_club', 'Which?', array['opt1','opt2'], null)) ->> 'poll_id' as a_poll \gset
select id as a_opt1 from public.club_poll_options where poll_id = :'a_poll' order by sort_order limit 1 \gset
select public.cast_club_vote(:'a_poll', :'a_opt1');                 -- owner's vote
select public.toggle_club_reaction(:'a_item', 'fire');              -- owner's reaction

-- a user-4 (to-be-revoked) footprint created while still a member
select tests.as_user(tests.uid(4));
select public.toggle_club_reaction(:'a_item', 'heart');
select id as a_opt2 from public.club_poll_options where poll_id = :'a_poll' order by sort_order desc limit 1 \gset
select public.cast_club_vote(:'a_poll', :'a_opt2');
select tests.eq('revoked-to-be member can read the club before revocation', (select count(*) from public.clubs where id = :'a_club'), 1::bigint);
select tests.eq('revoked-to-be member sees club rails before revocation', (select count(*) from public.club_rails where club_id = :'a_club'), 1::bigint);

-- ---- cross-member list visibility inside the bundle (4 members, 'progress' club) ----
-- F36 (prepared 20261005150000): fetch_club_bundle is an authorized SECURITY DEFINER
-- aggregate, so the other members' statuses reach the bundle (per sharing level) while
-- their raw list rows stay owner-only.
select tests.reset();
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(1)::text, 424242, 'WATCHING', 5);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(2)::text, 424242, 'COMPLETED', 12);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(4)::text, 424242, 'DROPPED', 1);
select tests.as_user(tests.uid(2));
select tests.eq('bundle (4 members): caller sees own status for the item',
  (public.fetch_club_bundle(:'a_club')) #>> '{rails,0,items,0,my_status}', 'COMPLETED');
select tests.eq('F36: bundle (4 members, progress club) member_statuses lists all 3 tracking members',
  jsonb_array_length((public.fetch_club_bundle(:'a_club')) #> '{rails,0,items,0,member_statuses}'), 3);
select tests.eq('F36: member_status_counts aggregate across members',
  (public.fetch_club_bundle(:'a_club')) #> '{rails,0,items,0,member_status_counts}', '{"WATCHING": 1, "COMPLETED": 1, "DROPPED": 1}'::jsonb);
select tests.eq('...while the raw list rows of the others stay invisible to the caller',
  (select count(*) from public.anime_user_lists where anime_id = 424242), 1::bigint);

-- ---- owner (user 1) ---------------------------------------------------------
select tests.as_user(tests.uid(1));
select tests.eq('owner reads the club', (select count(*) from public.clubs where id = :'a_club'), 1::bigint);
select tests.eq('F34: owner reads only their own membership row through the table API', (select count(*) from public.club_members where club_id = :'a_club'), 1::bigint);
select tests.eq('...and the full member list through the authorized bundle', jsonb_array_length((public.fetch_club_bundle(:'a_club')) -> 'members'), 4);
select tests.eq('owner reads rail / item / poll / options',
  (select count(*) from public.club_rails where club_id=:'a_club')
  + (select count(*) from public.club_rail_items where rail_id=:'a_rail')
  + (select count(*) from public.club_polls where club_id=:'a_club')
  + (select count(*) from public.club_poll_options where poll_id=:'a_poll'), 5::bigint);
select tests.eq('owner updates own club', tests.affected(format($q$update public.clubs set description='owner-edit' where id=%L$q$, :'a_club')), 1::bigint);
select tests.eq('owner locks a rail (admin update)', tests.affected(format($q$update public.club_rails set is_locked=false where id=%L$q$, :'a_rail')), 1::bigint);
select tests.denied('direct INSERT into club_members is not allowed for anyone (membership only via RPC)',
  format($q$insert into public.club_members (club_id, user_id, role) values (%L, %L, 'member')$q$, :'a_club', tests.uid(3)));
select tests.denied('owner cannot forge a rail attributed to another user',
  format($q$insert into public.club_rails (club_id, title, created_by) values (%L, 'forged', %L)$q$, :'a_club', tests.uid(2)));

-- ---- plain member (user 2) --------------------------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('member reads the club', (select count(*) from public.clubs where id = :'a_club'), 1::bigint);
select tests.eq('member reads rails/items/polls',
  (select count(*) from public.club_rails where club_id=:'a_club') + (select count(*) from public.club_rail_items where rail_id=:'a_rail')
  + (select count(*) from public.club_polls where club_id=:'a_club'), 3::bigint);
select tests.eq('member cannot UPDATE the club (owner only): 0 rows', tests.affected(format($q$update public.clubs set name='hijack' where id=%L$q$, :'a_club')), 0::bigint);
select tests.eq('member cannot DELETE the club: 0 rows', tests.affected(format($q$delete from public.clubs where id=%L$q$, :'a_club')), 0::bigint);
select tests.eq('member cannot UPDATE a rail (admin only): 0 rows', tests.affected(format($q$update public.club_rails set title='x' where id=%L$q$, :'a_rail')), 0::bigint);
select tests.eq('member cannot DELETE a rail (admin only): 0 rows', tests.affected(format($q$delete from public.club_rails where id=%L$q$, :'a_rail')), 0::bigint);
select tests.eq('member cannot DELETE the owner membership row: 0 rows', tests.affected(format($q$delete from public.club_members where club_id=%L and user_id=%L$q$, :'a_club', tests.uid(1))), 0::bigint);
-- (role / club_id / user_id writes are covered by 60_club_role_guard.sql; here only the RLS row scope)
select tests.eq('member cannot UPDATE another member''s row (self only): 0 rows', tests.affected(format($q$update public.club_members set sharing_level='private' where club_id=%L and user_id=%L$q$, :'a_club', tests.uid(5))), 0::bigint);
-- own item / reaction / vote via direct table access
select tests.eq('member inserts a reaction as themself',
  tests.affected(format($q$insert into public.club_rail_item_reactions (rail_item_id, user_id, emoji) values (%L, auth.uid(), 'eyes')$q$, :'a_item')), 1::bigint);
select tests.denied('member cannot insert a reaction attributed to someone else',
  format($q$insert into public.club_rail_item_reactions (rail_item_id, user_id, emoji) values (%L, %L, '100')$q$, :'a_item', tests.uid(5)));
select tests.eq('member cannot delete another user''s reaction: 0 rows',
  tests.affected(format($q$delete from public.club_rail_item_reactions where rail_item_id=%L and user_id=%L$q$, :'a_item', tests.uid(1))), 0::bigint);
select tests.eq('member votes through the RPC', (public.cast_club_vote(:'a_poll', :'a_opt1')) ->> 'success', 'true');
select tests.eq('member cannot delete another user''s vote: 0 rows',
  tests.affected(format($q$delete from public.club_votes where poll_id=%L and user_id=%L$q$, :'a_poll', tests.uid(1))), 0::bigint);

-- rail creation: the RPC requires admin/owner. The direct-INSERT side of this
-- (former finding "club_rails_insert_member vs create_club_rail") is asserted in
-- 61_club_rail_insert_policy.sql against the pending fix.
select tests.raises('member: create_club_rail RPC is admin/owner only (NOT_ADMIN)',
  format($q$select public.create_club_rail(%L, 'member rail', null)$q$, :'a_club'), '%NOT_ADMIN%');

-- ---- outsider (user 3) ------------------------------------------------------
select tests.as_user(tests.uid(3));
select tests.eq('outsider reads 0 clubs',        (select count(*) from public.clubs), 0::bigint);
select tests.eq('outsider reads 0 memberships',  (select count(*) from public.club_members), 0::bigint);
select tests.eq('outsider reads 0 rails',        (select count(*) from public.club_rails), 0::bigint);
select tests.eq('outsider reads 0 rail items',   (select count(*) from public.club_rail_items), 0::bigint);
select tests.eq('outsider reads 0 reactions',    (select count(*) from public.club_rail_item_reactions), 0::bigint);
select tests.eq('outsider reads 0 polls',        (select count(*) from public.club_polls), 0::bigint);
select tests.eq('outsider reads 0 poll options', (select count(*) from public.club_poll_options), 0::bigint);
select tests.eq('outsider reads 0 votes',        (select count(*) from public.club_votes), 0::bigint);
select tests.eq('outsider UPDATE club: 0 rows',  tests.affected(format($q$update public.clubs set name='x' where id=%L$q$, :'a_club')), 0::bigint);
select tests.eq('outsider DELETE club: 0 rows',  tests.affected(format($q$delete from public.clubs where id=%L$q$, :'a_club')), 0::bigint);
select tests.denied('outsider cannot insert a rail',     format($q$insert into public.club_rails (club_id, title, created_by) values (%L,'x',auth.uid())$q$, :'a_club'));
select tests.denied('outsider cannot insert a rail item',format($q$insert into public.club_rail_items (rail_id, media_type, media_id, added_by) values (%L,'MANGA',424242,auth.uid())$q$, :'a_rail'));
select tests.denied('outsider cannot insert a reaction', format($q$insert into public.club_rail_item_reactions (rail_item_id, user_id, emoji) values (%L,auth.uid(),'fire')$q$, :'a_item'));
select tests.denied('outsider cannot insert a poll',     format($q$insert into public.club_polls (club_id, question, created_by) values (%L,'q',auth.uid())$q$, :'a_club'));
select tests.denied('outsider cannot insert a vote',     format($q$insert into public.club_votes (poll_id, option_id, user_id) values (%L,%L,auth.uid())$q$, :'a_poll', :'a_opt1'));
select tests.raises('outsider fetch_club_bundle raises NOT_A_MEMBER', format($q$select public.fetch_club_bundle(%L)$q$, :'a_club'), '%NOT_A_MEMBER%');
select tests.raises('outsider cast_club_vote raises NOT_A_MEMBER',    format($q$select public.cast_club_vote(%L,%L)$q$, :'a_poll', :'a_opt1'), '%NOT_A_MEMBER%');
select tests.raises('outsider toggle_club_reaction raises NOT_A_MEMBER', format($q$select public.toggle_club_reaction(%L,'fire')$q$, :'a_item'), '%NOT_A_MEMBER%');
select tests.raises('outsider create_club_poll raises NOT_A_MEMBER',  format($q$select public.create_club_poll(%L,'q',array['a','b'],null)$q$, :'a_club'), '%NOT_A_MEMBER%');
select tests.raises('outsider leave_club raises NOT_A_MEMBER',        format($q$select public.leave_club(%L)$q$, :'a_club'), '%NOT_A_MEMBER%');

-- ---- anon -------------------------------------------------------------------
select tests.as_anon();
select tests.eq('anon reads 0 clubs',   (select count(*) from public.clubs), 0::bigint);
select tests.eq('anon reads 0 members', (select count(*) from public.club_members), 0::bigint);
select tests.raises('anon create_club raises UNAUTHENTICATED', $q$select public.create_club('x', null, 'status')$q$, '%UNAUTHENTICATED%');

-- ---- REVOCATION: owner removes user 4 (club_members_delete_self_or_admin) ----
select tests.as_user(tests.uid(1));
select tests.eq('F35/F34: a direct table DELETE of another member''s row affects 0 rows (own-row SELECT; removal is the RPC)',
  tests.affected(format($q$delete from public.club_members where club_id=%L and user_id=%L$q$, :'a_club', tests.uid(4))), 0::bigint);
select tests.eq('owner removes member 4 through remove_club_member',
  (public.remove_club_member(:'a_club', tests.uid(4))) ->> 'removed', 'true');

select tests.as_user(tests.uid(4));
select tests.eq('REVOKED: clubs invisible',            (select count(*) from public.clubs where id=:'a_club'), 0::bigint);
select tests.eq('REVOKED: membership rows invisible',  (select count(*) from public.club_members where club_id=:'a_club'), 0::bigint);
select tests.eq('REVOKED: rails invisible',            (select count(*) from public.club_rails where club_id=:'a_club'), 0::bigint);
select tests.eq('REVOKED: rail items invisible',       (select count(*) from public.club_rail_items where rail_id=:'a_rail'), 0::bigint);
select tests.eq('REVOKED: reactions invisible (incl. their own earlier reaction)', (select count(*) from public.club_rail_item_reactions where rail_item_id=:'a_item'), 0::bigint);
select tests.eq('REVOKED: polls invisible',            (select count(*) from public.club_polls where club_id=:'a_club'), 0::bigint);
select tests.eq('REVOKED: poll options invisible',     (select count(*) from public.club_poll_options where poll_id=:'a_poll'), 0::bigint);
select tests.eq('REVOKED: votes invisible (incl. their own earlier vote)', (select count(*) from public.club_votes where poll_id=:'a_poll'), 0::bigint);
select tests.eq('REVOKED: messages invisible',         (select count(*) from public.club_messages where club_id=:'a_club'), 0::bigint);
select tests.denied('REVOKED: cannot add a rail',      format($q$insert into public.club_rails (club_id, title, created_by) values (%L,'x',auth.uid())$q$, :'a_club'));
select tests.denied('REVOKED: cannot add a rail item', format($q$insert into public.club_rail_items (rail_id, media_type, media_id, added_by) values (%L,'MANGA',424242,auth.uid())$q$, :'a_rail'));
select tests.denied('REVOKED: cannot add a reaction',  format($q$insert into public.club_rail_item_reactions (rail_item_id, user_id, emoji) values (%L,auth.uid(),'fire')$q$, :'a_item'));
select tests.denied('REVOKED: cannot add a poll',      format($q$insert into public.club_polls (club_id, question, created_by) values (%L,'q',auth.uid())$q$, :'a_club'));
select tests.denied('REVOKED: cannot add a vote',      format($q$insert into public.club_votes (poll_id, option_id, user_id) values (%L,%L,auth.uid())$q$, :'a_poll', :'a_opt1'));
select tests.denied('REVOKED: cannot post a message',  format($q$insert into public.club_messages (club_id, user_id, text) values (%L,auth.uid(),'hi')$q$, :'a_club'));
select tests.eq('REVOKED: cannot update the club: 0 rows', tests.affected(format($q$update public.clubs set name='x' where id=%L$q$, :'a_club')), 0::bigint);
select tests.raises('REVOKED: fetch_club_bundle raises NOT_A_MEMBER', format($q$select public.fetch_club_bundle(%L)$q$, :'a_club'), '%NOT_A_MEMBER%');
select tests.raises('REVOKED: cast_club_vote raises NOT_A_MEMBER',    format($q$select public.cast_club_vote(%L,%L)$q$, :'a_poll', :'a_opt1'), '%NOT_A_MEMBER%');
select tests.raises('REVOKED: toggle_club_reaction raises NOT_A_MEMBER', format($q$select public.toggle_club_reaction(%L,'fire')$q$, :'a_item'), '%NOT_A_MEMBER%');
select tests.raises('REVOKED: create_club_poll raises NOT_A_MEMBER',  format($q$select public.create_club_poll(%L,'q',array['a','b'],null)$q$, :'a_club'), '%NOT_A_MEMBER%');

-- ---- F35 revoked member: re-join is refused until an owner/admin restores ----
select tests.as_user(tests.uid(4));
select tests.raises('F35: REMOVED user 4 cannot re-join with the unchanged invite code',
  format($q$select public.join_club(%L)$q$, :'a_code'), '%REMOVED_FROM_CLUB%');
select tests.eq('...and is still not a member', (select count(*) from public.club_members where club_id=:'a_club' and user_id = auth.uid()), 0::bigint);
select tests.as_user(tests.uid(1));
select tests.eq('owner restores member 4', (public.restore_club_member(:'a_club', tests.uid(4))) ->> 'restored', 'true');
select tests.as_user(tests.uid(4));
select tests.eq('restored member 4 re-joins with the valid invite code', (public.join_club(:'a_code')) ->> 'club_id', :'a_club');
select tests.as_user(tests.uid(1));
select tests.eq('owner removes member 4 again', (public.remove_club_member(:'a_club', tests.uid(4))) ->> 'removed', 'true');

-- ---- revocation by leave_club (user 5 leaves) -------------------------------
select tests.as_user(tests.uid(5));
select tests.eq('member 5 reads rails before leaving', (select count(*) from public.club_rails where club_id=:'a_club'), 1::bigint);
select tests.eq('leave_club succeeds', (public.leave_club(:'a_club')) ->> 'success', 'true');
select tests.eq('LEFT: rails invisible',    (select count(*) from public.club_rails where club_id=:'a_club'), 0::bigint);
select tests.eq('LEFT: members invisible',  (select count(*) from public.club_members where club_id=:'a_club'), 0::bigint);
select tests.denied('LEFT: cannot add a reaction', format($q$insert into public.club_rail_item_reactions (rail_item_id, user_id, emoji) values (%L,auth.uid(),'fire')$q$, :'a_item'));

-- ---- REVOKED user's earlier raw rows persist but are excluded and private ----
select tests.reset();
select tests.eq('revoked user 4''s earlier vote row is kept (excluded, not deleted)',
  (select count(*) from public.club_votes where poll_id=:'a_poll' and user_id = tests.uid(4)), 1::bigint);
select tests.as_user(tests.uid(2));
select tests.eq('F34: ...but remaining members cannot read it through the table API',
  (select count(*) from public.club_votes where poll_id=:'a_poll' and user_id = tests.uid(4)), 0::bigint);
select tests.eq('F34: ...nor the revoked user''s reaction row',
  (select count(*) from public.club_rail_item_reactions where rail_item_id=:'a_item' and user_id = tests.uid(4)), 0::bigint);
select tests.eq('F35: the revoked user''s heart is excluded from the bundle reaction totals',
  (public.fetch_club_bundle(:'a_club')) #> '{rails,0,items,0,reactions}', '{"eyes": 1, "fire": 1}'::jsonb);

-- ============================================================================
-- RAW per-user rows (F34): a MEMBER reads only their OWN vote / reaction /
-- membership rows through the table API; others arrive only as authorized
-- aggregates through fetch_club_bundle.
-- ============================================================================
select tests.as_user(tests.uid(2));
select tests.eq('F34 RAW votes: a plain member reads no other member''s vote row',
  (select count(*) from public.club_votes where poll_id=:'a_poll' and user_id <> auth.uid()), 0::bigint);
select tests.eq('F34 RAW votes: ...but their own',
  (select count(*) from public.club_votes where poll_id=:'a_poll' and user_id = auth.uid()), 1::bigint);
select tests.eq('F34 RAW reactions: a plain member reads no other member''s reaction row',
  (select count(*) from public.club_rail_item_reactions where rail_item_id=:'a_item' and user_id <> auth.uid()), 0::bigint);
select tests.eq('F34 RAW memberships: a plain member reads no other member''s club_members row',
  (select count(*) from public.club_members where club_id=:'a_club' and user_id <> auth.uid()), 0::bigint);
select tests.eq('F36: ...while the bundle still counts both current voters',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((public.fetch_club_bundle(:'a_club')) #> '{polls,0,options}') o)::int, 2);

-- sharing_level='private' / <3-member gating exists only inside fetch_club_bundle
select tests.as_user(tests.uid(1));
select (public.create_club('Club B private', null, 'private')) ->> 'club_id' as b_club \gset
select invite_code as b_code from public.clubs where id = :'b_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'b_code');
select tests.as_user(tests.uid(2));
select tests.eq('private club: bundle exposes ONLY the caller''s own membership',
  jsonb_array_length((public.fetch_club_bundle(:'b_club')) -> 'members'), 1);
select tests.eq('F34 private club: a direct club_members read returns only the caller''s row (no bypass of the bundle gate)',
  (select count(*) from public.club_members where club_id=:'b_club'), 1::bigint);

-- Role escalation (former finding "club role self-escalation"): asserted in
-- 60_club_role_guard.sql against the pending fix 20261005120000.

select tests.reset();
rollback;
