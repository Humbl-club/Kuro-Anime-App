-- Roll social_activity_v1 from 0% to 100%
UPDATE public.feature_flags
SET rollout_percentage = 100
WHERE flag_name = 'social_activity_v1';
