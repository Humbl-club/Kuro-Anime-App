-- Realm repair Phase 1, Fix 6 — hygiene (spec: 2026-08-04-realm-repair-and-critique-plan.md §3.6).
--
-- PART A — drop the swarm-era secret-scraping scaffolding.
--   20260802011000/013000 created SECURITY DEFINER helpers that regex the
--   IMPORT_SECRET literal out of cron.job.command text. 20260802017000 dropped
--   two of the three (_ops_peek_import_secret, _ops_list_import_crons) but
--   deliberately kept _ops_import_secret_from_cron "for enqueue_realm_describe_batch
--   only". That justification is now gone: the realm-describe drain crons
--   (realm-describe-drain-3m/-2m) were unscheduled by 20260802120000 and the
--   drain moved to the local Mac worker (scripts/realm_descriptor_worker.js),
--   which reads its secret from env. enqueue_realm_describe_batch(integer) is
--   the ONLY caller of _ops_import_secret_from_cron (verified against live
--   pg_proc.prosrc, 2026-08-05) and nothing calls enqueue_realm_describe_batch
--   (no cron job, no function, no repo consumer) — so both are dropped together;
--   dropping only the scraper would leave enqueue broken at runtime.
--   The sibling drops are re-stated drop-if-exists for idempotency on fresh DBs.
--
-- PART B — clear the 3 ERROR-level security advisors (security_definer_view):
--   public.realm_affinity_effective, public.media_realm_llm_pending,
--   public.media_realm_profile — all owned by postgres with no security_invoker,
--   so client reads ran with the owner's rights (RLS bypass surface).
--   ALTER VIEW ... SET (security_invoker = true) is used instead of a
--   drop/recreate: it flips ONLY the security property and leaves the stored
--   SELECT body byte-identical (verified pre/post via pg_get_viewdef).
--   Invoker mode is safe for every live consumer because everything the views
--   read is public-readable under the invoker's own rights (verified live,
--   2026-08-05):
--     - anime / manga:               RLS SELECT qual `true` + anon/authenticated grants
--     - media_realm_llm:             RLS `media_realm_llm_select_all` (true) + grants
--     - media_realm_tier:            RLS `media_realm_tier_select_all` (true) + grants
--     - realm_affinity (matview):    no RLS (grant-gated), anon/authenticated/service_role grants
--     - realm_affinity_overrides:    RLS `realm_affinity_overrides_select_all` (true) + grants
--   Consumers per view (evidence in Fix 6 report):
--     - realm_affinity_effective: read ONLY inside SECURITY DEFINER functions
--       (_recommend_ids_similar_to_seeds_live, rebuild_media_similar_titles),
--       which execute as the view/table owner (postgres) — no client grant
--       needed. Its live ACL absurdly granted anon/authenticated FULL
--       privileges (arwdDxtm); trimmed to service_role SELECT (ops probes).
--     - media_realm_llm_pending: local descriptor workers
--       (scripts/realm_descriptor_worker.js, scripts/realm_llm_pass_fetch.js —
--       KURO_TEST_JWT i.e. authenticated, or service key) and the
--       realm-describe edge function (service-role client). Keeps
--       authenticated + service_role SELECT; anon had (and gets) nothing.
--     - media_realm_profile: NO consumers anywhere (repo grep across
--       Kuro/, scripts/, eval/, supabase/functions/ + live pg_proc.prosrc scan
--       both empty) — it is a Stage 2b ops/QA read surface. anon grant removed
--       (plan requirement); authenticated + service_role SELECT retained for
--       ad-hoc ops reads. fetch_my_taste_profile reads user_taste_profiles
--       only — it never touches this view.
--   Grants are re-asserted explicitly after the flip so the final ACL is the
--   documented minimum, independent of what earlier migrations left behind.
--
-- No function bodies are created or replaced here (drops + view/grant DDL only),
-- so no SET search_path clauses are required.

begin;

-- ---------------------------------------------------------------------------
-- A) Secret-scraping scaffolding: drop the last survivor + its only caller.
-- ---------------------------------------------------------------------------

drop function if exists public.enqueue_realm_describe_batch(integer);
drop function if exists public._ops_import_secret_from_cron();

-- Siblings already dropped by 20260802017000 — re-stated for idempotency.
drop function if exists public._ops_peek_import_secret();
drop function if exists public._ops_list_import_crons();

-- ---------------------------------------------------------------------------
-- B1) security_invoker on the three flagged views (SELECT bodies untouched).
-- ---------------------------------------------------------------------------

alter view public.realm_affinity_effective set (security_invoker = true);
alter view public.media_realm_llm_pending  set (security_invoker = true);
alter view public.media_realm_profile      set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- B2) Grants trimmed to the actual consumer set (owner postgres keeps implicit
--     rights; SECURITY DEFINER readers of realm_affinity_effective run as owner).
-- ---------------------------------------------------------------------------

revoke all on public.realm_affinity_effective from public, anon, authenticated, service_role;
grant select on public.realm_affinity_effective to service_role;

revoke all on public.media_realm_llm_pending from public, anon, authenticated, service_role;
grant select on public.media_realm_llm_pending to authenticated, service_role;

revoke all on public.media_realm_profile from public, anon, authenticated, service_role;
grant select on public.media_realm_profile to authenticated, service_role;

commit;
