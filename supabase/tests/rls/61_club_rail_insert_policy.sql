-- 61_club_rail_insert_policy.sql  --  R2: direct club_rails INSERT vs create_club_rail
--
-- Fix under test (PENDING, not deployed): 20261005120100_club_rails_insert_admin_only.sql
--   default run           -> PASS
--   --exclude-pending     -> FAILS at the first R2 assertion (deployed-chain behavior:
--                            any member may insert a rail through the table API)
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

select tests.make_user(1), tests.make_user(2), tests.make_user(3);
insert into public.anime (id) values (515151);

select tests.as_user(tests.uid(1));
select (public.create_club('Rail Club', null, 'status')) ->> 'club_id' as k_club \gset
select invite_code as k_code from public.clubs where id = :'k_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'k_code');

-- ---- R2: plain member ---------------------------------------------------------
select tests.as_user(tests.uid(2));
select tests.denied('R2: plain member cannot INSERT a rail through the table API (own created_by)',
  format($q$insert into public.club_rails (club_id, title, created_by) values (%L, 'member rail', auth.uid())$q$, :'k_club'));
select tests.raises('R2: plain member create_club_rail RPC still raises NOT_ADMIN (unchanged)',
  format($q$select public.create_club_rail(%L, 'member rail', null)$q$, :'k_club'), '%NOT_ADMIN%');
select tests.eq('R2: no rail was created by the member', (select count(*) from public.club_rails where club_id = :'k_club'), 0::bigint);

-- ---- policy shape --------------------------------------------------------------
select tests.reset();
select tests.eq('R2: exactly one INSERT policy on club_rails',
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'club_rails' and cmd = 'INSERT'), 1::bigint);
select tests.ok('R2: the INSERT policy requires owner/admin and created_by = caller',
  (select with_check like '%is_club_admin_or_owner(club_id)%' and with_check like '%created_by = %auth.uid()%'
     from pg_policies where schemaname = 'public' and tablename = 'club_rails' and cmd = 'INSERT'));
select tests.ok('R2: RLS still enabled on club_rails', (select relrowsecurity from pg_class where oid = 'public.club_rails'::regclass));

-- ---- legit: owner paths ------------------------------------------------------------
select tests.as_user(tests.uid(1));
select (public.create_club_rail(:'k_club', 'Owner rail', 'desc')) ->> 'rail_id' as k_rail \gset
select tests.eq('legit: owner creates a rail via create_club_rail', (select count(*) from public.club_rails where id = :'k_rail'), 1::bigint);
savepoint owner_direct;
select tests.eq('legit: owner direct INSERT with own created_by is allowed (policy aligned with the RPC, not stricter)',
  tests.affected(format($q$insert into public.club_rails (club_id, title, created_by) values (%L, 'owner direct', auth.uid())$q$, :'k_club')), 1::bigint);
rollback to savepoint owner_direct;
select tests.denied('legit: owner cannot forge a rail attributed to another user',
  format($q$insert into public.club_rails (club_id, title, created_by) values (%L, 'forged', %L)$q$, :'k_club', tests.uid(2)));

-- ---- legit: members still add items to rails via the RPC ------------------------------
select tests.as_user(tests.uid(2));
select tests.ok('legit: member adds an item to the owner''s rail via add_club_rail_item',
  (public.add_club_rail_item(:'k_rail', 'ANIME', 515151, 'try this')) ->> 'item_id' is not null);
select tests.eq('legit: member sees the rail and the item',
  (select count(*) from public.club_rail_items where rail_id = :'k_rail'), 1::bigint);

-- ---- outsider ---------------------------------------------------------------------
select tests.as_user(tests.uid(3));
select tests.denied('outsider cannot INSERT a rail',
  format($q$insert into public.club_rails (club_id, title, created_by) values (%L, 'x', auth.uid())$q$, :'k_club'));
select tests.raises('outsider create_club_rail raises NOT_ADMIN',
  format($q$select public.create_club_rail(%L, 'x', null)$q$, :'k_club'), '%NOT_ADMIN%');

select tests.reset();
rollback;
