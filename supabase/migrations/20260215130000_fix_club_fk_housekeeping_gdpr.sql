-- ============================================================
-- FIX: Club FK constraints, housekeeping regression, GDPR gap
--
-- 1. Alter club table FKs to auth.users so account deletion works:
--    - created_by / added_by → ON DELETE SET NULL (preserve content)
--    - user_id (membership/votes/reactions) → ON DELETE CASCADE
-- 2. Restore club_analytics cleanup in concierge_housekeeping()
-- 3. Add club_analytics + club tables to delete_user_concierge_data()
-- 4. RPC: check_club_activity_since() for P0-CLUB-1 indicator
--
-- NOTE: generate_invite_code() CSPRNG and club_members INSERT policy
-- were already applied in 20260215125056.
-- ============================================================

begin;
-- ==========================================================
-- 1. Fix club FK constraints for account deletion
--    Current: all NO ACTION → blocks auth.users deletion
-- ==========================================================

-- clubs.created_by → SET NULL (club persists, creator anonymized)
ALTER TABLE public.clubs
  DROP CONSTRAINT IF EXISTS clubs_created_by_fkey,
  ADD CONSTRAINT clubs_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.clubs ALTER COLUMN created_by DROP NOT NULL;
-- club_members.user_id → CASCADE (membership removed on user delete)
ALTER TABLE public.club_members
  DROP CONSTRAINT IF EXISTS club_members_user_id_fkey,
  ADD CONSTRAINT club_members_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- club_rails.created_by → SET NULL (rail persists, creator anonymized)
ALTER TABLE public.club_rails
  DROP CONSTRAINT IF EXISTS club_rails_created_by_fkey,
  ADD CONSTRAINT club_rails_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.club_rails ALTER COLUMN created_by DROP NOT NULL;
-- club_rail_items.added_by → SET NULL (item persists, adder anonymized)
ALTER TABLE public.club_rail_items
  DROP CONSTRAINT IF EXISTS club_rail_items_added_by_fkey,
  ADD CONSTRAINT club_rail_items_added_by_fkey
    FOREIGN KEY (added_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.club_rail_items ALTER COLUMN added_by DROP NOT NULL;
-- club_polls.created_by → SET NULL (poll persists, creator anonymized)
ALTER TABLE public.club_polls
  DROP CONSTRAINT IF EXISTS club_polls_created_by_fkey,
  ADD CONSTRAINT club_polls_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.club_polls ALTER COLUMN created_by DROP NOT NULL;
-- club_votes.user_id → CASCADE (vote removed on user delete)
ALTER TABLE public.club_votes
  DROP CONSTRAINT IF EXISTS club_votes_user_id_fkey,
  ADD CONSTRAINT club_votes_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- club_rail_item_reactions.user_id → CASCADE (new table from 20260215125312)
ALTER TABLE public.club_rail_item_reactions
  DROP CONSTRAINT IF EXISTS club_rail_item_reactions_user_id_fkey,
  ADD CONSTRAINT club_rail_item_reactions_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- ==========================================================
-- 2. Restore club_analytics cleanup in concierge_housekeeping()
--    Lost when privacy migration (20260211110000) overwrote the function.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.concierge_housekeeping()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cfg jsonb;
  r jsonb;
  days_rate integer;
  days_llm integer;
  days_import integer;
  days_runs integer;
  days_feedback integer;
  days_events integer;
  days_rag_feedback integer;
  days_club_analytics integer;
BEGIN
  cfg := public.get_concierge_config();
  r := cfg->'retention_days';
  days_rate := coalesce((r->>'rate_limit_buckets')::int, 2);
  days_llm := coalesce((r->>'llm_daily_usage')::int, 90);
  days_import := coalesce((r->>'import_sessions')::int, 30);
  days_runs := coalesce((r->>'concierge_runs')::int, 60);
  days_feedback := coalesce((r->>'parse_feedback')::int, 14);
  days_events := coalesce((r->>'concierge_events')::int, 90);
  days_rag_feedback := coalesce((r->>'rag_retrieval_feedback')::int, 180);
  days_club_analytics := coalesce((r->>'club_analytics')::int, 90);

  -- Rate limit buckets
  DELETE FROM public.rate_limit_buckets
  WHERE window_start < now() - make_interval(days => greatest(1, days_rate));

  -- LLM daily usage
  DELETE FROM public.llm_daily_usage
  WHERE day < (timezone('utc', now())::date - greatest(7, days_llm));

  -- Import sessions/items (only completed/cancelled/failed; keep drafts)
  DELETE FROM public.import_session_items i
  USING public.import_sessions s
  WHERE i.session_id = s.id
    AND s.status IN ('applied','cancelled','failed')
    AND s.updated_at < now() - make_interval(days => greatest(7, days_import));

  DELETE FROM public.import_sessions
  WHERE status IN ('applied','cancelled','failed')
    AND updated_at < now() - make_interval(days => greatest(7, days_import));

  -- Concierge runs
  DELETE FROM public.concierge_runs
  WHERE created_at < now() - make_interval(days => greatest(14, days_runs));

  -- Parse feedback
  DELETE FROM public.concierge_parse_feedback
  WHERE created_at < now() - make_interval(days => greatest(7, days_feedback));

  -- Concierge telemetry events
  DELETE FROM public.concierge_events
  WHERE created_at < now() - make_interval(days => greatest(14, days_events));

  -- RAG retrieval cache: delete expired rows
  DELETE FROM public.rag_retrieval_cache
  WHERE expires_at < now();

  -- RAG retrieval feedback
  DELETE FROM public.rag_retrieval_feedback
  WHERE created_at < now() - make_interval(days => greatest(30, days_rag_feedback));

  -- Club analytics (restored from 20260209220000, lost in 20260211110000)
  DELETE FROM public.club_analytics
  WHERE created_at < now() - make_interval(days => greatest(30, days_club_analytics));
END;
$$;
-- ==========================================================
-- 3. Add club_analytics + club data to GDPR deletion function
-- ==========================================================

CREATE OR REPLACE FUNCTION public.delete_user_concierge_data(p_user_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  caller uuid;
  deleted_counts jsonb := '{}'::jsonb;
  cnt integer;
BEGIN
  -- Validate caller: must be the user themselves or service_role
  caller := auth.uid();
  IF caller IS NULL THEN
    RETURN jsonb_build_object('error', 'unauthenticated');
  END IF;

  -- Allow self-deletion only (service_role bypasses RLS anyway)
  IF caller::text <> p_user_id THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  -- Parse UUID for tables that use uuid type
  BEGIN
    uid := p_user_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('error', 'invalid_user_id');
  END;

  -- concierge_events (user_id is text)
  DELETE FROM public.concierge_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_events', cnt);

  -- rag_retrieval_feedback (user_id is text)
  DELETE FROM public.rag_retrieval_feedback WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('rag_retrieval_feedback', cnt);

  -- concierge_parse_feedback (user_id is uuid)
  DELETE FROM public.concierge_parse_feedback WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_parse_feedback', cnt);

  -- concierge_runs (user_id is uuid)
  DELETE FROM public.concierge_runs WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_runs', cnt);

  -- concierge_mode_cache (user_id is uuid)
  DELETE FROM public.concierge_mode_cache WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_mode_cache', cnt);

  -- title_aliases (user_id is uuid)
  DELETE FROM public.title_aliases WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_aliases', cnt);

  -- import_session_items (via session FK cascade)
  DELETE FROM public.import_session_items i
  USING public.import_sessions s
  WHERE i.session_id = s.id AND s.user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_session_items', cnt);

  DELETE FROM public.import_sessions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_sessions', cnt);

  -- llm_daily_usage (user_id is uuid)
  DELETE FROM public.llm_daily_usage WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('llm_daily_usage', cnt);

  -- user_taste_profiles (user_id is uuid)
  DELETE FROM public.user_taste_profiles WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_taste_profiles', cnt);

  -- club_analytics (user_id is uuid, no FK — cleanup needed)
  DELETE FROM public.club_analytics WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_analytics', cnt);

  -- Club reactions (user_id is uuid; also handled by FK CASCADE)
  DELETE FROM public.club_rail_item_reactions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_rail_item_reactions', cnt);

  -- Club votes (user_id is uuid; also handled by FK CASCADE, but explicit for count)
  DELETE FROM public.club_votes WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_votes', cnt);

  -- Club memberships (also handled by FK CASCADE, explicit for count)
  DELETE FROM public.club_members WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_members', cnt);

  -- Nullify created_by/added_by in clubs content (SET NULL FK handles this too,
  -- but explicit for reporting deleted-user ownership transfer)
  UPDATE public.clubs SET created_by = NULL WHERE created_by = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('clubs_anonymized', cnt);

  UPDATE public.club_rails SET created_by = NULL WHERE created_by = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_rails_anonymized', cnt);

  UPDATE public.club_rail_items SET added_by = NULL WHERE added_by = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_rail_items_anonymized', cnt);

  UPDATE public.club_polls SET created_by = NULL WHERE created_by = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_polls_anonymized', cnt);

  RETURN jsonb_build_object('success', true, 'deleted', deleted_counts);
END;
$$;
-- Re-grant to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_user_concierge_data(text) TO authenticated;
-- ==========================================================
-- 4. RPC: check_club_activity_since(timestamp)
--    Returns the latest activity timestamp across all clubs
--    the caller is a member of. Used by the activity indicator
--    (P0-CLUB-1) to show a badge when new activity exists.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.check_club_activity_since(p_since timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  latest timestamptz;
  has_new boolean;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN jsonb_build_object('has_new_activity', false);
  END IF;

  SELECT GREATEST(
    (SELECT MAX(cr.created_at) FROM club_rails cr
     JOIN club_members cm ON cm.club_id = cr.club_id
     WHERE cm.user_id = uid AND cr.created_at > p_since),
    (SELECT MAX(cri.created_at) FROM club_rail_items cri
     JOIN club_rails cr2 ON cr2.id = cri.rail_id
     JOIN club_members cm2 ON cm2.club_id = cr2.club_id
     WHERE cm2.user_id = uid AND cri.created_at > p_since),
    (SELECT MAX(cp.created_at) FROM club_polls cp
     JOIN club_members cm3 ON cm3.club_id = cp.club_id
     WHERE cm3.user_id = uid AND cp.created_at > p_since),
    (SELECT MAX(cv.created_at) FROM club_votes cv
     JOIN club_polls cp2 ON cp2.id = cv.poll_id
     JOIN club_members cm4 ON cm4.club_id = cp2.club_id
     WHERE cm4.user_id = uid AND cv.created_at > p_since)
  ) INTO latest;

  has_new := latest IS NOT NULL;

  RETURN jsonb_build_object(
    'has_new_activity', has_new,
    'latest_activity_at', latest
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_club_activity_since(timestamptz) TO authenticated;
commit;
