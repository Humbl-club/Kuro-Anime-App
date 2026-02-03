-- Adds streaming link fields to episodes for Watch CTA support
ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_url TEXT;

ALTER TABLE public.episodes
  ADD COLUMN IF NOT EXISTS stream_site TEXT;
