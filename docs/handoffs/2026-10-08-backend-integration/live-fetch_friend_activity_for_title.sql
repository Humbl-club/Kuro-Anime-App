CREATE OR REPLACE FUNCTION public.fetch_friend_activity_for_title(p_media_type text, p_media_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

