-- ============================================================
-- Streaming Availability v1
-- 1. streaming_services — canonical registry (replaces hardcoded allowlists)
-- 2. user_streaming_services — user subscription preferences
-- 3. batch_providers_for_media() — server-side provider lookup
-- 4. club_shared_providers() — club intersection RPC
-- 5. save_user_streaming_services() — upsert user services
-- 6. Feature flag: streaming_availability_v1 at 0%
-- 7. GDPR: add to delete_user_concierge_data()
-- ============================================================

BEGIN;

-- ==========================================================
-- 1. streaming_services — canonical provider registry
-- ==========================================================

CREATE TABLE public.streaming_services (
  slug         text PRIMARY KEY CHECK (slug ~ '^[a-z0-9_-]+$'),
  display_name text NOT NULL,
  media_types  text[] NOT NULL DEFAULT '{ANIME,MANGA}',
  site_patterns text[] NOT NULL,
  priority     int NOT NULL DEFAULT 50,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.streaming_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "streaming_services_public_read" ON public.streaming_services
  FOR SELECT USING (true);

-- Seed rows matching existing hardcoded allowlists
INSERT INTO public.streaming_services (slug, display_name, media_types, site_patterns, priority) VALUES
  ('crunchyroll',  'Crunchyroll',  '{ANIME}',       '{crunchyroll}',                            1),
  ('netflix',      'Netflix',      '{ANIME,MANGA}', '{netflix}',                                2),
  ('hidive',       'HIDIVE',       '{ANIME}',       '{hidive}',                                 3),
  ('disney',       'Disney+',      '{ANIME}',       '{disney}',                                 4),
  ('amazon',       'Prime Video',  '{ANIME}',       '{amazon,prime video,prime}',               5),
  ('hulu',         'Hulu',         '{ANIME}',       '{hulu}',                                   6),
  ('youtube',      'YouTube',      '{ANIME}',       '{youtube}',                                7),
  ('apple',        'Apple TV+',    '{ANIME}',       '{apple tv,apple}',                         8),
  ('max',          'Max',          '{ANIME}',       '{max}',                                    9),
  ('manga-plus',   'Manga Plus',   '{MANGA}',       '{manga plus,mangaplus}',                   1),
  ('viz',          'Viz Media',    '{MANGA}',       '{viz media,viz}',                          2),
  ('bookwalker',   'BookWalker',   '{MANGA}',       '{global bookwalker,bookwalker}',           3),
  ('comixology',   'Comixology',   '{MANGA}',       '{comixology}',                             4),
  ('kindle',       'Kindle',       '{MANGA}',       '{kindle}',                                 5),
  ('kobo',         'Kobo',         '{MANGA}',       '{kobo}',                                   6),
  ('kodansha',     'Kodansha',     '{MANGA}',       '{kodansha}',                               7),
  ('yen-press',    'Yen Press',    '{MANGA}',       '{yen press}',                              8),
  ('azuki',        'Azuki',        '{MANGA}',       '{azuki}',                                  9),
  ('j-novel-club', 'J-Novel Club', '{MANGA}',       '{j-novel club}',                           10);

-- ==========================================================
-- 2. user_streaming_services — user subscription preferences
-- ==========================================================

CREATE TABLE public.user_streaming_services (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  service    text NOT NULL REFERENCES streaming_services(slug),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, service)
);

CREATE INDEX idx_uss_user ON public.user_streaming_services(user_id);

ALTER TABLE public.user_streaming_services ENABLE ROW LEVEL SECURITY;

-- Own rows only. Shared data exposed only via SECURITY DEFINER RPCs.
CREATE POLICY "uss_select_own" ON public.user_streaming_services
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "uss_insert_own" ON public.user_streaming_services
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "uss_delete_own" ON public.user_streaming_services
  FOR DELETE USING (user_id = auth.uid());

-- ==========================================================
-- 3. Ensure external_links index exists
-- ==========================================================

CREATE INDEX IF NOT EXISTS idx_external_links_media
  ON public.external_links(media_type, media_id);

-- ==========================================================
-- 4. batch_providers_for_media(p_items text)
--    Input: JSON array of [{media_type, media_id}]
--    Returns: [{media_type, media_id, providers: [{slug, display_name, language}]}]
-- ==========================================================

CREATE OR REPLACE FUNCTION public.batch_providers_for_media(p_items text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  result jsonb := '[]'::jsonb;
  req jsonb;
  item_row record;
  provider_row record;
  providers jsonb;
BEGIN
  -- Parse the input JSON array
  BEGIN
    req := p_items::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', 'invalid_json');
  END;

  FOR item_row IN
    SELECT
      (elem->>'media_type') AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(req) AS elem
  LOOP
    -- For each media item, find matching providers via site_patterns
    SELECT jsonb_agg(sub.prov ORDER BY sub.prio) INTO providers
    FROM (
      SELECT DISTINCT ON (ss.slug)
        jsonb_build_object(
          'slug', ss.slug,
          'display_name', ss.display_name,
          'language', el.language
        ) AS prov,
        ss.priority AS prio
      FROM external_links el
      CROSS JOIN streaming_services ss
      CROSS JOIN LATERAL unnest(ss.site_patterns) AS pattern
      WHERE el.media_type = item_row.media_type
        AND el.media_id = item_row.media_id
        AND ss.is_active = true
        AND lower(el.site) LIKE '%' || pattern || '%'
      ORDER BY ss.slug, length(pattern) DESC, ss.priority ASC
    ) sub;

    result := result || jsonb_build_array(
      jsonb_build_object(
        'media_type', item_row.media_type,
        'media_id', item_row.media_id,
        'providers', COALESCE(providers, '[]'::jsonb)
      )
    );
  END LOOP;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.batch_providers_for_media(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_providers_for_media(text) TO authenticated;

-- ==========================================================
-- 5. club_shared_providers(p_club_id uuid)
--    Returns intersection of all members' streaming services
--    + coverage metadata
-- ==========================================================

CREATE OR REPLACE FUNCTION public.club_shared_providers(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  uid uuid;
  total_members int;
  members_with_services int;
  shared jsonb;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN jsonb_build_object('error', 'unauthenticated');
  END IF;

  -- Verify caller is a club member
  IF NOT EXISTS (
    SELECT 1 FROM club_members WHERE club_id = p_club_id AND user_id = uid
  ) THEN
    RETURN jsonb_build_object('error', 'not_a_member');
  END IF;

  -- Count total members
  SELECT count(*) INTO total_members
  FROM club_members WHERE club_id = p_club_id;

  -- Count members who have set at least one service
  SELECT count(DISTINCT uss.user_id) INTO members_with_services
  FROM user_streaming_services uss
  JOIN club_members cm ON cm.user_id = uss.user_id AND cm.club_id = p_club_id;

  -- Need at least 2 members with services for meaningful intersection
  IF members_with_services < 2 THEN
    RETURN jsonb_build_object(
      'shared_services', '[]'::jsonb,
      'member_count_total', total_members,
      'member_count_with_services', members_with_services,
      'coverage_pct', CASE WHEN total_members > 0
        THEN (members_with_services * 100 / total_members) ELSE 0 END
    );
  END IF;

  -- Find services that ALL members-with-services share
  SELECT jsonb_agg(
    jsonb_build_object('slug', ss.slug, 'display_name', ss.display_name)
    ORDER BY ss.priority
  ) INTO shared
  FROM (
    SELECT uss.service, count(DISTINCT uss.user_id) AS member_count
    FROM user_streaming_services uss
    JOIN club_members cm ON cm.user_id = uss.user_id AND cm.club_id = p_club_id
    GROUP BY uss.service
    HAVING count(DISTINCT uss.user_id) = members_with_services
  ) common
  JOIN streaming_services ss ON ss.slug = common.service
  WHERE ss.is_active = true;

  RETURN jsonb_build_object(
    'shared_services', COALESCE(shared, '[]'::jsonb),
    'member_count_total', total_members,
    'member_count_with_services', members_with_services,
    'coverage_pct', CASE WHEN total_members > 0
      THEN (members_with_services * 100 / total_members) ELSE 0 END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.club_shared_providers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.club_shared_providers(uuid) TO authenticated;

-- ==========================================================
-- 6. save_user_streaming_services(p_services text[])
--    Upsert: delete removed, insert new, ignore existing
-- ==========================================================

CREATE OR REPLACE FUNCTION public.save_user_streaming_services(p_services text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  uid uuid;
  inserted int;
  deleted int;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN jsonb_build_object('error', 'unauthenticated');
  END IF;

  -- Delete services no longer selected
  DELETE FROM user_streaming_services
  WHERE user_id = uid AND service != ALL(p_services);
  GET DIAGNOSTICS deleted = ROW_COUNT;

  -- Insert new selections (FK validates slugs)
  INSERT INTO user_streaming_services (user_id, service)
  SELECT uid, unnest(p_services)
  ON CONFLICT (user_id, service) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'inserted', inserted,
    'deleted', deleted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_user_streaming_services(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_user_streaming_services(text[]) TO authenticated;

-- ==========================================================
-- 7. Feature flag: streaming_availability_v1 at 0%
-- ==========================================================

INSERT INTO public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES ('streaming_availability_v1', true, 0, '{}', 'Streaming service availability on cards, filters, and clubs')
ON CONFLICT (flag_name) DO NOTHING;

-- ==========================================================
-- 8. GDPR: add user_streaming_services to deletion function
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

  -- concierge_runs (user_id is text)
  DELETE FROM public.concierge_runs WHERE user_id = p_user_id;
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
