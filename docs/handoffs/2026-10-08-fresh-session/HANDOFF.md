# Kuro fresh session handoff

Continue the existing local Kuro application, starting with the requested native design polish. The user wants a fresh Claude Code or Codex session with complete repository context, original designs, implemented behavior and an honest distinction between local work, GitHub main, deployed backend and installed simulator.

The latest design plan is saved but not implemented. Existing Home is functional on the simulator, but the user rejected its visual translation. The approved backend is already deployed. The complete import and Library scope still has unqualified real-user journeys. No TestFlight or public release is requested.

## Start here

Open `/Users/max/Kuro-Anime-App` as the workspace. Start the new session in this exact checkout. Read [START_PROMPT.md](START_PROMPT.md), then this handoff and the [native design plan](../../plans/2026-10-08-native-design-polish.md). The prompt can be pasted directly into either Claude Code or Codex.

A fresh clone of main or the remote taste branch will omit substantial required work. A Git patch alone will also omit the untracked packages, capability folders, designs and evidence. This handoff is an index and checkpoint, not a source backup. Keep the current checkout intact. If moving machines, transfer a reviewed copy of the required working files and dependency configuration; provision credentials separately. Never include private keys, tokens or account passwords in a repository or shared handoff.

## Verified checkout and remote state

The handoff initiative performed read-only GitHub branch and live Supabase metadata checks. Exact timestamps and file provenance are in the adjacent JSON/text artifacts. Recheck them when resuming if the checkout has changed.

| Layer | State at handoff |
| --- | --- |
| Workspace | `/Users/max/Kuro-Anime-App` |
| Current branch | `codex/integrated-testflight` |
| HEAD | `a7f39b66237bc5a9558b5ab2a6758cd1b085e466` |
| GitHub main | `10f3c9acca5c90250e2289fa0191a36acfb7935b` |
| GitHub taste branch | `0edeff5b88e9459bb427b7fe63d6561d22506cc0` |
| Remote current branch | No `codex/integrated-testflight` head returned; no upstream configured |
| Local HEAD relative to main | 46 commits ahead, zero behind, against freshly matching remote tips |
| Local HEAD relative to remote taste | 14 commits ahead, zero behind |
| Dirty tree before handoff additions | 110 tracked modified files, 23 tracked deletions, 1,861 non-ignored untracked files |

The dirty counts use individual files, not collapsed directory entries. They include design/evidence/support files and are not all unfinished implementation. The final [checkout snapshot](checkout-snapshot.json) and [dirty file manifest](dirty-files.json) capture the handoff additions too. They contain file metadata and hashes, not a source archive. Deleted legacy service files reflect migration into owned capabilities; do not restore them automatically.

The branch name contains “testflight” for historical reasons. The current target is simulator only. Git state is independent of Supabase deployment: uncommitted backend source can already have a deployed identity. Do not infer deployment status from whether a file is tracked or merged.

No commit, push, merge, reset, stash, cleanup or branch switch occurred to create this handoff. Preserve unrelated work. Before staging anything later, inspect and stage only an intentional reviewed set; do not use `git add .` on the whole migration tree.

## Current user decisions

- Begin with a coherent design refinement of Home, Anime/Manga details and Profile.
- Keep the selected Poster medium switch, shallow Anime scenes, equal Manga covers, independent progress controls and intended season panels.
- Empty Home needs large type over artwork and gentle animation, related to the existing login scenery. Plain text links alone do not satisfy the design.
- Reconsider the yellow page tint. The new plan proposes neutral white/gray canvases, with color local to actual artwork. Exact palette/composition remains subject to native visual review.
- Reorganize Profile around identity, Library, imports/connections, pending work, preferences and account/privacy.
- Library stays the sole tracking authority. Preserve durable actions, replay, guarded Undo, account isolation and club permission checks.
- Keep verification proportional. Reuse meaningful scoped tests; do not repeatedly run unchanged suites or build another test framework.
- Simulator delivery only. No TestFlight, archive/upload, App Store submission or global Home rollout.
- No old-session backfill, deletion-barrier cron, catalog backfill or worker scheduling in this scope.
- The exact prior backend approval has been fulfilled. It is not blanket approval for a new deployment delta.
- A controlled MAL user account is unavailable. Do not ask the user to log into an account they say they do not have. Only real MAL account/OAuth qualification depends on that access; other implementation and checks can proceed.

## Read the authorities in this order

1. Project `AGENTS.md` and applicable current session instructions. Its March product map and commands contain historical details; follow the newer explicit user scope and current evidence where they supersede them.
2. [Native design polish plan](../../plans/2026-10-08-native-design-polish.md): complete new presentation scope, first actions, palette/motion, Profile and native preview acceptance.
3. [Import and Library completion plan](../../plans/2026-10-08-import-library-home-completion.md): functional invariants, existing two implementation waves and remaining real journeys.
4. [Current approved deployment evidence](../2026-10-08-backend-integration/approved-deployment-live-evidence.md), [installed state](../2026-10-08-backend-integration/approved-installed-home-readiness.json) and [four gates](../2026-10-08-backend-integration/import-v2-gates.json).
5. Relevant current sections and latest change logs in `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md` and `IMPLEMENTATION_PLAN_Variation1.md`. Use focused searches instead of loading their entire historical contents into context.
6. [Module guide](../../modules/README.md), [98-finding modularity register](../../plans/2026-10-05-modularity-completion-register.csv), [Home repair ledger](../2026-10-07-home-series-evidence/REPAIR_LEDGER.md) and [27-finding import register](../2026-10-08-backend-integration/import-user-journey-review.md), as needed for changed seams.

The registers cover different scopes. Do not create another competing finding register. Many modularity rows still say fixed/pending review; later scoped evidence does not automatically close all 98. Whole-codebase modularity and complete release readiness are not certified.

Some existing files retain historical headings or fields: the Home repair ledger calls the foundation prepared; `backend-deployment-DRAFT.json` retains the pre-deploy baseline and an old NOT DEPLOYED requirement; older installed summaries refer to flags off and an earlier bundle. Their history must not override the approved receipts/current state. The import implementation remaining-work list is corrected during this handoff. When a stale statement matters, follow the latest explicit evidence and reconcile its current summary without rewriting the historical record.

## Original designs and visual evidence

The original references are local, interactive browser prototypes with controlled fictional progress, releases and club activity. They are composition references, not production data or backend proof.

| Reference | Purpose |
| --- | --- |
| `tools/design-directions/instrument.html` | Selected Poster switch, Anime Home and detail interactions |
| `tools/design-directions/manga-library.html` | Equal Manga covers and independent per-book actions |
| `tools/design-directions/instrument.css` and `instrument.js` | Actual composition, interaction and artwork material rules |
| `tools/design-directions/manga-philosophies.css` and `.js` | Selected Library treatment; other explicitly named studies are historical |
| `tools/design-directions/instrument-detail-data.js` | Controlled season/detail content and behavior |
| `tools/design-directions/instrument-art-materials.js` | Image material identities and explicit fixture overrides |
| `tools/design-directions/INSTRUMENT_README.md` | Design evolution; selected treatment first, historical versions afterward |
| `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md` | Accepted product/design decisions; earlier distribution/scale/status clauses are superseded |

If the prototype server is not already running, serve it locally:

```sh
python3 -m http.server 8803 --bind 127.0.0.1 --directory tools/design-directions
```

Inspect `http://127.0.0.1:8803/instrument.html?switch=poster` and `http://127.0.0.1:8803/manga-library.html`. These have no production writes. Verify the loaded local artifact rather than assuming a stale browser tab is current. Do not resurrect rejected Crosscut, offset/masonry or old workbench alternatives. The new neutral palette and empty-Home/Profile request supersede the old cream styling; retain the accepted composition decisions.

Native controlled-content screenshots are under `docs/handoffs/2026-10-07-home-series-evidence/repairs/screenshots/native/`: `anime-home-390.png`, `manga-home-390.png`, `detail-anime-390.png` and `detail-manga-390.png`, with narrow/wide variants. They show the imperfect translation being refined. Some pre-final screenshots retain an earlier Close color; source/installed identity is authoritative.

Actual live-account empty Home captures are `approved-installed-home-anime.png` and `approved-installed-home-manga.png` in the backend evidence directory. The account has no saved titles, so empty artwork/progress does not establish populated live fidelity. `import-v2-installed-profile.png` shows the old Profile layout. `approved-installed-mal-login.png` is historical: that browser was dismissed.

Login uses `AuthSceneryLoop` inside `Kuro/Views/AuthView.swift`, with bundled `KuroZenMountains` artwork. Current onboarding is a card pager in `OnboardingView.swift`. The scenery component is private and continuously clocked; a shared extraction must add visibility/background, Reduce Motion and low-power controls while preserving accepted login appearance. No animation framework or new backend is necessary. Do not invent a shared onboarding animation that the current source does not have.

## What is implemented locally

### Architecture and tracking

The legacy `SupabaseService` family has been extracted into capability folders with composition in `Kuro/Composition`. App folders remain conventions; `Packages/KuroModules` supplies compiled `KuroCore`, `KuroLibrary` and `KuroSupabase` boundaries. Continue this structure instead of rebuilding it.

Library owns durable SQLite progress/outbox, mutation identities, lifecycle/revision checks, affected-key sequencing and the confirmed/pending projection. Home consumes that projection. Credential leases and account generation fence private async work; club-derived content has permission-generation handling. View state remains account keyed. Keep package language/isolation policy unchanged.

### Imports and integration

AniList, MAL account and MAL XML converge on typed canonical pages, staged review and explicit field approvals. Existing titles default to Keep. Immutable attempted actions, protected source manifests and server receipts preserve uncertain delivery/restart recovery. Stop retains commits; guarded Undo skips subsequent edits/removals/replacements. Results are owner-paged, persistent and expose readiness. Imported titles are a Collection filter over Library. One publication hook connects mounted Home, Collection and Releases.

Primary seams: `Kuro/Imports/ImportsService+Workflow*`, `ProfileImportCoordinator.swift`, `MALNativeAccountConnector.swift`, package `LibraryImportWorkflow*`, `LibraryProgress.swift`, `LibraryImportBatch.swift`, `ImportWorkflowSheet.swift`, `ImportHistorySection.swift`, `ImportCatalogMatchPicker.swift`, `LibraryActions` and `AppComposition`.

Native MAL registration is configured for Debug simulator only. Callback is `kuro://mal/callback`; no confidential client secret is embedded. Registration is distinct from a MAL user account/OAuth grant. Do not widen release connector availability as part of visual polish.

### Home and details

Home is mounted in Taste ← Home → Discover → Collection → Clubs. Global search and existing routes remain. Source-local presentation fixes include equal Manga frames, grouped calendar, artwork overflow correction and compact book/header treatment. Library reader now requests Manga-only `volumes_progress` only from Manga. Home cache selection now preserves a deliberate medium choice through fallback and late bootstrap.

These repairs passed focused review/tests and are installed. The user still rejects the visual translation. The new empty-Home scene, neutral palette and Profile redesign are planned only. Do not mistake source acceptance for owner visual approval.

## Production backend versus pending production work

Project: `bkdifromsqxkndnllmdj`, `https://bkdifromsqxkndnllmdj.supabase.co`.

Four reviewed original SQL inputs were applied in one approved transaction. Current CLI history again confirms them remotely:

- `20261007040000_series_home_foundation_v1.sql`
- `20261007130000_series_account_lifecycle.sql`
- `20261008100000_import_status_fence_preserves_units.sql`
- `20261008110000_import_review_recovery_v2.sql`

They remain under `supabase/prepared-migrations/`, outside the historical local migration directory. The CLI therefore shows four remote-only identities. That is intentional; do not “repair” history or blanket-push the migration directory. Live history has 249 recorded identities; the historical local directory has 245. Of the 14 top-level prepared files, `20261007120000_feature_flag_overrides.sql` is absent remotely and was intentionally excluded for Debug-only local flags. The opt-in backfill remains excluded.

Exact approved atomic transaction SHA256: `ca18fb6931c3afac3f8eec9fe85e0de9c9a903132780dbdb2448cf62a3a11fd8`. All four input hashes and six closure source pins still match their approved manifest at this handoff.

| Approved Edge closure | Freshly listed deployed version |
| --- | --- |
| concierge-import-anilist | 6 |
| concierge-apply | 27 |
| concierge-undo | 18 |
| delete-account | 10 |
| concierge-recommend | 50 |
| concierge-retrieve-assist | 9 |

All six are ACTIVE with JWT verification. Full metadata for all 16 live slugs is in [live-functions.json](live-functions.json). Runtime bundle hashes are provider bundle identities; do not compare them directly with a single local source hash. Local changes to other Edge functions/workers were excluded from this deployment set; parity for those local closures is not established by the six deployments. Do not deploy them opportunistically.

Last recorded live Home flags are both false/0%; that flag reading was not repeated by this handoff. The installed app uses local Debug overrides only. Resolve, retrieval rollout and other staged capabilities retain existing activation decisions; deployed code is not permission to enable a feature. No backfill or worker scheduling occurred.

Relevant receipts live under `docs/handoffs/2026-10-08-backend-integration/`: `approved-sql-deployment-receipt.json`, `approved-deployment-postflight.json`, `approved-import-v2-effective-grants.json`, `approved-edge-deployment-receipts.json` and `approved-functions-postflight.json`.

## Qualification already recorded and still missing

- Real hosted import v2: PASS, 142 bounded requests/two disposable accounts; stage/no-write, default Keep, selected updates, replay, conflicts, Stop, guarded Undo, ownership and administrative cleanup. Synthetic staged input over actual catalog references does not prove provider ingestion or UI orchestration.
- Corrected hosted Realtime: PASS, 23 requests/three disposable accounts; activity, own membership removal, revocation and outsider exclusion. The earlier failure was the probe SDK falling back to anonymous; retain it and the corrected producer evidence.
- Storage: origin cleanup, GoTrue deletion and old-token upload denial PASS, including overlapping upload. Original public URL stayed cached during the producer's 60-second observation, so that recorded producer remains FAIL. Later all recorded URLs returned NoSuchKey. Do not overwrite this with a longer-deadline rerun to claim success. Assess the actual public-CDN privacy/product requirement; the producer's window is not a new universal release SLO. No test accounts/images remain at origin according to recorded administrative proof.
- Relevant SQL rehearsal: 265 assertions PASS. Package baseline: 95 tests PASS plus scoped final cases. Native import r5: 41 distinct methods/54 executions PASS; r6: 14 methods PASS. Home composition: six affected native tests PASS. Shared-reader regressions and actual Home/SQLite medium-selection harness PASS. Use the source pins and exact summaries before reusing evidence.
- Actual installed restore, Home default and Anime→Manga switching: PASS. Full provider ingestion, reviewed updates, interruption/restart, result navigation, Stop/Undo, populated shared Home/Collection/Releases and account-transition journeys remain pending.
- MAL consent/callback/real list ingestion is specifically BLOCKED by a controlled MAL user account. XML cannot substitute for account qualification. It does not block the design preview or independently executable workflows.
- Historical whole-schema replay remains incomplete; no unsupported performance/scale claim follows from these tests.

The four functional gates remain scoped: source safety PASS; product integration BLOCKED; backend qualification FAIL for the full recorded Storage producer; simulator delivery BLOCKED for complete journeys. The visual design is separately not owner accepted. Preserve those distinctions and update only evidence invalidated or genuinely completed by new work.

## Exact installed simulator candidate

- Owned UUID: `7FC4B58A-430C-457D-A017-6B0095723F3F`, named **iPhone 17 Pro Kuro Qualification**, iOS 26.0. “Qualification” is a device name, not a product page or passed certification.
- Installed app: `com.Kuro.app`, Debug 1.0 (17).
- Bundle tree SHA256: `431a94a3c854a835fbafa93673a507b86c0c1682720dbf595f24914a959774ac`.
- Receipt: `../2026-10-08-backend-integration/home-medium-switch-install-receipt.json`.
- 223 source/config/dependency inputs still match `home-medium-switch-source.after.json`. Current installed executable, debug dylib and Info.plist hashes were read again and match the receipt. No install/launch occurred in this handoff initiative.
- Frozen local artifact: `/private/tmp/kuro-home-medium-switch-20261008/Kuro.app`; temporary artifacts may disappear. Durable source and evidence are in the repository.
- Existing development account is restored. Preserve simulator data/Keychain and do not delete that account. Credentials are held locally outside the repository; never paste them into a prompt, screenshot, log or Git.
- Another ordinary iPhone 17 Pro simulator belongs to other work. Use the owned UUID explicitly rather than a helper that chooses by name.

Build/install commands should use this destination when later implementation warrants them:

```sh
xcodebuild -project Kuro.xcodeproj -scheme Kuro \
  -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' build
xcrun simctl install 7FC4B58A-430C-457D-A017-6B0095723F3F /absolute/path/to/Kuro.app
xcrun simctl launch 7FC4B58A-430C-457D-A017-6B0095723F3F com.Kuro.app \
  --ff-on=series_foundation_v1 --ff-on=series_home_native_v1
```

Do not run these just to read the handoff. Test runners may spawn clones; do not erase or inspect unrelated device data. Existing package and native test hosts are sufficient. For UI, use supported simulator/computer controls and visibly verify outcomes; a fixture snapshot is a different evidence layer.

## Next work and completion

1. Read the focused authorities and inspect the exact dirty source. Summarize the current baseline briefly; do not restart the architecture or re-audit every unchanged accepted repair.
2. Implement the first native design pass: shared neutral roles, lifecycle-aware artwork welcome, focused first actions, representative Anime/Manga/detail compositions and organized Profile. Keep original design references alongside the native rendering.
3. Show the coherent native compositions for owner feedback before propagating an unaccepted direction. While feedback is pending, continue independent state/route/accessibility checks that do not depend on the visual choice.
4. Complete the reviewed design integration and actual relevant workflows. Use controlled preview data for visual coverage and recorded disposable resources for hosted writes, never invented production data. Existing live bounds are five accounts/five concurrent/five RPS/1,000 requests per run.
5. Reconcile remaining import/Library journeys independently; keep missing MAL account access precise. Prepare a fresh exact deployment delta only if a required backend repair is discovered, and obtain the applicable new approval.
6. Install the exact candidate, show actual screenshots and record relevant evidence, source identity, remaining blockers and cleanup. Update three canonical state documents and permitted memory extension once for the completed initiative.

Weights from the existing execution plan remain correctness/privacy/recovery 35%, ownership 25%, compatibility/integration 20%, verification 10%, simplicity 10%. They guide tradeoffs and do not compensate for lost data or an unaccepted visual composition. No hard line caps; review approximately 400–600-line files or 350–500-line stateful types for mixed ownership, lifetime or failure policy.

Success for visual work is an owner-reviewed coherent native composition with real routes and preserved behavior on the exact installed simulator candidate. Whole import/backend qualification remains a separate honest verdict. Never declare the whole migration production ready from a build, screenshot, source review or self-awarded score.
