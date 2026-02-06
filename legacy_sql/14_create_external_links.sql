-- Stores curated external streaming links for anime/manga detail CTAs
CREATE TABLE IF NOT EXISTS public.external_links (
  id SERIAL PRIMARY KEY,
  media_type TEXT CHECK (media_type IN ('ANIME','MANGA')) NOT NULL,
  media_id INT NOT NULL,
  site TEXT,
  url TEXT NOT NULL,
  language TEXT,
  color TEXT,
  priority INT DEFAULT 999,
  is_disabled BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(media_type, media_id, url)
);

CREATE INDEX IF NOT EXISTS idx_external_links_media ON public.external_links(media_type, media_id);

ALTER TABLE public.external_links ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  BEGIN
    CREATE POLICY "Public read access" ON public.external_links FOR SELECT USING (true);
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END;
$$;
