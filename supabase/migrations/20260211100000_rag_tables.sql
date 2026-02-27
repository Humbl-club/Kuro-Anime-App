-- ============================================================
-- RAG RETRIEVAL TABLES
-- Creates tables for server-side RAG entity retrieval:
--   - rag_entity_index: canonical entity catalog
--   - rag_entity_aliases: alternative titles/names
--   - rag_entity_tags: genre/theme/demographic/mood tags
--   - rag_retrieval_cache: query result caching
--   - rag_retrieval_feedback: user acceptance/rejection
--   - concierge_events: privacy-safe telemetry events
--
-- pg_trgm is already enabled (concierge_core migration).
-- SET search_path = public on all helper functions.
-- ============================================================

begin;
-- Ensure trigram operator class exists for gin_trgm_ops indexes below.
create extension if not exists pg_trgm with schema public;
-- ==========================================================
-- 1. rag_entity_index
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.rag_entity_index (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  anilist_id       int         NOT NULL,
  media_type       text        NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  canonical_title  text        NOT NULL,
  normalized_title text        NOT NULL,
  locale           text        NOT NULL DEFAULT 'und',
  year             int         NULL,
  format           text        NULL,
  popularity       int         NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (anilist_id, media_type, locale)
);
ALTER TABLE public.rag_entity_index ENABLE ROW LEVEL SECURITY;
-- Trigram index for fuzzy search on normalized_title.
-- NOTE: gin_trgm_ops may live in non-public schemas (e.g. extensions).
DO $$
DECLARE
  trgm_schema text;
BEGIN
  IF to_regclass('public.idx_rag_entity_norm_title_trgm') IS NULL THEN
    SELECT n.nspname
    INTO trgm_schema
    FROM pg_opclass opc
    JOIN pg_namespace n ON n.oid = opc.opcnamespace
    WHERE opc.opcname = 'gin_trgm_ops'
    ORDER BY CASE WHEN n.nspname = 'public' THEN 0 WHEN n.nspname = 'extensions' THEN 1 ELSE 2 END
    LIMIT 1;

    IF trgm_schema IS NULL THEN
      RAISE EXCEPTION 'gin_trgm_ops opclass not found; ensure pg_trgm extension is installed';
    END IF;

    EXECUTE format(
      'CREATE INDEX idx_rag_entity_norm_title_trgm ON public.rag_entity_index USING gin (normalized_title %I.gin_trgm_ops)',
      trgm_schema
    );
  END IF;
END $$;
-- Composite btree for filtered queries
CREATE INDEX IF NOT EXISTS idx_rag_entity_locale_year_format
  ON public.rag_entity_index (locale, year, format);
-- RLS: anon can SELECT (public catalog data)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rag_entity_index'
      AND policyname = 'rag_entity_index_select_anon'
  ) THEN
    CREATE POLICY rag_entity_index_select_anon ON public.rag_entity_index
      FOR SELECT USING (true);
  END IF;
END $$;
-- updated_at trigger
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'rag_entity_index_set_updated_at') THEN
    CREATE TRIGGER rag_entity_index_set_updated_at
      BEFORE UPDATE ON public.rag_entity_index
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;
-- ==========================================================
-- 2. rag_entity_aliases
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.rag_entity_aliases (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id        uuid        NOT NULL REFERENCES public.rag_entity_index(id) ON DELETE CASCADE,
  alias            text        NOT NULL,
  normalized_alias text        NOT NULL,
  locale           text        NOT NULL,
  alias_type       text        NOT NULL,
  UNIQUE (entity_id, normalized_alias, locale)
);
ALTER TABLE public.rag_entity_aliases ENABLE ROW LEVEL SECURITY;
-- Trigram index for fuzzy search on normalized_alias.
DO $$
DECLARE
  trgm_schema text;
BEGIN
  IF to_regclass('public.idx_rag_alias_norm_trgm') IS NULL THEN
    SELECT n.nspname
    INTO trgm_schema
    FROM pg_opclass opc
    JOIN pg_namespace n ON n.oid = opc.opcnamespace
    WHERE opc.opcname = 'gin_trgm_ops'
    ORDER BY CASE WHEN n.nspname = 'public' THEN 0 WHEN n.nspname = 'extensions' THEN 1 ELSE 2 END
    LIMIT 1;

    IF trgm_schema IS NULL THEN
      RAISE EXCEPTION 'gin_trgm_ops opclass not found; ensure pg_trgm extension is installed';
    END IF;

    EXECUTE format(
      'CREATE INDEX idx_rag_alias_norm_trgm ON public.rag_entity_aliases USING gin (normalized_alias %I.gin_trgm_ops)',
      trgm_schema
    );
  END IF;
END $$;
-- FK index
CREATE INDEX IF NOT EXISTS idx_rag_entity_aliases_entity_id
  ON public.rag_entity_aliases (entity_id);
-- RLS: anon can SELECT (public catalog data)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rag_entity_aliases'
      AND policyname = 'rag_entity_aliases_select_anon'
  ) THEN
    CREATE POLICY rag_entity_aliases_select_anon ON public.rag_entity_aliases
      FOR SELECT USING (true);
  END IF;
END $$;
-- ==========================================================
-- 3. rag_entity_tags
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.rag_entity_tags (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id      uuid        NOT NULL REFERENCES public.rag_entity_index(id) ON DELETE CASCADE,
  tag            text        NOT NULL,
  normalized_tag text        NOT NULL,
  tag_group      text        NOT NULL CHECK (tag_group IN ('genre', 'theme', 'demographic', 'mood')),
  UNIQUE (entity_id, normalized_tag, tag_group)
);
ALTER TABLE public.rag_entity_tags ENABLE ROW LEVEL SECURITY;
-- Trigram index for fuzzy search on normalized_tag.
DO $$
DECLARE
  trgm_schema text;
BEGIN
  IF to_regclass('public.idx_rag_tag_norm_trgm') IS NULL THEN
    SELECT n.nspname
    INTO trgm_schema
    FROM pg_opclass opc
    JOIN pg_namespace n ON n.oid = opc.opcnamespace
    WHERE opc.opcname = 'gin_trgm_ops'
    ORDER BY CASE WHEN n.nspname = 'public' THEN 0 WHEN n.nspname = 'extensions' THEN 1 ELSE 2 END
    LIMIT 1;

    IF trgm_schema IS NULL THEN
      RAISE EXCEPTION 'gin_trgm_ops opclass not found; ensure pg_trgm extension is installed';
    END IF;

    EXECUTE format(
      'CREATE INDEX idx_rag_tag_norm_trgm ON public.rag_entity_tags USING gin (normalized_tag %I.gin_trgm_ops)',
      trgm_schema
    );
  END IF;
END $$;
-- FK index
CREATE INDEX IF NOT EXISTS idx_rag_entity_tags_entity_id
  ON public.rag_entity_tags (entity_id);
-- RLS: anon can SELECT (public catalog data)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rag_entity_tags'
      AND policyname = 'rag_entity_tags_select_anon'
  ) THEN
    CREATE POLICY rag_entity_tags_select_anon ON public.rag_entity_tags
      FOR SELECT USING (true);
  END IF;
END $$;
-- ==========================================================
-- 4. rag_retrieval_cache
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.rag_retrieval_cache (
  cache_key      text        PRIMARY KEY,
  query          text        NOT NULL,
  normalized_query text      NOT NULL,
  locale         text        NOT NULL,
  constraints_hash text      NULL,
  result_json    jsonb       NOT NULL,
  config_version text        NOT NULL,
  expires_at     timestamptz NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rag_retrieval_cache ENABLE ROW LEVEL SECURITY;
-- btree on expires_at for cleanup
CREATE INDEX IF NOT EXISTS idx_rag_cache_expires
  ON public.rag_retrieval_cache (expires_at);
-- RLS: service_role only (no anon access). Deny all for anon/authenticated.
-- Edge functions use service_role key to read/write cache.
-- No policies = deny all by default (RLS enabled, no permissive policies).

-- ==========================================================
-- 5. rag_retrieval_feedback
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.rag_retrieval_feedback (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           text        NOT NULL,
  query             text        NOT NULL,
  locale            text        NOT NULL,
  selected_entity_id uuid      NULL REFERENCES public.rag_entity_index(id),
  accepted          boolean     NOT NULL,
  rejected_reason   text        NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rag_retrieval_feedback ENABLE ROW LEVEL SECURITY;
-- RLS: users can INSERT their own feedback, SELECT own rows
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rag_retrieval_feedback'
      AND policyname = 'rag_feedback_insert_own'
  ) THEN
    CREATE POLICY rag_feedback_insert_own ON public.rag_retrieval_feedback
      FOR INSERT WITH CHECK (user_id = auth.uid()::text);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'rag_retrieval_feedback'
      AND policyname = 'rag_feedback_select_own'
  ) THEN
    CREATE POLICY rag_feedback_select_own ON public.rag_retrieval_feedback
      FOR SELECT USING (user_id = auth.uid()::text);
  END IF;
END $$;
-- ==========================================================
-- 6. concierge_events
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.concierge_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     text        NULL,
  event_name  text        NOT NULL,
  language    text        NOT NULL,
  market      text        NOT NULL,
  payload     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.concierge_events ENABLE ROW LEVEL SECURITY;
-- btree for analytics queries
CREATE INDEX IF NOT EXISTS idx_concierge_events_name_market_created
  ON public.concierge_events (event_name, market, created_at);
-- RLS: INSERT where user_id matches or is NULL (anonymous events), no SELECT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'concierge_events'
      AND policyname = 'concierge_events_insert_own'
  ) THEN
    CREATE POLICY concierge_events_insert_own ON public.concierge_events
      FOR INSERT WITH CHECK (
        user_id IS NULL OR user_id = auth.uid()::text
      );
  END IF;
END $$;
-- ==========================================================
-- 7. Cache cleanup helper function
-- ==========================================================

CREATE OR REPLACE FUNCTION public.rag_cache_cleanup()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.rag_retrieval_cache
  WHERE expires_at < now();
END;
$$;
commit;
