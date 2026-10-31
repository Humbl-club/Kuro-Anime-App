-- Release tester cohort; private decisions never change global percentages.
BEGIN;
CREATE TABLE public.feature_flag_overrides (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    flag_name text NOT NULL REFERENCES public.feature_flags(flag_name) ON DELETE CASCADE,
    enabled boolean NOT NULL,
    PRIMARY KEY (user_id, flag_name)
);
ALTER TABLE public.feature_flag_overrides ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.feature_flag_overrides FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.feature_flag_overrides TO authenticated;
GRANT ALL ON public.feature_flag_overrides TO service_role;
CREATE POLICY feature_flag_override_owner_read ON public.feature_flag_overrides
    FOR SELECT TO authenticated USING (user_id = auth.uid());
COMMENT ON TABLE public.feature_flag_overrides IS
    'Administrator-managed account cohort. Clients may read only their own decisions and cannot write.';
COMMIT;
