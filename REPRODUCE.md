# Kuro — How to Reproduce from Scratch

This file documents the exact steps to stand up the Kuro backend from a clean clone.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) v2.54+
- Node.js 18+
- Xcode 16+ (for iOS build)
- A Supabase project (current ref: `bkdifromsqxkndnllmdj`)

## 1. Link to the Supabase project

```bash
supabase link --project-ref bkdifromsqxkndnllmdj
```

## 2. Apply all migrations

```bash
supabase db push --linked
```

This applies all 63 migrations in `supabase/migrations/` in timestamp order.

To verify alignment between local files and the remote DB:

```bash
supabase migration list --linked
```

Every row should have both a Local and Remote timestamp. No gaps.

## 3. Deploy edge functions

```bash
supabase functions deploy concierge-parse --project-ref bkdifromsqxkndnllmdj
supabase functions deploy concierge-recommend --project-ref bkdifromsqxkndnllmdj
supabase functions deploy concierge-resolve --project-ref bkdifromsqxkndnllmdj
supabase functions deploy concierge-apply --project-ref bkdifromsqxkndnllmdj
supabase functions deploy concierge-undo --project-ref bkdifromsqxkndnllmdj
supabase functions deploy bulk-import-anime --project-ref bkdifromsqxkndnllmdj
supabase functions deploy bulk-import-manga --project-ref bkdifromsqxkndnllmdj
supabase functions deploy mirror-images --project-ref bkdifromsqxkndnllmdj
```

## 4. Run the quality audit

```bash
node scripts/audit_curated_rails_quality.js
```

Expected output:
- 38 rails checked
- 111 warnings (overlap in the 15-36% range — acceptable for editorial overlap between related genres)
- 0 adult/ecchi/hentai content
- 0 score-floor violations in premium/gateway rails

## 5. Build the iOS app

Open `Kuro.xcodeproj` in Xcode and build for the target device or simulator.

The app reads the Supabase URL and anon key from `Kuro/Services/SupabaseService.swift`.

## Current state summary

| Metric | Value |
|--------|-------|
| Local migration files | 63 |
| Curated rails | 38 |
| Vibe modes | 17 |
| Edge functions | 8 |
| Parser abbreviations | 30 |
| Audit script checks | 5 (overlap, franchise, classics year, rail size, score floor) |

## Changing curated rails

All 38 curated rails are defined in `scripts/rail_config.json`. To make changes:

1. Edit `scripts/rail_config.json` (add/remove/reorder items, change rail metadata)
2. Generate a migration:
   ```bash
   node scripts/generate_rail_migration.js supabase/migrations/YYYYMMDDHHMMSS_rail_update.sql
   ```
3. Review the generated SQL (should be a clean diff)
4. Apply to the remote DB:
   ```bash
   supabase db push --linked
   ```
5. Verify with the quality audit:
   ```bash
   node scripts/audit_curated_rails_quality.js
   ```

The generator validates constraints (no duplicates, max 100 items per rail, valid media types)
and fails with clear errors if the config is invalid. The output is deterministic: same config
always produces the same SQL.

**Note:** The older query-based generator scripts (`generate_vibe_rails_migration.js`,
`generate_curated_rails_migration.js`, `generate_more_vibe_rails_migration.js`,
`generate_premium_picks_rails_migration.js`, `generate_refined_short_and_fantasy_rails_migration.js`)
are **deprecated**. They were used to produce the initial rail seeds from live DB queries.
All rail changes should now go through `rail_config.json` + `generate_rail_migration.js`.

## Running the router eval

Tests that the concierge mode router returns the expected mode for known prompts:

```bash
SUPABASE_URL="https://<project>.supabase.co" SUPABASE_ANON_KEY="<anon>" node scripts/eval_router.js
```

Uses anonymous auth by default. For authenticated eval, set env vars:
```bash
SUPABASE_TEST_EMAIL="..." SUPABASE_TEST_PASSWORD="..." SUPABASE_URL="https://<project>.supabase.co" SUPABASE_ANON_KEY="<anon>" node scripts/eval_router.js
```

Expected: 90%+ pass rate across 63 test cases. Exit 1 if below threshold.
Retries 429/5xx with exponential backoff (up to 3 retries, honours Retry-After).
Infra errors (rate limits after retries) are reported separately and excluded
from the pass rate so flaky infra doesn't mask routing regressions.

## Verification commands

```bash
# Count local migration files
ls supabase/migrations/*.sql | wc -l
# Expected: 63

# Check local/remote alignment
supabase migration list --linked
# Expected: all 63 rows have both Local and Remote columns

# Run audit
node scripts/audit_curated_rails_quality.js
# Expected: 38 rails, 111 warnings, 0 errors

# Check working tree is clean
git status --short
# Expected: empty (no uncommitted changes)
```
