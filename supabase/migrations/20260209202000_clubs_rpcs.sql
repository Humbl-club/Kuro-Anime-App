-- ============================================================
-- CLUBS RPCs MIGRATION
-- Creates 6 club RPCs + 2 helper functions.
--
-- RPCs: create_club, join_club, leave_club, fetch_club_bundle,
--       add_club_rail_item, cast_club_vote.
--
-- Security notes:
--   - SECURITY DEFINER RPCs validate auth.uid() IS NOT NULL at top
--   - Explicit membership checks (DEFINER bypasses RLS)
--   - fetch_club_bundle uses SECURITY INVOKER (read-only)
--   - user_id::text cast for joins to anime_user_lists/manga_user_lists
--   - Votes are anonymous: return counts only, never voter identities
-- ============================================================

begin;

-- ==========================================================
-- 0. HELPER FUNCTIONS (used by RPCs and RLS policies)
-- ==========================================================

-- Membership check: returns true if auth.uid() is a member of the given club.
CREATE OR REPLACE FUNCTION public.is_club_member(p_club_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  );
$$;

-- Admin/owner check: returns true if auth.uid() is admin or owner of the given club.
CREATE OR REPLACE FUNCTION public.is_club_admin_or_owner(p_club_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id
      AND user_id = auth.uid()
      AND role IN ('owner', 'admin')
  );
$$;

-- Sharing level numeric rank for comparisons: private=0, status=1, progress=2.
CREATE OR REPLACE FUNCTION public.sharing_level_rank(p_level text)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_level
    WHEN 'private'  THEN 0
    WHEN 'status'   THEN 1
    WHEN 'progress' THEN 2
    ELSE 0
  END;
$$;

GRANT EXECUTE ON FUNCTION public.is_club_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_club_admin_or_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sharing_level_rank(text) TO authenticated;

-- ==========================================================
-- 1. create_club
-- ==========================================================

CREATE OR REPLACE FUNCTION public.create_club(
  p_name text,
  p_description text DEFAULT NULL,
  p_sharing_level text DEFAULT 'status'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _club_id uuid;
  _invite_code text;
  _clean_name text;
  _attempts int := 0;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Strip control characters, trim whitespace
  _clean_name := regexp_replace(trim(p_name), '[\x00-\x1F\x7F]', '', 'g');

  -- Validate name
  IF _clean_name IS NULL OR char_length(_clean_name) = 0 THEN
    RAISE EXCEPTION 'INVALID_NAME: name must not be empty' USING ERRCODE = 'P0001';
  END IF;
  IF char_length(_clean_name) > 80 THEN
    RAISE EXCEPTION 'INVALID_NAME: name must be <= 80 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Validate sharing level
  IF p_sharing_level NOT IN ('private', 'status', 'progress') THEN
    RAISE EXCEPTION 'INVALID_SHARING_LEVEL' USING ERRCODE = 'P0001';
  END IF;

  -- Generate unique invite code with collision retry (max 5 attempts)
  LOOP
    _invite_code := public.generate_invite_code(8);
    _attempts := _attempts + 1;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.clubs WHERE invite_code = _invite_code);
    IF _attempts >= 5 THEN
      RAISE EXCEPTION 'INVITE_CODE_GENERATION_FAILED' USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  -- Create club
  INSERT INTO public.clubs (name, description, created_by, invite_code, sharing_level)
  VALUES (_clean_name, p_description, _uid, _invite_code, p_sharing_level)
  RETURNING id INTO _club_id;

  -- Add creator as owner
  INSERT INTO public.club_members (club_id, user_id, role, sharing_level)
  VALUES (_club_id, _uid, 'owner', NULL);

  RETURN jsonb_build_object(
    'club_id', _club_id,
    'invite_code', _invite_code,
    'name', _clean_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_club(text, text, text) TO authenticated;

-- ==========================================================
-- 2. join_club
-- ==========================================================

CREATE OR REPLACE FUNCTION public.join_club(p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _club record;
  _member_count int;
  _rate_hits int;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: max 10 join attempts per user per minute (60s window)
  _rate_hits := public.rate_limit_hit('club_join:' || _uid::text, 60);
  IF _rate_hits > 10 THEN
    RAISE EXCEPTION 'RATE_LIMITED: too many join attempts, try again later' USING ERRCODE = 'P0001';
  END IF;

  -- Look up club by invite code
  SELECT c.id, c.name, c.invite_expires_at, c.invite_max_uses,
         c.invite_use_count, c.max_members, c.is_archived
  INTO _club
  FROM public.clubs c
  WHERE c.invite_code = p_invite_code;

  IF _club IS NULL THEN
    RAISE EXCEPTION 'INVALID_CODE' USING ERRCODE = 'P0001';
  END IF;

  -- Check invite code expiry
  IF _club.invite_expires_at IS NOT NULL AND _club.invite_expires_at < now() THEN
    RAISE EXCEPTION 'CODE_EXPIRED' USING ERRCODE = 'P0001';
  END IF;

  -- Check invite use count
  IF _club.invite_max_uses IS NOT NULL AND _club.invite_use_count >= _club.invite_max_uses THEN
    RAISE EXCEPTION 'CODE_EXHAUSTED' USING ERRCODE = 'P0001';
  END IF;

  -- Check already member
  IF EXISTS (SELECT 1 FROM public.club_members WHERE club_id = _club.id AND user_id = _uid) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Check member cap
  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = _club.id;
  IF _member_count >= _club.max_members THEN
    RAISE EXCEPTION 'CLUB_FULL' USING ERRCODE = 'P0001';
  END IF;

  -- Insert member
  INSERT INTO public.club_members (club_id, user_id, role, sharing_level)
  VALUES (_club.id, _uid, 'member', NULL);

  -- Increment invite use count
  UPDATE public.clubs SET invite_use_count = invite_use_count + 1 WHERE id = _club.id;

  RETURN jsonb_build_object(
    'club_id', _club.id,
    'club_name', _club.name,
    'role', 'member'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_club(text) TO authenticated;

-- ==========================================================
-- 3. leave_club
-- ==========================================================

CREATE OR REPLACE FUNCTION public.leave_club(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _member record;
  _remaining int;
  _new_owner_id uuid;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Verify membership
  SELECT id, role INTO _member
  FROM public.club_members
  WHERE club_id = p_club_id AND user_id = _uid;

  IF _member IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Remove the member
  DELETE FROM public.club_members WHERE club_id = p_club_id AND user_id = _uid;

  -- If caller was the owner, handle ownership transfer
  IF _member.role = 'owner' THEN
    -- Count remaining members
    SELECT count(*) INTO _remaining FROM public.club_members WHERE club_id = p_club_id;

    IF _remaining = 0 THEN
      -- No members left: delete club (CASCADE handles child tables)
      DELETE FROM public.clubs WHERE id = p_club_id;
    ELSE
      -- Transfer ownership: oldest admin first, then oldest member (L2)
      SELECT user_id INTO _new_owner_id
      FROM public.club_members
      WHERE club_id = p_club_id AND role = 'admin'
      ORDER BY joined_at ASC
      LIMIT 1;

      IF _new_owner_id IS NULL THEN
        SELECT user_id INTO _new_owner_id
        FROM public.club_members
        WHERE club_id = p_club_id
        ORDER BY joined_at ASC
        LIMIT 1;
      END IF;

      UPDATE public.club_members
      SET role = 'owner'
      WHERE club_id = p_club_id AND user_id = _new_owner_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_club(uuid) TO authenticated;

-- ==========================================================
-- 4. fetch_club_bundle
--    SECURITY INVOKER — relies on RLS for data access.
--    Explicit membership check for defense-in-depth.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.fetch_club_bundle(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _members jsonb;
  _rails jsonb;
  _polls jsonb;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Verify membership (defense-in-depth; RLS also checks)
  SELECT cm.role, cm.sharing_level, cm.joined_at
  INTO _my_membership
  FROM public.club_members cm
  WHERE cm.club_id = p_club_id AND cm.user_id = _uid;

  IF _my_membership IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Fetch club info
  SELECT c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  INTO _club
  FROM public.clubs c
  WHERE c.id = p_club_id;

  IF _club IS NULL THEN
    RAISE EXCEPTION 'CLUB_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  -- Compute effective sharing level for the caller
  _my_effective_level := CASE
    WHEN _my_membership.sharing_level IS NULL THEN _club.sharing_level
    WHEN public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      THEN _my_membership.sharing_level
    ELSE _club.sharing_level
  END;

  _club_sharing_rank := public.sharing_level_rank(_club.sharing_level);

  -- Count members
  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = p_club_id;

  -- --------------------------------------------------------
  -- MEMBERS: respect sharing_level privacy
  -- --------------------------------------------------------
  -- If sharing_level = 'private': aggregates only, no per-member data
  -- If sharing_level = 'status': names + statuses, no progress numbers
  -- If sharing_level = 'progress': full detail
  -- If member_count < 3: only own status + "N others tracking" (H1)
  IF _club_sharing_rank = 0 THEN
    -- 'private': only return the caller's own membership
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', cm.user_id,
      'role', cm.role,
      'sharing_level', COALESCE(cm.sharing_level, _club.sharing_level),
      'joined_at', cm.joined_at
    ))
    INTO _members
    FROM public.club_members cm
    WHERE cm.club_id = p_club_id AND cm.user_id = _uid;
  ELSIF _member_count < 3 THEN
    -- H1: fewer than 3 members — only own data
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', cm.user_id,
      'role', cm.role,
      'sharing_level', COALESCE(cm.sharing_level, _club.sharing_level),
      'joined_at', cm.joined_at
    ))
    INTO _members
    FROM public.club_members cm
    WHERE cm.club_id = p_club_id AND cm.user_id = _uid;
  ELSE
    -- 'status' or 'progress': return all members
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', cm.user_id,
      'role', cm.role,
      'sharing_level', COALESCE(cm.sharing_level, _club.sharing_level),
      'joined_at', cm.joined_at
    ))
    INTO _members
    FROM public.club_members cm
    WHERE cm.club_id = p_club_id;
  END IF;

  _members := COALESCE(_members, '[]'::jsonb);

  -- --------------------------------------------------------
  -- RAILS + ITEMS with media join + per-item aggregates
  -- --------------------------------------------------------
  -- Uses LEFT JOINs to anime/manga + user lists (one join each, not
  -- N scalar subqueries per item). Aggregates via correlated subquery
  -- on club_members only for the status_counts bucket.
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'title', r.title,
      'description', r.description,
      'is_locked', r.is_locked,
      'sort_order', r.sort_order,
      'created_by', r.created_by,
      'items', COALESCE(r.items, '[]'::jsonb)
    ) ORDER BY r.sort_order
  ), '[]'::jsonb)
  INTO _rails
  FROM (
    SELECT
      cr.id, cr.title, cr.description, cr.is_locked, cr.sort_order, cr.created_by,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', enriched.item_id,
            'media_type', enriched.media_type,
            'media_id', enriched.media_id,
            'sort_order', enriched.sort_order,
            'note', enriched.note,
            'added_by', enriched.added_by,
            'title_display', enriched.title_display,
            'cover_image_medium', enriched.cover_image_medium,
            'average_score', enriched.average_score,
            'year', enriched.year,
            'format', enriched.format,
            'my_status', enriched.my_status,
            'my_progress', enriched.my_progress,
            'my_rating', enriched.my_rating,
            'member_status_counts', enriched.member_status_counts,
            'member_statuses', enriched.member_statuses
          ) ORDER BY enriched.sort_order
        )
        FROM (
          SELECT
            cri.id AS item_id,
            cri.media_type,
            cri.media_id,
            cri.sort_order,
            cri.note,
            cri.added_by,
            -- Media display fields via LEFT JOIN (single lookup per media table)
            COALESCE(
              CASE WHEN cri.media_type = 'ANIME' THEN COALESCE(a.title_english, a.title_romaji)
                   WHEN cri.media_type = 'MANGA' THEN COALESCE(m.title_english, m.title_romaji)
              END, 'Unknown'
            ) AS title_display,
            CASE WHEN cri.media_type = 'ANIME' THEN a.cover_image_medium
                 WHEN cri.media_type = 'MANGA' THEN m.cover_image_medium
            END AS cover_image_medium,
            CASE WHEN cri.media_type = 'ANIME' THEN a.average_score
                 WHEN cri.media_type = 'MANGA' THEN m.average_score
            END AS average_score,
            CASE WHEN cri.media_type = 'ANIME' THEN a.season_year
                 WHEN cri.media_type = 'MANGA' THEN m.start_date_year
            END AS year,
            CASE WHEN cri.media_type = 'ANIME' THEN a.format
                 WHEN cri.media_type = 'MANGA' THEN m.format
            END AS format,
            -- Caller's own status/progress (single LEFT JOIN per list table)
            COALESCE(my_aul.list_type, my_mul.list_type) AS my_status,
            COALESCE(my_aul.progress, my_mul.progress) AS my_progress,
            COALESCE(my_aul.rating, my_mul.rating) AS my_rating,
            -- Aggregate status counts across club members
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN
                jsonb_build_object('_tracking_count', (
                  SELECT count(*)
                  FROM public.club_members cm2
                  WHERE cm2.club_id = p_club_id
                    AND cm2.user_id != _uid
                    AND (
                      CASE WHEN cri.media_type = 'ANIME' THEN
                        EXISTS (SELECT 1 FROM public.anime_user_lists aul2
                                WHERE aul2.user_id = cm2.user_id::text AND aul2.anime_id = cri.media_id)
                      WHEN cri.media_type = 'MANGA' THEN
                        EXISTS (SELECT 1 FROM public.manga_user_lists mul2
                                WHERE mul2.user_id = cm2.user_id::text AND mul2.manga_id = cri.media_id)
                      END
                    )
                ))
              ELSE
                (
                  SELECT COALESCE(jsonb_object_agg(sa.list_type, sa.cnt), '{}'::jsonb)
                  FROM (
                    SELECT ul.list_type, count(*) AS cnt
                    FROM public.club_members cm3
                    JOIN LATERAL (
                      SELECT CASE
                        WHEN cm3.sharing_level IS NULL THEN _club_sharing_rank
                        WHEN public.sharing_level_rank(cm3.sharing_level) < _club_sharing_rank
                          THEN public.sharing_level_rank(cm3.sharing_level)
                        ELSE _club_sharing_rank
                      END AS eff_rank
                    ) eff ON true
                    LEFT JOIN LATERAL (
                      SELECT aul3.list_type FROM public.anime_user_lists aul3
                      WHERE cri.media_type = 'ANIME' AND aul3.user_id = cm3.user_id::text AND aul3.anime_id = cri.media_id
                      UNION ALL
                      SELECT mul3.list_type FROM public.manga_user_lists mul3
                      WHERE cri.media_type = 'MANGA' AND mul3.user_id = cm3.user_id::text AND mul3.manga_id = cri.media_id
                    ) ul ON true
                    WHERE cm3.club_id = p_club_id AND eff.eff_rank >= 1 AND ul.list_type IS NOT NULL
                    GROUP BY ul.list_type
                  ) sa
                )
            END AS member_status_counts,
            -- Per-member status for this item (only when sharing >= 'status' and >= 3 members)
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN NULL
              ELSE (
                SELECT jsonb_agg(jsonb_build_object(
                  'user_id', ms.user_id,
                  'status', ms.list_type,
                  'progress', CASE WHEN _club_sharing_rank >= 2 THEN ms.progress ELSE NULL END
                ))
                FROM (
                  SELECT cm4.user_id, ul4.list_type, ul4.progress
                  FROM public.club_members cm4
                  JOIN LATERAL (
                    SELECT CASE
                      WHEN cm4.sharing_level IS NULL THEN _club_sharing_rank
                      WHEN public.sharing_level_rank(cm4.sharing_level) < _club_sharing_rank
                        THEN public.sharing_level_rank(cm4.sharing_level)
                      ELSE _club_sharing_rank
                    END AS eff_rank
                  ) eff4 ON true
                  LEFT JOIN LATERAL (
                    SELECT aul4.list_type, aul4.progress FROM public.anime_user_lists aul4
                    WHERE cri.media_type = 'ANIME' AND aul4.user_id = cm4.user_id::text AND aul4.anime_id = cri.media_id
                    UNION ALL
                    SELECT mul4.list_type, mul4.progress FROM public.manga_user_lists mul4
                    WHERE cri.media_type = 'MANGA' AND mul4.user_id = cm4.user_id::text AND mul4.manga_id = cri.media_id
                  ) ul4 ON true
                  WHERE cm4.club_id = p_club_id AND eff4.eff_rank >= 1 AND ul4.list_type IS NOT NULL
                ) ms
              )
            END AS member_statuses
          FROM public.club_rail_items cri
          -- JOIN media tables once per item (not N scalar subqueries)
          LEFT JOIN public.anime a ON cri.media_type = 'ANIME' AND a.id = cri.media_id
          LEFT JOIN public.manga m ON cri.media_type = 'MANGA' AND m.id = cri.media_id
          -- JOIN caller's own list entries once per item
          LEFT JOIN public.anime_user_lists my_aul
            ON cri.media_type = 'ANIME' AND my_aul.user_id = _uid::text AND my_aul.anime_id = cri.media_id
          LEFT JOIN public.manga_user_lists my_mul
            ON cri.media_type = 'MANGA' AND my_mul.user_id = _uid::text AND my_mul.manga_id = cri.media_id
          WHERE cri.rail_id = cr.id
        ) enriched
      ) AS items
    FROM public.club_rails cr
    WHERE cr.club_id = p_club_id
  ) r;

  -- --------------------------------------------------------
  -- POLLS + OPTIONS + VOTE COUNTS (anonymous — no voter IDs, M5)
  -- --------------------------------------------------------
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'question', p.question,
      'is_closed', p.is_closed,
      'closes_at', p.closes_at,
      'created_by', p.created_by,
      'created_at', p.created_at,
      'options', COALESCE(p.options, '[]'::jsonb),
      'my_vote_option_id', p.my_vote_option_id
    ) ORDER BY p.is_closed ASC, p.created_at DESC
  ), '[]'::jsonb)
  INTO _polls
  FROM (
    SELECT
      cp.id, cp.question, cp.is_closed, cp.closes_at, cp.created_by, cp.created_at,
      -- Options with vote counts only (anonymous)
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', cpo.id,
            'label', cpo.label,
            'media_type', cpo.media_type,
            'media_id', cpo.media_id,
            'sort_order', cpo.sort_order,
            'vote_count', (SELECT count(*) FROM public.club_votes cv WHERE cv.option_id = cpo.id)
          ) ORDER BY cpo.sort_order
        )
        FROM public.club_poll_options cpo
        WHERE cpo.poll_id = cp.id
      ) AS options,
      -- Caller's vote on this poll
      (
        SELECT cv2.option_id
        FROM public.club_votes cv2
        WHERE cv2.poll_id = cp.id AND cv2.user_id = _uid
      ) AS my_vote_option_id
    FROM public.club_polls cp
    WHERE cp.club_id = p_club_id
  ) p;

  -- --------------------------------------------------------
  -- Build final response
  -- --------------------------------------------------------
  RETURN jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      -- Only expose invite_code to owner/admin
      'invite_code', CASE WHEN _my_membership.role IN ('owner', 'admin') THEN _club.invite_code ELSE NULL END,
      'created_at', _club.created_at
    ),
    'members', _members,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', _rails,
    'polls', _polls,
    'member_count', _member_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fetch_club_bundle(uuid) TO authenticated;

-- ==========================================================
-- 5. add_club_rail_item
-- ==========================================================

CREATE OR REPLACE FUNCTION public.add_club_rail_item(
  p_rail_id uuid,
  p_media_type text,
  p_media_id int,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _rail record;
  _club_id uuid;
  _is_member boolean;
  _is_admin boolean;
  _item_id uuid;
  _next_sort int;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Validate media_type
  IF p_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION 'INVALID_MEDIA_TYPE' USING ERRCODE = 'P0001';
  END IF;

  -- Find the rail and its club
  SELECT cr.id, cr.club_id, cr.is_locked
  INTO _rail
  FROM public.club_rails cr
  WHERE cr.id = p_rail_id;

  IF _rail IS NULL THEN
    RAISE EXCEPTION 'RAIL_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  _club_id := _rail.club_id;

  -- Verify caller is a member of the club
  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = _club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- If rail is locked, verify caller is admin/owner
  IF _rail.is_locked THEN
    SELECT EXISTS (
      SELECT 1 FROM public.club_members
      WHERE club_id = _club_id AND user_id = _uid AND role IN ('owner', 'admin')
    ) INTO _is_admin;

    IF NOT _is_admin THEN
      RAISE EXCEPTION 'RAIL_LOCKED: only admin or owner can add to locked rails' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Verify media exists
  IF p_media_type = 'ANIME' THEN
    IF NOT EXISTS (SELECT 1 FROM public.anime WHERE id = p_media_id) THEN
      RAISE EXCEPTION 'MEDIA_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
  ELSIF p_media_type = 'MANGA' THEN
    IF NOT EXISTS (SELECT 1 FROM public.manga WHERE id = p_media_id) THEN
      RAISE EXCEPTION 'MEDIA_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Validate note length
  IF p_note IS NOT NULL AND char_length(p_note) > 280 THEN
    RAISE EXCEPTION 'NOTE_TOO_LONG: max 280 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Compute next sort_order
  SELECT COALESCE(max(sort_order), -1) + 1 INTO _next_sort
  FROM public.club_rail_items
  WHERE rail_id = p_rail_id;

  -- Insert the item (UNIQUE constraint handles duplicates)
  BEGIN
    INSERT INTO public.club_rail_items (rail_id, media_type, media_id, added_by, sort_order, note)
    VALUES (p_rail_id, p_media_type, p_media_id, _uid, _next_sort, p_note)
    RETURNING id INTO _item_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'DUPLICATE_ITEM: this media is already in the rail' USING ERRCODE = 'P0001';
  END;

  RETURN jsonb_build_object(
    'item_id', _item_id,
    'sort_order', _next_sort
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_club_rail_item(uuid, text, int, text) TO authenticated;

-- ==========================================================
-- 6. cast_club_vote
-- ==========================================================

CREATE OR REPLACE FUNCTION public.cast_club_vote(p_poll_id uuid, p_option_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid;
  _poll record;
  _club_id uuid;
  _is_member boolean;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Find the poll
  SELECT cp.id, cp.club_id, cp.is_closed, cp.closes_at
  INTO _poll
  FROM public.club_polls cp
  WHERE cp.id = p_poll_id;

  IF _poll IS NULL THEN
    RAISE EXCEPTION 'POLL_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  _club_id := _poll.club_id;

  -- Verify caller is a member
  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = _club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Check poll is open
  IF _poll.is_closed THEN
    RAISE EXCEPTION 'POLL_CLOSED' USING ERRCODE = 'P0001';
  END IF;

  IF _poll.closes_at IS NOT NULL AND _poll.closes_at <= now() THEN
    RAISE EXCEPTION 'POLL_CLOSED' USING ERRCODE = 'P0001';
  END IF;

  -- Verify the option belongs to this poll
  IF NOT EXISTS (
    SELECT 1 FROM public.club_poll_options WHERE id = p_option_id AND poll_id = p_poll_id
  ) THEN
    RAISE EXCEPTION 'INVALID_OPTION' USING ERRCODE = 'P0001';
  END IF;

  -- Delete any existing vote by this user on this poll (single-choice re-vote)
  DELETE FROM public.club_votes WHERE poll_id = p_poll_id AND user_id = _uid;

  -- Insert new vote
  INSERT INTO public.club_votes (poll_id, option_id, user_id)
  VALUES (p_poll_id, p_option_id, _uid);

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cast_club_vote(uuid, uuid) TO authenticated;

commit;
