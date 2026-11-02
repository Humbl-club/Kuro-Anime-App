-- 62_comment_reaction_visibility.sql  --  R3: toggle_comment_reaction must respect shares_club_with
--
-- Fix under test (PENDING, not deployed): 20261005120200_toggle_comment_reaction_visibility.sql
--   default run           -> PASS
--   --exclude-pending     -> FAILS at the first R3 assertion (deployed-chain behavior:
--                            a stranger who knows the comment uuid can react)
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
-- @requires table public.title_comments
-- @requires table public.title_comment_reactions
-- @requires function public.upsert_title_comment(text,integer,text)
-- @requires function public.toggle_comment_reaction(uuid,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4);
insert into public.anime (id) values (626262);

-- author 1 shares a club with 2 and 4; 3 shares none
select tests.as_user(tests.uid(1));
select (public.create_club('Comment Club', null, 'status')) ->> 'club_id' as m_club \gset
select invite_code as m_code from public.clubs where id = :'m_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'m_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'m_code');
select tests.as_user(tests.uid(1));
select (public.upsert_title_comment('ANIME', 626262, 'author take')) ->> 'id' as c1 \gset

-- ---- R3: stranger -------------------------------------------------------------
select tests.as_user(tests.uid(3));
select tests.raises_detail('R3: stranger who knows the comment uuid cannot react (COMMENT_NOT_FOUND)',
  format($q$select public.toggle_comment_reaction(%L, 'down')$q$, :'c1'), 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
select tests.raises_detail('R3: a non-existent comment uuid gives the identical error (no existence oracle)',
  $q$select public.toggle_comment_reaction(gen_random_uuid(), 'down')$q$, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
select tests.reset();
select tests.eq('R3: the stranger''s attempt wrote nothing',
  (select count(*) from public.title_comment_reactions where comment_id = :'c1' and user_id = tests.uid(3)), 0::bigint);
select tests.ok('R3: toggle_comment_reaction is still SECURITY DEFINER with search_path public, extensions',
  (select prosecdef and proconfig = array['search_path=public, extensions']
     from pg_proc where oid = 'public.toggle_comment_reaction(uuid,text)'::regprocedure));

-- ---- legit: club-mate (user 2) --------------------------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('legit: club-mate reacts up', (public.toggle_comment_reaction(:'c1', 'up')) ->> 'toggled_on', 'true');
select tests.eq('legit: club-mate switches to down (still on)', (public.toggle_comment_reaction(:'c1', 'down')) ->> 'reaction_type', 'down');
select tests.eq('legit: ...one row, type down',
  (select string_agg(reaction_type, ',') from public.title_comment_reactions where comment_id = :'c1' and user_id = auth.uid()), 'down');
select tests.eq('legit: club-mate toggles down again -> removed', (public.toggle_comment_reaction(:'c1', 'down')) ->> 'toggled_on', 'false');
select tests.eq('legit: ...no row left', (select count(*) from public.title_comment_reactions where comment_id = :'c1' and user_id = auth.uid()), 0::bigint);
select tests.eq('legit: club-mate reacts up again', (public.toggle_comment_reaction(:'c1', 'up')) ->> 'toggled_on', 'true');
select tests.raises('legit: invalid reaction type still INVALID_REACTION_TYPE',
  format($q$select public.toggle_comment_reaction(%L, 'meh')$q$, :'c1'), 'INVALID_REACTION_TYPE');
select tests.eq('legit: friend activity still shows the comment with the reaction to the club-mate',
  jsonb_array_length((public.fetch_friend_activity_for_title('ANIME', 626262)) -> 'comments'), 1);

-- ---- legit: author ------------------------------------------------------------------
select tests.as_user(tests.uid(1));
select tests.raises('legit: author still gets CANNOT_REACT_OWN (checked before visibility)',
  format($q$select public.toggle_comment_reaction(%L, 'up')$q$, :'c1'), 'CANNOT_REACT_OWN');
select tests.eq('legit: author sees the club-mate''s reaction',
  (select count(*) from public.title_comment_reactions where comment_id = :'c1'), 1::bigint);

-- ---- R3: leaver (user 4 reacts as a member, then leaves) ------------------------------
select tests.as_user(tests.uid(4));
select tests.eq('legit: club-mate 4 reacts while a member', (public.toggle_comment_reaction(:'c1', 'up')) ->> 'toggled_on', 'true');
select public.leave_club(:'m_club');
select tests.raises_detail('R3: after leave_club the former club-mate cannot react any more',
  format($q$select public.toggle_comment_reaction(%L, 'down')$q$, :'c1'), 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');

-- ---- R3: archived shared club stops sharing (same rule as the policies) ------------------
select tests.reset();
update public.clubs set is_archived = true where id = :'m_club';
select tests.as_user(tests.uid(2));
select tests.raises_detail('R3: archived club -> shares_club_with false -> cannot react',
  format($q$select public.toggle_comment_reaction(%L, 'down')$q$, :'c1'), 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
select tests.reset();
update public.clubs set is_archived = false where id = :'m_club';

-- ---- anon ----------------------------------------------------------------------
select tests.as_anon();
select tests.raises('anon: toggle_comment_reaction raises UNAUTHENTICATED',
  format($q$select public.toggle_comment_reaction(%L, 'up')$q$, :'c1'), 'UNAUTHENTICATED');

select tests.reset();
rollback;
