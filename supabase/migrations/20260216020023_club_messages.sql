
-- ============================================================
-- Club Messages: ephemeral chat for clubs
-- - 280 char max, auto-pruned after 30 days
-- - Rate limited: 20 msgs/min per user
-- - RLS: member-gated SELECT/INSERT, self-only DELETE
-- ============================================================

BEGIN;

-- Table
CREATE TABLE IF NOT EXISTS public.club_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  text text NOT NULL CHECK (char_length(text) >= 1 AND char_length(text) <= 280),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_club_messages_club_created
  ON public.club_messages (club_id, created_at DESC);

-- RLS
ALTER TABLE public.club_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY club_messages_select_member ON public.club_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.club_members cm
      WHERE cm.club_id = club_messages.club_id AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY club_messages_insert_member ON public.club_messages
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.club_members cm
      WHERE cm.club_id = club_messages.club_id AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY club_messages_delete_own ON public.club_messages
  FOR DELETE USING (auth.uid() = user_id);

-- Add to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.club_messages;

-- RPC: send_club_message
CREATE OR REPLACE FUNCTION public.send_club_message(p_club_id uuid, p_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION public.send_club_message(uuid, text) TO authenticated;

-- RPC: fetch_club_messages (paginated, newest first)
CREATE OR REPLACE FUNCTION public.fetch_club_messages(
  p_club_id uuid,
  p_limit int DEFAULT 50,
  p_before timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION public.fetch_club_messages(uuid, int, timestamptz) TO authenticated;

-- Cron: prune messages older than 30 days (daily at 3 AM UTC)
SELECT cron.schedule(
  'prune_club_messages',
  '0 3 * * *',
  $$DELETE FROM public.club_messages WHERE created_at < now() - interval '30 days'$$
);

-- GDPR: add club_messages to delete_user_concierge_data
-- (Already handled by FK CASCADE on user_id, but adding explicit for completeness)

COMMIT;
;
