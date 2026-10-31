# Kuro modular architecture: large-file semantic review (gate G6)

Companion to the [plan](2026-10-05-modular-architecture-plan.md) (§2 G6, §4 "Full execution does not mean rewriting every file", §5 "Size and complexity"), the [ownership map](2026-10-05-modular-architecture-ownership-map.md) and the [execution ledger](2026-10-05-modular-architecture-execution-ledger.md). This document records one keep/split decision per large file. It claims no gate result; the ledger owns gate status.

- **Source:** branch `kuro/taste-overhaul`, HEAD `471c609` plus the uncommitted migration tree as of 2026-10-05. Line numbers are point-in-time. Other lanes edited files during this review: `KuroTests/KuroTests.swift` changed and its cited lines were re-checked; `Kuro/Composition/AppComposition.swift` was touched but its line count is unchanged. A file edited after this review needs its cited lines re-checked.
- **Method:** source reading only. No build, test run or deployment was done for this review. For every file: physical lines (`wc -l`), nonblank lines (`grep -c .`), top-level declarations, `@State`/`@Environment` owners, `.task`/`Task {}`/`Task.detached` sites, SDK/transport calls (`rg -n '\.rpc\(|\.from\(|client\.'`), external consumers of each top-level type (`rg -l -w <Type> Kuro KuroTests`), churn (`git log --since=2026-04-05 --oneline -- <file> | wc -l`, all-time in brackets) and the migration diff (`git diff --numstat HEAD -- <file>`). Bodies were read in full where a split was plausible: both detail screens and their loaders, `ConciergeView`'s send/import/clarify/apply/undo path, `ProfileView`'s AniList import, the Discover loader, `ClubDetailView`'s lifecycle and the Collection batch path. The other files were read at the declaration, state and side-effect level.
- **History is thin.** Most files have under 10 commits since 2026-04-05. Files created by this migration are untracked and show `new`. That means "new in this migration", not "unchanged".
- **Template:** the plan has no "Review record template" section. `IMPLEMENTATION_PLAN_Variation1.md:1271` refers to "review examples/template" in a superseded version. The record fields below come from G6's evidence column ("short keep/split decisions and reviewer walkthrough of representative workflows"), §5 and the lead's brief. Each record gives: owner and capability, what the file owns now, its representative workflow, its dependencies, tests and evidence, the decision, remaining risks, and the change that would trigger reassessment.

## Current continuation rationale

The historical tables below preserve their original source/line identities. Current process uses review signals, not line caps. `ProfileImportCoordinator` (currently624lines) stays cohesive because it owns one mounted card/action's retry, Undo, file and task lifetime; OAuth/Keychain/pagination, journal/application and Library state are separate owners. Splitting the coordinator by callback would scatter cancellation and retry identity. `AccountActionScope` is a small SDK-free admission helper and creates no second state authority. Profile rendering retains local forms/settings; MAL list mapping/paging and both-stream orchestration have separate files. Changed high-risk boundaries were independently source-reviewed and actual helper/owner checks passed; native qualification remains pending.

## 1. Scope

| Group | Selection rule | Count |
| --- | --- | ---: |
| Native Swift files | Handwritten `.swift` in `Kuro/` (119 files) and `Packages/KuroModules/Sources` (9 files, max 370 lines) over 600 physical lines | 33 |
| Stateful types over ~350 lines in files under 600 | Aggregated across own extensions (`ProviderAvailabilityStore` spans two files) | 6 |
| Test files | The 8 largest (606–1,120 lines) | 8 |
| Edge TypeScript | Files over 500 lines under `supabase/functions`; decisions taken from [docs/modules/edge-functions.md](../modules/edge-functions.md), not re-derived | 8 |
| **Total reviewed** | | **55** |

Not reviewed as large files, on purpose:
- `Kuro/KuroApp.swift` (177 lines) is a root file under R-E8-1.
- `Kuro/Views/TastePicksView.swift` (191 lines) is the user's untracked WIP under R-E6-1.
- `LibraryStore` (370/323 lines, `KuroLibrary`) is just under the prompt range. It is the single compiled tracking authority, covered by `LibraryStoreTests` (25 tests) and recorded in the ownership map.

## 2. Decision vocabulary

- **KEEP COHESIVE:** a reviewer can follow the entrypoint, state and tests, and no independent responsibility, cancellation policy or consumer set diverges inside the file.
- **SPLIT — REQUIRED, OPEN:** a plan stage text requires this separation, and the file has a concrete divergent consumer, duplicated policy or untested decision. It is not done, so it stays open and blocks G6.
- **SPLIT — RECOMMENDED:** a real semantic seam exists, but no stage text requires it and no gate depends on it. Do it at the next change to that area.
- **DEFER:** the work is postponed, with a reason, an owner and a checkpoint. A deferred item that is part of required stage work remains OPEN ("a deferred required split is not completion").

## 3. Condensed record table (native Swift, over 600 lines)

Owner key: Cat = `CatalogStore`, Rec = `RecommendationsReader`, FM = `AppleFMService`, Flags = `FeatureFlags`, Lib = `LibraryStore`, LibA = `LibraryActions`, Prov = `ProviderAvailabilityStore`, Out = `OutboundLinkTelemetry`, Clubs = `ClubsStore`, Soc = `SocialActivityStore`, Disc = `DiscoveryStore`, Coll = `CollectionStore`, Imp = `ImportsService`, Conc = `ConciergeStore`, Tel = `InteractionTelemetry`.

| # | File | Phys / NB | Owns now (state / authority) | Top-level types | Churn since 04-05 [all] | Migration effect (diff vs HEAD) | Decision |
| ---: | --- | --- | --- | ---: | --- | --- | --- |
| 1 | `Views/DetailPages/AnimeDetailView.swift` | 2213 / 2031 | Presentation + 5 section loaders (local `@State`), no SDK; reads Cat, Rec, FM, Flags, Lib, LibA, Prov, Out | 38 | 1 [26] | +77/−288: `SupabaseService` swapped for owners, 5 dead structs deleted, no decomposition | **SPLIT — REQUIRED, OPEN** |
| 2 | `Views/DetailPages/MangaDetailView.swift` | 1511 / 1394 | Same pattern as #1; depends on 10 declarations in #1 | 16 | 1 [25] | +76/−109: owner swap, `MangaStatsGrid` deleted | **SPLIT — REQUIRED, OPEN** |
| 3 | `Views/EditorialDiscoverView.swift` | 1664 / 1515 | Discover screen loader writing a `DiscoverViewModel` bag; hosts connected cards used by Browse/TastePicks | 14 | 4 [20] | +43/−131: owner swap | **DEFER** (open: cards, with typed navigation) |
| 4 | `Views/ConciergeComponents.swift` | 1594 / 1449 | Presentation only (mascot, bubbles, clarify cards, EN/DE copy, `ConciergeMessage` value) | 18 | 0 [15] | +27/−97 | KEEP |
| 5 | `Views/AuthView.swift` | 1439 / 1291 | Auth form (forwards to `SessionController`/`AuthService`) + 725-line decorative welcome hero | 9 | 2 [8] | +15/−12 | SPLIT — RECOMMENDED |
| 6 | `Views/ConciergeView.swift` | 1438 / 1297 | Session-local conversation (36 `@State`, 9 task handles) + routing/clarify/preselect decisions; reads Imp, Conc, Lib, LibA, Coll, Cat, FM, Flags, Tel | 1 | 0 [42] | +129/−372: reconcile rules moved to `ImportReconciler` | **SPLIT — REQUIRED, OPEN** |
| 7 | `Views/ClubDetailTabComponents.swift` | 1389 / 1248 | Presentation of the 3 club tabs; reads Clubs, LibA, Lib, Flags | 16 | 1 [3] | +38/−33 | KEEP |
| 8 | `Views/TasteDeckView.swift` | 1304 / 1187 | Deck screen + `TasteDeckModel` (`@Observable` screen model); signals go to `TasteStore` | 10 | 4 [4] | +48/−96: signal delivery moved to `TasteStore` | KEEP |
| 9 | `Models/SupabaseModels.swift` | 1297 / 1191 | Shared app value models (catalog, entities, ladder, provider notes, legacy `UserList`) | 41 | 0 [12] | +25/−52 | KEEP |
| 10 | `Views/ProfileView.swift` | 1152 / 1042 | Profile menu; AniList import workflow incl. a private apply decision; deletion + Apple re-auth UI; streaming-service picker | 10 | 1 [12] | +82/−183 | **SPLIT — REQUIRED, OPEN** (apply decision only) |
| 11 | `Views/ClubDetailView.swift` | 1042 / 947 | Club detail session: bundle load, revocation epochs, realtime subscribe/stop through `ClubDetailLifecycle`, optimistic votes | 9 | 1 [19] | +132/−77: lifecycle rule extracted and tested | KEEP |
| 12 | `Views/ConciergeImportCards.swift` | 952 / 875 | Presentation only (~245 lines are preview mocks) | 16 | 0 [8] | +19/−13 | KEEP |
| 13 | `Catalog/CatalogStore.swift` | 950 / 868 | Public catalog reads + caches; 26 SDK sites | 1 | new | new (absorbed `+Clubs`/`+UserLists` catalog reads) | KEEP |
| 14 | `ContentView.swift` | 911 / 842 | Pager, header, deep-link sheets, reconnect refresh | 10 | 3 [32] | +40/−34 (R-E8-1 mechanical) | DEFER (R-E8-1) |
| 15 | `Views/EditorialCollectionComponents.swift` | 893 / 817 | Collection grid/list/batch presentation; reads Lib, LibA, `ReleasesStore` | 10 | 0 [2] | +30/−73 | KEEP |
| 16 | `Views/ClubsView.swift` | 850 / 762 | Club list + private create/join sheets | 8 | 1 [10] | +30/−78 | KEEP |
| 17 | `Views/EditorialCollectionView.swift` | 838 / 776 | Collection screen: filter/sort/search (FM intent)/batch edit, presentation `@State` only | 1 | 0 [12] | +74/−65 | KEEP |
| 18 | `Clubs/ClubsStore.swift` | 833 / 752 | Club authority: membership list, bundles (300 s), writes, revocation, badge prefs; 14 SDK sites | 2 | new | new | KEEP |
| 19 | `Views/BrowseComponents.swift` | 812 / 743 | Browse controls/grid presentation | 13 | 0 [2] | +17/−8 | KEEP |
| 20 | `Views/ConciergeInputField.swift` | 762 / 659 | Input field + its own intent detector driving auto-send | 7 | 0 [17] | +0/−169 (dead code removed) | SPLIT — RECOMMENDED |
| 21 | `Views/EditorialSearchView.swift` | 745 / 671 | Search sheet presentation over `SearchStore` | 12 | 0 [7] | +30/−56 | KEEP |
| 22 | `Views/DetailPages/ClubActivitySection.swift` | 735 / 661 | Detail club section + shared `AddToClubRailSheet` (4 external consumers) | 6 | 0 [13] | +59/−56 | **DEFER** (open: sheet, with typed navigation) |
| 23 | `Services/AppleFMService.swift` | 723 / 600 | Device intelligence (FM sessions, caches, `sanitizeForLLM`) | 20 | 0 [3] | none | KEEP |
| 24 | `Design/KuroDesignSystem.swift` | 716 / 648 | Tokens and pure modifiers | 21 | 0 [5] | none | KEEP |
| 25 | `Views/DetailPages/EntityDetailSheets.swift` | 715 / 646 | Character/staff/author/studio sheets + tested filter enums; reads Cat | 15 | 0 [2] | +9/−8 | KEEP |
| 26 | `Views/QuickVerdictActionCard.swift` | 699 / 626 | Verdict UI + `friendlyListMutationMessage` (used by 4 files) | 9 | 0 [1] | +124/−176 | KEEP |
| 27 | `Views/ConciergeRecommendationRails.swift` | 690 / 659 | Rail presentation + `RecommendationRailViewModel` | 7 | 0 [10] | +1/−1 | KEEP |
| 28 | `Collection/CollectionStore.swift` | 689 / 632 | Account-scoped card pages + feed, generations, Library sink; 3 RPCs | 1 | new | new | KEEP |
| 29 | `Views/ConciergeView+AniListImport.swift` | 674 / 621 | `ConciergeAniListImportSheet` (used by Concierge and Profile); the filename is misleading, it holds no `ConciergeView` extension | 1 | 0 [3] | +8/−8 | KEEP |
| 30 | `Discovery/DiscoveryStore.swift` | 655 / 603 | Discover bundle (account-keyed), rails, browse pages; 20 SDK sites | 1 | new | new | KEEP |
| 31 | `Views/ClubDetailSheets.swift` | 651 / 597 | Add-item-to-rail and club settings sheets | 3 | 1 [2] | +33/−68 | KEEP |
| 32 | `Composition/AppComposition.swift` | 608 / 578 | Composition root (one client, graph factories, account-scoped list) | 7 | new | new | KEEP |
| 33 | `Services/SupabaseRPCParams.swift` | 608 / 517 | 30 `Encodable` RPC payloads, each used by exactly one of 8 owners (1 unused) | 30 | 0 [10] | +0/−29 | SPLIT — RECOMMENDED |

## 4. Per-file records

### 4.1 Detail pages: the question the lead asked

**Verdict:** the plan required this split and it was not done. It is not an acceptable "low-value split rejected with evidence". E5 requires: "Split detail screen composition/state/sections at useful seams while retaining distinct Anime/Manga designs. Keep one documented loading coordinator and bounded section requests." The migration changed data access only. Each file swapped `SupabaseService` for the owners and deleted dead structs (Anime: `StatsGrid`, `StatCard`, `MediaProviderActionCard`, `SecondaryActionButton`, `SecondaryShareButton`; Manga: `MangaStatsGrid`). No decomposition was done, and no keep rationale was recorded in the ledger or the ownership map. The source shows three concrete problems.

What is already acceptable:
- The screen structs are small. `AnimeDetailView` is lines 8–266 and `MangaDetailView` is lines 8–263.
- Sections are already separate structs, and the Anime and Manga designs are distinct: `HeroSection`/`MangaHeroSection`, `TitleSection`/`MangaTitleSection`, `EpisodesSection`/`ChaptersSection`, `ActionButtons`/`MangaActionButtons`, `SimilarSection`/`MangaSimilarSection`.
- All requests are bounded (limits 10/12/14, paged sheets), and every loader is a SwiftUI `.task(id:)` that SwiftUI cancels on key change or disappear.

The three problems:

**D1. Shared detail chrome lives inside the Anime page file.** `MangaDetailView` depends on 10 declarations defined in `AnimeDetailView.swift`: `DescriptionSection` (:699), `GenresSection` (:763), `TagChipsSection` (:422), `BackButton` (:2079), `DetailSectionUtilityButton` (:1734), `ProviderSheetItem` (:1762), `makeVerifiedProviderItems` (:1775), `makeCatalogProviderItems` (:1812), `providerAvailabilityStatusCaption` (:1873) and `ProviderSelectionSheet` (:1896, with its explainer and link cards up to :2078).

`FlowLayout` (:2101), a pure `Layout`, is consumed by 5 unrelated files: `BrowseComponents`, `ProfileFreshnessCard`, `AddToListSheet`, `ProfileView` and `CreditsSection`.

Three helpers are duplicated as `private` copies in both files: `KuroDetailScrollOffsetPreferenceKey` (Anime :578 / Manga :425), `DetailCreditsSkeleton` (:2154 / :1452) and `DetailLadderSkeleton` (:2196 / :1494).

So an edit to the Anime page file can break the Manga page and five other screens. This is the plan's own split criterion: the consumers diverge. The ownership map kept `FlowLayout` in its E0 home without a rationale. This review disagrees, because it has five unrelated consumers.

**D2. Provider-availability policy is duplicated in two views and has no owner.**
- `ActionButtons.refreshLinks` (Anime :1554–1635) and `MangaActionButtons.refreshLinks` (Manga :1353–~1425) carry the same ~70-line resolution. Status, provider v2 fetch, `enqueueAvailabilityRefreshIfStale` (a server write), status re-read, verified-vs-catalog item lists, preferred primary, note and caption.
- The outbound-link scheme allowlist `validatedURL` (http/https only) exists 4 times: Anime :1637, Manga :695, :1046, :1427. A related `isValidHttpURL` is at `ProviderAvailabilityStore+LegalLinks.swift:54`.
- §4 assigns this to "ProviderAvailability + preference owner". The pure builders (`makeVerifiedProviderItems`, `makeCatalogProviderItems`, `preferredPrimaryProviderItem`) are tested in `KuroTests.swift:731–748`. The composition that uses them is untested and lives in views.
- The Anime and Manga loaders are keyed differently, and this is justified. Anime is keyed on `userEntry?.progress` (:1468) because the primary link is the next episode's stream link. Manga is keyed on `manga.id` (:1267).
- The Manga page also resolves read links a second way: `ChaptersSection` (:657 → :686) and `ChapterListSheet` (:1037) use `getBestLegalReadLink`. Chapter rows therefore open the catalog best link, while the action bar uses verified-or-catalog items. Whether that divergence is intended is a product question; this review records it, not changes it.

**D3. There is no documented loading coordinator.** Each page runs these loaders with distinct keys and lifetimes, plus two view-triggered server writes:

| Loader (Anime / Manga) | Key | Work |
| --- | --- | --- |
| Screen (:212 / :210) | media id | top tags, similar, ladder → `enqueueMediaRelationRefreshIfNeeded` (server write, cooldown-gated) → FM synopsis condense |
| Credits (:239 / :237) | id + `credits_cast_v1` | studios/staff/cast or authors/cast |
| Units preview (`EpisodesSection` :927 / `ChaptersSection` :657) | next unit number | next 10 units (Manga: + chapter status + legal read link) |
| Units sheet (`EpisodeListSheet` :1231 / `ChapterListSheet` :954) | sheet appear + load-more | paged units |
| Watch/read links (`ActionButtons` :1468 / `MangaActionButtons` :1267) | progress / id | D2 resolution incl. `enqueueAvailabilityRefreshIfStale` (server write) |
| `ClubActivitySection`, `FriendsActivitySection` | own `.task` | club activity, friend comments |

`refreshLinks` publishes through `await MainActor.run { ... }` after several awaits and never checks `Task.isCancelled`. A superseded `.task(id: progress)` run can therefore overwrite a newer run's link set. The effect is limited to presentation, but it is a real stale-write path.

**Required change (smallest that satisfies E5).** The Anime/Manga designs stay distinct and no new compiled target is needed.
1. **D1:** move the shared chrome into one detail-shared file, for example `Kuro/Views/DetailPages/DetailSharedComponents.swift`. Delete the three private duplicates. Move `FlowLayout` to `Kuro/Design/`, because a pure layout primitive belongs to the DesignSystem per §5.
2. **D2:** move the provider presentation (`ProviderSheetItem`, the builders, caption, `ProviderSelectionSheet`, brand mark) into one provider-links file. Move the duplicated resolution into the ProviderAvailability owner as one typed snapshot, for example `{primary, all, note, statusCaption}` for watch and read. Keep one outbound-URL validator. Add one test for verified-vs-catalog fallback, flag off and refresh-requested; the existing builder tests carry over unchanged.
3. **D3:** add a short documented load table, like the one above, to the file header or the ownership map, and add the cancellation check before publishing. A detail screen-model type is **not** recommended: no invariant or failure test currently needs it, and the `.task(id:)` loaders already have correct lifetimes. The lead decides whether a documented table satisfies "one documented loading coordinator" or whether the two id-keyed screen tasks should be merged into one documented loader function.

Remaining risks: force unwrap `URL(string: "kuro://anime/\(anime.id)")!` at Anime :131 (pre-existing at HEAD :126); D2 test gap; D3 stale write. **Owner:** lead or a presentation agent, after E5 interfaces are stable. **Reassess:** this is open now; there is no trigger to wait for.

### 4.2 Concierge and imports: decisions still in rendering

**ConciergeView.swift (#6). SPLIT — REQUIRED, OPEN (partial).**
- **Owner and capability:** Concierge/Imports. The view holds the session-local conversation, which is the intended policy: 36 `@State`, 9 stored task handles, all cancelled in `.onDisappear` (:158–167), and 6 `Task.detached` uses for warmup, prefetch and post-apply Collection refresh.
- **Representative workflow:** `send` (:423) → low-signal gate → FM intent or keyword routing → `handleImportFlow` (:699) → preselect → auto-apply (`autoApplyImport` :895) or confirm (`confirmImport` :1088) → toast with Undo → `undoApply` (:1234).
- **What the migration did:** moved the reconcile rules to the pure, tested `ImportReconciler` (`ImportReconcilerTests`: 23 tests, `ImportLoadStateGateTests`, `ImportApplyGateTests`) and the transport to `ImportsService`/`ConciergeStore` (`AssistantContractTests`).
- **What E6 still requires** ("Move import reconciliation, clarification, preview/apply/Undo decisions out of rendering"). These are still private view logic with no test:
  - The clarification gate `shouldAskClarifyingQuestion` (:655–697).
  - The FM routing threshold `confidence >= 0.65` (:483) and the intent-to-flow switch (:497–513).
  - The `intent_unclear` re-route (:569–582).
  - The preselection loop, duplicated at :606–615 and :762–775 (score ≥ `preselectMinimumScore` and not ambiguous → select; action).
- **Required change:** move these rules into pure types beside `ImportReconciler`, for example `ImportReconciler.initialSelections(for:)` and a `ConciergeRouting` rule set in `Kuro/Concierge/`. Test them against existing fixtures or corpora per §3 "Imports and assistant rules".
- **Recommended, not required:** extract the conversation sequence (messages, selections, task handles, send/apply/undo) into a session-local `@Observable` model in `Kuro/Concierge/`, so apply/Undo ordering becomes testable.
- **Risks:** apply/undo sequencing is untestable while private.
- **Reassess:** the recommended extraction is triggered by the next change to the apply/Undo flow.

**ProfileView.swift (#10). SPLIT — REQUIRED, OPEN (apply decision only). The rest of the file is KEEP.**
- **Owner and capability:** the Profile screen, rendering four owners' UI: Identity (deletion with Apple re-auth via `AppleAuthCodeDelegate` :1127), Providers preferences (`StreamingServicePickerSheet` :856), Clubs, and Imports.
- **Problem:** the AniList import path (:520–622) contains its own apply decision `profileImportDecision` (:584–615). Its rule is "no parser ambiguity, `canApply`, `shouldAutoApply`, every item has a top candidate, non-empty payload, else review". It is composed from tested `ImportReconciler` rules, but the composition itself is private and untested. It is an apply decision in rendering, so it belongs to the same E6 item.
- **Required change:** move it to `ImportReconciler`, for example `autoApplyPlan(...)`, shared with Concierge's auto-apply gate, with a test.
- **Keep the rest:** the remaining sections are thin UI over owners that hold the authority.
- **Risks:** the "Sync Data" (:372–377) and post-import (:617–622) manual refresh of Collection/Releases sits alongside the Library change sinks. This is redundant-request risk, not a correctness defect.
- **Reassess:** if the Profile import gains a review UI of its own, move the workflow next to the Concierge conversation model.

**ConciergeInputField.swift (#20). SPLIT — RECOMMENDED.**
- **What it holds:** a third client-side intent heuristic, `ConciergeIntentDetector` (:81–200), plus paste-list detection (`looksLikeImportListText` :430, `segmentLooksTitleLike` :457). Together they drive `maybeAutoSend` (:386). None has a test. They sit alongside `TextNormalization.looksLikeImport`, which is tested in `KuroTests.swift:22+`, and the view's clarify gate.
- **Recommended change:** fold the detector into the same pure `ConciergeRouting` rules with tests. `KuroGrowingTextView` and `ConciergeHapticsManager` stay.
- **Why not required:** auto-send is input UX, not an import/apply decision. The lead may scope it into the open item.
- **Reassess:** any change to auto-send or suggestions.

**ConciergeComponents.swift (#4). KEEP.** The file is presentation for one feature; all 7 externally used types are consumed only by `ConciergeView`. `ConciergeCuratedCopy` holds the EN/DE copy and `ConciergeMessage` is a value type.
- **Reassess:** if the conversation model is extracted, `ConciergeMessage` moves with it.

**ConciergeImportCards.swift (#12). KEEP.** Pure presentation; about 245 lines (:705–952) are preview mocks. Its only external consumer is `ImportCardContainer`, used from `ConciergeComponents`.
- **Reassess:** the import card gains editing state that must survive outside the message.

**ConciergeRecommendationRails.swift (#27). KEEP.** Rail presentation plus a local `RecommendationRailViewModel`; consumed by `ConciergeComponents`.
- **Reassess:** a second recommendation surface reuses the rail.

**ConciergeView+AniListImport.swift (#29). KEEP.** A single sheet (`ConciergeAniListImportSheet`) shared by Concierge and Profile, with `ImportsService` injected through `init`. The filename suggests a `ConciergeView` extension, which it is not (§4: "Extension filenames are not ownership evidence"). A rename is a navigation fix, not a split.
- **Reassess:** the next edit to the sheet.

### 4.3 Other screens

**EditorialDiscoverView.swift (#3). DEFER, part of a required item that remains OPEN.**
- **Screen (KEEP):** one lifetime and one consumer (`ContentView`). Its representative workflow is `refreshSections` (:430–614): bundle → daily feature → flag-gated Because-You (≥4 cards) or personalized NEW TO YOU → realm shelf and hidden gem → friend-count, ladder and image prefetch, all written into the passive `DiscoverViewModel` (61 lines). Discover, Browse and Search state are separated at the owner level (E5): `DiscoveryStore` is account-scoped, and `SearchStore` and `BrowseView` hold their own cursors. Sign-out unmounts `ContentView` (`KuroApp` `RootView` shows `AuthView`), so personalized rails held in view `@State` do not cross accounts.
- **Deferred part:** the connected cards `GridAnimeCard` (:881, reads Lib/LibA/Clubs, presents `MediaDetailSheet`, `AddToListSheet`, `AddToClubRailSheet`) and `CompactAnimeCard` (:778) are consumed by `BrowseComponents` and `TastePicksView`. E5 requires "connected cards ... in their reviewed presentation owners" together with typed routing outputs. The ownership map kept their E0 homes without a rationale, and lists typed navigation as not implemented. Moving the cards without the routing conversion would only relocate the direct sheet constructors, so the move belongs with that item.
- **Owner and checkpoint:** lead or a presentation agent, when the typed navigation outputs (`openMedia`, `openClub`, `presentTrackingEditor`) are implemented.
- **Dead code:** `GenrePickerSheet` (:1617) is never referenced. `CompactHorizontalSection` and `CompactHorizontalMangaSection` are used only by `GenreHubView`, which is itself unreferenced (§7).
- **Reassess the screen:** a second consumer of the Discover composition (for example Home) or a need to test rail-selection policy. Then move `refreshSections` into a screen model.

**AuthView.swift (#5). SPLIT — RECOMMENDED.**
- **Auth workflow (KEEP):** `AuthView` (:9–677) runs `submit` (:599), which calls `SessionController.signInWithEmail` or `signUpWithEmail`, plus Apple sign-in with nonce generation (:616, :663) and password reset. It is thin over Identity, which owns the policy (`IdentityCompositionTests`, `AuthErrorMappingTests`).
- **Seam:** the welcome hero family (`AuthGenieHero` :715 through `MetaballShaders` :1411, about 725 lines) has its own loop task (:1073), has no auth dependency and changes for artwork reasons (for example commit `697a5bc` "remove Zen TV"). Move it to its own file, for example `AuthWelcomeHero.swift`.
- **Why not required:** it is presentation-only with one consumer, so no gate depends on it.
- **Reassess:** the next artwork or auth-form change.

**ContentView.swift (#14). DEFER.**
- **Reason:** R-E8-1 authorizes only minimal mechanical edits to this user-dirty root file.
- **Owns:** the pager and gesture policy, the header (`KuroHeaderNew` :605, about 260 lines), deep-link routing (`handleDeepLink` :492) with sheet bindings (:433–470), and a reconnect refresh (:404–415).
- **Assessment:** no required split was identified beyond the deep-link and detail sheet constructors, which belong to the typed-navigation item.
- **Owner and checkpoint:** user and lead, once the user's concurrent edits land or the typed navigation outputs are implemented.

**ClubDetailView.swift (#11). KEEP.**
- **What it is:** one club-detail session. Bundle loading with revocation-epoch guards (:394–437), realtime subscribe/stop through the pure `ClubDetailLifecycle` rule (tested in `ClubsViewRulesTests`), shared providers guarded by epoch (:165–170), and optimistic votes. The 10 `Task {}` sites are:
  - user reload and vote actions (`loadBundle` checks `lifecycle.acceptsLoads`);
  - the epoch-guarded loading snapshot (:401);
  - a toast timer;
  - a delayed dismiss after membership loss (:554).
- **Evidence:** `ClubsViewRulesTests`, plus `ClubsContractTests` for the store.
- **Reassess:** if realtime deltas start to be merged into view state (optimistic votes reconciled with events), move that into a screen model.

**EditorialCollectionView.swift (#17). KEEP.**
- **What it is:** one screen holding only presentation selection state; `LibraryStore`/`CollectionStore` are the authorities. Search is FM-assisted with a debounced and cancelled task (:34, :490–496). The batch flows are `batchChangeStatus` (:757) and `confirmBatchRemove` (:792, refresh deferred).
- **Risks:** batch status change is not wrapped in `withCollectionRefreshDeferred`, so N writes trigger N sink refreshes plus one explicit fetch. This is already recorded open in the ledger (E3).
- **Reassess:** if filter/sort derivation needs tests or a second consumer, extract a pure collection query model.

**ClubsView.swift (#16). KEEP.** The club list page plus its private `CreateClubSheet`/`JoinClubSheet`, used only here. Club creation and rails/polls sheets live in `ClubCreateSheets.swift` (the CLAUDE.md description of that file is inaccurate).
- **Reassess:** a sheet gains a second consumer.

**EditorialSearchView.swift (#21). KEEP.** The search sheet over `SearchStore`, whose cancellation policy is tested (`PublicDataHTTPContractTests:381`); some search tests are in `KuroTests`.
- **Reassess:** search results become shared with another surface.

**TasteDeckView.swift (#8). KEEP.**
- **What it is:** the view and model are already separate. `TasteDeckModel` (:57) owns the queue, undo and fetch tasks (`cancelPendingWork`), with banner rules tested in `TasteDeckBannerTests`. Signal delivery is in `TasteStore` (`TasteContractTests`).
- **Reassess:** `TasteDeckModel` gains a second consumer; then move it to `Kuro/Taste/`.

### 4.4 Presentation component collections (one feature consumer each)

All KEEP. Each file below is presentation for a single screen, and no type has a divergent consumer.

| File | Single consumer | Note / reassessment trigger |
| --- | --- | --- |
| `ClubDetailTabComponents.swift` (#7) | `ClubDetailView` (4 tab types) | Reads Clubs/LibA for card actions. Reassess when a tab becomes reachable outside club detail |
| `EditorialCollectionComponents.swift` (#15) | `EditorialCollectionView` | `CollectionGridCard` (:306, 323 lines) is the largest piece. Reassess if Home reuses it |
| `BrowseComponents.swift` (#19) | `BrowseView` | `FilterChip` is also used by Discover/GenreHub (tiny). Depends on `GridAnimeCard` from Discover (see #3) |
| `ClubDetailSheets.swift` (#31) | `ClubDetailView` | `AddItemToRailSheet` uses stateless `SearchStore.fetchSearch*Page`, so it shares no state with the Search sheet |
| `EntityDetailSheets.swift` (#25) | `CastSection`, `CreditsSection` | Filter/era enums tested in `KuroTests` (`EntityWorkIdentityTests`, `EntityDiscoveryFilterTests`) |
| `QuickVerdictActionCard.swift` (#26) | Collection components, both detail pages, `TrackingDraft` | `friendlyListMutationMessage` (:76) is a Library error-text mapping used by 4 files; moving it to `LibraryViewActions.swift` is optional |

**ClubActivitySection.swift (#22). DEFER, part of the same open typed-navigation item.** The detail section itself is KEEP: it reads Clubs, Identity, Flags and Telemetry and owns its `.task`. The shared `AddToClubRailSheet` (:111, about 274 lines) is consumed by `EditorialDiscoverView`, `KuroRefinedCard`, `ClubViewLifecycle` and `ClubsViewRulesTests`. Its placement belongs with the card/sheet routing decision in #3.
- **Owner and checkpoint:** as for #3.

### 4.5 Owner stores and composition (new in this migration)

**CatalogStore.swift (#13). KEEP.**
- **Owner and capability:** Catalog. It is the single public read owner (ownership map decision). Public caches survive accounts and are trimmed under memory pressure. Per-key loads use `AccountScopedLoads`.
- **Representative workflow:** `fetchAnimeById` (:93), credits (:414–568), `fetchMediaLadder` (:712) → `enqueueMediaRelationRefreshIfNeeded` (:775).
- **Evidence:** `PublicDataHTTPContractTests` (31 references).
- **Risks:** dead legacy paging state (:63–72: `animeItems`, `currentAnimePage`, `pageSize`, `hasMoreAnime`, `isLoading`, `errorMessage`; the comment admits no writer). `ImportsService:421` still reads the always-empty `animeItems` as a title fallback. Delete both; this is cleanup, not a split.
- **Reassess:** if Catalog gains private state or a compiled target.

**ClubsStore.swift (#18). KEEP.**
- **Owner and capability:** Clubs. The responsibilities are tightly coupled through the (user, club) cache and revocation epochs: membership list, CRUD, bundle cache (300 s), rail/poll/reaction writes, the Library sink (:588), the unseen badge with account-scoped `UserDefaults` prefs (:232–320), and `ClubError` (:718). Realtime is already split into `ClubRealtimeCoordinator`.
- **Evidence:** `ClubsContractTests` (20 tests in 8 suites: account transition, revocation, realtime, bundle cache, RPC contract, realtime serialization, revocation counter, Library change), `ClubErrorTests`, `AccountLifecycleTests`.
- **Reassess:** split the badge/notification prefs out if notifications become push-driven or the prefs gain their own lifetime.

**CollectionStore.swift (#28). KEEP.**
- **Owner and capability:** Collection, account-scoped. Generation-guarded pages and feed, snapshot restore, Library sink with deferral (:628–689).
- **Evidence:** `CollectionContractTests` (request counts pinned), `LibraryFacadeTests`, `AccountLifecycleTests`.
- **Risks:** `collectionAnimeItems`/`collectionMangaItems` are fetched but read by no view (ledger E5c), and request dates are sent without a time zone.
- **Reassess:** if the unused card pages are dropped, or Home consumes the feed.

**DiscoveryStore.swift (#30). KEEP.**
- **Owner and capability:** Discovery and Browse. Account-keyed bundle cache (:71–134), Browse keyset pages (:490–576), daily feature and personalized/realm rails (:578–655).
- **Evidence:** `PublicDataHTTPContractTests` (bundle stale guard, `clearPrivateState` :289, Browse keyset :236).
- **Risks:** about 300 lines (:136–490: essentials, classics, new-to-you, top-rated, genre tags) are called only from the unreferenced `GenreHubView`. The one exception is `fetchTrendingAnime`, used by `AuthView:594`. That code inflates the store's size. The owner should decide whether to delete `GenreHubView` with that family or reconnect it.
- **Reassess:** that decision.

**AppComposition.swift (#32). KEEP.**
- **What it is:** the composition root by design (§5: "The application creates the shared SDK client once"). It holds only factory functions grouped by owner family (`makeShell`, `makePublicData`, `makePersonalData`, `makeClubs`, `makeAssistant`, `makeAccountScopedStates`) plus the `UnconfiguredLibraryBackend` fallback.
- **Evidence:** `IdentityCompositionTests` (`CompositionGraphTests` asserts account-scoped membership and order), and it is used by 8 test files through `testingGraph`.
- **Reassess:** if it acquires runtime behavior beyond construction.

**AppleFMService.swift (#23). KEEP.**
- **Owner and capability:** DeviceIntelligence. Unchanged by the migration (3 commits total). A single framework dependency, `#available` guards, and `@Generable` output types ordered reasoning-first.
- **Evidence:** no unit tests; FM is unavailable in tests.
- **Risks (already recorded elsewhere):** `synopsisCache` is keyed by bare `mediaId` (anime 7 and manga 7 collide; ledger E6b). `StubFMProvider` (:693) is never instantiated (final review); the fallback is `isAvailable`.
- **Reassess:** when the cache key is fixed, or a second provider implementation is needed.

### 4.6 Models, parameters and design tokens

**SupabaseModels.swift (#9). KEEP.**
- **What it is:** the shared app value vocabulary, with `Anime`/`Manga` referenced by 23 files.
- **Why keep:** splitting per capability would touch about 40 files with no isolation or test benefit while no Catalog target exists (ownership map E5a). The legacy `UserList` (0–100 display projection) is used only by `LibraryActions` and `ImportsService`. `ProviderAvailabilityNoteBuilder` (:1045, about 85 lines of provider policy, tested in `ProviderAvailabilityNoteTests`) could move with D2, but that is optional.
- **Reassess:** a Catalog compiled target, or a capability-private type being added here.

**SupabaseRPCParams.swift (#33). SPLIT — RECOMMENDED.**
- **Seam:** each of the 30 payload structs has exactly one consumer owner (Discovery 3, Search 2, Collection 3, Clubs 8, Social 5, Providers 5, Catalog 2, Recommendations 1). `RPCGetMediaProviderAvailabilityDetailParams` (:498) has none.
- **Benefit:** moving each payload next to its only writer removes a file that 8 capabilities edit, and lets the ownership map name one owner per RPC contract (G3). Delete the dead struct.
- **Why not required:** no gate depends on it.
- **Reassess:** the next change to any param struct.

**KuroDesignSystem.swift (#24). KEEP.**
- **What it is:** the DesignSystem owner (tokens, pure modifiers, metrics); unchanged.
- **Reassess:** it receives `FlowLayout` under D1, or a design-system target is justified.

### 4.7 Stateful types over ~350 lines in files under 600

| Type (file) | Phys / NB | Type lines | Churn | Owns | Decision and evidence | Reassessment trigger |
| --- | --- | ---: | --- | --- | --- | --- |
| `ProviderAvailabilityStore` (`Providers/ProviderAvailabilityStore.swift` + `+LegalLinks.swift`) | 569/521 + 95/82 | 635 | new | Public half (registry, ranking/allowlists, availability caches, status/refresh enqueue, observability) survives sign-out. Private half (user services, club-shared providers) is cleared by `clearPrivateState`, plus `invalidateClubSharedProviders` | **KEEP**, as recorded in the ownership map ("two explicit halves"). Private-half reset and club invalidation are tested (`AccountLifecycleTests:178–220`, `PersonalDataHTTPContractTests:272–330`). This is the closest keep: the plan's §4 row reads "ProviderAvailability + preference owner", and lifetimes and consumers do differ (Profile picker, Collection filters, ClubDetail) | Split preferences into their own account-scoped owner when they gain a third field, their own sync, or a consumer that should not see public availability. This store also receives D2 |
| `SessionController` (`Identity/SessionController.swift`) | 568/529 | 548 | new | The single account-transition funnel: restore, SDK events, sign-in/up/Apple, callback guard, deletion, sign-out, ordered teardown of 11 account-scoped owners | **KEEP**: the ordering is the protected invariant (R-E1-3, sign-out before teardown) and splitting would separate the order from the transitions. Evidence: `AccountLifecycleTests` (`SessionEntryPointTests`, `AuthCallbackGuardTests`), `IdentityCompositionTests` (`SessionSDKTests`) | A new entry path that needs a different policy |
| `BrowseView` (`Views/BrowseView.swift`) | 580/528 | 575 | 0 [10] | Browse filters, 6 keyset cursor fields, reload generation and task in view `@State`. Fetches are stateless on `DiscoveryStore` | **KEEP**: public data, one consumer, the reload is generation-guarded and cancelled on disappear (:315). Evidence: `PublicDataHTTPContractTests:236` ("Browse cursor derivation lives in BrowseView") | Cursor-boundary tests needed, or a second Browse consumer. Then move paging into a screen model |
| `SearchStore` (`Search/SearchStore.swift`) | 458/425 | 446 | new | Query generation, in-flight cancel, keyset cursors | **KEEP**: cancellation tested (`PublicDataHTTPContractTests:381`) | Multiple concurrent search surfaces needing separate state |
| `ImportsService` (`Imports/ImportsService.swift`) | 437/387 | 410 | new | Account-scoped parse cache, apply/undo through `LibraryRefreshHook`, AniList, export text | **KEEP**: `AssistantContractTests` (`ImportsContractTests`). Dead fallback at :421 (see #13) | Export-title resolution grows, at which point it moves to Catalog |
| `FriendsActivitySection` (`Views/DetailPages/FriendsActivitySection.swift`) | 417/377 | 411 | 0 [2] | One section: friend comments and reactions over `SocialActivityStore` | **KEEP**: one responsibility; the store's account guard is tested (`PersonalDataHTTPContractTests:373`) | Comments get their own screen |

## 5. Test files

All KEEP. Each file groups suites by capability or harness, and Swift Testing selects by suite.

| File | Phys / NB | Status | Content | Trigger |
| --- | --- | --- | --- | --- |
| `KuroTests/KuroTests.swift` | 1120 / 1009 | tracked, +5/−28 (edited concurrently during this review) | 11 pre-existing suites (import intent, auth errors, credit roles, provider notes, entities, ladder, search, detail truthfulness, Taste, deep links), 83 `@Test` | Move a suite with its capability when that capability gets a target |
| `KuroTests/ClubsContractTests.swift` | 1119 / 1010 | new | `ClubsHarness` + 8 suites, 20 tests | Harness reused by another feature |
| `KuroTests/AssistantContractTests.swift` | 834 / 750 | new | Imports/Concierge/Taste/composition contracts with controlled clocks, 17 tests | Concierge conversation model extracted (its tests belong here or beside it) |
| `KuroTests/ImportReconcilerTests.swift` | 760 / 680 | new | Pure reconcile and gates, 23 tests | Receives the §4.2 rule tests |
| `Packages/.../LibraryStoreTests.swift` | 665 / 582 | new | Fields, sequencing, Undo, load state, 25 tests | n/a |
| `KuroTests/AccountLifecycleTests.swift` | 648 / 574 | new | Lifecycle harness + 6 suites, 9 tests | n/a |
| `KuroTests/IdentityCompositionTests.swift` | 609 / 535 | new | Realtime, composition graph, SDK session, 12 tests | n/a |
| `KuroTests/CollectionContractTests.swift` | 606 / 542 | new | Request counts + contracts, 8 tests | n/a |

## 6. Edge entrypoints (decisions from `docs/modules/edge-functions.md`)

| File | Phys / NB | Churn since 04-05 [all] | Migration diff | Decision |
| --- | --- | --- | --- | --- |
| `manga-chapter-enrich/index.ts` | 2088 / 1898 | 0 [2] | none | KEEP, untouched on purpose. Secret gate, lock in `finally`, clamped budgets, RPS limiter. Trigger: any mapping change → extract the matcher (:899–1576) first |
| `concierge-recommend/index.ts` | 1806 / 1648 | 0 [22] | +50/−1029 (router extracted) | KEEP (recorded E7 decision). **Reviewer dissent:** the remainder is one ~1,300-line `serve` closure (:505–1806: auth, rate limit, rails, cache, narration) with no handler test. That contradicts the layout rule in that same doc ("`index.ts` ... stays thin where a split exists"). It is the weakest keep in this review. Trigger: any change to rail selection, rate limiting or narration → extract the handler first with a controlled-client test (the `concierge-apply` pattern) |
| `concierge-recommend/router.ts` | 1073 / 982 | new | new | KEEP: the extracted pure routing rules, with offline and corpus tests |
| `concierge-parse/rules.ts` | 1041 / 937 | new | new | KEEP: the extracted pure parser, 107 corpus cases (17 recorded disagreements) |
| `bulk-import-manga/index.ts` / `bulk-import-anime/index.ts` | 770 / 729, 747 / 710 | 0 [7], 0 [8] | none | KEEP: cron-driven, secret-gated, kill switch, lock and cursor. Trigger: deduplicating the ~100 shared helper lines needs a controlled-AniList handler test first |
| `realm-describe/index.ts` | 536 / 491 | 3 [3] | none | KEEP: dormant (manual driver only). Trigger: reactivation → extract `descriptor.ts` or retire the slug |
| `mirror-images/index.ts` | 523 / 486 | 1 [7] | none | KEEP with recorded gaps: no host allowlist, size cap or timeout on `fetch(url)`; bucket taken from the payload. Trigger: any change → decide those policies first |

## 7. Findings that are not splits (cleanup, owner decisions)

- Dead state or code:
  - `CatalogStore` legacy paging state (:63–72) and the `ImportsService:421` fallback that reads it.
  - `GenrePickerSheet` (`EditorialDiscoverView:1617`).
  - `RPCGetMediaProviderAvailabilityDetailParams`.
  - `StubFMProvider`.
  - `GenreHubView` (unreferenced), which keeps alive about 300 lines of `DiscoveryStore` rail fetchers and two Discover section types. An owner decision is needed: delete or reconnect.
- Fetched but unread: Collection card pages (ledger E5c).
- Duplicated outbound URL validation: 4 `validatedURL` copies plus `isValidHttpURL`. This is resolved by D2.
- Force unwrap in `AnimeDetailView:131` (pre-existing).

## 8. Summary

| File | Lines (phys) | Decision | Trigger / checkpoint |
| --- | ---: | --- | --- |
| AnimeDetailView.swift | 2213 | **SPLIT — REQUIRED, OPEN** (D1/D2/D3) | Open now |
| MangaDetailView.swift | 1511 | **SPLIT — REQUIRED, OPEN** (D1/D2/D3) | Open now |
| ConciergeView.swift | 1438 | **SPLIT — REQUIRED, OPEN** (decision rules) | Open now; conversation model at next apply/Undo change |
| ProfileView.swift | 1152 | **SPLIT — REQUIRED, OPEN** (`profileImportDecision`) | Open now |
| EditorialDiscoverView.swift | 1664 | DEFER (connected cards; required, OPEN) | Typed navigation outputs implemented |
| DetailPages/ClubActivitySection.swift | 735 | DEFER (`AddToClubRailSheet`; required, OPEN) | Typed navigation outputs implemented |
| ContentView.swift | 911 | DEFER (R-E8-1) | User's edits land / typed navigation |
| AuthView.swift | 1439 | SPLIT — RECOMMENDED (welcome hero) | Next artwork or auth-form change |
| ConciergeInputField.swift | 762 | SPLIT — RECOMMENDED (intent detector → tested rules) | Next auto-send change |
| SupabaseRPCParams.swift | 608 | SPLIT — RECOMMENDED (payloads to owners) | Next param change |
| ConciergeComponents.swift | 1594 | KEEP | Conversation model extracted |
| ClubDetailTabComponents.swift | 1389 | KEEP | Tab reachable outside club detail |
| TasteDeckView.swift | 1304 | KEEP | `TasteDeckModel` gets a 2nd consumer |
| SupabaseModels.swift | 1297 | KEEP | Catalog target / private type added |
| ClubDetailView.swift | 1042 | KEEP | Realtime deltas merged into view state |
| ConciergeImportCards.swift | 952 | KEEP | Card editing state outlives message |
| CatalogStore.swift | 950 | KEEP (delete dead paging) | Private state or target |
| EditorialCollectionComponents.swift | 893 | KEEP | Home reuses grid card |
| ClubsView.swift | 850 | KEEP | Sheet gets 2nd consumer |
| EditorialCollectionView.swift | 838 | KEEP | Filter/sort needs tests or 2nd consumer |
| ClubsStore.swift | 833 | KEEP | Push notifications / badge lifetime |
| BrowseComponents.swift | 812 | KEEP | Browse UI reused |
| EditorialSearchView.swift | 745 | KEEP | Results shared elsewhere |
| AppleFMService.swift | 723 | KEEP | Cache key fix / 2nd provider |
| KuroDesignSystem.swift | 716 | KEEP | Receives `FlowLayout` / target |
| EntityDetailSheets.swift | 715 | KEEP | Entity pages beyond sheets |
| QuickVerdictActionCard.swift | 699 | KEEP | Error-text helper relocation (optional) |
| ConciergeRecommendationRails.swift | 690 | KEEP | 2nd recommendation surface |
| CollectionStore.swift | 689 | KEEP | Unused pages dropped / Home feed |
| ConciergeView+AniListImport.swift | 674 | KEEP (rename optional) | Next edit |
| DiscoveryStore.swift | 655 | KEEP | GenreHub delete/reconnect decision |
| ClubDetailSheets.swift | 651 | KEEP | n/a |
| AppComposition.swift | 608 | KEEP | Runtime behavior beyond construction |
| ProviderAvailabilityStore (+LegalLinks) | 569+95 | KEEP (closest call) | Preferences gain field/sync/consumer; receives D2 |
| SessionController.swift | 568 | KEEP | New entry path with different policy |
| BrowseView.swift | 580 | KEEP | Cursor tests / 2nd consumer |
| SearchStore.swift | 458 | KEEP | Concurrent search surfaces |
| ImportsService.swift | 437 | KEEP | Export-title growth |
| FriendsActivitySection.swift | 417 | KEEP | Comments screen |
| 8 test files | 606–1120 | KEEP | Capability targets |
| 8 edge files | 523–2088 | KEEP (concierge-recommend: weakest, dissent recorded) | See §6 |

Decision counts over 55 files: **KEEP 45** (29 native, 8 test, 8 edge), **SPLIT — REQUIRED, OPEN 4**, **DEFER 3** (2 of them parts of a required open item), **SPLIT — RECOMMENDED 3**.

## 9. Open required splits (state these as open; in this reviewer's assessment G6 cannot pass while they remain, and the ledger records the gate result)

1. **Detail pages** (`AnimeDetailView.swift`, `MangaDetailView.swift`; E5):
   - D1: move the shared detail chrome out of the Anime page file and delete the private duplicates; move `FlowLayout` to the DesignSystem.
   - D2: move the duplicated provider-link resolution and the outbound-URL validator into the ProviderAvailability owner as one tested typed snapshot.
   - D3: document the page loading coordinator (load table) and add the missing cancellation check in `refreshLinks`.

   The migration did not decompose these files. The evidence (cross-file coupling, duplicated policy, untested view-held policy) does not support recording this as a rejected low-value split.
2. **Concierge/Imports decisions still in rendering** (`ConciergeView.swift`, `ProfileView.swift`; E6): the clarification gate and FM/keyword routing thresholds, the twice-duplicated preselection loop, and `profileImportDecision` must become pure, tested rules beside `ImportReconciler`.
3. **Connected shared cards and sheets** (`GridAnimeCard`/`CompactAnimeCard` in `EditorialDiscoverView.swift`, `AddToClubRailSheet` in `ClubActivitySection.swift`; E5): deferred together with the typed navigation outputs already listed as not implemented in the ownership map. This item remains OPEN; it adds placement to that existing item, not a new one.

No other required split is open. The three SPLIT — RECOMMENDED items and the `ContentView` deferral do not block G6.

## 10. Resolution (after the lanes below)

Appended after the final E8 lanes; the body above is the original review and is not rewritten. Lane reports and reviews live in the session scratchpad, not in the repo. This section records what closed each §9 item in source; the gate result (G6) is recorded only in the [execution ledger](2026-10-05-modular-architecture-execution-ledger.md). Nothing below was run on a simulator or device.

| §9 open required split | Closed by | What changed in source (verified by `ls`/`wc`/`rg` on 2026-10-05) | Review |
| --- | --- | --- | --- |
| 1. Detail pages, D1–D3 | Detail lane (`e8/E8-detail-report.md`) | D1: shared chrome moved to `Kuro/Views/DetailPages/DetailSharedComponents.swift` (265 lines) and the provider sheet to `ProviderLinkViews.swift` (262); Manga's private duplicates removed; `FlowLayout` moved to `Kuro/Design/FlowLayout.swift`. D2: link resolution moved to the owner as one `ProviderLinkSnapshot` API (`Kuro/Providers/ProviderAvailabilityStore+DetailLinks.swift`) with pure builders in `Kuro/Providers/ProviderLinkBuilders.swift` and one `validatedOutboundURL` (the duplicated `validatedURL` copies are gone); tested by `DetailProviderLinksTests`. D3: load tables in both page headers and `docs/modules/detail-pages.md`; the cancellation check before publishing links added. `AnimeDetailView.swift` 2213 → 1413 lines, `MangaDetailView.swift` 1511 → 1348 | `review-e8/review-detail.md`: APPROVE-WITH-FIXES (docs/structure fixes; disposition in the ledger) |
| 2. Concierge/Imports decisions in rendering | Concierge-rules lane (`e8/E8-concierge-report.md`) | `Kuro/Concierge/ConciergeRouting.swift` (408 lines): clarification gate, FM threshold 0.65 and keyword routing, clarification route, parser clarification; `PrototypeConciergeIntent`/`ConciergeIntentDetector` moved verbatim from `ConciergeInputField` with the paste/auto-send rules. `ImportReconciler.initialSelections` (replaces the twice-duplicated preselection loop) and `ImportReconciler.autoApplyPlan` (replaces the Concierge gate and `profileImportDecision`). Tested by `ConciergeRoutingTests` and the new `ImportReconcilerTests` cases, including a differential check against the pre-E6 compositions. Four flag arguments encode preserved Concierge/Profile divergences and are not guarded by a unit test (lane report). `ConciergeView.swift` 1438 → 1381, `ProfileView.swift` 1152 → 1140, `ConciergeInputField.swift` 762 → 542 | No review file seen at the time of writing; see the ledger |
| 3. Connected shared cards/sheets + typed navigation | SharedCards lane (`e8/E8-cards-report.md`) and routes lane (`e8/E8-routes-report.md`) | `GridAnimeCard`, `CompactAnimeCard` and `AddToClubRailSheet` moved verbatim (byte-identity proof in the lane) to `Kuro/Views/SharedCards/`; connected components kept in the app by recorded decision. Typed routes in `Kuro/Views/Routing/KuroRoutes.swift` (`openMedia`, `openClub`, `presentTrackingEditor`, `presentAddToClub`, `.routePresenter()`, pure `RoutePolicy`); 26 cross-feature constructions migrated; tested by `RoutingTests` (pure policy only). Recorded deviation: the tracking-editor route carries `any MediaDisplayable`. `EditorialDiscoverView.swift` 1664 (at review) → 1375, `ClubActivitySection.swift` 735 → 461 | Routes: `review-e8/review-routes.md`, APPROVE conditional on the simulator smoke run (not run; journeys in `docs/modules/README.md`). Cards: no review file seen; see the ledger |

The §8 SPLIT — RECOMMENDED item for `ConciergeInputField` (intent detector → tested rules) was also carried out by the Concierge-rules lane. `ContentView.swift` received only the route edits (R-E8-1) and stays DEFER for the user's own edits.

**Still RECOMMENDED or awaiting an owner decision (not closed by the lanes):**
- `AuthView.swift` (1439 lines): split the welcome hero — SPLIT — RECOMMENDED, trigger: next artwork or auth-form change.
- `ConciergeView` conversation model: extract at the next apply/Undo change.
- `SupabaseRPCParams.swift` (608 lines): move payloads to their owners — SPLIT — RECOMMENDED, trigger: next param change.
- `GenreHubView.swift`: still unreferenced; owner decision to delete or reconnect (it keeps about 300 lines of `DiscoveryStore` rail fetchers alive).
- `concierge-recommend/index.ts`: no handler test for the ~1,300-line `serve` closure (reviewer dissent in §6 stands).
- Legacy `CatalogStore` paging state and the `ImportsService` export fallback that reads the always-empty `animeItems` (`ImportsService.swift:421`).
- Collection card pages fetched but never read (ledger E5c).


## Integrated continuation semantic review — 7 October 2026

Historical OPEN rows above are not a size-based split mandate. Current independent review found real lifetime seams: unowned Concierge intent/auto-Apply/feedback could cross accounts or survive New Chat; legacy previews and sheet pagination could publish cancelled/superseded results. These paths now receive named chat lifetime/task ownership and generation/offset/cancellation guards. Full native regressions remain license-blocked. Profile retry/Undo/file/persistence decisions move into Imports-owned ProfileImportCoordinator; source review exposed structured Retry/card issues, which were repaired and independently accepted in source. Original-pipeline retry survives rollout changes; failed Undo remains actionable. Native execution is still unavailable.

KEEP rationale: Anime/Manga render different editorial layouts and public section arrays; local sheet/scroll state belongs to each account-keyed mounted view. Credits/shared chrome/provider resolution/routing/import rules already have owners. Concierge conversation presentation remains local while originating account/chat/task lifetime has a capability owner. Profile coordinator is cohesive around one import-card/retry/Undo lifetime; crossing a signal requires this rationale, not further arbitrary files. Updating cancellation guards alone is not a full native gate pass. F55/F56 dispositions stay tied to final source acceptance and relevant execution.
