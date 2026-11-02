# Operational scripts: index (no moves)

Current source update, 2026-10-07: worker/dashboard runners and the six worker/dashboard installers use the established project-root resolver; generated job environments pin `KURO_PROJECT_ROOT`. The three individual dashboards retain explicit report-directory overrides, and dashboard installers retain applicable installed port/report tuning. Pipeline labels, wrapper names, lock layout and default ports are stable. F57 passed 13 offline checks and independent review; no installer or job was executed.

`local_cd.sh` defaults `DEPLOY_SUPABASE=0`; explicit deployment opt-in remains required. Media-relations configuration takes a complete owned environment/config pair or a complete existing fallback pair, never pieces from different providers. Existing installed jobs and credentials were not inspected or changed in this repair.

The root/hazard and corpus-count sections below are **historical 5 October observations**, superseded by this update, current source and the completion register. They do not describe a presently running worker or deployed bundle.

## Launchd families (separate pipelines; never share label, lock, report root or port)

| Family | Label | Installer -> runner -> worker | Default interval | Lock (`$REPORT_DIR/.worker.lock`, PID + TTL) | Report root | Dashboard |
|---|---|---|---|---|---|---|
| Synopsis enrichment | `com.kuro.synopsis-enrichment` | `install_synopsis_enrichment_launchd.sh` -> `run_synopsis_enrichment.sh` -> `synopsis_enrichment_worker.swift` (compiled on demand) | 240 s | `SYNOPSIS_LOCK_TTL_SECONDS` 1800 | `reports/synopsis-enrichment` | `synopsis_dashboard_server.js` :8787 (label `com.kuro.synopsis-dashboard`, KeepAlive) |
| Catalog safety | `com.kuro.catalog-safety` | `install_catalog_safety_launchd.sh` -> `run_catalog_safety.sh` -> `catalog_safety_worker.swift` | 600 s | `CATALOG_SAFETY_LOCK_TTL_SECONDS` 1800 | `reports/catalog-safety` | `catalog_safety_dashboard_server.js` :8788 (no installer; started by hand) |
| Media relations | `com.kuro.media-relations` | `install_media_relations_launchd.sh` -> `run_media_relations_refresh.sh` -> `media_relations_worker.js` | 900 s | `MEDIA_RELATIONS_LOCK_TTL_SECONDS` 21600 | `reports/media-relations` | unified dashboard only |
| Provider availability | `com.kuro.provider-availability` | `install_provider_availability_launchd.sh` -> `run_provider_availability.sh` -> `provider_availability_worker.swift` | 600 s | `PROVIDER_AVAILABILITY_LOCK_TTL_SECONDS` 7200 | `reports/provider-availability` | `provider_availability_dashboard_server.js` :8789 (no installer) |
| Unified dashboard | `com.kuro.unified-dashboard` | `install_unified_dashboard_launchd.sh` -> `unified_local_dashboard_server.js` | KeepAlive | none | `reports/local-dashboard` | :8791 (links 8787/8788/8789) |
| Local CI / CD | `com.kuro.local-ci`, `com.kuro.local-cd` | `install_local_cicd_launchd.sh` -> `run_local_ci_logged.sh` / `run_local_cd_logged.sh` -> `local_ci.sh` / `local_cd.sh` | CI 21600 s; CD 03:30 (only with `--with-cd`) | none | `<repo>/reports/local-cicd` | none |

Plists live at `~/Library/LaunchAgents/<label>.plist`; installers re-read existing env and
`StartInterval` from them so a reinstall keeps operator tuning, and fail fast without
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`.

## Paths that must stay stable

- Labels above; plist location; wrapper names `run_*.sh` / `run_local_c[id]_logged.sh` (literal in
  installed plists, matched by name in `unified_local_dashboard_server.js` `SERVICE_DEFS`, and in
  `.github/workflows/local-ci.yml` / `local-cd.yml`).
- Worker file names (`*_worker.swift`, `media_relations_worker.js`): compiled-binary names and the
  `-nt` recompile checks in the runners, plus the unified dashboard's process matchers.
- Report roots and file names read by dashboards (`latest-status.json`, `run-*.log`, `worker.log`,
  `latest-run.json`, `*-latest.md`) and the `.worker.lock/{pid,started_at_unix}` layout.
- Ports 8787, 8788, 8789, 8791 (hard-coded as links in the unified dashboard).
- `scripts/project_public.env`, `scripts/lib/load_project_public_env.sh`, `scripts/lib/project_config.js`
  (sourced/required by relative path).
- `scripts/*.js` at depth 1 (syntax-checked by `local_ci.sh`), `scripts/quality-gates/*` names
  (`run_all.sh` table, `fastlane/Fastfile:16,53`, `local_ci.sh:64-66`; `router_test_cases.js` is
  whitelisted by name in `check_secrets.sh` and `.githooks/pre-commit`).
- Gitignored checkpoints `scripts/.realm_descriptor_progress.json`, `scripts/.rec_edges_progress.json`.
- `scripts/db/` is reserved for the disposable-database test harness (other lane).

## Hard-coded `/Applications/Kuro` defaults (18 lines in 18 files)

- No override (code location itself): the 6 worker/dashboard installers (`install_*_launchd.sh:5`,
  except `install_local_cicd_launchd.sh`, which derives the repo path), the 4 runners
  (`run_synopsis_enrichment.sh:4`, `run_catalog_safety.sh:4`, `run_provider_availability.sh:4`,
  `run_media_relations_refresh.sh:4`), `unified_local_dashboard_server.js:8` (no env override at all),
  `media_relations_worker.js:8` (ROOT only feeds the report-dir default).
- Env-overridable report-dir defaults: the 3 Swift workers and the 3 single-family dashboards
  (`*_REPORTS_DIR`).
- Consequence: with the repo elsewhere, local CI/CD writes `<repo>/reports/local-cicd` while the
  unified dashboard reads `/Applications/Kuro/reports/local-cicd`.

## Hazards worth an owner decision (not changed here)

- `local_cd.sh` deploys to the linked production project by default (`DEPLOY_SUPABASE=1` `:7`,
  `supabase db push --linked --yes` `:77`, `functions deploy` `:97-99`; default functions
  `bulk-import-anime,bulk-import-manga,manga-chapter-enrich` `:9`). Run only with deployment approval.
- `run_media_relations_refresh.sh:10-16` borrows `SUPABASE_*` credentials from the other three
  pipelines' plists, so their labels and plist paths are part of its contract.
- The pre-commit hook is inactive in this clone (`core.hooksPath` unset); secrets/migration-name
  checks run only through `scripts/quality-gates/run_all.sh`.

## Quality gates touched in E7

| `run_all.sh` label | Script | What it verifies |
|---|---|---|
| `corpora-shape+exec` | `test_concierge_corpora.sh` | `[corpora-shape]` JSON structure of the 4 corpus files; `[corpora-execution]` 107 parser + 67 router cases through the production `rules.ts` / `router.ts` (deno). Parser: 17 cases disagree with the corpus as written: 13 pinned with current production output, 4 re-expected in the test (see `edge-functions.md`). Router: 2 pinned. All printed each run |
| `router-rules-exec` | `test_router_offline.sh` | production `router.ts` chain vs the 73 offline cases + 22 German-only alternatives + fallback-mode characterisation (deno) |

Both gates now require `deno` (previously `node` ran a copied router).
