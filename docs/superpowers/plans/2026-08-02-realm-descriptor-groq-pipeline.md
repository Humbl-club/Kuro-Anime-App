# Realm Descriptor Groq Pipeline — Implementation Plan

> **For agentic workers:** implement task-by-task; verify each step.

**Goal:** Salvage swarm JSONL + ship Groq `realm-describe` + checkpointed worker; drain pending queue.

**Files:**
- Create: `supabase/functions/realm-describe/index.ts`
- Create: `scripts/realm_descriptor_worker.js`
- Create: `scripts/realm_llm_salvage_swarm.js`
- Create: `supabase/migrations/20260802010000_realm_describe_drain_cron.sql` (optional cron drain)
- Modify: `.gitignore` (progress file)
- Docs: design already at `docs/superpowers/specs/2026-08-02-realm-descriptor-groq-pipeline-design.md`

## Task 1: Salvage script + run
## Task 2: Edge function
## Task 3: Worker
## Task 4: Deploy + smoke + drain
## Task 5: Docs + PR review
