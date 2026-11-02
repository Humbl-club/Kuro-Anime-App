-- ============================================================
-- Clubs trust pack v1 (ADR 2026-07-31 — clubs overnight posture)
--
-- 1. toggle_club_reaction: align the emoji allowlist to the client's
--    canonical keys ('fire','heart','eyes','100'). fetch_club_bundle
--    aggregates club_rail_item_reactions by the stored value verbatim
--    (20260317110000, reactions/my_reactions blocks), so keys are now
--    stored and grouped consistently end-to-end.
-- 2. fetch_friend_activity_for_title + count_friends_tracking: port the
--    bundle's sharing-level semantics. For each shared (non-archived)
--    club, a subject member's effective rank is the least of the club
--    sharing_level rank and the subject member's own downgrade rank
--    (members can only downgrade themselves; NULL inherits club level).
--    eff_rank 0 across all shared clubs -> excluded entirely.
--    eff_rank 1 -> status only (progress/rating NULLed, columns kept).
--    eff_rank 2 -> full detail.
-- 3. Seed clubs feature flags (reactions/list enriched at 100%;
--    realtime/pace sync/notifications dark at 0%).
-- ============================================================

-- ============================================================
-- 1. toggle_club_reaction (preserves hardening from 20260219100006)
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_club_reaction(p_rail_item_id uuid, p_emoji text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
  _uid uuid;
  _club_id uuid;
  _is_member boolean;
  _existing uuid;
  _hits integer;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Reaction allowlist: client canonical keys (fire/heart/eyes/100)
  IF p_emoji NOT IN ('fire', 'heart', 'eyes', '100') THEN
    RAISE EXCEPTION 'INVALID_EMOJI' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 30 reactions per 60 seconds
  _hits := rate_limit_hit('club_react:' || _uid::text, 60);
  IF _hits > 30 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  SELECT cr.club_id INTO _club_id
  FROM public.club_rail_items cri
  JOIN public.club_rails cr ON cri.rail_id = cr.id
  WHERE cri.id = p_rail_item_id;

  IF _club_id IS NULL THEN
    RAISE EXCEPTION 'ITEM_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = _club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO _existing
  FROM public.club_rail_item_reactions
  WHERE rail_item_id = p_rail_item_id AND user_id = _uid AND emoji = p_emoji;

  IF _existing IS NOT NULL THEN
    DELETE FROM public.club_rail_item_reactions WHERE id = _existing;
    RETURN jsonb_build_object('action', 'removed', 'emoji', p_emoji);
  ELSE
    INSERT INTO public.club_rail_item_reactions (rail_item_id, user_id, emoji)
    VALUES (p_rail_item_id, _uid, p_emoji);
    RETURN jsonb_build_object('action', 'added', 'emoji', p_emoji);
  END IF;
END;
$function$;

-- ============================================================
-- 2a. fetch_friend_activity_for_title with sharing-level enforcement
-- ============================================================
CREATE OR REPLACE FUNCTION public.fetch_friend_activity_for_title(
  p_media_type text,
  p_media_id   integer
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid             uuid := auth.uid();
  _friend_uuids    uuid[];
  _detail_uuids    uuid[];
  _friends_json    jsonb;
  _comments_json   jsonb;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('friends_tracking', '[]'::jsonb, 'comments', '[]'::jsonb);
  END IF;

  -- Friend visibility map: per friend, the MAX effective sharing rank across
  -- all shared non-archived clubs. Effective rank mirrors fetch_club_bundle:
  -- least of club sharing_level rank and the subject member's own downgrade
  -- (member sharing_level can only lower exposure; NULL inherits club level).
  -- eff_rank 0 everywhere -> not visible at all; >= 1 -> status-level;
  -- >= 2 -> progress/rating detail.
  WITH friend_visibility AS (
    SELECT
      cm2.user_id AS friend_id,
      MAX(
        CASE
          WHEN cm2.sharing_level IS NULL THEN public.sharing_level_rank(c.sharing_level)
          WHEN public.sharing_level_rank(cm2.sharing_level) < public.sharing_level_rank(c.sharing_level)
            THEN public.sharing_level_rank(cm2.sharing_level)
          ELSE public.sharing_level_rank(c.sharing_level)
        END
      ) AS eff_rank
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
  )
  SELECT
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 1), '{}'::uuid[]),
    COALESCE(ARRAY(SELECT friend_id FROM friend_visibility WHERE eff_rank >= 2), '{}'::uuid[])
  INTO _friend_uuids, _detail_uuids;

  -- Friends tracking this title (from user lists)
  -- NOTE: anime_user_lists/manga_user_lists have TEXT user_id, so cast uuid::text
  WITH friends_tracking AS (
    SELECT
      f_uid AS user_id,
      p.display_name,
      ul.status,
      ul.progress,
      ul.rating,
      ul.updated_at::text AS updated_at
    FROM unnest(_friend_uuids) AS f_uid
    JOIN profiles p ON p.id = f_uid
    INNER JOIN (
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM anime_user_lists
      WHERE anime_id = p_media_id AND 'ANIME' = p_media_type
      UNION ALL
      SELECT user_id, list_type AS status, progress, rating, updated_at
      FROM manga_user_lists
      WHERE manga_id = p_media_id AND 'MANGA' = p_media_type
    ) ul ON ul.user_id = f_uid::text
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', ft.user_id,
      'display_name', ft.display_name,
      'status', ft.status,
      -- eff_rank 1 = status only: keep columns but NULL the detail fields
      'progress', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.progress ELSE NULL END,
      'rating', CASE WHEN ft.user_id = ANY(_detail_uuids) THEN ft.rating ELSE NULL END,
      'updated_at', ft.updated_at
    )
  ), '[]'::jsonb)
  INTO _friends_json
  FROM friends_tracking ft;

  -- Comments from self + visible friends, with reaction counts
  WITH visible_comments AS (
    SELECT tc.*
    FROM title_comments tc
    WHERE tc.media_type = p_media_type
      AND tc.media_id = p_media_id
      AND (tc.user_id = _uid OR tc.user_id = ANY(_friend_uuids))
  ),
  comment_agg AS (
    SELECT
      vc.id,
      vc.user_id,
      p.display_name,
      vc.text,
      vc.created_at::text AS created_at,
      vc.updated_at::text AS updated_at,
      (vc.user_id = _uid) AS is_own,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'up' THEN 1 ELSE 0 END), 0)::int AS up_count,
      COALESCE(SUM(CASE WHEN cr.reaction_type = 'down' THEN 1 ELSE 0 END), 0)::int AS down_count,
      (SELECT cr2.reaction_type FROM title_comment_reactions cr2
       WHERE cr2.comment_id = vc.id AND cr2.user_id = _uid
       LIMIT 1) AS my_reaction
    FROM visible_comments vc
    JOIN profiles p ON p.id = vc.user_id
    LEFT JOIN title_comment_reactions cr ON cr.comment_id = vc.id
    GROUP BY vc.id, vc.user_id, p.display_name, vc.text, vc.created_at, vc.updated_at
    ORDER BY vc.created_at DESC
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ca.id,
      'user_id', ca.user_id,
      'display_name', ca.display_name,
      'text', ca.text,
      'created_at', ca.created_at,
      'updated_at', ca.updated_at,
      'is_own', ca.is_own,
      'up_count', ca.up_count,
      'down_count', ca.down_count,
      'my_reaction', ca.my_reaction
    )
  ), '[]'::jsonb)
  INTO _comments_json
  FROM comment_agg ca;

  RETURN jsonb_build_object(
    'friends_tracking', _friends_json,
    'comments', _comments_json
  );
END;
$$;

-- ============================================================
-- 2b. count_friends_tracking with sharing-level enforcement
-- p_items is text (not jsonb) to avoid Swift/PostgREST type-mismatch; cast inside.
-- ============================================================
CREATE OR REPLACE FUNCTION public.count_friends_tracking(p_items text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid        uuid := auth.uid();
  _items_json jsonb := p_items::jsonb;
  _result     jsonb;
BEGIN
  IF _uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Only friends whose MAX effective sharing rank across shared non-archived
  -- clubs is >= 1 count toward indicators (private club or self-downgrade
  -- to 'private' in every shared club -> invisible). Same eff-rank rule as
  -- fetch_club_bundle / fetch_friend_activity_for_title.
  WITH friend_ids AS (
    SELECT cm2.user_id
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
    GROUP BY cm2.user_id
    HAVING MAX(
      CASE
        WHEN cm2.sharing_level IS NULL THEN public.sharing_level_rank(c.sharing_level)
        WHEN public.sharing_level_rank(cm2.sharing_level) < public.sharing_level_rank(c.sharing_level)
          THEN public.sharing_level_rank(cm2.sharing_level)
        ELSE public.sharing_level_rank(c.sharing_level)
      END
    ) >= 1
  ),
  items AS (
    SELECT
      (elem->>'media_type')::text AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(_items_json) AS elem
  ),
  counts AS (
    SELECT
      i.media_type,
      i.media_id,
      COUNT(DISTINCT ul.user_id)::int AS count
    FROM items i
    JOIN (
      SELECT user_id, 'ANIME'::text AS media_type, anime_id AS media_id FROM anime_user_lists
      UNION ALL
      SELECT user_id, 'MANGA'::text AS media_type, manga_id AS media_id FROM manga_user_lists
    ) ul ON ul.media_type = i.media_type AND ul.media_id = i.media_id
    WHERE ul.user_id::uuid IN (SELECT user_id FROM friend_ids)
    GROUP BY i.media_type, i.media_id
    HAVING COUNT(DISTINCT ul.user_id) > 0
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'media_type', c.media_type,
      'media_id', c.media_id,
      'count', c.count
    )
  ), '[]'::jsonb)
  INTO _result
  FROM counts c;

  RETURN _result;
END;
$$;

-- ============================================================
-- 3. Feature flags
-- ============================================================
INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES
  ('clubs_reactions_v1', true, 100, ARRAY['*'], 'Club rail item reactions (canonical keys fire/heart/eyes/100)'),
  ('clubs_list_enriched_v1', true, 100, ARRAY['*'], 'Enriched club list rows on the Clubs page'),
  ('clubs_realtime_v1', true, 0, ARRAY['*'], 'Club realtime refresh (dark until ramped)'),
  ('clubs_pace_sync_v1', true, 0, ARRAY['*'], 'Club pace sync milestones and banners (dark until ramped)'),
  ('clubs_notifications_v1', true, 0, ARRAY['*'], 'Club activity notifications (dark until ramped)')
ON CONFLICT (flag_name) DO NOTHING;
