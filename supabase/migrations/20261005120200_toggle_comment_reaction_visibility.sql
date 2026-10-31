-- ============================================================================
-- toggle_comment_reaction: only on comments the caller may see
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate,
--         explicit human approval. Listed in supabase/tests/pending_migrations.txt.
--         This file lives in supabase/prepared-migrations/ so no push can deploy it by
--         accident; after approval, `git mv` it into supabase/migrations/.
--
-- Finding (E2 backend harness, finding 5, observed in the local fixture):
--   toggle_comment_reaction is SECURITY DEFINER and only checked that the
--   comment exists and is not the caller's own. A user who shares no club with
--   the author (or who has left the shared club) could react to the comment if
--   they knew its uuid, and the author then saw that reaction. Direct INSERT is
--   already denied by the comment_reactions_insert policy, which requires
--   author = caller OR shares_club_with(author).
--
-- Fix: the RPC applies the same visibility rule as the title_comments /
-- title_comment_reactions policies. A comment the caller may not see is reported
-- exactly like a missing one (same message 'COMMENT_NOT_FOUND', same
-- DETAIL = 'COMMENT_NOT_FOUND'), so the RPC is not an existence oracle for comment
-- uuids. Only the missing-comment branch gains DETAIL (message unchanged), so the
-- two outcomes stay indistinguishable. Everything else is the 20260224150000 body
-- verbatim: same signature, return shape, rate limit, error codes, SECURITY
-- DEFINER, search_path. CREATE OR REPLACE keeps the existing EXECUTE grants.
-- iOS impact: SupabaseService.toggleCommentReaction only reacts to comments
-- returned by fetch_friend_activity_for_title (already club-mates), so the normal
-- path is unchanged; a stale UI after the user left the club now gets an error
-- instead of a silent write.
--
-- Production parity: this repo chain is production's captured policy state;
-- production can differ through changes made outside the chain. Verify read-only
-- before deploying that the deployed body still matches 20260224150000:
--   select pg_get_functiondef('public.toggle_comment_reaction(uuid,text)'::regprocedure);
--
-- Idempotent: CREATE OR REPLACE.
-- Rollback: re-run the function definition from 20260224150000_social_activity_layer.sql.
-- ============================================================================

create or replace function public.toggle_comment_reaction(
  p_comment_id    uuid,
  p_reaction_type text
)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  _uid          uuid := auth.uid();
  _comment      record;
  _existing     record;
  _hits         int;
  _toggled_on   boolean;
begin
  if _uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = 'P0001';
  end if;

  if p_reaction_type not in ('up', 'down') then
    raise exception 'INVALID_REACTION_TYPE' using errcode = 'P0001';
  end if;

  -- Rate limit: 30 reactions per minute
  _hits := rate_limit_hit('comment_react:' || _uid::text, 60);
  if _hits > 30 then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;

  -- Check comment exists and is not own
  select id, user_id into _comment from title_comments where id = p_comment_id;
  if not found then
    raise exception 'COMMENT_NOT_FOUND' using errcode = 'P0001', detail = 'COMMENT_NOT_FOUND';
  end if;
  if _comment.user_id = _uid then
    raise exception 'CANNOT_REACT_OWN' using errcode = 'P0001';
  end if;

  -- Visibility: same rule as the comment_reactions_insert policy (the caller is
  -- not the author here, so they must share a non-archived club with the author).
  -- Reported exactly like a missing comment (no existence oracle).
  if not public.shares_club_with(_comment.user_id) then
    raise exception 'COMMENT_NOT_FOUND' using errcode = 'P0001', detail = 'COMMENT_NOT_FOUND';
  end if;

  -- Check for existing reaction
  select id, reaction_type into _existing
  from title_comment_reactions
  where comment_id = p_comment_id and user_id = _uid;

  if found then
    if _existing.reaction_type = p_reaction_type then
      -- Same type: remove (toggle off)
      delete from title_comment_reactions where id = _existing.id;
      _toggled_on := false;
    else
      -- Different type: switch
      update title_comment_reactions
      set reaction_type = p_reaction_type
      where id = _existing.id;
      _toggled_on := true;
    end if;
  else
    -- New reaction
    insert into title_comment_reactions (comment_id, user_id, reaction_type)
    values (p_comment_id, _uid, p_reaction_type);
    _toggled_on := true;
  end if;

  return jsonb_build_object(
    'toggled_on', _toggled_on,
    'reaction_type', p_reaction_type
  );
end;
$$;
