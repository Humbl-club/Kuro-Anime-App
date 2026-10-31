# Kuro modular architecture — frozen contracts (E2)

Authority: [execution brief](2026-10-05-modular-architecture-plan.md). Status: contract drafts for stages E3-E8; any change after a consumer migrates is a contract change recorded in the [ledger](2026-10-05-modular-architecture-execution-ledger.md). Evidence behind each decision: inventories produced at E2 (service-member map, state-lifetime inventory, write map, consumer matrix) summarized in the [ownership map](2026-10-05-modular-architecture-ownership-map.md).

## 1. Architecture shape

Logical ownership first, compiled boundaries where they pay for themselves.

| Target (local package `Packages/KuroModules`) | Owns | Depends on | Why a target |
| --- | --- | --- | --- |
| `KuroCore` | Foundation-only shared value contracts: `MediaKind`, `MediaKey`, `AccountContext`, `AccountSessionCoordinator`, `AccountScopedLoads` | Foundation | Every capability needs typed identity and account scoping; no UI/SDK; runs under macOS `swift test` |
| `KuroLibrary` | Tracking domain: `ListStatus`, `Verdict`, `UserRating`, `LibraryEntry`, `LibraryEdit`, `LibraryOutcome`, `LibraryBackend` protocol, `LibraryStore` | `KuroCore`, Observation | Single tracking authority with real consumers and a failure-test seam (fake backend) |
| `KuroSupabase` | Designated SDK adapters, one file per capability owner (starts with the Library list adapter + shared client factory) | `KuroCore`, `KuroLibrary`, supabase-swift | The only place SDK payloads/table names may live; split per capability only when consumers or isolation justify it |

Not created up front: Catalog, Clubs, Releases, Concierge/Imports, DesignSystem, Platform targets. Each is introduced only when its stage (E5/E6) demonstrates real consumers, lifecycle or isolation needs; otherwise the capability stays an owned in-app store with an evidence-backed keep decision. The app target keeps composition (`AppComposition`), routing and all SwiftUI features.

Dependency direction (acyclic): features → capability stores/contracts → adapters → SDK. Features never import adapters; `AppComposition` creates the shared SDK client once and injects stores through `@Environment(Type.self)` (concrete `@MainActor @Observable final class`, per the DI inventory), plus value-type closure environment keys for routes.

Isolation policy for package targets (explicit, Swift language mode 5): value types `Sendable`, nonisolated; stores `@MainActor @Observable final`; adapters `Sendable` structs/actors; no reliance on the app's `SWIFT_DEFAULT_ACTOR_ISOLATION`.

## 2. Identity / account lifecycle (E1, implemented in the current architecture)

- `AccountContext { userId: String; generation: Int }`.
- `AccountSessionCoordinator.begin(userId:) -> .started | .unchanged | .switched`, `end()`, `isCurrent(_:)`. Same-user events keep the context (ruling R-E1-1).
- `AccountScopedLoads<Key, Value>`: keyed in-flight loads that join only for the same key and same context, cancel on end, and clear their slot only by token.
- Rule: every async completion publishing private state captures its `AccountContext` at start and checks `isCurrent` before every write. Every private store has exactly one clear rule in one `clearPrivateState()` list per owner.
- Public caches (catalog detail, entity, ladder, disk detail cache) are not account-scoped and are never cleared by sign-out.

## 3. Library

### 3.1 Identity and values
```swift
enum MediaKind: String, Codable, Sendable { case anime, manga }       // existing
struct MediaKey: Hashable, Sendable { let kind: MediaKind; let id: Int } // anime 42 != manga 42
struct UserRating: Hashable, Sendable { let value: Int }                 // 1...10 = database scale; init?(value:) rejects others
extension UserRating { var score100: Int { value * 10 } }               // display/legacy projection only
```
Decision (rating scale): the database stores `rating` 1–10 (`CHECK`, captured live in `BACKEND_EVIDENCE.json` and the baseline). The legacy client model `UserList.score` (0–100 = rating×10) stays a display projection only. Writers never send 0–100 values: this repairs the confirmed defects in `AddToListSheet` (score×10), `incrementProgress` (`entry.score`) and `toggleFavorite` (rating 100), which would violate the CHECK. `isFavorited` (score ≥ 90) is preserved as rating ≥ 9 for read compatibility; the favourite toggle writes rating 10 / clears.

### 3.2 Entry and edit
```swift
struct LibraryEntry: Equatable, Sendable {
  let key: MediaKey; let rowId: Int
  var status: ListStatus; var progress: Int
  var rating: UserRating?; var notes: String?; var verdict: Verdict?
  var createdAt: Date; var updatedAt: Date
  var revision: Int64?          // nil until the server revision fence exists (master §6/§12.3)
}
enum FieldChange<T: Sendable & Equatable>: Sendable, Equatable { case unchanged, set(T), clear }  // clear only where the column is nullable
struct LibraryEdit: Sendable {
  var status: FieldChange<ListStatus> = .unchanged     // never .clear (NOT NULL)
  var progress: FieldChange<Int> = .unchanged          // absolute desired position, never an increment
  var rating: FieldChange<UserRating> = .unchanged
  var notes: FieldChange<String> = .unchanged
  var verdict: FieldChange<Verdict> = .unchanged
}
```
Field ownership: an edit changes exactly the fields it names. A progress change can never overwrite a rating, note, verdict or status, and a stale snapshot is never re-sent (repairs the `setUserProgress` full-row rewrite). Swift can now clear rating/notes/verdict (`.clear` encodes JSON `null`), which the current synthesized-`Encodable` writers cannot.

### 3.3 Reader / writer
```swift
@MainActor protocol LibraryReading {
  func entry(for key: MediaKey) -> LibraryEntry?
  func isTracked(_ key: MediaKey) -> Bool
  func keys(withStatus status: ListStatus, kind: MediaKind) -> Set<MediaKey>
  var allEntries: [LibraryEntry] { get }                     // projection order = updatedAt desc
}
@MainActor protocol LibraryWriting {
  func save(_ key: MediaKey, status: ListStatus) async -> LibraryOutcome        // ensure tracked; NEVER overwrites an existing entry
  func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus?) async -> LibraryOutcome
  func remove(_ key: MediaKey) async -> LibraryOutcome
  func undo(_ change: LibraryChange) async -> LibraryOutcome                    // compensating absolute edit / re-save, not receipt deletion
}
enum LibraryOutcome: Sendable { case applied(LibraryChange); case failed(LibraryError) }
struct LibraryChange: Sendable { let key: MediaKey; let kind: Kind /* added|updated|removed */; let previous: LibraryEntry?; let current: LibraryEntry?; let mutationId: UUID }
enum LibraryError: Error, Sendable {
  case notAuthenticated                // session lost / account changed mid-flight
  case invalidValue(field: String)     // e.g. rating outside 1...10, negative progress
  case notFound                        // edit of a removed entry; never recreates it
  case conflict(server: LibraryEntry?) // reserved for revision conflicts (adapter returns it once the fence exists)
  case retryable(message: String)      // transport / timeout / 5xx
  case unavailable(message: String)    // capability not configured
}
```
`LibraryStore` (`@MainActor @Observable final class`, implements both) is the only authoritative local projection (`entries: [MediaKey: LibraryEntry]`). Lookup structures (`collectionAnimeIds`, `userListByTypeAndId`, `userIdsByTypeAndStatus`, `isInCollection`) are derived from it at read time, never separately mutable copies. The store:
- serializes operations per `MediaKey` (FIFO), allows concurrency across keys;
- applies an optimistic projection, then reconciles with the backend's canonical row; on failure restores the prior value and returns a typed error;
- drops stale reads: a refresh started before a local mutation of key K cannot overwrite K (per-key local sequence);
- is bound to an `AccountContext`: completions for an ended context are rejected, `reset` clears the projection;
- generates `mutationId: UUID` once per operation and passes `baseRevision` (nil today) through to the backend, so durable queueing/idempotency from the master spec can sit behind this interface later without changing consumers. **No durable offline behavior is claimed by this architecture work** (§6 of the master remains product scope).

### 3.4 Backend port and adapter
```swift
protocol LibraryBackend: Sendable {
  func fetchAll(for account: AccountContext) async throws -> [LibraryEntry]
  func edit(_ edit: LibraryEdit, key: MediaKey, createIfMissing: ListStatus?, mutationId: UUID, baseRevision: Int64?, account: AccountContext) async throws -> LibraryEntry
  func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryEntry   // PostgREST ignore-duplicates
  func remove(_ key: MediaKey, account: AccountContext) async throws
}
```
Supabase adapter request contract (`anime_user_lists` / `manga_user_lists`; `user_id` text = `auth.uid()::text`, identity from the account context, RLS enforces ownership):

| Operation | HTTP | Body / filter | Notes |
| --- | --- | --- | --- |
| fetchAll | GET both tables | `select=id,user_id,<anime_id|manga_id>,list_type,progress,rating,notes,verdict,created_at,updated_at` | paged, finite; existing mapping `statusFromDB` preserved |
| edit existing | PATCH `?user_id=eq.<uid>&<anime_id|manga_id>=eq.<id>` | only masked columns; `.clear` → explicit `null`; `Prefer: return=representation` | zero rows → `notFound` unless `createIfMissing` |
| edit with `createIfMissing` | PATCH, then on zero rows POST with `list_type` + masked columns, `Prefer: resolution=ignore-duplicates` | then re-PATCH if the insert lost a race | never resets an existing row |
| insertIfMissing | POST `Prefer: resolution=ignore-duplicates,return=representation` | `user_id, <media>_id, list_type, progress=0` | `save` semantics (fixes W-02/W-13 reset) |
| remove | DELETE same filter | – | tombstone/lifecycle fence is a server concern (master §12.3) |

Errors map: 401/JWT → `notAuthenticated`; 23514 (check) → `invalidValue`; network/5xx/timeout → `retryable`; everything else → `unavailable`. `ListStatus.repeating` has no database representation; the adapter stores it as WATCHING (anime) / READING (manga) exactly as today (unchanged behavior, recorded).

### 3.5 Change fan-out (no global bus)
`LibraryStore` takes an explicit list of `LibraryChangeSink`s from composition (protocol with one method `libraryDidChange(_:)`). Registered sinks: Releases/reminders (schedule/cancel anime airing reminders, refresh upcoming only for anime adds/removes) and Collection (invalidate/refresh its feed page only when the change can affect the current filter). This replaces the unconditional `fetchUserLists + fetchCollectionItems + fetchCollectionFeed + fetchUpcomingForUser` quartet after every write.

### 3.6 Writers outside Swift (fence, not rewrite)
Edge `concierge-apply` / `concierge-undo` and SQL `record_taste_deck_signal('love')` write the same tables. They remain server-side writers; the store reconciles via realtime hints plus an explicit `refresh` after import apply/undo. Their null-clobber/progress-null behavior is audited in E6/E7; a database-owned revision fence for them belongs to the master spec (§3).

## 4. Other capabilities (E5/E6) — contract summaries

- **Catalog**: public, stable provider IDs; read-only readers `CatalogReading` (detail, credits, relations, ladder) over a public cache; no account state; `MediaSummary` (id, kind, title, poster URL, format, year) is the immutable value shared cards receive. Moves the credits/ladder/relation methods now misfiled in `+Clubs` and links/episodes/chapters misfiled in `+UserLists`.
- **Discovery/Search**: query owners with cursors; personalized rails keyed by user id and cleared with the context.
- **Releases + ReminderDelivery**: schedule truth (`user_airing_next`, upcoming) separate from device notification scheduling behind a 2-method seam; reminders are account-scoped.
- **Clubs / SocialActivity / ProviderAvailability**: separate owners; club realtime subscription ownership with late-event guards; permission revocation invalidates private projections.
- **Recommendations/Taste, Concierge/Imports**: transport vs. rules vs. presentation separated; import reconcile/preview/apply/undo decisions leave the views; apply/undo results flow into Library via explicit refresh.
- **Navigation**: features emit typed routes through a value-type environment key (`EnvironmentValues.kuroRoutes`) handled by a presenter each presentation context installs (`.routePresenter()`; pure `RoutePolicy`). As built: `openMedia(MediaRoute)` (a `MediaKey`, optionally with an already-loaded detail model), `openClub(String)`, `presentTrackingEditor(TrackingEditorRequest)` (wraps `any MediaDisplayable`, so the editor can show title/poster/totals as well as edit by key), and `presentAddToClub(MediaKey)` (added during E8; not in the original list).
- **Runtime**: the `FeatureFlags` instance built once in `AppComposition` is injected where flags are read; `FeatureFlags.shared` is gone (blocking check in `check_architecture.sh`). A separate read-only `RuntimeFlags` snapshot type was NOT introduced (deviation from the original design: a second type over the same data added a copy without a consumer that needed it).

## 5. Contract examples (selected failure/success cases)

| Case | Input | Expected |
| --- | --- | --- |
| Rated entry +1 episode | `apply(.progress(set 5), to: anime 42)` on an entry with rating 8 | PATCH body `{"progress":5}` only; rating stays 8 |
| Clear a note | `apply(.notes(.clear))` | PATCH body `{"notes":null}` |
| Rating out of range | `apply(.rating(set UserRating(value: 80)))` | `UserRating.init?` is `nil`; no request is made |
| Save an already tracked title | `save(anime 42, .planning)` where the entry is COMPLETED | no overwrite; returns `applied` with the existing entry unchanged |
| Edit a removed entry | `apply(...)` with no row and `createIfMissing == nil` | `.failed(.notFound)`; no row recreated |
| Equal numeric ids | `anime 7` and `manga 7` | distinct keys, distinct tables, independent projections |
| Account switch mid-flight | A's edit completes after B signed in | `.failed(.notAuthenticated)` for A's caller; B's projection untouched |
| Overlapping edits same key | two `apply` calls started together | executed FIFO; final projection = server's last canonical row |
