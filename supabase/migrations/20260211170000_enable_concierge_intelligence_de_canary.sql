-- Enable concierge intelligence flags for DE/AT/CH canary rollout (5%).
begin;
update public.feature_flags
set enabled = true,
    rollout_percentage = 5,
    target_markets = array['DE','AT','CH'],
    updated_at = now()
where flag_name in ('rag_assist_v1', 'fm_assist_v1', 'clarify_v2');
commit;
