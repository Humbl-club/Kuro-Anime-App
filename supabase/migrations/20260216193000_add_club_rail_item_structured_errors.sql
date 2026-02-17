-- add_club_rail_item: emit structured machine-readable error codes
-- in DETAIL so clients can branch without parsing free-form messages.

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
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Unauthenticated',
      DETAIL = 'UNAUTHENTICATED';
  END IF;

  IF p_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Invalid media type',
      DETAIL = 'INVALID_MEDIA_TYPE';
  END IF;

  SELECT cr.id, cr.club_id, cr.is_locked
  INTO _rail
  FROM public.club_rails cr
  WHERE cr.id = p_rail_id;

  IF _rail IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Rail not found',
      DETAIL = 'RAIL_NOT_FOUND';
  END IF;

  _club_id := _rail.club_id;

  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = _club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Not a club member',
      DETAIL = 'NOT_A_MEMBER';
  END IF;

  IF _rail.is_locked THEN
    SELECT EXISTS (
      SELECT 1 FROM public.club_members
      WHERE club_id = _club_id AND user_id = _uid AND role IN ('owner', 'admin')
    ) INTO _is_admin;

    IF NOT _is_admin THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'Rail is locked',
        DETAIL = 'RAIL_LOCKED';
    END IF;
  END IF;

  IF p_media_type = 'ANIME' THEN
    IF NOT EXISTS (SELECT 1 FROM public.anime WHERE id = p_media_id) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'Media not found',
        DETAIL = 'MEDIA_NOT_FOUND';
    END IF;
  ELSIF p_media_type = 'MANGA' THEN
    IF NOT EXISTS (SELECT 1 FROM public.manga WHERE id = p_media_id) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'Media not found',
        DETAIL = 'MEDIA_NOT_FOUND';
    END IF;
  END IF;

  IF p_note IS NOT NULL AND char_length(p_note) > 280 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Note too long',
      DETAIL = 'NOTE_TOO_LONG';
  END IF;

  SELECT COALESCE(max(sort_order), -1) + 1 INTO _next_sort
  FROM public.club_rail_items
  WHERE rail_id = p_rail_id;

  BEGIN
    INSERT INTO public.club_rail_items (rail_id, media_type, media_id, added_by, sort_order, note)
    VALUES (p_rail_id, p_media_type, p_media_id, _uid, _next_sort, p_note)
    RETURNING id INTO _item_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'Duplicate rail item',
      DETAIL = 'DUPLICATE_ITEM';
  END;

  RETURN jsonb_build_object(
    'item_id', _item_id,
    'sort_order', _next_sort
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_club_rail_item(uuid, text, int, text) TO authenticated;
