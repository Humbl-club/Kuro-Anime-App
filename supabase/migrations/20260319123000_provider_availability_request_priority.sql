BEGIN;

ALTER TABLE public.provider_availability_refresh_state
  ADD COLUMN IF NOT EXISTS last_requested_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS request_reason text NOT NULL DEFAULT 'scheduled';

UPDATE public.provider_availability_refresh_state
SET
  last_requested_at = COALESCE(updated_at, next_refresh_at, now()),
  request_reason = CASE
    WHEN status IN ('pending', 'unresolved')
      AND COALESCE(last_error, '') IN ('detail_open', 'user_tap', 'on_demand', 'on_demand_open', 'scheduled')
      THEN last_error
    ELSE COALESCE(NULLIF(request_reason, ''), 'scheduled')
  END,
  last_error = CASE
    WHEN status IN ('pending', 'unresolved')
      AND COALESCE(last_error, '') IN ('detail_open', 'user_tap', 'on_demand', 'on_demand_open', 'scheduled')
      THEN NULL
    ELSE last_error
  END
WHERE true;

CREATE INDEX IF NOT EXISTS idx_provider_availability_refresh_request_priority
  ON public.provider_availability_refresh_state (status, request_reason, last_requested_at DESC, next_refresh_at ASC);

CREATE OR REPLACE FUNCTION public.get_provider_availability_refresh_candidates(
  p_limit int DEFAULT 100,
  p_force_media_type text DEFAULT NULL,
  p_force_media_id int DEFAULT NULL,
  p_stale_days int DEFAULT 30
)
RETURNS TABLE(media_type text, media_id int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_force_media_type IS NOT NULL AND p_force_media_id IS NOT NULL THEN
    RETURN QUERY
    SELECT upper(p_force_media_type), p_force_media_id;
    RETURN;
  END IF;

  RETURN QUERY
  WITH media_pool AS (
    SELECT DISTINCT el.media_type::text AS media_type, el.media_id::int AS media_id
    FROM public.external_links el
    WHERE el.is_disabled = false
  ),
  state AS (
    SELECT
      mp.media_type,
      mp.media_id,
      rs.status,
      rs.next_refresh_at,
      rs.last_refreshed_at,
      rs.last_requested_at,
      rs.request_reason,
      COALESCE(pa_stats.has_rows, false) AS has_rows,
      CASE
        WHEN rs.status = 'pending'
          AND rs.request_reason IN ('detail_open', 'user_tap')
          AND rs.last_requested_at >= now() - interval '15 minutes' THEN 0
        WHEN COALESCE(pa_stats.has_rows, false) = false THEN 1
        WHEN rs.status = 'unresolved'
          AND COALESCE(rs.next_refresh_at, now()) <= now() THEN 2
        WHEN COALESCE(rs.next_refresh_at, now()) <= now()
          OR rs.last_refreshed_at <= now() - make_interval(days => GREATEST(p_stale_days, 1)) THEN 3
        WHEN rs.id IS NULL OR rs.last_refreshed_at IS NULL THEN 4
        ELSE 99
      END AS priority
    FROM media_pool mp
    LEFT JOIN public.provider_availability_refresh_state rs
      ON rs.media_type = mp.media_type
     AND rs.media_id = mp.media_id
     AND rs.source_name = 'watchmode'
    LEFT JOIN LATERAL (
      SELECT true AS has_rows
      FROM public.provider_availability pa
      WHERE pa.media_type = mp.media_type
        AND pa.media_id = mp.media_id
      LIMIT 1
    ) pa_stats ON true
  )
  SELECT s.media_type, s.media_id
  FROM state s
  WHERE s.priority < 99
  ORDER BY
    s.priority ASC,
    CASE
      WHEN s.priority = 0 THEN s.last_requested_at
      ELSE COALESCE(s.next_refresh_at, to_timestamp(0))
    END ASC,
    s.media_type ASC,
    s.media_id ASC
  LIMIT GREATEST(COALESCE(p_limit, 100), 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_media_availability_refresh(
  p_media_type text,
  p_media_id int,
  p_reason text DEFAULT 'on_demand'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  mt text := upper(trim(COALESCE(p_media_type, '')));
  normalized_reason text := COALESCE(NULLIF(trim(p_reason), ''), 'scheduled');
BEGIN
  IF mt NOT IN ('ANIME', 'MANGA') THEN
    RETURN jsonb_build_object('error', 'invalid_media_type');
  END IF;

  INSERT INTO public.provider_availability_refresh_state (
    media_type,
    media_id,
    source_name,
    status,
    next_refresh_at,
    retry_count,
    updated_at,
    last_requested_at,
    request_reason,
    last_error
  ) VALUES (
    mt,
    p_media_id,
    'watchmode',
    'pending',
    now(),
    0,
    now(),
    now(),
    normalized_reason,
    NULL
  )
  ON CONFLICT (media_type, media_id, source_name)
  DO UPDATE SET
    status = 'pending',
    next_refresh_at = now(),
    updated_at = now(),
    last_requested_at = now(),
    request_reason = normalized_reason;

  RETURN jsonb_build_object(
    'success', true,
    'media_type', mt,
    'media_id', p_media_id,
    'queued_at', now(),
    'request_reason', normalized_reason
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_provider_availability_refresh_queue_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH pending AS (
    SELECT *
    FROM public.provider_availability_refresh_state rs
    WHERE rs.source_name = 'watchmode'
      AND rs.status = 'pending'
  ),
  reason_counts AS (
    SELECT request_reason, count(*)::int AS count
    FROM pending
    GROUP BY request_reason
  )
  SELECT jsonb_build_object(
    'urgent_pending_count',
    COALESCE((
      SELECT count(*)::int
      FROM pending
      WHERE request_reason IN ('detail_open', 'user_tap')
        AND last_requested_at >= now() - interval '15 minutes'
    ), 0),
    'oldest_pending_request_age_seconds',
    COALESCE((
      SELECT floor(extract(epoch FROM (now() - min(last_requested_at))))::int
      FROM pending
    ), 0),
    'request_reason_mix',
    COALESCE((
      SELECT jsonb_object_agg(request_reason, count ORDER BY request_reason)
      FROM reason_counts
    ), '{}'::jsonb)
  );
$$;

REVOKE ALL ON FUNCTION public.get_provider_availability_refresh_queue_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_provider_availability_refresh_queue_summary() TO service_role;

COMMIT;
