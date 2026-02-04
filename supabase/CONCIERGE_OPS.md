# Concierge Ops (Guardrails + Metrics)

## Tunables (no redeploy)

Guardrails are driven by a single JSON row:

- Table: `public.concierge_config` (single row, `id=true`)
- Reader: `public.get_concierge_config()` (RPC)

To update limits/budgets in the Supabase SQL editor, example:

```sql
update public.concierge_config
set config =
  jsonb_set(
    config,
    '{rate_limits,parse,max_ip}',
    to_jsonb(1200),
    true
  )
where id = true;
```

Disable all LLM usage (resolve + narration) instantly:

```sql
update public.system_flags
set enabled = false
where key = 'llm_enabled';
```

## Retention / housekeeping

Server-side cleanup runs via `pg_cron` as `concierge_housekeeping_daily` and deletes old rows from:

- `rate_limit_buckets`
- `llm_daily_usage`
- `import_sessions` / `import_session_items` (only applied/cancelled/failed; drafts are kept)
- `concierge_runs`
- `concierge_parse_feedback`

You can also run it manually:

```sql
select public.concierge_housekeeping();
```

## Metrics (admin-only)

Views (no grants; use Dashboard/service access):

- `public.concierge_metrics_hourly`
- `public.llm_usage_daily_totals`
- `public.rate_limit_recent_top`

## Parse feedback loop

Low-confidence parse lines are logged (best-effort) into:

- `public.concierge_parse_feedback`

This is meant for building a real-world corpus of "hard cases" and improving parsing safely over time.

