-- Add rate limit + club cap to create_club
CREATE OR REPLACE FUNCTION public.create_club(p_name text, p_description text DEFAULT NULL::text, p_sharing_level text DEFAULT 'status'::text)
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
  _hits integer;
  _club_count integer;
BEGIN
  -- Auth gate
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 5 club creations per hour
  _hits := rate_limit_hit('club_create:' || _uid::text, 3600);
  IF _hits > 5 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  -- Club membership cap: max 20 clubs per user
  SELECT count(*) INTO _club_count FROM public.club_members WHERE user_id = _uid;
  IF _club_count >= 20 THEN
    RAISE EXCEPTION 'TOO_MANY_CLUBS' USING ERRCODE = 'P0001';
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
$function$;;
