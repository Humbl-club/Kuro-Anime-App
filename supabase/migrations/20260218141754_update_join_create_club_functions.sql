-- Capture join_club (with CLUB_ARCHIVED check), update create_club with description validation, drop validate_club_invite

CREATE OR REPLACE FUNCTION public.join_club(p_invite_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.create_club(p_name text, p_description text DEFAULT NULL, p_sharing_level text DEFAULT 'status')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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

  -- Validate description
  IF p_description IS NOT NULL THEN
    p_description := regexp_replace(trim(p_description), '[\x00-\x09\x0B-\x1F\x7F]', '', 'g');
    IF char_length(p_description) > 500 THEN
      RAISE EXCEPTION 'DESCRIPTION_TOO_LONG: max 500 characters' USING ERRCODE = 'P0001';
    END IF;
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
$function$;

-- Drop superseded validate_club_invite (all logic now in join_club)
DROP FUNCTION IF EXISTS public.validate_club_invite(text);;
