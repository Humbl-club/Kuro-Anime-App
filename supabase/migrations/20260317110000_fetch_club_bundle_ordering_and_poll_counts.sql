-- ============================================================
-- Tune fetch_club_bundle: deterministic ordering + poll count aggregation
--
-- Performance/consistency changes:
--   1. Add deterministic tie-breakers to JSON aggregation ordering
--   2. Aggregate poll option vote counts per poll (instead of per-option count subqueries)
--   3. Preserve existing RPC contract/shape
-- ============================================================

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
  IF _club_sharing_rank = 0 THEN
    -- 'private': only return the caller's own membership
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id AND cm.user_id = _uid
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  ELSIF _member_count < 3 THEN
    -- H1: fewer than 3 members — only own data
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id AND cm.user_id = _uid
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  ELSE
    -- 'status' or 'progress': return all members
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  END IF;

  _members := COALESCE(_members, '[]'::jsonb);

  -- --------------------------------------------------------
  -- RAILS + ITEMS with media join + per-item aggregates + reactions
  -- --------------------------------------------------------
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'title', r.title,
      'description', r.description,
      'is_locked', r.is_locked,
      'sort_order', r.sort_order,
      'created_by', r.created_by,
      'items', COALESCE(r.items, '[]'::jsonb)
    ) ORDER BY r.sort_order, r.id
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
            'episode_count', enriched.episode_count,
            'chapter_count', enriched.chapter_count,
            'my_status', enriched.my_status,
            'my_progress', enriched.my_progress,
            'my_rating', enriched.my_rating,
            'member_status_counts', enriched.member_status_counts,
            'member_statuses', enriched.member_statuses,
            'reactions', enriched.reactions,
            'my_reactions', enriched.my_reactions
          ) ORDER BY enriched.sort_order, enriched.item_id
        )
        FROM (
          SELECT
            cri.id AS item_id,
            cri.media_type,
            cri.media_id,
            cri.sort_order,
            cri.note,
            cri.added_by,
            -- Media display fields via LEFT JOIN
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
            CASE WHEN cri.media_type = 'ANIME' THEN a.episodes ELSE NULL END AS episode_count,
            CASE WHEN cri.media_type = 'MANGA' THEN m.chapters ELSE NULL END AS chapter_count,
            -- Caller's own status/progress
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
            -- Per-member status for this item
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN NULL
              ELSE (
                SELECT jsonb_agg(jsonb_build_object(
                  'user_id', ms.user_id,
                  'display_name', ms.display_name,
                  'status', ms.list_type,
                  'progress', CASE WHEN _club_sharing_rank >= 2 THEN ms.progress ELSE NULL END,
                  'updated_at', ms.updated_at
                ) ORDER BY ms.updated_at DESC NULLS LAST, ms.user_id)
                FROM (
                  SELECT cm4.user_id, nullif(trim(coalesce(p4.display_name, '')), '') AS display_name, ul4.list_type, ul4.progress, ul4.updated_at
                  FROM public.club_members cm4
                  LEFT JOIN public.profiles p4 ON p4.id = cm4.user_id
                  JOIN LATERAL (
                    SELECT CASE
                      WHEN cm4.sharing_level IS NULL THEN _club_sharing_rank
                      WHEN public.sharing_level_rank(cm4.sharing_level) < _club_sharing_rank
                        THEN public.sharing_level_rank(cm4.sharing_level)
                      ELSE _club_sharing_rank
                    END AS eff_rank
                  ) eff4 ON true
                  LEFT JOIN LATERAL (
                    SELECT aul4.list_type, aul4.progress, aul4.updated_at FROM public.anime_user_lists aul4
                    WHERE cri.media_type = 'ANIME' AND aul4.user_id = cm4.user_id::text AND aul4.anime_id = cri.media_id
                    UNION ALL
                    SELECT mul4.list_type, mul4.progress, mul4.updated_at FROM public.manga_user_lists mul4
                    WHERE cri.media_type = 'MANGA' AND mul4.user_id = cm4.user_id::text AND mul4.manga_id = cri.media_id
                  ) ul4 ON true
                  WHERE cm4.club_id = p_club_id AND eff4.eff_rank >= 1 AND ul4.list_type IS NOT NULL
                ) ms
              )
            END AS member_statuses,
            -- Reactions: anonymous aggregate counts {fire: 3, heart: 1}
            (
              SELECT COALESCE(jsonb_object_agg(rc.emoji, rc.cnt), '{}'::jsonb)
              FROM (
                SELECT r2.emoji, count(*) AS cnt
                FROM public.club_rail_item_reactions r2
                WHERE r2.rail_item_id = cri.id
                GROUP BY r2.emoji
              ) rc
            ) AS reactions,
            -- My reactions: ["fire", "heart"]
            (
              SELECT COALESCE(jsonb_agg(r3.emoji), '[]'::jsonb)
              FROM public.club_rail_item_reactions r3
              WHERE r3.rail_item_id = cri.id AND r3.user_id = _uid
            ) AS my_reactions
          FROM public.club_rail_items cri
          LEFT JOIN public.anime a ON cri.media_type = 'ANIME' AND a.id = cri.media_id
          LEFT JOIN public.manga m ON cri.media_type = 'MANGA' AND m.id = cri.media_id
          LEFT JOIN public.anime_user_lists my_aul
            ON cri.media_type = 'ANIME' AND my_aul.user_id = _uid::text AND my_aul.anime_id = cri.media_id
          LEFT JOIN public.manga_user_lists my_mul
            ON cri.media_type = 'MANGA' AND my_mul.user_id = _uid::text AND my_mul.manga_id = cri.media_id
          WHERE cri.rail_id = cr.id
          ORDER BY cri.sort_order, cri.id
          LIMIT 50
        ) enriched
      ) AS items
    FROM public.club_rails cr
    WHERE cr.club_id = p_club_id
  ) r;

  -- --------------------------------------------------------
  -- POLLS + OPTIONS + VOTE COUNTS
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
    ) ORDER BY p.is_closed ASC, p.created_at DESC, p.id DESC
  ), '[]'::jsonb)
  INTO _polls
  FROM (
    SELECT
      cp.id, cp.question, cp.is_closed, cp.closes_at, cp.created_by, cp.created_at,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', option_rows.id,
            'label', option_rows.label,
            'media_type', option_rows.media_type,
            'media_id', option_rows.media_id,
            'sort_order', option_rows.sort_order,
            'vote_count', option_rows.vote_count
          ) ORDER BY option_rows.sort_order, option_rows.id
        )
        FROM (
          SELECT
            cpo.id,
            cpo.label,
            cpo.media_type,
            cpo.media_id,
            cpo.sort_order,
            COALESCE(vc.vote_count, 0)::int AS vote_count
          FROM public.club_poll_options cpo
          LEFT JOIN (
            SELECT cv.option_id, count(*) AS vote_count
            FROM public.club_votes cv
            WHERE cv.poll_id = cp.id
            GROUP BY cv.option_id
          ) vc ON vc.option_id = cpo.id
          WHERE cpo.poll_id = cp.id
        ) option_rows
      ) AS options,
      (
        SELECT cv2.option_id
        FROM public.club_votes cv2
        WHERE cv2.poll_id = cp.id AND cv2.user_id = _uid
        LIMIT 1
      ) AS my_vote_option_id
    FROM public.club_polls cp
    WHERE cp.club_id = p_club_id
    ORDER BY cp.is_closed ASC, cp.created_at DESC, cp.id DESC
    LIMIT 20
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
