CREATE TABLE IF NOT EXISTS public.concierge_mode_analytics (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mode_id text NOT NULL,
  prompt_hash text,
  matched_synonyms text[],
  confidence real,
  was_llm_routed boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Index for querying mode popularity
CREATE INDEX IF NOT EXISTS idx_mode_analytics_mode_id ON public.concierge_mode_analytics(mode_id);
CREATE INDEX IF NOT EXISTS idx_mode_analytics_created ON public.concierge_mode_analytics(created_at);

-- RLS
ALTER TABLE public.concierge_mode_analytics ENABLE ROW LEVEL SECURITY;

-- Only service_role can insert (from edge function)
CREATE POLICY mode_analytics_insert ON public.concierge_mode_analytics
  FOR INSERT TO authenticated WITH CHECK (false);

-- Allow service_role full access (edge functions use service_role)
GRANT ALL ON public.concierge_mode_analytics TO service_role;
GRANT USAGE ON SEQUENCE concierge_mode_analytics_id_seq TO service_role;;
