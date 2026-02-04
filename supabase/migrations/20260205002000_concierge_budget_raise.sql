-- Raise LLM token budgets (requested):
-- - global daily tokens: 1,000,000
-- - per-user daily tokens: 50,000

begin;

update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      config,
      '{llm_budget,daily_tokens}',
      to_jsonb(50000),
      true
    ),
    '{global_llm_budget,daily_tokens}',
    to_jsonb(1000000),
    true
  )
where id = true;

commit;

