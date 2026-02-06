-- Cursor table for scheduled imports
CREATE TABLE IF NOT EXISTS public.import_state (
  media_type text PRIMARY KEY, -- 'ANIME' | 'MANGA'
  last_page integer NOT NULL DEFAULT 0,
  updated_at timestamp with time zone DEFAULT now()
);

-- Seed rows if not present
INSERT INTO public.import_state (media_type, last_page)
VALUES ('ANIME', 0)
ON CONFLICT (media_type) DO NOTHING;

INSERT INTO public.import_state (media_type, last_page)
VALUES ('MANGA', 0)
ON CONFLICT (media_type) DO NOTHING;

