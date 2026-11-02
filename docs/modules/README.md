# Kuro modules — navigation map and developer guide

How Kuro is organised during the modular-architecture migration ([execution brief](../plans/2026-10-05-modular-architecture-plan.md), [ledger with evidence and rulings](../plans/2026-10-05-modular-architecture-execution-ledger.md), [contracts](../plans/2026-10-05-modular-architecture-contracts.md), [ownership map](../plans/2026-10-05-modular-architecture-ownership-map.md)). `CURRENT_APP_STATE.md` stays the technical authority for product behavior; this page tells you where things live and how to change them safely.

> Current acceptance: [integrated execution and all findings](../handoffs/2026-10-07-integrated-testflight-execution.md) and [finding register](../plans/2026-10-05-modularity-completion-register.csv). This map describes ownership; it does not certify every gate or production release. App-folder boundaries remain conventions outside the three package targets.

## Import recovery and shared tracking implementation

[Current import/Library/Home specification](../plans/2026-10-08-import-library-home-completion.md) and [finding dispositions](../handoffs/2026-10-08-backend-integration/import-user-journey-review.md) govern this initiative. Imports owns selection, protected source pages, reviews, immutable decisions, job results and compensation. Library owns affected-title FIFO admission, durable local intent and authoritative tracking. Home, Collection and Releases consume its publication hook. Imported-title navigation is a Collection filter, never another list authority.

Contract types live in `KuroLibrary/LibraryImportWorkflow.swift`; protected manifests in `LibraryImportWorkflowJournal.swift`; app orchestration is split across `ImportsService+Workflow`, `+WorkflowSources` and `+WorkflowRPC`. Native presentation lives in `ImportWorkflowSheet`, `ImportHistorySection` and `ImportCatalogMatchPicker`. SDK transport stays behind owners. The approximately 400-line journal remains cohesive because atomic persistence, retirement and account deletion share one protected-record lifecycle; parser and source transport policies remain separate.

Apply/Resume/Undo reserve affected Library keys through the same typed API. Attempted approvals and bodies remain immutable. Private asynchronous work retains credential leases and generation checks. New capabilities define one lifecycle owner, typed consumers, account scope and the smallest meaningful failure proof, then register once in composition. Removal first retires consumers, tasks and composition; it never authorizes deleting historical migrations or customer data. Changed authentication, permissions, recovery and deployment contracts require focused independent review.

## Current implementation rules

The [integrated executor and rules](../handoffs/2026-10-07-integrated-testflight-execution.md) cover both product waves and all release gates. No hard line caps: files400–600lines, stateful types350–500including extensions and capabilities2,000–3,000are review signals only. Keep/split depends on independent authority, lifetime, permissions, dependencies and recovery. Library owns durable tracking; Home caches a bounded personal snapshot, never club bodies. Profile import policy and Concierge chat-action lifetime have named owners; ordinary presentation stays account-keyed in views. Local cache/owner tests do not prove installed/live behavior.

TastePicksView is the mounted Taste surface. The unreferenced TasteDeckView alternative is deferred; retained server/model contracts are compatibility inputs, not a second current product.

Capability model/RPC contracts now live with Catalog, Imports, Providers, Discovery, Search, Collection, Clubs and Social. Retired central model/RPC files are absent. The ownership manifest must include new Home snapshot, Profile coordinator and Concierge lifetime sources.

## The shape in one paragraph

One capability = one **owner** that holds its state, its caches, its tasks and its Supabase queries, and exposes a small typed API. Owners are `@MainActor @Observable final class`es (plain value types for contracts), built **once** in `Kuro/Composition/AppComposition.swift` over **one** Supabase client, and read by views through `@Environment(Type.self)`. Account-scoped owners implement `AccountScopedState` and are cleared by one funnel (`SessionController`). Only the Library domain is compiled into package targets (`KuroLibrary`, plus the shared identity/account-scoping contracts in `KuroCore` and its SDK-free list adapter in `KuroSupabase`; it has a real failure-test seam); every other owner is an in-app folder by recorded decision (they depend on app model/presentation types and are read by 1–12 view files each, and a target would add no isolation or test benefit).

## Map

| Capability | Where | Owner / entry point | State lifetime |
| --- | --- | --- | --- |
| Identity, session, deletion | `Kuro/Identity/` | `IdentityStore` (state), `AuthService` (SDK auth calls), `SessionController` (the E1 lifecycle funnel) | App lifetime; drives every account transition |
| Library (tracking) | `Packages/KuroModules/` (`KuroCore`, `KuroLibrary`, `KuroSupabase`), `Kuro/Composition/PostgrestLibraryTransport.swift`, `Kuro/Library/` | `LibraryStore` (the ONLY tracking projection), `LibraryActions` (view-facing writes + banners), `LibraryRealtime` (list-change channel) | Account-scoped; `loadState` gates imports |
| Home / series serving | `Kuro/Home/` | `HomeStore`, typed Home/detail contracts, `HomePersonalSnapshotCache`; progress delegates to Library | Account-scoped personal projection and permission-scoped club data; bounded personal disk cache excludes social/club bodies |
| Catalog (details, credits, relations, units) | `Kuro/Catalog/` | `CatalogStore` | Public caches survive sign-out |
| Discovery + Browse | `Kuro/Discovery/` | `DiscoveryStore`, `RecommendationsReader` | Public caches; personalised rails account-keyed |
| Search | `Kuro/Search/` | `SearchStore` | Per-query; new query cancels the old |
| Collection (feed projection) | `Kuro/Collection/` | `CollectionStore` (no tracking fields: Library is the authority) | Account-scoped |
| Releases + reminders | `Kuro/Releases/` | `ReleasesStore`, `ReminderScheduler` (not an `AccountScopedState`: `SessionController` calls its account rules directly) | Account-scoped; reminders removed on account end |
| Provider availability | `Kuro/Providers/` | `ProviderAvailabilityStore` (public registry; private user/club-shared halves) | Public half survives sign-out |
| Social activity | `Kuro/Social/` | `SocialActivityStore` | Account- and permission-scoped |
| Clubs + realtime | `Kuro/Clubs/` | `ClubsStore`, `ClubRealtimeCoordinator`, `ClubError`, `ClubsLibrarySink` | Account-scoped; revocation invalidates |
| Imports / Concierge | `Kuro/Imports/`, `Kuro/Concierge/` | `ImportsService`, `ProfileImportCoordinator`, `MALNativeAccountConnector` (configured only after registration approval), `ImportsService+MALAccount`, `KuroLibrary.MALAccountListReader`, `ImportReconciler`, `ConciergeStore`, `ConciergeRouting`, `ConciergeWorkflowLifetime` | Caches account-scoped; conversation session-local (by policy) |
| Taste | `Kuro/Taste/` | `TasteStore` (deck RPCs, bounded signal outbox) | Account-scoped |
| Telemetry | `Kuro/Telemetry/` | `InteractionTelemetry`, `OutboundLinkTelemetry` | Offline queue account-scoped |
| Navigation (typed routes) | `Kuro/Views/Routing/` | `EnvironmentValues.kuroRoutes` (`openMedia`, `openClub`, `presentTrackingEditor`, `presentAddToClub`), `.routePresenter()`, pure `RoutePolicy` | One route slot per presentation context |
| Detail pages, shared cards | `Kuro/Views/DetailPages/` ([detail-pages.md](detail-pages.md)), `Kuro/Views/SharedCards/`, `Kuro/Design/FlowLayout.swift` | Anime/Manga pages + `DetailSharedComponents`, `ProviderLinkViews`; `CompactAnimeCard`, `GridAnimeCard`, `AddToClubRailSheet`; link policy in `ProviderAvailabilityStore+DetailLinks` / `ProviderLinkBuilders` | View state; keyed/cancellable screen loaders and owned paging tasks |
| Shared infrastructure | `Kuro/Infrastructure/`, `Kuro/Composition/BannerCenter.swift` | `TimedCache`, `withRetry`, `MemoryPressureTrimmable`, `BannerCenter` | App lifetime |
| Runtime flags, config, FM | `Kuro/Services/` | `FeatureFlags` (injected instance), `AppConfig`, `AppleFMService` (existing `FMProvider` seam) | App lifetime |
| Composition root | `Kuro/Composition/` | `AppComposition` (`makeGraph` builds production and test graphs), `LibraryChangeSinks`, `LibraryRefreshHook`, `AccountScopedState` | App lifetime |
| Backend | `supabase/functions/*`, `supabase/migrations/` | See [edge functions](edge-functions.md), [operations](operations.md), [SQL function index](sql-function-index.md) | n/a |
| DB tests | `supabase/tests/`, `scripts/db/` | `scripts/db/run_local_db_tests.sh` (throwaway local Postgres, audited-schema fixture) | n/a |

Prepared-but-not-deployed backend changes live in `supabase/prepared-migrations/` (outside the deploy path on purpose) and the edge functions listed in the ledger.

## Rules that are enforced

| Rule | Enforced by |
| --- | --- |
| Package target graph is acyclic; targets import only what they declare; files import the module whose declarations they use | SwiftPM + `MemberImportVisibility` (`scripts/quality-gates/test_packages.sh`, the app build) |
| No code references the retired `SupabaseService`; no `FeatureFlags.shared`; no SDK imports in views; list tables named only in the Library transport/realtime; the package stays SDK-free and UI-free; legacy writer mapping lives only in `LibraryActions` | `scripts/quality-gates/check_architecture.sh` |
| Account isolation: every async completion that publishes private state captures its `AccountContext` and checks `isCurrent` before every write; every private store has one clear rule in its owner's `clearPrivateState()`; the registered list is built in one place | `AccountLifecycleTests`, `IdentityCompositionTests` (exact membership and order), per-owner stale-completion tests |
| One write authority for tracking | `LibraryStore` (per-key FIFO, optimistic projection, typed `LibraryOutcome`/`LibraryError`) + the HTTP-level contract tests |
| Safety-critical lifecycle order (context invalidated before the first suspension; SDK sign-out before channel teardown; deletion clears local state only after confirmed success; fail-closed auth-callback guard with `exp` requirement) | `SessionController` + the order tests; see the E1 section of the ledger before touching it |

## Mounted private actions

`KuroCore.AccountActionScope` captures the rendered `AccountContext`, presentation generation and scope instance before creating work. Screens retain/cancel their tasks and guard dispatch/publication; club-derived work also uses current permission generation. It is an admission helper, not an alternative account owner or generic task framework. Library retains mutation authority. `MALNativeAccountConnector` owns OAuth/Keychain/provider generation; `ImportsService+MALAccount` owns both-medium journal/checkpoint orchestration; `KuroLibrary.MALAccountListReader` owns provider fields and pagination policy.

## Verify a change

```bash
# package (host, fast)
cd Packages/KuroModules && swift test
# app unit tests (simulator)
xcodebuild -project Kuro.xcodeproj -scheme Kuro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KuroTests
# repository gates (secrets, migrations, corpora, router, docs, architecture, packages, builds)
SKIP_RAILS_AUDIT=1 scripts/quality-gates/run_all.sh     # rails audit needs the live project
# local database authorization tests (throwaway Postgres; refuses any non-local target)
scripts/db/run_local_db_tests.sh
# edge function rules (per function directory)
(cd supabase/functions/concierge-apply && deno test)
```

## Add a capability

1. **Name the owner and its invariants** in one sentence (what it owns, which state, which lifetime, who consumes it).
2. **Create the folder** `Kuro/<Capability>/` with the owner (`@MainActor @Observable final class`). Take the Supabase client by initializer (never create a second client); keep the client `private let client: SupabaseClient?` behind a guard so a missing configuration fails like a transport error.
3. **Decide account scope.** Public data: no scoping, survives sign-out. Anything derived from the user, their lists, clubs or permissions: conform to `AccountScopedState` (`cancelAccountWork()`, `clearPrivateState()`), capture `AccountContext` at the start of every async operation and guard `accountSession.isCurrent(context)` before every private write; key caches by user.
4. **Register it** in `AppComposition` (one `make…` builder used by both production and `testingGraph`), add it to `makeAccountScopedStates` if it is account-scoped (order matters; the composition test asserts it), and inject it into the environment in `KuroApp.swift`.
5. **Expose typed values, not SDK payloads.** Views never import `Supabase`/`PostgREST`/`Realtime`/`Auth`/`Functions`/`Storage`; map errors to a typed error at the owner boundary.
6. **Verify the changed risk** using an existing meaningful test where possible. For a new transport or lifecycle failure, use the real SDK against `StubPostgREST` (request shape, a late account completion or revoked permission); add only a missing regression case. Mutation checks are optional when they resolve uncertainty about an assertion. Do not add getter/forwarder tests, duplicate layers or rerun unaffected suites.
7. **Wire consumers** through `@Environment(Type.self)`; sibling features reach each other only through typed owner APIs or the route environment key (`@Environment(\.kuroRoutes)`: open another feature's detail, editor, club or add-to-club sheet instead of constructing it), never through another feature's private types. A new sheet whose content contains routed cards installs its own `.routePresenter()`.
8. **Run the affected checks**, then update the ownership map and the three canonical state documents. Use the full integrated set once when preparing a release candidate, not after every small edit.

## Remove a capability

1. List its consumers (`rg` the owner type and its environment key) and remove their routes/controls first.
2. Stop its owned work: drop it from `makeAccountScopedStates`, cancel tasks/subscriptions in its `cancelAccountWork()`, and remove its builder from `AppComposition`.
3. Delete its folder and tests; keep shared contracts other owners use.
4. Run `check_architecture.sh`, affected consumer tests and the docs gate. Removing a feature never authorizes dropping user data, historical migrations or deployed RPCs: those need their own approved migration.

## Historical route checklist (NOT run; no independent exhaustive release gate)

The current integrated release requires six representative installed journeys rather than this older sixteen-route matrix. Use individual cases below only when a changed route warrants them. The typed routes are unit-tested only as a pure policy (`RoutingTests`); whether each sheet actually appears and stacks needs a simulator or device. None of these journeys was run during the migration (source: the routes lane report and its review):

1. Discover: card → detail → "MORE LIKE THIS" card; the second detail stacks and animates as before.
2. Discover hero and The One Thing each open the detail.
3. "See all": grid card → detail over the sheet; long-press → Add to List… and Add to Club… (needs a club).
4. Browse: hero and grid → detail; grid long-press → editor and add-to-club.
5. Search: row → detail over Search; long-press → editor.
6. Collection: grid → detail; long-press "Edit List" → editor; list row → detail; QuickVerdict sheets unchanged.
7. Clubs: club → rail item → detail; repeat via Profile → Clubs → club → rail item (three levels).
8. Detail action bar: ADD TO LIST → editor over the detail; Verdict; Watch/Read provider sheet.
9. Detail → Cast → character: work card → detail; long-press → editor and add-to-club.
10. Concierge (Profile sheet and `--kuro-start=concierge`): recommendation → detail with no spinner; a not-found recommendation shows the inline error; an import-card poster/title opens the preview detail.
11. Deep links `kuro://anime/N`, `kuro://manga/N`, `kuro://club/ID`, cold and warm: a second link replaces the open detail; a link while Search is open does nothing; a link under the Onboarding cover behaves as before.
12. A fast double tap on a card opens one sheet.
13. A pager swipe over cards opens no detail (UI test `testSwipeDoesNotOpenCardDetail`).
14. Behaviour deltas: pull down in a detail opened from Discover (page refresh is no longer inherited); Collection Watching filter → mark completed (the sheet stays up).
15. Root install: a cold-start `kuro://anime/N` presents the detail.
16. Sheet-site install: Profile → Concierge → recommendation presents the detail.

Also device-only: replace animation, a failed presentation leaving a stale slot (a later tap on the same title is ignored), a deep link discarding an open root editor's unsaved edits, and destinations inheriting styling from the context root. The Concierge-rules lane adds two checks no unit test sees: on a first parse a tracked line with ambiguous adaptations groups under Add; with `clarify_v2` off an "I watched X" line auto-applies in Concierge but goes to review from Profile.

## Where the open items live

The ledger's "Blockers and open gates", "Prepared, NOT deployed" and per-stage notes list what is not done and why (production casing check for `user_id`, club RLS decisions, edge deployments, device/UI journeys, hosted capacity). Nothing here claims those pass.
