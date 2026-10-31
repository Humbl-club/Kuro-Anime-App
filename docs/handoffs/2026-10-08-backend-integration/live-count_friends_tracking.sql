CREATE OR REPLACE FUNCTION public.count_friends_tracking(p_items text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

