-- 60_club_role_guard.sql  --  R1: club_members role self-escalation
--
-- Fix under test (PENDING, not deployed): 20261005120000_club_members_role_column_guard.sql
--   default run           -> PASS (fixture includes the pending migration)
--   --exclude-pending     -> FAILS at the first R1 assertion (deployed-chain behavior:
--                            a member may set their own role to owner)
-- The "legit:" assertions are the flows that must keep working in both states.
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
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4);

-- ---- legit: membership only through the RPCs ---------------------------------
select tests.as_user(tests.uid(1));
select (public.create_club('Role Club', null, 'status')) ->> 'club_id' as r_club \gset
select invite_code as r_code from public.clubs where id = :'r_club' \gset
select tests.eq('legit: create_club makes the caller owner',
  (select role from public.club_members where club_id = :'r_club' and user_id = auth.uid()), 'owner');
select tests.as_user(tests.uid(2));
select tests.eq('legit: join_club with the invite code returns the club', (public.join_club(:'r_code')) ->> 'club_id', :'r_club');
select tests.eq('legit: a joiner is a plain member',
  (select role from public.club_members where club_id = :'r_club' and user_id = auth.uid()), 'member');
select tests.as_user(tests.uid(3)); select public.join_club(:'r_code');

-- ---- R1: a member can no longer change role / identity columns ---------------
select tests.as_user(tests.uid(2));
select tests.denied('R1: member cannot set OWN role to owner',
  format($q$update public.club_members set role = 'owner' where club_id = %L and user_id = auth.uid()$q$, :'r_club'));
select tests.denied('R1: member cannot set OWN role to admin',
  format($q$update public.club_members set role = 'admin' where club_id = %L and user_id = auth.uid()$q$, :'r_club'));
select tests.denied('R1: member cannot move their membership row to another club (club_id)',
  format($q$update public.club_members set club_id = gen_random_uuid() where club_id = %L and user_id = auth.uid()$q$, :'r_club'));
select tests.denied('R1: member cannot re-attribute their membership row (user_id)',
  format($q$update public.club_members set user_id = %L where club_id = %L and user_id = auth.uid()$q$, tests.uid(4), :'r_club'));
select tests.denied('R1: member cannot rewrite joined_at (seniority decides ownership transfer)',
  format($q$update public.club_members set joined_at = '2000-01-01' where club_id = %L and user_id = auth.uid()$q$, :'r_club'));
select tests.denied('R1: a SET list that names role is rejected even with the unchanged value (column privilege, not value check)',
  format($q$update public.club_members set sharing_level = 'status', role = 'member' where club_id = %L and user_id = auth.uid()$q$, :'r_club'));
select tests.ok('R1: member is still not owner', not public.is_club_owner(:'r_club'));
select tests.ok('R1: member is still not admin/owner', not public.is_club_admin_or_owner(:'r_club'));
select tests.eq('R1: member still cannot rename the club: 0 rows',
  tests.affected(format($q$update public.clubs set name = 'escalated' where id = %L$q$, :'r_club')), 0::bigint);
select tests.eq('R1: member still cannot delete the owner membership: 0 rows',
  tests.affected(format($q$delete from public.club_members where club_id = %L and user_id = %L$q$, :'r_club', tests.uid(1))), 0::bigint);

-- the owner cannot hand out roles through the table API either (there is no promote RPC)
select tests.as_user(tests.uid(1));
select tests.denied('R1: owner cannot promote a member to admin via the table API',
  format($q$update public.club_members set role = 'admin' where club_id = %L and user_id = %L$q$, :'r_club', tests.uid(3)));

select tests.as_anon();
select tests.denied('R1: anon holds no UPDATE privilege on club_members at all',
  format($q$update public.club_members set sharing_level = 'private' where club_id = %L$q$, :'r_club'));

-- grant shape: catches any later in-chain re-grant of the table-level UPDATE
select tests.reset();
select tests.ok('R1 grant: authenticated has no UPDATE on club_members.role',      not has_column_privilege('authenticated', 'public.club_members', 'role', 'UPDATE'));
select tests.ok('R1 grant: authenticated has no UPDATE on club_members.club_id',   not has_column_privilege('authenticated', 'public.club_members', 'club_id', 'UPDATE'));
select tests.ok('R1 grant: authenticated has no UPDATE on club_members.user_id',   not has_column_privilege('authenticated', 'public.club_members', 'user_id', 'UPDATE'));
select tests.ok('R1 grant: authenticated has no UPDATE on club_members.joined_at', not has_column_privilege('authenticated', 'public.club_members', 'joined_at', 'UPDATE'));
select tests.ok('R1 grant: anon has no UPDATE on any club_members column',         not has_any_column_privilege('anon', 'public.club_members', 'UPDATE'));
select tests.ok('R1 grant: authenticated keeps UPDATE on club_members.sharing_level', has_column_privilege('authenticated', 'public.club_members', 'sharing_level', 'UPDATE'));
select tests.ok('R1: RLS still enabled on club_members', (select relrowsecurity from pg_class where oid = 'public.club_members'::regclass));
select tests.eq('R1: club_members_update_self policy unchanged (own row only)',
  (select qual || ' / ' || with_check from pg_policies where schemaname = 'public' and tablename = 'club_members' and policyname = 'club_members_update_self'),
  '(user_id = auth.uid()) / (user_id = auth.uid())');

-- ---- legit: what a member may still change ----------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('legit: member updates OWN sharing_level (downgrade to private): 1 row',
  tests.affected(format($q$update public.club_members set sharing_level = 'private' where club_id = %L and user_id = auth.uid()$q$, :'r_club')), 1::bigint);
select tests.eq('legit: ...and the value is stored',
  (select sharing_level from public.club_members where club_id = :'r_club' and user_id = auth.uid()), 'private');
select tests.eq('legit: member cannot change ANOTHER member''s sharing_level: 0 rows (RLS own row)',
  tests.affected(format($q$update public.club_members set sharing_level = 'private' where club_id = %L and user_id = %L$q$, :'r_club', tests.uid(3))), 0::bigint);
select tests.eq('legit: bundle reflects the member''s own downgrade',
  (public.fetch_club_bundle(:'r_club')) ->> 'my_sharing_level', 'private');

-- ---- legit: the sanctioned role change (leave_club ownership transfer, SECURITY DEFINER) ----
-- all rows were inserted in one transaction (same now()); make seniority explicit so the
-- transfer target is deterministic (leave_club orders by joined_at only)
select tests.reset();
update public.club_members set joined_at = joined_at + interval '1 minute' where club_id = :'r_club' and user_id = tests.uid(3);
select tests.as_user(tests.uid(1));
select tests.eq('legit: owner leaves via leave_club', (public.leave_club(:'r_club')) ->> 'success', 'true');
select tests.as_user(tests.uid(2));
select tests.eq('legit: ownership transferred to the oldest member by the RPC',
  (select role from public.club_members where club_id = :'r_club' and user_id = auth.uid()), 'owner');
select tests.ok('legit: new owner passes is_club_owner()', public.is_club_owner(:'r_club'));
select tests.eq('legit: new owner can rename the club (owner policy): 1 row',
  tests.affected(format($q$update public.clubs set name = 'Renamed by new owner' where id = %L$q$, :'r_club')), 1::bigint);
select tests.ok('legit: new owner sees the invite code in the bundle',
  (public.fetch_club_bundle(:'r_club')) #>> '{club,invite_code}' = :'r_code');
select tests.as_user(tests.uid(3));
select tests.eq('legit: remaining member is still a plain member',
  (select role from public.club_members where club_id = :'r_club' and user_id = auth.uid()), 'member');
select tests.ok('legit: plain member does not see the invite code in the bundle',
  (public.fetch_club_bundle(:'r_club')) #>> '{club,invite_code}' is null);

select tests.reset();
rollback;
