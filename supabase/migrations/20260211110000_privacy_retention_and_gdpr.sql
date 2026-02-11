-- ============================================================
-- PRIVACY HARDENING: Retention policies, GDPR deletion, RLS fixes
--
-- 1. Extend concierge_housekeeping() with retention for:
--    - concierge_events (90 days)
--    - rag_retrieval_cache (expired rows)
--    - rag_retrieval_feedback (180 days)
-- 2. GDPR: delete_user_concierge_data() function
-- 3. Fix RLS initplan optimization on RAG table policies
-- ============================================================

begin;

-- ==========================================================
-- 1. Update concierge_config retention defaults
-- ==========================================================

UPDATE public.concierge_config
SET config = config || jsonb_build_object(
  'retention_days', (config->'retention_days') || jsonb_build_object(
    'concierge_events', 90,
    'rag_retrieval_feedback', 180
  )
)
WHERE id = true
  AND NOT (config->'retention_days' ? 'concierge_events');

-- ==========================================================
-- 2. Extend concierge_housekeeping() with new retention
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

  -- Concierge telemetry events (new)
  DELETE FROM public.concierge_events
  WHERE created_at < now() - make_interval(days => greatest(14, days_events));

  -- RAG retrieval cache: delete expired rows
  DELETE FROM public.rag_retrieval_cache
  WHERE expires_at < now();

  -- RAG retrieval feedback (new)
  DELETE FROM public.rag_retrieval_feedback
  WHERE created_at < now() - make_interval(days => greatest(30, days_rag_feedback));
END;
$$;

-- ==========================================================
-- 3. GDPR: delete_user_concierge_data()
--    Deletes all user-associated data from concierge tables.
--    Caller must be authenticated as the user or service_role.
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
  -- Delete sessions owned by user; items cascade
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

  RETURN jsonb_build_object('success', true, 'deleted', deleted_counts);
END;
$$;

-- Grant to authenticated users (they can only delete their own data)
GRANT EXECUTE ON FUNCTION public.delete_user_concierge_data(text) TO authenticated;

-- ==========================================================
-- 4. Fix RLS initplan optimization on RAG table policies
--    Replace bare auth.uid() with (SELECT auth.uid()) for
--    single evaluation per query instead of per-row.
-- ==========================================================

-- rag_retrieval_feedback: drop and recreate with initplan
DO $$ BEGIN
  DROP POLICY IF EXISTS rag_feedback_insert_own ON public.rag_retrieval_feedback;
  DROP POLICY IF EXISTS rag_feedback_select_own ON public.rag_retrieval_feedback;

  CREATE POLICY rag_feedback_insert_own ON public.rag_retrieval_feedback
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid())::text);

  CREATE POLICY rag_feedback_select_own ON public.rag_retrieval_feedback
    FOR SELECT USING (user_id = (SELECT auth.uid())::text);
END $$;

-- concierge_events: drop and recreate with initplan
DO $$ BEGIN
  DROP POLICY IF EXISTS concierge_events_insert_own ON public.concierge_events;

  CREATE POLICY concierge_events_insert_own ON public.concierge_events
    FOR INSERT WITH CHECK (
      user_id IS NULL OR user_id = (SELECT auth.uid())::text
    );
END $$;

-- concierge_events: no SELECT policy (analytics only via service_role/dashboard)
-- This is intentional: users should not be able to read telemetry events.

commit;
