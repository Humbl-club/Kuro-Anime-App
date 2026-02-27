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

  -- Block joining archived clubs
  IF _club.is_archived THEN
    RAISE EXCEPTION 'CLUB_ARCHIVED' USING ERRCODE = 'P0001';
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
$$;;
