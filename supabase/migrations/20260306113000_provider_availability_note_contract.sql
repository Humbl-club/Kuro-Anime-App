-- Extend provider availability RPC output so the client can render
-- fact-based audio/subtitle notes without inferring missing fields.

BEGIN;

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
                    WHEN COALESCE(array_length(pa_audio.audio_langs, 1), 0) > 0 THEN pa_audio.audio_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                FROM public.provider_availability pa_audio
                WHERE pa_audio.media_type = item_row.media_type
                  AND pa_audio.media_id = item_row.media_id
                  AND pa_audio.provider_slug = pa.provider_slug

                UNION

                SELECT unnest(
                  CASE
                    WHEN COALESCE(array_length(pa_sub.subtitle_langs, 1), 0) > 0 THEN pa_sub.subtitle_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                FROM public.provider_availability pa_sub
                WHERE pa_sub.media_type = item_row.media_type
                  AND pa_sub.media_id = item_row.media_id
                  AND pa_sub.provider_slug = pa.provider_slug
              ) provider_languages
              WHERE p_include_unknown OR lang <> 'unknown'
            ) final_langs
          ), '[]'::jsonb),
          'audio_languages', COALESCE((
            SELECT jsonb_agg(lang ORDER BY lang)
            FROM (
              SELECT DISTINCT lang
              FROM (
                SELECT unnest(
                  CASE
                    WHEN COALESCE(array_length(pa_audio.audio_langs, 1), 0) > 0 THEN pa_audio.audio_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                FROM public.provider_availability pa_audio
                WHERE pa_audio.media_type = item_row.media_type
                  AND pa_audio.media_id = item_row.media_id
                  AND pa_audio.provider_slug = pa.provider_slug
              ) audio_langs
              WHERE p_include_unknown OR lang <> 'unknown'
            ) final_audio_langs
          ), '[]'::jsonb),
          'subtitle_languages', COALESCE((
            SELECT jsonb_agg(lang ORDER BY lang)
            FROM (
              SELECT DISTINCT lang
              FROM (
                SELECT unnest(
                  CASE
                    WHEN COALESCE(array_length(pa_sub.subtitle_langs, 1), 0) > 0 THEN pa_sub.subtitle_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                FROM public.provider_availability pa_sub
                WHERE pa_sub.media_type = item_row.media_type
                  AND pa_sub.media_id = item_row.media_id
                  AND pa_sub.provider_slug = pa.provider_slug
              ) subtitle_langs
              WHERE p_include_unknown OR lang <> 'unknown'
            ) final_subtitle_langs
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
                  pa_audio.country_code
                FROM public.provider_availability pa_audio
                CROSS JOIN LATERAL unnest(
                  CASE
                    WHEN COALESCE(array_length(pa_audio.audio_langs, 1), 0) > 0 THEN pa_audio.audio_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                WHERE pa_audio.media_type = item_row.media_type
                  AND pa_audio.media_id = item_row.media_id
                  AND pa_audio.provider_slug = pa.provider_slug
                  AND (p_include_unknown OR lang <> 'unknown')
              ) rows_by_lang
              GROUP BY lang
            ) lang_group
          ), '{}'::jsonb),
          'countries_by_sub_lang', COALESCE((
            SELECT jsonb_object_agg(lang_group.lang, lang_group.countries)
            FROM (
              SELECT
                lang,
                jsonb_agg(country_code ORDER BY country_code) AS countries
              FROM (
                SELECT DISTINCT
                  lang,
                  pa_sub.country_code
                FROM public.provider_availability pa_sub
                CROSS JOIN LATERAL unnest(
                  CASE
                    WHEN COALESCE(array_length(pa_sub.subtitle_langs, 1), 0) > 0 THEN pa_sub.subtitle_langs
                    ELSE ARRAY['unknown']::text[]
                  END
                ) AS lang
                WHERE pa_sub.media_type = item_row.media_type
                  AND pa_sub.media_id = item_row.media_id
                  AND pa_sub.provider_slug = pa.provider_slug
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

COMMIT;
