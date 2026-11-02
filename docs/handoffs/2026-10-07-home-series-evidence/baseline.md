# Home / series baseline — 7 October 2026

Local execution pin. No production connection was opened. No secrets are recorded here.

| Item | Value |
| --- | --- |
| Working directory | `/Users/max/Kuro-Anime-App` |
| Branch | `kuro/taste-overhaul` |
| HEAD | `a7f39b66237bc5a9558b5ab2a6758cd1b085e466` |
| HEAD subject | Stop deleted accounts from leaving public media behind. |
| Handout SHA | `471c609943d2374c6dda940aebdfde2fcb077d50` is an ancestor, not HEAD |
| Dirty work | Modular capability split is uncommitted and was preserved. `SupabaseService.swift` is deleted in the working tree. New Home work is additive on `AppComposition`. |
| Design manifest | 46/46 files under `tools/design-directions/` match the handout SHA-256 list |
| Toolchain | macOS 27.0.1, Xcode 26.2, Swift 6.2.3, PostgreSQL 17.10, Supabase CLI 2.78.1 |
| Database target | Throwaway local cluster only (`scripts/db/run_local_db_tests.sh`). Production project `bkdifromsqxkndnllmdj` was not queried. |
| Migration | `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql` is prepared, not in `supabase/migrations/`, not deployed |
| Flags | `series_foundation_v1` and `series_home_native_v1` insert disabled at 0% when `feature_flags` exists. The native pager uses the flag, which stays off until the row is enabled |

Unrelated dirty work (workers, concierge splits, club privacy migrations already in the tree, Taste, docs) was not reset.
