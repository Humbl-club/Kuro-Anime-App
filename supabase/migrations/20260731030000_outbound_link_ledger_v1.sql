-- Outbound Link Ledger v1 (ADR 2026-07-31: monetization posture)
-- Scaffold only: records taps on outbound links users already use (WATCH/READ CTAs,
-- provider sheet picks, external reference links). No affiliate decoration, no StoreKit.

-- ============================================================
-- 1. TABLE
-- ============================================================

CREATE TABLE public.outbound_link_events (
  id          bigserial   PRIMARY KEY,
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  media_type  text        NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id    integer     NOT NULL,
  link_kind   text        NOT NULL CHECK (link_kind IN ('watch', 'read', 'provider_sheet', 'external_reference')),
  provider    text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_outbound_link_events_user_created
  ON public.outbound_link_events(user_id, created_at DESC);
CREATE INDEX idx_outbound_link_events_provider_created
  ON public.outbound_link_events(provider, created_at DESC);

-- ============================================================
-- 2. RLS
-- ============================================================

ALTER TABLE public.outbound_link_events ENABLE ROW LEVEL SECURITY;

-- Users can read only their own rows.
CREATE POLICY "outbound_link_events_select" ON public.outbound_link_events
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Writes only via record_outbound_link() (SECURITY DEFINER): no INSERT policy and
-- no direct table privilege for clients. RLS default-deny covers UPDATE/DELETE.
REVOKE INSERT ON public.outbound_link_events FROM authenticated, anon;

-- ============================================================
-- 3. RPC: record an outbound link tap (rate-limited)
-- ============================================================

CREATE OR REPLACE FUNCTION public.record_outbound_link(
  p_media_type text,
  p_media_id   integer,
  p_link_kind  text,
  p_provider   text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _uid    uuid := auth.uid();
  _recent int;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  IF p_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION 'INVALID_MEDIA_TYPE' USING ERRCODE = 'P0001';
  END IF;

  IF p_link_kind NOT IN ('watch', 'read', 'provider_sheet', 'external_reference') THEN
    RAISE EXCEPTION 'INVALID_KIND' USING ERRCODE = 'P0001';
  END IF;

  IF p_provider IS NULL OR char_length(TRIM(p_provider)) < 1 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER' USING ERRCODE = 'P0001';
  END IF;

  -- Rate limit: 120 events per user per hour (count check on the ledger itself)
  SELECT count(*) INTO _recent
  FROM public.outbound_link_events
  WHERE user_id = _uid
    AND created_at > now() - interval '1 hour';
  IF _recent >= 120 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.outbound_link_events (user_id, media_type, media_id, link_kind, provider)
  VALUES (_uid, p_media_type, p_media_id, p_link_kind, TRIM(p_provider));
END;
$$;

-- ============================================================
-- 4. Retention: purge rows older than 90 days (daily 04:40 UTC, pure SQL cron)
-- ============================================================

CREATE OR REPLACE FUNCTION public.purge_outbound_link_events()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  DELETE FROM public.outbound_link_events
  WHERE created_at < now() - interval '90 days';
END;
$$;

do $$
begin
  -- Ensure we don't double-schedule.
  if not exists (select 1 from cron.job where jobname = 'outbound-link-ledger-retention') then
    perform cron.schedule('outbound-link-ledger-retention', '40 4 * * *', 'select public.purge_outbound_link_events();');
  end if;
end $$;

-- ============================================================
-- 5. Feature flag (seeded OFF; nothing consumes it yet)
-- ============================================================

INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES ('affiliate_links_v1', false, 0, ARRAY['*'], 'Affiliate decoration on outbound links; legal review precedes any flag flip')
ON CONFLICT (flag_name) DO NOTHING;
