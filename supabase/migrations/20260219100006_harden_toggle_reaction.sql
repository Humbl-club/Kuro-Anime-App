-- Replace toggle_club_reaction with rate limit + emoji allowlist
CREATE OR REPLACE FUNCTION public.toggle_club_reaction(p_rail_item_id uuid, p_emoji text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

  -- Emoji allowlist (fire/heart/eyes/100)
  IF p_emoji NOT IN ('🔥', '❤️', '👀', '💯') THEN
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
