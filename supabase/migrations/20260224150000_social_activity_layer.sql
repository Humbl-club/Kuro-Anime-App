-- Social Activity Layer: title-level comments + friend indicators
-- "Friends" = users who share at least one non-archived club

-- ============================================================
-- 1. TABLES
-- ============================================================

-- One comment per user per title (flat, not threaded)
CREATE TABLE public.title_comments (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  media_type    text        NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id      integer     NOT NULL,
  text          text        NOT NULL CHECK (char_length(text) BETWEEN 1 AND 500),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, media_type, media_id)
);

CREATE INDEX idx_title_comments_media ON title_comments(media_type, media_id);
CREATE INDEX idx_title_comments_user  ON title_comments(user_id);

-- Reuse existing set_updated_at() trigger function
CREATE TRIGGER title_comments_updated_at BEFORE UPDATE ON title_comments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Thumbs up/down on others' comments (one reaction per user per comment)
CREATE TABLE public.title_comment_reactions (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id    uuid        NOT NULL REFERENCES title_comments(id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction_type text        NOT NULL CHECK (reaction_type IN ('up', 'down')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id)
);

CREATE INDEX idx_comment_reactions_comment ON title_comment_reactions(comment_id);
CREATE INDEX idx_comment_reactions_user    ON title_comment_reactions(user_id);

-- ============================================================
-- 2. RLS HELPER: "shares at least one non-archived club"
-- ============================================================

CREATE OR REPLACE FUNCTION public.shares_club_with(p_other_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = (SELECT auth.uid())
      AND cm2.user_id = p_other_user_id
      AND NOT c.is_archived
      AND cm1.user_id != cm2.user_id
  );
$$;

-- ============================================================
-- 3. RLS POLICIES
-- ============================================================

ALTER TABLE public.title_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.title_comment_reactions ENABLE ROW LEVEL SECURITY;

-- title_comments: SELECT own + friends
CREATE POLICY "title_comments_select" ON title_comments FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR shares_club_with(user_id)
  );

-- title_comments: INSERT own only
CREATE POLICY "title_comments_insert" ON title_comments FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

-- title_comments: UPDATE own only
CREATE POLICY "title_comments_update" ON title_comments FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- title_comments: DELETE own only
CREATE POLICY "title_comments_delete" ON title_comments FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- title_comment_reactions: SELECT visible comments
CREATE POLICY "comment_reactions_select" ON title_comment_reactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM title_comments tc
      WHERE tc.id = comment_id
        AND (tc.user_id = (SELECT auth.uid()) OR shares_club_with(tc.user_id))
    )
  );

-- title_comment_reactions: INSERT only on visible comments
CREATE POLICY "comment_reactions_insert" ON title_comment_reactions FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND comment_id IN (
      SELECT tc.id FROM title_comments tc
      WHERE tc.user_id = (SELECT auth.uid()) OR public.shares_club_with(tc.user_id)
    )
  );

-- title_comment_reactions: DELETE own only
CREATE POLICY "comment_reactions_delete" ON title_comment_reactions FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 4. RPCs
-- ============================================================

-- 4a. Upsert title comment (one per user per title)
CREATE OR REPLACE FUNCTION public.upsert_title_comment(
  p_media_type text,
  p_media_id   integer,
  p_text       text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid  uuid := auth.uid();
  _hits int;
  _result record;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  IF p_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION 'INVALID_MEDIA_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF char_length(TRIM(p_text)) < 1 OR char_length(TRIM(p_text)) > 500 THEN
    RAISE EXCEPTION 'INVALID_TEXT_LENGTH' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 10 comments per 5 minutes
  _hits := rate_limit_hit('title_comment:' || _uid::text, 300);
  IF _hits > 10 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO title_comments (user_id, media_type, media_id, text)
  VALUES (_uid, p_media_type, p_media_id, TRIM(p_text))
  ON CONFLICT (user_id, media_type, media_id) DO UPDATE
    SET text = TRIM(EXCLUDED.text),
        updated_at = now()
  RETURNING id, user_id, text, created_at, updated_at
  INTO _result;

  RETURN jsonb_build_object(
    'id', _result.id,
    'user_id', _result.user_id,
    'text', _result.text,
    'created_at', _result.created_at,
    'updated_at', _result.updated_at
  );
END;
$$;

-- 4b. Delete title comment
CREATE OR REPLACE FUNCTION public.delete_title_comment(
  p_media_type text,
  p_media_id   integer
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM title_comments
  WHERE user_id = _uid
    AND media_type = p_media_type
    AND media_id = p_media_id;
END;
$$;

-- 4c. Toggle comment reaction (up/down). Can't react to own comment.
CREATE OR REPLACE FUNCTION public.toggle_comment_reaction(
  p_comment_id    uuid,
  p_reaction_type text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid          uuid := auth.uid();
  _comment      record;
  _existing     record;
  _hits         int;
  _toggled_on   boolean;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  IF p_reaction_type NOT IN ('up', 'down') THEN
    RAISE EXCEPTION 'INVALID_REACTION_TYPE' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 30 reactions per minute
  _hits := rate_limit_hit('comment_react:' || _uid::text, 60);
  IF _hits > 30 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  -- Check comment exists and is not own
  SELECT id, user_id INTO _comment FROM title_comments WHERE id = p_comment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COMMENT_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;
  IF _comment.user_id = _uid THEN
    RAISE EXCEPTION 'CANNOT_REACT_OWN' USING ERRCODE = 'P0001';
  END IF;

  -- Check for existing reaction
  SELECT id, reaction_type INTO _existing
  FROM title_comment_reactions
  WHERE comment_id = p_comment_id AND user_id = _uid;

  IF FOUND THEN
    IF _existing.reaction_type = p_reaction_type THEN
      -- Same type: remove (toggle off)
      DELETE FROM title_comment_reactions WHERE id = _existing.id;
      _toggled_on := false;
    ELSE
      -- Different type: switch
      UPDATE title_comment_reactions
      SET reaction_type = p_reaction_type
      WHERE id = _existing.id;
      _toggled_on := true;
    END IF;
  ELSE
    -- New reaction
    INSERT INTO title_comment_reactions (comment_id, user_id, reaction_type)
    VALUES (p_comment_id, _uid, p_reaction_type);
    _toggled_on := true;
  END IF;

  RETURN jsonb_build_object(
    'toggled_on', _toggled_on,
    'reaction_type', p_reaction_type
  );
END;
$$;

-- 4d. Fetch friend activity for a title (friends tracking + comments with reaction counts)
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
  _friends_json    jsonb;
  _comments_json   jsonb;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('friends_tracking', '[]'::jsonb, 'comments', '[]'::jsonb);
  END IF;

  -- Build friend set ONCE: users sharing at least one non-archived club
  SELECT ARRAY(
    SELECT DISTINCT cm2.user_id
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
  ) INTO _friend_uuids;

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
      'progress', ft.progress,
      'rating', ft.rating,
      'updated_at', ft.updated_at
    )
  ), '[]'::jsonb)
  INTO _friends_json
  FROM friends_tracking ft;

  -- Comments from self + friends, with reaction counts
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

-- 4e. Batch count friends tracking items (for card indicators)
-- p_items is text (not jsonb) to avoid Swift/PostgREST type-mismatch; cast inside.
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

  WITH friend_ids AS (
    SELECT DISTINCT cm2.user_id
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = _uid
      AND cm2.user_id != _uid
      AND NOT c.is_archived
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
-- 5. Feature flag (0% rollout initially)
-- ============================================================

INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES ('social_activity_v1', true, 0, ARRAY['*'], 'Social activity layer: friend comments and indicators on titles')
ON CONFLICT (flag_name) DO NOTHING;

-- ============================================================
-- 6. Chat deprecation: unschedule prune_club_messages cron
-- ============================================================

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'prune_club_messages';

-- Disable club chat feature flag
UPDATE feature_flags SET enabled = false WHERE flag_name = 'clubs_chat_v1';
