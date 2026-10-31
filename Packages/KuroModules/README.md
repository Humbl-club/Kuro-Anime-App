# KuroModules

Local Swift package with the first compiled boundaries of the modular architecture
(`docs/plans/2026-10-05-modular-architecture-contracts.md`, sections 1-3).

| Target | Owns | Depends on | Owner |
| --- | --- | --- | --- |
| `KuroCore` | `MediaKind`, `MediaKey`, `AccountContext`, `AccountSessionCoordinator`, `AccountScopedLoads` | Foundation | Identity / account lifecycle (E1) |
| `KuroLibrary` | `ListStatus`, `Verdict`, `UserRating`, `LibraryEntry`, `LibraryEdit`, outcomes/errors, `LibraryBackend` port, `LibraryReading`/`LibraryWriting`, `LibraryChangeSink`, `LibraryStore` | `KuroCore`, Observation | Library (tracking) |
| `KuroSupabase` | `LibraryRowTransport` seam + `SupabaseLibraryBackend` (list-table request contract, row/status/error mapping) | `KuroCore`, `KuroLibrary` | Library list adapter |

Dependency direction (acyclic, enforced by SwiftPM): app features -> `KuroLibrary` -> `KuroCore`;
app composition -> `KuroSupabase` -> `KuroLibrary`/`KuroCore`. No target imports SwiftUI, UIKit or
supabase-swift. The SDK binding of `LibraryRowTransport` lives in the app, which creates the single
SDK client; table names, columns and payload shapes stay in `KuroSupabase`.

## Isolation policy

Declared per target in `Package.swift` (nothing is inherited from the app's build settings):
Swift language mode 5, default isolation `nonisolated`, `StrictConcurrency` (complete checking) and
`MemberImportVisibility`. Value types are `Sendable` and nonisolated; `LibraryStore`,
`AccountSessionCoordinator` and `AccountScopedLoads` are explicitly `@MainActor`; the adapter is a
`Sendable` struct. App types that conform to `LibraryRowTransport`/`LibraryBackend` must be
declared `nonisolated` (the app target defaults to `MainActor`).

## Running the tests

```sh
cd Packages/KuroModules
swift build
swift test
```

Swift Testing on the macOS host; no network, no database, no simulator. Fakes model only external
outcomes (a controlled backend that waits for the test's answer; a recording transport with
scripted PostgREST replies). Waiting uses explicit continuations and observation, never sleeps.

## What is not claimed

- No durable offline queue or outbox: pending mutations live in memory only.
- No server revision fence: `mutationId`/`baseRevision` are generated and passed through, not sent.
- Package tests do not prove RLS, PostgREST behavior or the SDK binding; those need the app-side
  transport against a real (non-production) database.
- `fetchAll` pages 1000 rows per request and treats a shorter page as the end of a table, which
  assumes the project's PostgREST `max_rows` is at least 1000 (the Supabase default).
