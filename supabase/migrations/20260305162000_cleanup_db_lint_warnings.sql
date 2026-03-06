-- Clean up plpgsql lint warnings:
-- 1) remove unused provider_row variable in batch_providers_for_media
-- 2) remove loop-variable shadowing in generate_invite_code

BEGIN;

CREATE OR REPLACE FUNCTION public.batch_providers_for_media(p_items text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  result jsonb := '[]'::jsonb;
  req jsonb;
  item_row record;
  providers jsonb;
BEGIN
  BEGIN
    req := p_items::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', 'invalid_json');
  END;

  FOR item_row IN
    SELECT
      (elem->>'media_type') AS media_type,
      (elem->>'media_id')::int AS media_id
    FROM jsonb_array_elements(req) AS elem
  LOOP
    SELECT jsonb_agg(sub.prov ORDER BY sub.prio) INTO providers
    FROM (
      SELECT DISTINCT ON (ss.slug)
        jsonb_build_object(
          'slug', ss.slug,
          'display_name', ss.display_name,
          'language', el.language
        ) AS prov,
        ss.priority AS prio
      FROM external_links el
      CROSS JOIN streaming_services ss
      CROSS JOIN LATERAL unnest(ss.site_patterns) AS pattern
      WHERE el.media_type = item_row.media_type
        AND el.media_id = item_row.media_id
        AND ss.is_active = true
        AND lower(el.site) LIKE '%' || pattern || '%'
      ORDER BY ss.slug, length(pattern) DESC, ss.priority ASC
    ) sub;

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

CREATE OR REPLACE FUNCTION public.generate_invite_code(p_length int DEFAULT 8)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  _alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  _code text := '';
BEGIN
  FOR loop_idx IN 1..p_length LOOP
    _code := _code || substr(_alphabet, floor(random() * 62 + 1)::int, 1);
  END LOOP;
  RETURN _code;
END;
$$;

COMMIT;
