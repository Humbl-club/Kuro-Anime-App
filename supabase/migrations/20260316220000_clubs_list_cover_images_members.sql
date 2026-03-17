-- ============================================================
-- Enrich fetch_my_clubs_enriched() with cover_images and
-- member_names for mosaic card rendering on the clubs list page.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fetch_my_clubs_enriched()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  result jsonb;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(jsonb_agg(row_data ORDER BY row_data->>'last_activity_at' DESC NULLS LAST), '[]'::jsonb)
  INTO result
  FROM (
    SELECT jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'sharing_level', c.sharing_level,
      'is_archived', c.is_archived,
      'created_at', c.created_at,
      'member_count', (SELECT count(*) FROM club_members cm2 WHERE cm2.club_id = c.id),
      'last_activity_at', GREATEST(
        (SELECT MAX(cri.created_at) FROM club_rail_items cri
         JOIN club_rails cr ON cr.id = cri.rail_id
         WHERE cr.club_id = c.id),
        (SELECT MAX(cp.created_at) FROM club_polls cp WHERE cp.club_id = c.id),
        (SELECT MAX(cv.created_at) FROM club_votes cv
         JOIN club_polls cp2 ON cp2.id = cv.poll_id
         WHERE cp2.club_id = c.id)
      ),
      'activity_preview', (
        SELECT CASE
          WHEN latest.source = 'item' THEN 'Added: ' || left(latest.label, 40)
          WHEN latest.source = 'poll' THEN 'Poll: ' || left(latest.label, 40)
          WHEN latest.source = 'vote' THEN 'Vote on: ' || left(latest.label, 40)
          ELSE NULL
        END
        FROM (
          SELECT 'item' AS source,
                 COALESCE(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') AS label,
                 cri2.created_at AS ts
          FROM club_rail_items cri2
          JOIN club_rails cr2 ON cr2.id = cri2.rail_id
          LEFT JOIN anime a ON cri2.media_type = 'ANIME' AND a.id = cri2.media_id
          LEFT JOIN manga m ON cri2.media_type = 'MANGA' AND m.id = cri2.media_id
          WHERE cr2.club_id = c.id
          UNION ALL
          SELECT 'poll' AS source, cp3.question AS label, cp3.created_at AS ts
          FROM club_polls cp3
          WHERE cp3.club_id = c.id
          UNION ALL
          SELECT 'vote' AS source, cp4.question AS label, cv2.created_at AS ts
          FROM club_votes cv2
          JOIN club_polls cp4 ON cp4.id = cv2.poll_id
          WHERE cp4.club_id = c.id
          ORDER BY ts DESC
          LIMIT 1
        ) latest
      ),
      'cover_images', (
        SELECT COALESCE(jsonb_agg(img_url), '[]'::jsonb)
        FROM (
          SELECT CASE
            WHEN cri3.media_type = 'ANIME' THEN a3.cover_image_medium
            WHEN cri3.media_type = 'MANGA' THEN m3.cover_image_medium
          END AS img_url
          FROM club_rail_items cri3
          JOIN club_rails cr3 ON cr3.id = cri3.rail_id
          LEFT JOIN anime a3 ON cri3.media_type = 'ANIME' AND a3.id = cri3.media_id
          LEFT JOIN manga m3 ON cri3.media_type = 'MANGA' AND m3.id = cri3.media_id
          WHERE cr3.club_id = c.id
            AND (a3.cover_image_medium IS NOT NULL OR m3.cover_image_medium IS NOT NULL)
          ORDER BY cri3.created_at DESC
          LIMIT 4
        ) imgs
      ),
      'member_names', (
        SELECT COALESCE(jsonb_agg(dn), '[]'::jsonb)
        FROM (
          SELECT COALESCE(NULLIF(TRIM(p.display_name), ''), 'Member') AS dn
          FROM club_members cm3
          LEFT JOIN profiles p ON p.id = cm3.user_id
          WHERE cm3.club_id = c.id
          ORDER BY cm3.joined_at ASC
          LIMIT 4
        ) names
      )
    ) AS row_data
    FROM clubs c
    JOIN club_members cm ON cm.club_id = c.id
    WHERE cm.user_id = uid AND c.is_archived = false
  ) enriched;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fetch_my_clubs_enriched() TO authenticated;
