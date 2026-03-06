-- Fix remaining uuid/text mismatch in delete_user_concierge_data() and
-- restore full GDPR deletion coverage for concierge-adjacent user tables.

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
  caller := auth.uid();
  IF caller IS NULL THEN
    RETURN jsonb_build_object('error', 'unauthenticated');
  END IF;

  IF caller::text <> p_user_id THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  BEGIN
    uid := p_user_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('error', 'invalid_user_id');
  END;

  -- text-keyed telemetry/feedback tables
  DELETE FROM public.concierge_events WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_events', cnt);

  DELETE FROM public.rag_retrieval_feedback WHERE user_id = p_user_id;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('rag_retrieval_feedback', cnt);

  -- uuid-keyed concierge core tables
  DELETE FROM public.concierge_parse_feedback WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_parse_feedback', cnt);

  DELETE FROM public.concierge_runs WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_runs', cnt);

  DELETE FROM public.concierge_mode_cache WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('concierge_mode_cache', cnt);

  DELETE FROM public.title_aliases WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_aliases', cnt);

  -- import tables (import_sessions.user_id is uuid)
  DELETE FROM public.import_session_items i
  USING public.import_sessions s
  WHERE i.session_id = s.id AND s.user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_session_items', cnt);

  DELETE FROM public.import_sessions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('import_sessions', cnt);

  -- usage/profile tables
  DELETE FROM public.llm_daily_usage WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('llm_daily_usage', cnt);

  DELETE FROM public.user_taste_profiles WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_taste_profiles', cnt);

  -- social + club tables
  DELETE FROM public.club_analytics WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('club_analytics', cnt);

  DELETE FROM public.title_comment_reactions WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comment_reactions', cnt);

  DELETE FROM public.title_comments WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('title_comments', cnt);

  -- streaming preferences
  DELETE FROM public.user_streaming_services WHERE user_id = uid;
  GET DIAGNOSTICS cnt = ROW_COUNT;
  deleted_counts := deleted_counts || jsonb_build_object('user_streaming_services', cnt);

  RETURN jsonb_build_object('success', true, 'deleted', deleted_counts);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_concierge_data(text) TO authenticated;

COMMIT;
