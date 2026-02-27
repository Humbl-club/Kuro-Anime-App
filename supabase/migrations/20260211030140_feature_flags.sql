
-- Feature flags for server-controlled rollout of new concierge capabilities.
-- Flags are evaluated client-side using hash(user_id) % 100 < rollout_percentage.

CREATE TABLE IF NOT EXISTS feature_flags (
    flag_name text PRIMARY KEY,
    enabled boolean NOT NULL DEFAULT false,
    rollout_percentage int NOT NULL DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
    target_markets text[] DEFAULT '{}',
    description text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Trigger to auto-update updated_at on changes
CREATE OR REPLACE FUNCTION update_feature_flags_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_feature_flags_updated_at ON feature_flags;
CREATE TRIGGER trg_feature_flags_updated_at
    BEFORE UPDATE ON feature_flags
    FOR EACH ROW
    EXECUTE FUNCTION update_feature_flags_timestamp();

-- RLS: anon + authenticated can read flags; only service_role can mutate.
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feature_flags_select_all"
    ON feature_flags FOR SELECT
    USING (true);

-- Seed initial flags
INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
VALUES
    ('rag_assist_v1', false, 0, '{}', 'Server-side RAG assist for concierge recommendations'),
    ('fm_assist_v1', false, 0, '{}', 'Apple Foundation Models on-device classification assist'),
    ('clarify_v2', false, 0, '{}', 'Inline clarification cards v2 with DE+EN support')
ON CONFLICT (flag_name) DO NOTHING;

COMMENT ON TABLE feature_flags IS 'Server-controlled feature flags for gradual rollout of concierge intelligence features.';
;
