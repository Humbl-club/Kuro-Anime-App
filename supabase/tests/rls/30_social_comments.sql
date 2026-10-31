-- 30_social_comments.sql  --  (c) title_comments / title_comment_reactions via shares_club_with
-- Visibility of a comment = author OR shares a (non-archived) club with the author.
-- @requires table public.title_comments
-- @requires table public.title_comment_reactions
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires function public.shares_club_with(uuid)
-- @requires function public.upsert_title_comment(text,integer,text)
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.leave_club(uuid)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3);
insert into public.anime (id) values (424242);

-- users 1 and 2 share a club (through the real RPCs); user 3 shares none
select tests.as_user(tests.uid(1));
select (public.create_club('Club S', null, 'status')) ->> 'club_id' as s_club \gset
select invite_code as s_code from public.clubs where id = :'s_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'s_code');

-- policy shape the tests rely on
select tests.eq('title_comments has 4 policies (select/insert/update/delete)',
  (select count(*) from pg_policies where schemaname='public' and tablename='title_comments'), 4::bigint);
select tests.eq('title_comment_reactions has 3 policies (select/insert/delete; no UPDATE)',
  (select count(*) from pg_policies where schemaname='public' and tablename='title_comment_reactions'), 3::bigint);

-- ---- author writes ----------------------------------------------------------
select tests.as_user(tests.uid(1));
select public.upsert_title_comment('ANIME', 424242, 'user-1 take');
select tests.eq('author reads own comment', (select count(*) from public.title_comments where media_id=424242), 1::bigint);
select id as c1 from public.title_comments where media_id=424242 and user_id = auth.uid() \gset
select tests.denied('cannot insert a comment as another user',
  format($q$insert into public.title_comments (user_id, media_type, media_id, text) values (%L,'ANIME',424242,'forged')$q$, tests.uid(2)));
select tests.eq('author updates own comment', tests.affected(format($q$update public.title_comments set text='edited' where id=%L$q$, :'c1')), 1::bigint);
select tests.denied('author cannot reassign the comment to another user',
  format($q$update public.title_comments set user_id=%L where id=%L$q$, tests.uid(2), :'c1'));

-- ---- club-mate (user 2) -----------------------------------------------------
select tests.as_user(tests.uid(2));
select tests.ok('shares_club_with(user 1) is true for a club-mate', public.shares_club_with(tests.uid(1)));
select tests.eq('club-mate reads the comment', (select count(*) from public.title_comments where id=:'c1'), 1::bigint);
select tests.eq('club-mate cannot UPDATE it: 0 rows', tests.affected(format($q$update public.title_comments set text='hijack' where id=%L$q$, :'c1')), 0::bigint);
select tests.eq('club-mate cannot DELETE it: 0 rows', tests.affected(format($q$delete from public.title_comments where id=%L$q$, :'c1')), 0::bigint);
select tests.eq('club-mate reacts through the RPC', (public.toggle_comment_reaction(:'c1', 'up')) ->> 'toggled_on', 'true');
select tests.eq('club-mate sees own reaction', (select count(*) from public.title_comment_reactions where comment_id=:'c1'), 1::bigint);
select tests.eq('RPC friend activity exposes the comment to the club-mate',
  jsonb_array_length((public.fetch_friend_activity_for_title('ANIME', 424242)) -> 'comments'), 1);

-- ---- outsider (user 3) ------------------------------------------------------
select tests.as_user(tests.uid(3));
select tests.ok('shares_club_with(user 1) is false for a stranger', not public.shares_club_with(tests.uid(1)));
select tests.eq('outsider cannot read the comment', (select count(*) from public.title_comments where id=:'c1'), 0::bigint);
select tests.eq('outsider cannot read reactions on it', (select count(*) from public.title_comment_reactions where comment_id=:'c1'), 0::bigint);
select tests.eq('outsider UPDATE: 0 rows', tests.affected(format($q$update public.title_comments set text='x' where id=%L$q$, :'c1')), 0::bigint);
select tests.eq('outsider DELETE: 0 rows', tests.affected(format($q$delete from public.title_comments where id=%L$q$, :'c1')), 0::bigint);
select tests.denied('outsider cannot insert a reaction directly (comment not visible)',
  format($q$insert into public.title_comment_reactions (comment_id, user_id, reaction_type) values (%L, auth.uid(), 'up')$q$, :'c1'));
select tests.eq('RPC friend activity shows the outsider no comments',
  jsonb_array_length((public.fetch_friend_activity_for_title('ANIME', 424242)) -> 'comments'), 0);
-- RPC path for a stranger who knows the comment id: asserted in
-- 62_comment_reaction_visibility.sql against the pending fix 20261005120200
-- (former finding "toggle_comment_reaction skips the club check").
select tests.eq('the stranger cannot read reactions on the comment', (select count(*) from public.title_comment_reactions where comment_id=:'c1'), 0::bigint);

-- ---- anon -------------------------------------------------------------------
select tests.as_anon();
select tests.eq('anon reads 0 comments', (select count(*) from public.title_comments), 0::bigint);
select tests.eq('anon reads 0 reactions', (select count(*) from public.title_comment_reactions), 0::bigint);

-- ---- revocation: user 2 leaves the club -------------------------------------
select tests.as_user(tests.uid(2));
select tests.eq('before leaving: club-mate can read', (select count(*) from public.title_comments where id=:'c1'), 1::bigint);
select public.leave_club(:'s_club');
select tests.eq('after leaving: comment invisible', (select count(*) from public.title_comments where id=:'c1'), 0::bigint);
select tests.ok('after leaving: shares_club_with(user 1) is false', not public.shares_club_with(tests.uid(1)));
select tests.denied('after leaving: cannot react directly',
  format($q$insert into public.title_comment_reactions (comment_id, user_id, reaction_type) values (%L, auth.uid(), 'down')$q$, :'c1'));
select tests.eq('after leaving: own earlier reaction row is invisible too', (select count(*) from public.title_comment_reactions where comment_id=:'c1'), 0::bigint);
select tests.as_user(tests.uid(1));
select tests.eq('author still sees the leaver''s earlier reaction (author-visible)', (select count(*) from public.title_comment_reactions where comment_id=:'c1' and user_id = tests.uid(2)), 1::bigint);

-- ---- archived club stops sharing -------------------------------------------
select tests.as_user(tests.uid(2)); select public.join_club(:'s_code');
select tests.eq('re-joined: visible again', (select count(*) from public.title_comments where id=:'c1'), 1::bigint);
select tests.reset();
update public.clubs set is_archived = true where id = :'s_club';
select tests.as_user(tests.uid(2));
select tests.eq('archived club: shares_club_with is false so comment is invisible', (select count(*) from public.title_comments where id=:'c1'), 0::bigint);

select tests.reset();
rollback;
