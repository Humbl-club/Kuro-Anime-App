# Local GitHub Actions CI/CD

This project includes local-only GitHub Actions workflows:

- `/Applications/Kuro/.github/workflows/local-ci.yml`
- `/Applications/Kuro/.github/workflows/local-cd.yml`

They are `workflow_dispatch` only and intended for local execution.

## Scripts used by workflows

- `/Applications/Kuro/scripts/local_ci.sh`
- `/Applications/Kuro/scripts/local_cd.sh`
- `/Applications/Kuro/scripts/run_local_ci_logged.sh`
- `/Applications/Kuro/scripts/run_local_cd_logged.sh`

The workflows call the `run_local_*_logged.sh` wrappers so every run writes:

- full text logs under `/Applications/Kuro/reports/local-cicd/`
- latest status JSON files:
  - `/Applications/Kuro/reports/local-cicd/latest-ci-status.json`
  - `/Applications/Kuro/reports/local-cicd/latest-cd-status.json`

You can run these directly without an Actions runner:

```bash
cd /Applications/Kuro
./scripts/run_local_ci_logged.sh
./scripts/run_local_cd_logged.sh --supabase-only
./scripts/run_local_cd_logged.sh --testflight-only
```

Quickly check the latest result:

```bash
cd /Applications/Kuro
cat reports/local-cicd/latest-ci-status.json
cat reports/local-cicd/latest-cd-status.json
```

## Optional: run workflows with `act`

Install:

```bash
brew install act
```

Run Local CI:

```bash
cd /Applications/Kuro
act workflow_dispatch -W .github/workflows/local-ci.yml -j local-ci --self-hosted
```

Run Local CD:

```bash
cd /Applications/Kuro
act workflow_dispatch -W .github/workflows/local-cd.yml -j local-cd --self-hosted
```

## Required local tooling

- Node.js
- Supabase CLI (for Supabase deploy/lint)
- Xcode + command line tools (for iOS build/TestFlight)
- Fastlane (for TestFlight upload)

## Notes

- `local-ci` can skip expensive steps via workflow inputs:
  - `run_supabase_lint=0`
  - `run_ios_build=0`
- `local-cd` supports selective deploys:
  - `DEPLOY_FUNCTIONS` CSV list (default: `bulk-import-anime,bulk-import-manga,manga-chapter-enrich`)

## Automatic local runs (optional)

Use launchd installer:

```bash
cd /Applications/Kuro
./scripts/install_local_cicd_launchd.sh
```

That installs:

- CI launch agent (`com.kuro.local-ci`) running every 6 hours by default.

To also schedule nightly Supabase-only CD:

```bash
cd /Applications/Kuro
./scripts/install_local_cicd_launchd.sh --with-cd --cd-hour 3 --cd-minute 30
```

Remove agents:

```bash
cd /Applications/Kuro
./scripts/install_local_cicd_launchd.sh --uninstall
```

All automatic runs write to the same `reports/local-cicd` folder.
