-- Capture send_club_message and fetch_club_messages into migration history
CREATE OR REPLACE FUNCTION public.send_club_message(p_club_id uuid, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid;
  _is_member boolean;
  _clean_text text;
  _rate_hits int;
  _msg_id uuid;
  _created_at timestamptz;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Membership check
  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = p_club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  -- Sanitize: strip control chars except newline
  _clean_text := regexp_replace(trim(p_text), '[\x00-\x09\x0B-\x1F\x7F]', '', 'g');

  IF _clean_text IS NULL OR char_length(_clean_text) = 0 THEN
    RAISE EXCEPTION 'EMPTY_MESSAGE' USING ERRCODE = 'P0001';
  END IF;
  IF char_length(_clean_text) > 280 THEN
    RAISE EXCEPTION 'MESSAGE_TOO_LONG: max 280 characters' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 20 messages per minute per user
  _rate_hits := public.rate_limit_hit('club_msg:' || _uid::text, 60);
  IF _rate_hits > 20 THEN
    RAISE EXCEPTION 'RATE_LIMITED: too many messages, slow down' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_messages (club_id, user_id, text)
  VALUES (p_club_id, _uid, _clean_text)
  RETURNING id, created_at INTO _msg_id, _created_at;

  RETURN jsonb_build_object(
    'message_id', _msg_id,
    'created_at', _created_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fetch_club_messages(p_club_id uuid, p_limit integer DEFAULT 50, p_before timestamp with time zone DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid;
  _is_member boolean;
  _result jsonb;
  _effective_limit int;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.club_members WHERE club_id = p_club_id AND user_id = _uid
  ) INTO _is_member;

  IF NOT _is_member THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  _effective_limit := LEAST(GREATEST(p_limit, 1), 100);

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'created_at') ASC), '[]'::jsonb)
  INTO _result
  FROM (
    SELECT jsonb_build_object(
      'id', cm.id,
      'user_id', cm.user_id,
      'display_name', COALESCE(p.display_name, NULL),
      'text', cm.text,
      'created_at', cm.created_at
    ) AS row_data
    FROM public.club_messages cm
    LEFT JOIN public.profiles p ON p.id = cm.user_id
    WHERE cm.club_id = p_club_id
      AND (p_before IS NULL OR cm.created_at < p_before)
    ORDER BY cm.created_at DESC
    LIMIT _effective_limit
  ) sub;

  RETURN _result;
END;
$function$;;
