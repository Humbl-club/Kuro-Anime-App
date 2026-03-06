-- ============================================================
-- Streaming Availability Country + Language v1 (same launch train)
-- - provider_source_map: local media -> source identity map
-- - provider_availability: normalized provider/country rows with language arrays
-- - provider_availability_refresh_state: queue + freshness/backoff state
-- - RPCs for batch read/detail/status/queueing
-- ============================================================

BEGIN;

-- ============================================================
-- 1) Source identity mapping
-- ============================================================
CREATE TABLE IF NOT EXISTS public.provider_source_map (
  id bigserial PRIMARY KEY,
  media_type text NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id int NOT NULL,
  source_name text NOT NULL DEFAULT 'watchmode',
  source_media_id text NOT NULL,
  match_method text NOT NULL CHECK (match_method IN ('id', 'title_year', 'manual')),
  confidence numeric(4,3) NOT NULL DEFAULT 0.000,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'unresolved')),
  last_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (media_type, media_id, source_name),
  UNIQUE (source_name, source_media_id, media_type)
);

CREATE INDEX IF NOT EXISTS idx_provider_source_map_status
  ON public.provider_source_map (source_name, status, updated_at DESC);

ALTER TABLE public.provider_source_map ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2) Provider availability rows
-- ============================================================
CREATE TABLE IF NOT EXISTS public.provider_availability (
  id bigserial PRIMARY KEY,
  media_type text NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id int NOT NULL,
  provider_slug text NOT NULL REFERENCES public.streaming_services(slug),
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  availability_type text NOT NULL DEFAULT 'subscription',
  audio_langs text[] NOT NULL DEFAULT '{}',
  subtitle_langs text[] NOT NULL DEFAULT '{}',
  deep_link_url text,
  web_url text,
  source_name text NOT NULL DEFAULT 'watchmode',
  source_offer_id text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (media_type, media_id, provider_slug, country_code, availability_type)
);

CREATE INDEX IF NOT EXISTS idx_provider_availability_media
  ON public.provider_availability (media_type, media_id);

CREATE INDEX IF NOT EXISTS idx_provider_availability_provider_country
  ON public.provider_availability (provider_slug, country_code);

CREATE INDEX IF NOT EXISTS idx_provider_availability_last_seen
  ON public.provider_availability (last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_provider_availability_audio_gin
  ON public.provider_availability USING gin (audio_langs);

CREATE INDEX IF NOT EXISTS idx_provider_availability_subtitle_gin
  ON public.provider_availability USING gin (subtitle_langs);

ALTER TABLE public.provider_availability ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3) Refresh queue/state
-- ============================================================
CREATE TABLE IF NOT EXISTS public.provider_availability_refresh_state (
  id bigserial PRIMARY KEY,
  media_type text NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id int NOT NULL,
  source_name text NOT NULL DEFAULT 'watchmode',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'ok', 'error', 'unresolved')),
  last_refreshed_at timestamptz,
  next_refresh_at timestamptz NOT NULL DEFAULT now(),
  retry_count int NOT NULL DEFAULT 0,
  last_error text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (media_type, media_id, source_name)
);

CREATE INDEX IF NOT EXISTS idx_provider_availability_refresh_due
  ON public.provider_availability_refresh_state (status, next_refresh_at);

ALTER TABLE public.provider_availability_refresh_state ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4) Queue helper for local worker (service role use)
-- ============================================================
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
      COALESCE(pa_stats.has_rows, false) AS has_rows,
      CASE
        WHEN COALESCE(pa_stats.has_rows, false) = false THEN 1
        WHEN rs.status = 'unresolved' AND COALESCE(rs.next_refresh_at, now()) <= now() THEN 4
        WHEN rs.id IS NULL THEN 2
        WHEN COALESCE(rs.next_refresh_at, now()) <= now() THEN 3
        WHEN rs.last_refreshed_at IS NULL THEN 2
        WHEN rs.last_refreshed_at <= now() - make_interval(days => GREATEST(p_stale_days, 1)) THEN 3
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
    COALESCE(s.next_refresh_at, to_timestamp(0)) ASC,
    s.media_type ASC,
    s.media_id ASC
  LIMIT GREATEST(COALESCE(p_limit, 100), 1);
END;
$$;

REVOKE ALL ON FUNCTION public.get_provider_availability_refresh_candidates(int, text, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_provider_availability_refresh_candidates(int, text, int, int) TO service_role;

-- ============================================================
-- 5) batch_provider_availability_for_media_v2
-- ============================================================
CREATE OR REPLACE FUNCTION public.batch_provider_availability_for_media_v2(
  p_items text,
  p_audio_lang text DEFAULT NULL,
  p_sub_lang text DEFAULT NULL,
  p_include_unknown boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  req jsonb;
  result jsonb := '[]'::jsonb;
  item_row record;
  providers jsonb;
  normalized_audio text := NULLIF(lower(trim(COALESCE(p_audio_lang, ''))), '');
  normalized_sub text := NULLIF(lower(trim(COALESCE(p_sub_lang, ''))), '');
BEGIN
  BEGIN
    req := p_items::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', 'invalid_json');
  END;

  FOR item_row IN
    SELECT
      upper((elem->>'media_type')::text) AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(req) AS elem
  LOOP
    SELECT COALESCE(jsonb_agg(provider_obj ORDER BY provider_priority, provider_display_name), '[]'::jsonb)
      INTO providers
    FROM (
      SELECT
        pa.provider_slug,
        MIN(ss.display_name) AS provider_display_name,
        MIN(ss.priority) AS provider_priority,
        MIN(COALESCE(pa.web_url, pa.deep_link_url)) AS provider_url,
        bool_or(pa.last_seen_at < now() - interval '30 days') AS is_stale,
        COALESCE((
          SELECT jsonb_agg(lang ORDER BY lang)
          FROM (
            SELECT DISTINCT lang
            FROM (
              SELECT unnest(
                CASE
                  WHEN COALESCE(array_length(pa2.audio_langs, 1), 0) > 0 THEN pa2.audio_langs
                  ELSE ARRAY['unknown']::text[]
                END
              ) AS lang
              FROM public.provider_availability pa2
              WHERE pa2.media_type = item_row.media_type
                AND pa2.media_id = item_row.media_id
                AND pa2.provider_slug = pa.provider_slug
            ) languages
            WHERE p_include_unknown OR lang <> 'unknown'
          ) unique_langs
        ), '[]'::jsonb) AS languages,
        COALESCE((
          SELECT jsonb_object_agg(lang_group.lang, lang_group.countries)
          FROM (
            SELECT
              lang,
              jsonb_agg(country_code ORDER BY country_code) AS countries
            FROM (
              SELECT DISTINCT
                lang,
                pa3.country_code
              FROM public.provider_availability pa3
              CROSS JOIN LATERAL unnest(
                CASE
                  WHEN COALESCE(array_length(pa3.audio_langs, 1), 0) > 0 THEN pa3.audio_langs
                  ELSE ARRAY['unknown']::text[]
                END
              ) AS lang
              WHERE pa3.media_type = item_row.media_type
                AND pa3.media_id = item_row.media_id
                AND pa3.provider_slug = pa.provider_slug
                AND (p_include_unknown OR lang <> 'unknown')
            ) per_lang_country
            GROUP BY lang
          ) lang_group
        ), '{}'::jsonb) AS countries_by_audio_lang,
        jsonb_build_object(
          'slug', pa.provider_slug,
          'display_name', MIN(ss.display_name),
          'url', MIN(COALESCE(pa.web_url, pa.deep_link_url)),
          'languages', COALESCE((
            SELECT jsonb_agg(lang ORDER BY lang)
            FROM (
              SELECT DISTINCT lang
              FROM (
                SELECT unnest(
                  CASE
                    WHEN COALESCE(array_length(pa4.audio_langs, 1), 0) > 0 THEN pa4.audio_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                FROM public.provider_availability pa4
                WHERE pa4.media_type = item_row.media_type
                  AND pa4.media_id = item_row.media_id
                  AND pa4.provider_slug = pa.provider_slug
              ) provider_languages
              WHERE p_include_unknown OR lang <> 'unknown'
            ) final_langs
          ), '[]'::jsonb),
          'countries_by_audio_lang', COALESCE((
            SELECT jsonb_object_agg(lang_group.lang, lang_group.countries)
            FROM (
              SELECT
                lang,
                jsonb_agg(country_code ORDER BY country_code) AS countries
              FROM (
                SELECT DISTINCT
                  lang,
                  pa5.country_code
                FROM public.provider_availability pa5
                CROSS JOIN LATERAL unnest(
                  CASE
                    WHEN COALESCE(array_length(pa5.audio_langs, 1), 0) > 0 THEN pa5.audio_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                WHERE pa5.media_type = item_row.media_type
                  AND pa5.media_id = item_row.media_id
                  AND pa5.provider_slug = pa.provider_slug
                  AND (p_include_unknown OR lang <> 'unknown')
              ) rows_by_lang
              GROUP BY lang
            ) lang_group
          ), '{}'::jsonb),
          'is_stale', bool_or(pa.last_seen_at < now() - interval '30 days')
        ) AS provider_obj
      FROM public.provider_availability pa
      JOIN public.streaming_services ss
        ON ss.slug = pa.provider_slug
       AND ss.is_active = true
      WHERE pa.media_type = item_row.media_type
        AND pa.media_id = item_row.media_id
        AND (
          normalized_audio IS NULL
          OR pa.audio_langs @> ARRAY[normalized_audio]::text[]
          OR (p_include_unknown AND COALESCE(array_length(pa.audio_langs, 1), 0) = 0)
        )
        AND (
          normalized_sub IS NULL
          OR pa.subtitle_langs @> ARRAY[normalized_sub]::text[]
          OR (p_include_unknown AND COALESCE(array_length(pa.subtitle_langs, 1), 0) = 0)
        )
      GROUP BY pa.provider_slug
    ) provider_rows;

    result := result || jsonb_build_array(
      jsonb_build_object(
        'media_type', item_row.media_type,
        'media_id', item_row.media_id,
        'providers', COALESCE(providers, '[]'::jsonb)
      )
    );
  END LOOP;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.batch_provider_availability_for_media_v2(text, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_provider_availability_for_media_v2(text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.batch_provider_availability_for_media_v2(text, text, text, boolean) TO service_role;

-- ============================================================
-- 6) get_media_provider_availability_detail
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_media_provider_availability_detail(
  p_media_type text,
  p_media_id int,
  p_audio_lang text DEFAULT NULL,
  p_sub_lang text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payload text;
  batched jsonb;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object('media_type', upper(p_media_type), 'media_id', p_media_id)
  )::text;

  batched := public.batch_provider_availability_for_media_v2(payload, p_audio_lang, p_sub_lang, true);
  RETURN COALESCE(batched->0, jsonb_build_object('media_type', upper(p_media_type), 'media_id', p_media_id, 'providers', '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.get_media_provider_availability_detail(text, int, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_media_provider_availability_detail(text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_media_provider_availability_detail(text, int, text, text) TO service_role;

-- ============================================================
-- 7) enqueue_media_availability_refresh
-- ============================================================
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
    last_error
  ) VALUES (
    mt,
    p_media_id,
    'watchmode',
    'pending',
    now(),
    0,
    now(),
    p_reason
  )
  ON CONFLICT (media_type, media_id, source_name)
  DO UPDATE SET
    status = CASE
      WHEN provider_availability_refresh_state.status = 'ok' THEN 'pending'
      ELSE provider_availability_refresh_state.status
    END,
    next_refresh_at = now(),
    updated_at = now(),
    last_error = p_reason;

  RETURN jsonb_build_object(
    'success', true,
    'media_type', mt,
    'media_id', p_media_id,
    'queued_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_media_availability_refresh(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_media_availability_refresh(text, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_media_availability_refresh(text, int, text) TO service_role;

-- ============================================================
-- 8) get_media_availability_status
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_media_availability_status(
  p_media_type text,
  p_media_id int
)
RETURNS TABLE(
  has_rows boolean,
  status text,
  last_refreshed_at timestamptz,
  next_refresh_at timestamptz,
  stale_days int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH row_count AS (
    SELECT count(*)::int AS cnt
    FROM public.provider_availability pa
    WHERE pa.media_type = upper(p_media_type)
      AND pa.media_id = p_media_id
  ),
  refresh AS (
    SELECT
      rs.status,
      rs.last_refreshed_at,
      rs.next_refresh_at
    FROM public.provider_availability_refresh_state rs
    WHERE rs.media_type = upper(p_media_type)
      AND rs.media_id = p_media_id
      AND rs.source_name = 'watchmode'
    LIMIT 1
  )
  SELECT
    (rc.cnt > 0) AS has_rows,
    COALESCE(r.status, CASE WHEN rc.cnt > 0 THEN 'ok' ELSE 'pending' END) AS status,
    r.last_refreshed_at,
    r.next_refresh_at,
    CASE
      WHEN r.last_refreshed_at IS NULL THEN NULL
      ELSE GREATEST(0, floor(extract(epoch from (now() - r.last_refreshed_at)) / 86400)::int)
    END AS stale_days
  FROM row_count rc
  LEFT JOIN refresh r ON true;
$$;

REVOKE ALL ON FUNCTION public.get_media_availability_status(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_media_availability_status(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_media_availability_status(text, int) TO service_role;

COMMIT;
