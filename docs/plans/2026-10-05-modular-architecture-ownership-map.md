# Kuro modular architecture — ownership map

Evidence for gate G3. **The tables below are the 5 October owner-map snapshot** (state of the local checkout on 2026-10-05: executed locally, uncommitted, nothing deployed; structure verified by source inspection). Gate results, test counts and review dispositions are recorded only in the [execution ledger](2026-10-05-modular-architecture-execution-ledger.md); this map claims no gate as passed. How to add or remove a capability: [docs/modules/README.md](../modules/README.md). Contracts: [contracts](2026-10-05-modular-architecture-contracts.md).

## Companions

- [Ownership manifest](2026-10-05-modular-architecture-ownership-manifest.csv): current machine-readable source snapshot (refreshed during continuation; not gate acceptance): every Swift file in `Kuro/`, `Packages/` and the test targets with its kind, final capability owner, git state and line count. The historical table sizes and reader counts below are not current metrics. If they disagree, current code and the refreshed manifest win.
- [E0 baseline manifest](2026-10-05-modular-architecture-ownership-manifest-e0-baseline.csv): the pre-migration manifest generated at E0 (HEAD `471c609` plus the dirty tree; 94 files in `Kuro/`, 4 test files) with the owners **proposed at E2**, production status, service members used, singleton references and SDK imports. History only.
- [Service member map](2026-10-05-modular-architecture-service-member-map.csv): E0 baseline of every stored property, method and nested type of the 13 `SupabaseService` files (525 rows incl. 27 from the 68-line dead `#else` mock) with the owner proposed at E2, state kind, account scope, sign-out clearing and caller files. Line numbers are against the E0 tree and were not rewritten as members moved; the **name** column is the stable key. Use it for archaeology (which old member went where).
- [Large-file review](2026-10-05-modular-architecture-large-file-review.md): keep/split decisions for the large files and owners (G6).
- [Test matrix](2026-10-05-modular-architecture-test-matrix.md): risk-to-test mapping for the migration (G5).
- [Detail pages map](../modules/detail-pages.md): files, load tables and the provider-link snapshot of the decomposed Anime/Manga detail pages.
- Per-stage state/lifetime and write maps (E2 inventories) feed the owner sections of the contracts.

## Current continuation (7 October 2026)

The approved integrated release combines modularity and Home/series. Current ownership is in [the developer map](../modules/README.md), the refreshed source manifest and [the integrated executor/all114findings](../handoffs/2026-10-07-integrated-testflight-execution.md). The table below is historical, including its sizes/readers.

- Library owns tracking sequencing, confirmed/pending state, SQLite outbox, immutable attempted actions, ACK and compensation. Home/detail consume it; no second mutation queue.
- HomeStore owns typed serving, permission-scoped projections and a bounded personal cache. Personal snapshots exclude club/social bodies. Home's deletion hook purges only the captured account and blocks late writes.
- SessionController owns account transition and SDK credential ordering; AuthService hides SDK work. Flags privately read tester enrollment through leases and keep only bounded exact-account presentation eligibility.
- ImportsService owns shared structured jobs, provider namespace and account-scoped journal. ProfileImportCoordinator owns a mounted card's frozen retry/Undo/file/task lifetime. MAL native OAuth credentials have one Keychain owner; both-medium account-list ingestion is implemented in ImportsService+MALAccount using the typed KuroLibrary reader; actual registration/consent remains unqualified. AccountActionScope in KuroCore owns mounted action admission only; SessionController remains the account lifecycle owner.
- ConciergeWorkflowLifetime owns action origin/cancellation per mounted account/chat. Routing/reconcile policy already has capability owners; conversation rendering remains local.
- Capability models/RPCs live beside their owners; shared catalog values have one home. Collection owns only its visible feed; unused card arrays/Genre Hub are retired. TastePicksView is mounted; TasteDeckView alternative is explicitly deferred.
- Backend runs/operational roots retain compatibility slugs/wrappers. Mixed lifecycle orchestration needs semantic owner/risk review, not line-limit splits.

App-folder access still relies partly on conventions. Existing seven architecture checks enforce meaningful boundaries; they are not a complete dependency AST graph or proof of every feature's runtime. F51/F54/F55/F56 and final native/live release evidence remain explicitly assessed in the register.

## Composition — 5 October snapshot

`Kuro/Composition/AppComposition.swift` builds the graph once (`makeGraph`, also used by KuroTests through `testingGraph`) over one `SupabaseClient` and one `AccountSessionCoordinator`. `KuroApp` injects the view-facing owners with `.environment(...)`; views read them with `@Environment(Type.self)`. Account-scoped owners conform to `AccountScopedState` and are registered once in `makeAccountScopedStates` (order: `LibraryActions`, `CollectionStore`, `DiscoveryStore`, `ReleasesStore`, `SocialActivityStore`, `ProviderAvailabilityStore`, `ClubsStore`, `ImportsService`, `ConciergeStore`, `TasteStore`, `InteractionTelemetry`); `SessionController` cancels and clears exactly that list on every account transition, after rebinding/resetting `LibraryStore` itself. `memoryPressureOwners` is the one list of owners that shed public caches (Catalog, Discovery, Imports, Concierge).

## Capability owners (final)

"Readers" = view/app files reading the owner through `@Environment` on 2026-10-05 (`rg -l "@Environment(<Type>.self)" Kuro`).

| Capability | Where | Owner types | Readers | State owner and lifetime | Keep / split decision |
| --- | --- | --- | ---: | --- | --- |
| Identity / session / deletion | `Kuro/Identity/` | `IdentityStore`, `AuthService`, `SessionController`, `AuthCallbackGuard` | 7 / 2 / 3 | `IdentityStore` is the only holder of UI auth state (app lifetime); the account context (`AccountContext`, generation) lives in `KuroCore.AccountSessionCoordinator`; `SessionController` is the single transition funnel | Split by responsibility: observable identity vs SDK auth transport vs lifecycle funnel (ordering is safety-critical and tested). In-app: depends on supabase-swift Auth and app types |
| Library (tracking) | Package `Packages/KuroModules` (`KuroCore`, `KuroLibrary`, `KuroSupabase`); app `Kuro/Composition/PostgrestLibraryTransport.swift`, `Kuro/Library/LibraryActions.swift`, `Kuro/Library/LibraryRealtime.swift`; view adapters `Kuro/Views/LibraryViewActions.swift`, `Kuro/Views/TrackingDraft.swift` | `LibraryStore`, `SupabaseLibraryBackend`, `UserIdText`, `LibraryActions`, `LibraryRealtime` | 16 (store) / 11 (actions) | One projection `[MediaKey: LibraryEntry]`, account-scoped, rebound/reset by the funnel; `loadState` gates import apply; per-key FIFO writes | **Compiled targets** (R-E2-1): single write authority with a real failure-test seam (controlled backend), SDK-free adapter testable on the host. The SDK binding stays in the app so there is one client. `LibraryActions` is the one view-facing writer mapping (legacy writer names, banners, double-tap guard) |
| Catalog | `Kuro/Catalog/` | `CatalogStore` (+ `DiscoveryContentRules`, `MissingSupabaseConfiguration`) | 6 | Public caches (detail, entities, ladder, links, units) survive accounts; memory-pressure trimmable | Keep cohesive in-app (950 lines, one public read owner). Absorbed the catalog reads misfiled in `+Clubs` (credits/entities/ladder) and `+UserLists` (links, episodes, chapters). No target: depends on app models (`Anime`, `Manga`, …) and gains no isolation/test benefit |
| Discovery + Browse | `Kuro/Discovery/` | `DiscoveryStore`, `RecommendationsReader`, `DiscoverCards` | 6 / 2 | Bundle/rails cached publicly; personalised results account-keyed (`DiscoveryStore` is account-scoped) | In-app by E5a decision (app presentation dependencies, view consumers, no target benefit) |
| Search | `Kuro/Search/` | `SearchStore` | 2 | Per query; a new query cancels the previous in-flight page | In-app; separate from Discovery because its cancellation policy differs |
| Collection | `Kuro/Collection/` | `CollectionStore` | 4 | Account-scoped card pages and feed; refreshed by the Collection Library sink | In-app; holds no tracking fields (Library is the authority) |
| Releases + ReminderDelivery | `Kuro/Releases/` | `ReleasesStore`, `ReminderScheduler` (`PendingNotificationCenter` seam) | 2 | Upcoming/countdowns account-scoped; reminders removed on account end, kept for the restored owner (funnel calls the scheduler directly) | Split schedule truth from device delivery; `ReleasesStore` hosts the Library change sink |
| ProviderAvailability | `Kuro/Providers/` | `ProviderAvailabilityStore` (+ `LegalLinks`, + `DetailLinks`: the one `ProviderLinkSnapshot` API and the one `validatedOutboundURL`), pure `ProviderLinkBuilders` | 6 | Public registry/availability survive sign-out; user services and club-shared providers account-scoped (`invalidateClubSharedProviders(clubId:)`) | One store with two explicit halves (keep). Detail-page link resolution and the outbound-URL validator moved here from the two detail views (large-file review D2); tested by `DetailProviderLinksTests` |
| SocialActivity | `Kuro/Social/` | `SocialActivityStore` | 5 | Friend counts/comments account- and club-membership-scoped (`invalidateFriendProjection()`) | Separate from Clubs: different lifetime and consumers |
| Clubs | `Kuro/Clubs/` | `ClubsStore`, `ClubRealtimeCoordinator`, `ClubsLibrarySink`, club models, `ClubError` | 12 | (user, club)-keyed 300 s bundle cache; `invalidateClub` on leave/membership loss; realtime channels owned by the coordinator | Realtime split into its own coordinator with a fakeable channel seam; one typed error classifier |
| Imports | `Kuro/Imports/` | `ImportsService`, `ImportReconciler`, import models | 2 | Account-scoped parse cache and export; apply/Undo reach the Library through `LibraryRefreshHook` | Pure reconcile/auto-apply rules split out of the views into `ImportReconciler`, incl. `initialSelections` and `autoApplyPlan` shared by Concierge and Profile (large-file review §9 item 2) |
| Concierge | `Kuro/Concierge/` | `ConciergeStore`, `ConciergeRouting` (pure clarification gate, FM/keyword routing thresholds, input-field intent/paste rules) | 1 | Account-scoped caches; conversation session-local (policy unchanged) | In-app; routing decisions extracted from `ConciergeView`/`ConciergeInputField` into `ConciergeRouting` and tested by `ConciergeRoutingTests` |
| Taste | `Kuro/Taste/` | `TasteStore`, taste models | 2 | Account-scoped; bounded signal outbox drained on foreground | In-app; `TasteDeckView` delegates signal delivery to the store |
| Support (2026-11-02) | `Kuro/Support/` | `SupportStore` (contact form: `ContactDraft`, `ContactTopic`, `ContactSubmitState`) | 1 (`ContactSheet`) | Account-scoped draft and send state, cleared on every transition (registered in `makeAccountScopedStates` after `TasteStore`, before `InteractionTelemetry`); one `contact-submit` call per send as a credential lease, never auto-retried | In-app, own folder: different lifetime and consumers from Identity; the function and its table are prepared, not deployed |
| Telemetry | `Kuro/Telemetry/` | `InteractionTelemetry`, `OutboundLinkTelemetry` | 4 / 3 | Interaction queue account-scoped (cleared last); outbound ledger fire-and-forget | `+Monetization` became `OutboundLinkTelemetry` (existing logging only; no StoreKit/paywall capability) |
| DeviceIntelligence | `Kuro/Services/AppleFMService.swift` | `AppleFMService` | 4 | App lifetime; one instance per graph | Kept behind the existing `FMProvider` seam; falls back through its own availability guards (capabilities return `nil`); the defined `StubFMProvider` is never instantiated |
| RuntimeConfig | `Kuro/Services/FeatureFlags.swift`, `AppConfig.swift` | `FeatureFlags` (injected instance), `AppConfig` | 13 | Global, non-private; the funnel sets the rollout user id | `FeatureFlags.shared` removed; one instance injected. The `RuntimeFlags` read-only snapshot proposed in contracts §4 was not created |
| Navigation (typed routes) | `Kuro/Views/Routing/KuroRoutes.swift` | `KuroRoutes` (`EnvironmentValues.kuroRoutes`: `openMedia`, `openClub`, `presentTrackingEditor`, `presentAddToClub`), `.routePresenter()`, pure `RoutePolicy` | 15 readers in 13 files; 13 presenter installs | One route slot per presentation context (`@State`); same id is ignored, a different one replaces | Value-type environment key handled by presenters, no global router. 26 cross-feature constructions migrated; Catalog-private sections and Clubs-internal sheets stay private. Recorded deviation from contracts §4: the tracking-editor route carries `any MediaDisplayable` (id still the `MediaKey`); `presentAddToClub` added. Tested: `RoutingTests` (pure policy only) |
| Detail pages | `Kuro/Views/DetailPages/` (`AnimeDetailView`, `MangaDetailView`, `DetailSharedComponents`, `ProviderLinkViews`, …) | views; link policy in ProviderAvailability | – | Page-scoped `.task(id:)` loaders; load table in each page header | Decomposed per large-file review D1–D3: shared chrome extracted, provider-link resolution moved to the owner, cancellation check added, load tables documented. Distinct Anime/Manga designs kept. Map: [detail-pages.md](../modules/detail-pages.md) |
| Shared cards / sheets | `Kuro/Views/SharedCards/` (`CompactAnimeCard`, `GridAnimeCard`, `AddToClubRailSheet`) | connected views | – | View state only | Moved verbatim out of `EditorialDiscoverView` / `ClubActivitySection` (large-file review §9 item 3); kept in the app as connected components by recorded decision (they read Library/Clubs owners and routes) |
| Shared infrastructure | `Kuro/Infrastructure/`, `Kuro/Composition/BannerCenter.swift` | `TimedCache`, `withRetry`, `MemoryPressureTrimmable`/`MemoryPressureRelief`, `BannerCenter` | 3 (banner) | App lifetime; no private state | Neutral helpers moved out of the service unchanged |
| DesignSystem / ImagePipeline / disk detail cache | `Kuro/Design/` (incl. `FlowLayout.swift`, moved from `AnimeDetailView`), `Kuro/Services/ImagePipeline.swift`, `Kuro/Services/KuroDiskDetailCache.swift` | – | – | Public data | Not moved; no target justified |
| AppShell / composition | `Kuro/KuroApp.swift`, `Kuro/ContentView.swift`, `Kuro/Composition/` | `AppComposition`, `AppGraph`, `LibraryChangeSinks`, `LibraryRefreshHook`, `AccountScopedState` | – | Composition only | Root files received minimal mechanical edits only (R-E8-1; user-dirty) |

**Why only the Library domain is compiled (recorded decision, R-E2-1 / E5a):** `KuroCore` and `KuroLibrary` carry the contracts and the single write authority that need host-speed failure tests; `KuroSupabase` keeps the list-table payload contract SDK-free. Every other owner depends on app model/presentation types, is read by 1–12 view files, and a target would add access-control churn without isolation or test benefit. Catalog, Discovery, Search, Releases, Providers, Social, Clubs, Imports, Concierge, Taste, Telemetry and DesignSystem targets were therefore not created; the contracts are target-agnostic, so a later extraction does not change consumers.

## Retired concentrations

The `SupabaseService` family (13 files; 7,154 lines in the E0 working tree, i.e. 7,141 at HEAD plus the user's `--kuro-skip-auth` DEBUG hook, which is preserved in `Kuro/Identity/SessionController.swift` and `Kuro/KuroApp.swift`) is deleted. Where each part went:

| Retired file (HEAD lines) | Destination |
| --- | --- |
| `SupabaseService.swift` (2,972) | Auth, restore, SDK listener, sign-in/out, callbacks, deletion → `IdentityStore` / `AuthService` / `SessionController`; config error → `AppComposition.makeClient` + `IdentityStore.configError`; user lists and lookups → `LibraryStore` + `LibraryActions`; user-list channel → `LibraryRealtime`; detail data and entity caches → `CatalogStore`; `withRetry` / timed caches / memory trim → `Kuro/Infrastructure/`; banner → `BannerCenter`; interaction events → `InteractionTelemetry`; `fmService` → injected `AppleFMService`; `#else` mock and dead members deleted |
| `+Browse` (193) | `DiscoveryStore` (`browse_*_page`) |
| `+ClubRealtime` (143) | `ClubRealtimeCoordinator` |
| `+Clubs` (835) | Club CRUD, bundles, reactions, polls, notifications → `ClubsStore`; credits, entities, ladder (lines 484–835 at E0) → `CatalogStore` |
| `+Collection` (495) | Card pages and feed → `CollectionStore`; tracking reads → `LibraryStore` |
| `+Concierge` (137) | Parse, apply/Undo, AniList import, export → `ImportsService`; recommend, warmup, feedback → `ConciergeStore` |
| `+Discover` (325) | `DiscoveryStore` |
| `+Monetization` (51) | `OutboundLinkTelemetry` |
| `+Recommendations` (217) | `RecommendationsReader` |
| `+Social` (120) | `SocialActivityStore` |
| `+Streaming` (402) | `ProviderAvailabilityStore` (+ `LegalLinks`) |
| `+Taste` (412) | `TasteStore` (incl. personalised NEW TO YOU, now account-guarded) |
| `+UserLists` (839) | List writers → `LibraryStore` / `LibraryActions`; upcoming + notifications (lines 371–525 at E0) → `ReleasesStore` / `ReminderScheduler`; links, episodes, chapters (lines 525–817 at E0) → `CatalogStore` |

33 nested `SupabaseService.*` types moved with their owners (namespace removed). `check_architecture.sh` fails on any reference to the retired service.

## Shared presentation (final)

- Tracking editor: `AddToListSheet` stays in `Kuro/Views/`; its save rule is the pure `TrackingDraft` (the one `LibraryEdit` a save sends), and every view write goes through the typed-key adapters in `LibraryViewActions` to `LibraryActions` (no view writes `LibraryStore` directly; enforced).
- Club actions, provider and friend projections reach views through their own owners (`ClubsStore`, `ProviderAvailabilityStore`, `SocialActivityStore`), not a global service; views import no SDK module (enforced).
- `GridAnimeCard`, `CompactAnimeCard` (from `EditorialDiscoverView`) and `AddToClubRailSheet` (from `ClubActivitySection`) now live in `Kuro/Views/SharedCards/`; `FlowLayout` moved to `Kuro/Design/FlowLayout.swift`; `KuroCompactCard` stays in `KuroRefinedCard.swift`.
- Cross-feature detail, tracking-editor, club and add-to-club sheets are opened through the typed routes (`Kuro/Views/Routing/KuroRoutes.swift`), not constructed by the caller.
- Dead code deleted: `Cards.swift`, `EditorialCards.swift`, `UIComponents.swift`, `PosterView.swift`, `ConciergeIntentDeck.swift`, `ConciergeActionFooter.swift`, `ConciergeComposerDock.swift`. `GenreHubView.swift` stays (still unreferenced by grep; not deleted by this work).
- `Kuro/Views/TastePicksView.swift` (the user's untracked WIP) received only the minimal mechanical API swaps authorized by R-E6-1.

## Contract items: deviations and what is still open

- Typed navigation outputs (contracts §4): implemented in the final routes lane (above). Deviations recorded: `presentTrackingEditor` takes `any MediaDisplayable`; `presentAddToClub` added; no full-screen-cover route (no cross-feature site used one). Presentation behaviour (sheets appear and stack, deep links cold/warm, double tap, the behaviour deltas) is established by reasoning only; the device smoke journeys in `docs/modules/README.md` were NOT run.
- `RuntimeFlags` read-only snapshot (contracts §4): not introduced; the single `FeatureFlags` instance is injected instead.

## Decisions recorded at E2 (history)

- Keep one source of truth per concern: `SupabaseService` became a temporary forwarding facade holding no second copy of migrated state (R-E2-2) and was deleted after its last consumer migrated.
- Targets: `KuroCore`, `KuroLibrary`, `KuroSupabase` initially (contracts §1); everything else stays an owned in-app store unless a stage demonstrates a target is warranted. No later stage did.
- Large-file keep/split decisions are recorded per stage in the ledger and summarised in the table above.
