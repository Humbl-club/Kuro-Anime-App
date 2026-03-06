-- Fix type mismatch in GDPR deletion function:
-- concierge_runs.user_id is uuid, so compare against parsed uuid (uid), not text input.

BEGIN;

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

  -- import_session_items via import_sessions (user_id is text)
  DELETE FROM public.import_session_items
  WHERE session_id IN (SELECT id FROM public.import_sessions WHERE user_id = p_user_id);
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_session_items', cnt);

  -- import_sessions (user_id is text)
  DELETE FROM public.import_sessions WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_sessions', cnt);

  -- club_analytics (user_id is uuid)
  DELETE FROM public.club_analytics WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_analytics', cnt);

  -- title_comments (user_id is uuid)
  DELETE FROM public.title_comments WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comments', cnt);

  -- title_comment_reactions (user_id is uuid)
  DELETE FROM public.title_comment_reactions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comment_reactions', cnt);

  -- user_streaming_services (user_id is uuid)
  DELETE FROM public.user_streaming_services WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_streaming_services', cnt);

  RETURN jsonb_build_object('success', true, 'deleted', deleted_counts);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_concierge_data(text) TO authenticated;

COMMIT;
