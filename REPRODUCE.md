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
