# Kuro import, Library and Home: deep user-journey review

**8 October 2026 · Current verdict: APPROVED BACKEND DEPLOYED / HOSTED CONTRACT PROOFS PASS / INSTALLED JOURNEY QUALIFICATION IN PROGRESS.** Current delivery target is the installed simulator, not TestFlight. This review supersedes the earlier broad “source/local accepted” deployment recommendation. The previously reviewed legacy Apply/Undo repair remains accepted for its actual scope; it does not repair the structured importer.

**Implementation authorized:** [Canonical two-wave implementation specification](../../plans/2026-10-08-import-library-home-completion.md). The implementation dispositions below track the repairs in this same register. The exact four-input SQL and six named Edge closures are approved and deployed. Owner/outsider import policy, replay, Stop/Undo and Realtime proofs now pass live. Installed provider journeys and public-CDN deletion propagation remain unqualified; see [fresh deployment/live evidence](approved-deployment-live-evidence.md).

The original review below describes the preserved pre-repair baseline. The current implementation uses versioned reviewed contracts, durable manifests and Library-owned sequencing; its current evidence and remaining qualification are recorded below. Six candidate database defects were reproduced locally with the accepted forward repair installed. Additional findings below are source traces or product gaps, explicitly distinguished from hosted incidents. Nothing was deployed or written to the live backend in this review.

## Current implementation dispositions — 8 October 2026

These dispositions replace the pre-repair observations below. **Source repaired** does not mean deployed or installed/live qualified. All six originally reproduced SQL defects are repaired in the forward v2 migration. Changed high-risk SQL, journal, source adapters, approvals and compensation received focused independent review. The final Apply/Resume sequencing repair is independently accepted and its actual SDK/SQLite regression passes.

Evidence: [exact four-input SQL rehearsal](import-v2-atomic-rehearsal-summary.json) passed **265 assertions**; final integrated package run passed **95 tests**. Native r5 passed **41 distinct methods / 54 executions**, including ten actual SDK import tests, with all 222 source/config/dependency inputs unchanged during that run. These are controlled local proofs. Final affected r6 passes **14/14 methods** (eleven import workflows and three publication cases), zero failures/skips, with all **222 candidate inputs unchanged**. The pending-progress regression proves zero Apply/Finish dispatch, original intent retention and immutable Resume after synchronization. Unchanged compatibility and SQL evidence remain valid. [Final native summary](import-v2-native-final-summary.json), [source acceptance pins](import-v2-source-review.json).

| Finding | Source repair | Owner / implementation | Acceptance evidence and remaining qualification |
|---|---|---|---|
| F01 | Both Profile and Concierge route typed selection into Imports preparation; cached text remains display-only. | ProfileImportCoordinator; ConciergeAniListImportCoordinator; WorkflowSources | Native entry/retry and both-medium SDK tests; installed provider journey pending |
| F02 | Default Keep, explicit field approvals and immutable target/revision/lifecycle seal; Apply/Resume reserve affected Library keys and refuse unsent local intent. | LibraryImportWorkflow; Workflow; SQL97 | SQL policy/CAS cases; native approval test; final actual SDK/SQLite sequencing regression PASS |
| F03 | Progress/unit/label merge as one value; unavailable preserves, changed integer clears incompatible identity. | SQL08110000; LibraryProgress | SQL97 precision groups; package detail projection |
| F04 | Official MAL underscore statuses and compatibility aliases normalize before ingestion. | MALAccountList; MALExportParser; SQL08110000 | Package parser tests; SQL97 both-media status cases |
| F05 | Raw score, scale and normalized rating are coupled; unset/missing cannot replace just the scale. | LibraryImportWorkflow; SQL08110000 | SQL97 coupled score cases |
| F06 | XML 1–10 normalizes into ordinary rating; zero stays unset. | MALExportParser; LibraryRowTransport | Actual parser tests and SQL97; live XML projection pending |
| F07 | Identical effective decisions record Kept/Unchanged without row/Home bumps. | SQL08110000; ImportOutcome; ImportWorkflowSheet | SQL97 no-op and receipt replay |
| F08 | Canonical duplicate memberships combine; conflicting values become source_changed; approved incoming fields cannot expand after exhaustion. | WorkflowJournal; SQL08110000 | Package dedup and SQL97 cross-page/target-seal cases |
| F09 | Account-scoped manifests discovered after restore; Home/Profile expose recovery; original device resumes frozen input. | WorkflowJournal; Workflow; ImportHistorySection; HomeView | Native lost-delivery/restart/discovery; mounted live recovery pending |
| F10 | Owner-only Stop retains commits; unknown admitted start reconciles original action before cancel; new gesture gets a new identity. | Workflow; cancel_library_import_v2 | Native jobless/uncertain-start stop; SQL97 cancel/replay |
| F11 | XML canonical pages freeze before admission/application and recover without the selected file. | WorkflowSources; WorkflowJournal | Native orphan final-page/restart; package frozen-page tests |
| F12 | Atomic terminal marker then repeatable cleanup; unready projections retain full recovery; receipt-first, manifest-last retirement. | WorkflowJournal | Package terminal marker, interrupted retirement and retention tests |
| F13 | Typed outcome retains job, coverage, counts, Home revisions, readiness and history availability. | LibraryImportWorkflow; WorkflowRPC; Workflow | Native committed-refresh-failure and restart tests |
| F14 | Owner-only paged item trail; unresolved manual matching remains job-local; completed retry creates fresh reviewed action. | SQL08110000; Workflow; ImportCatalogMatchPicker | SQL97 matching/target seal/retry; native paged jobs/items |
| F15 | Stay dismisses without navigation; imported/full Collection use typed routes and authoritative subset filter. | ImportWorkflowSheet; ContentView; CollectionStore+ImportedTitles | Source review; native subset pagination; installed navigation pending |
| F16 | Bounded immutable Undo receipts restore only unchanged imported lifecycle/revision; skip later edits; pending local intent blocks dispatch. | SQL08110000; Workflow; LibraryProgress | SQL97 compensation/replay/retention; native durable pending guard and skips |
| F17 | One connected publication hook refreshes authoritative Library and mounted Home, Collection and Releases. | AppComposition; LibraryActions; LibraryRefreshHook | Native publication/facade tests with real owner wiring |
| F18 | Typed projection failures retain committed counts and finalization; Resume publishes without repeating writes. | LibraryActions; publishWorkflow | Native injected Library-read failure/restart/no reapply |
| F19 | Matching newer Library nil unit/label is authoritative; detail cannot revive old snapshot metadata. | LibraryProgress; SeriesDetailViews | Package nil/lifecycle projection tests |
| F20 | Apply chunks do not reread the whole Library; deliberate terminal publication coalesces owners; reminder reconciliation reuses fetched metadata. | Workflow; LibraryActions; ReminderScheduler | Native multi-page request counts and zero per-title reminder reads; live timing pending |
| F21 | Ordinary Library transport retains volumes/repeats/raw dates/privacy/score provenance; legacy text export remains explicitly limited. | LibraryValues; LibraryRowTransport; ImportLibraryProjectionModels | Package round-trip and SQL97 metadata cases |
| F22 | Strict XML hierarchy/numerics/status/limits; provider IDs range-checked before casts; malformed input remains actionable. | MALExportParser; MALAccountList; SQL08110000 | Actual parser regressions and SQL97 invalid ID/semantic cases |
| F23 | Typed Retry/Reconnect/Choose-file/source-limit actions; picker cancellation is neutral. | ImportFailure; ProfileImportCoordinator; ImportWorkflowSheet | Native admission/account/cancellation paths; source acceptance |
| F24 | Repeating is a real AniList selection and survives typed request/status. | ConciergeView+AniListImport; WorkflowSources | Source trace and typed selection tests; live source journey pending |
| F25 | Bounded XML parsing runs off MainActor; cancellation/account checks fence publication; one visible preparation phase. | ProfileImportCoordinator; WorkflowSources | Native cancelled preparation/account transition; representative live responsiveness pending |
| F26 | Connector exposes verified MAL identity, reconnect/reimport/disconnect and unavailable fields before approval. | MALNativeAccountConnector; ProfileView; ImportWorkflowSheet | Account callback/generation tests and source review; controlled live consent pending |
| F27 | 8 MiB record/64 MiB account active budget; bounded exact-account cleanup and deletion tombstone; latest ten terminal details retained. | WorkflowJournal; LibraryImportBatch; SQL08110000 | Package two-account/corruption/budget/retention; SQL97 history pruning; live cleanup pending |

The final four gates remain separate: source safety has focused source/local acceptance; installed product integration still needs real journeys; the exact approved backend is deployed and scoped hosted import/Realtime proofs pass, while the full recorded Storage producer retains its public-CDN observation failure; the current tested simulator candidate is installed, but complete provider/recovery/navigation journeys remain pending. Controlled MAL account qualification is specifically blocked by unavailable account access. [Current delivery evidence and gates](import-v2-implementation-evidence.md). No global rollout or TestFlight. [Deployment approval packet](deployment-approval.md), [contract](import-v2-contract.md), [canonical implementation specification](../../plans/2026-10-08-import-library-home-completion.md).

## Preserved pre-repair findings

The scenarios and line anchors below describe the review baseline; consult the disposition table above for their repaired state. Historical incidents and narrow earlier approvals remain evidence at their original layer.

## What a user should be able to rely on

- Import adds to the existing Library. It does not create a second tracking authority, empty the Library or delete titles missing from the source.
- A title already in Kuro is shown as existing, not as a failed duplicate. Existing status, progress, rating and notes stay unchanged by default.
- Updating existing titles requires an explicit decision. The user can inspect current and incoming values. Later edits, removals and a replacement entry remain protected even after approval.
- Anime and Manga remain distinct. Seasons and editions remain distinct tracked source entries beneath approved series groupings. Similar names never justify merging unrelated entries.
- “View imported titles” opens a filtered view of the same Library. “Stay here” preserves the current screen, filters and position. Neither action changes tracking status.
- A saved partial import survives closing the screen or restarting the app. Resume continues the same immutable attempt. Stop remaining work retains committed titles.
- “Saved” means a durable local input or acknowledged server change, with the distinction shown. “Complete” also requires truthful source coverage and usable screen state.
- Failed, unmatched, conflicted and unchanged items are visible. No all-rejected import gets a green completion message.
- Unavailable source fields do not erase Kuro fields. Provider privacy and private notes never become club content merely because they were imported.

These are proposed acceptance rules for the repair, not claims that the current app implements them.

## The simplest complete interaction

1. **Choose source.** AniList username, connected MAL account, or MAL XML. Show the verified provider account where available, selected media/statuses and source-field limitations. Explain that Kuro keeps the existing Library.
2. **Review.** Show “New titles”, “Already in Kuro”, “Changes available” and “Needs review”. Default to **Add new titles; keep existing Kuro values**. An explicit update option exposes the relevant before/after differences. Counts for incompletely fetched sources are labelled as loaded counts, not a complete account census.
3. **Confirm.** Freeze the action identity, selected policy, approved fields, source identity and immutable pages before any application. The server enforces the policy and revision/lifecycle baseline; approval in a view alone is insufficient.
4. **Import.** Show committed counts and actual source/page phase. Users may close the screen. An interrupted import becomes a persistent account-scoped Resume action. A timeout after commit means “Checking saved results”, not “Nothing imported”.
5. **Results.** Retain a reopenable result with Added, Updated, Kept/Unchanged and Needs review. Show affected titles and actionable reasons in bounded pages. Offer **Stay here**, **View imported titles** and, if useful, **View full Collection**.
6. **Resolve or stop.** Retry transport failures using the same body/key. Reconnect expired provider access. Resolve unmatched identity explicitly. Stop cancels remaining work without erasing committed rows. Any later intentional update is a new action with a fresh baseline.

Use the existing Imports owner, Library owner, account scopes and typed routes. This needs a durable manifest and a result surface, not a new event bus, second Library, generic workflow platform or package for every screen.

## All findings

P1 blocks acceptance of the included workflow because it can change data unexpectedly, lose recoverability or leave the main product inconsistent. P2 is a concrete fidelity, clarity or efficiency defect; important included behavior still needs repair, but speculative scale work is not a release gate. “Reproduced” below always means a disposable local fixture or actual-source parser, not production.

SQL references to “foundation” below mean `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql`. Package references are under `Packages/KuroModules/Sources/KuroLibrary/` unless a full path is shown. Source line anchors refer to this preserved dirty checkout and may move after repair.

### F01 · P1 · The normal AniList confirmation bypasses the durable structured path

- **User scenario:** Open the real AniList sheet, preview a list and confirm it, expecting complete import and recovery.
- **Current behavior:** Preview saves display text. Confirm sends that text as `cachedText`. The Edge cached response has no `libraryItems`, so Profile selects the legacy text branch. Concierge also routes the text into reparsing. The structured retry test injects `libraryItems` directly and therefore misses this actual entry chain.
- **Consequence:** Typed provider identity, full field fidelity and full-list streaming do not reach the normal journey. Text caps and reconciliation behavior can replace the intended durable contract.
- **Repair/proof:** Route the approved typed provider selection directly into the structured Imports owner when the foundation is enabled; preview text is display only. Keep flag-off legacy compatibility explicit. Exercise the actual preview → confirm → response → owner chain for both media, not only a direct service invocation.
- **Source:** `Kuro/Views/ConciergeAniListImportCoordinator.swift:81,103`; `supabase/functions/concierge-import-anilist/run.ts:83`; `Kuro/Imports/ProfileImportCoordinator.swift:272`; `Kuro/Views/ConciergeView.swift:127`.

### F02 · P1 · Existing titles are overwritten without a keep-versus-update decision

- **User scenario:** Kuro has WATCHING, progress12, rating9 and a deliberate note. An older provider entry says PLANNING, progress1, rating4 and another note.
- **Current behavior:** Structured UPSERT changes the Kuro fields. The job baseline protects edits made after job start, not deliberate choices already present before it. There is no structured existing-title decision screen or server field policy. **Locally reproduced.**
- **Repair/proof:** Default to preserving existing tracking/rating/notes; add only new titles. Explicitly approve existing-field updates and enforce the approved field mask and baseline in SQL. Test both default preservation and approved replacement, including an edit between preview and commit.
- **Source:** foundation `start_library_import_v1:2126`; `apply_import_chunk_v1:2299–2342`; `Kuro/Imports/ImportsService.swift:290`.

### F03 · P1 · Structured progress changes retain obsolete exact unit/label values

- **User scenario:** A Manga entry selected at chapter4.5 is imported at progress7.
- **Current behavior:** The integer becomes7 while the old unit ID and label4.5 remain. Home/detail may still display the old chapter. The prior forward migration fixes legacy Apply/Undo, not this function. **Locally reproduced.**
- **Repair/proof:** Treat progress, unit and label as one semantic value. An intentional supplied integer change clears incompatible precise metadata; unavailable progress preserves it. An unchanged integer must not automatically destroy a valid fractional identity. Test those three cases through the structured SQL writer and native display.
- **Source:** foundation `apply_import_chunk_v1:2301,2329`; `Kuro/Views/HomeView.swift:442`; `Kuro/Views/SeriesDetailViews.swift:552`.

### F04 · P1 · Official MAL planning/paused spellings are rejected

- **User scenario:** Import MAL Plan to Watch, Plan to Read and On Hold entries.
- **Current behavior:** The reader emits `plan_to_watch`, `plan_to_read`, `on_hold`; SQL accepts different spellings and records the valid entries as unsupported/unmatched. **All three locally reproduced.**
- **Repair/proof:** Normalize at a documented typed boundary, retaining compatibility aliases server-side where needed. Send actual MAL-derived drafts for Anime and Manga through the RPC; a parser-only test does not prove ingestion.
- **Source:** `Packages/KuroModules/Sources/KuroLibrary/MALAccountList.swift:92`; foundation `apply_import_chunk_v1:2237–2254`.

### F05 · P1 · Raw score and scale can become an invalid pair

- **User scenario:** Existing score is80/POINT_100; an unscored MAL entry supplies its MAL scale but no score.
- **Current behavior:** Independent coalescing retains80 and replaces the scale with MAL_10. Displayed rating8 remains, concealing corrupted source fidelity. **Locally reproduced.**
- **Repair/proof:** Merge raw score, scale and normalized rating together under an explicit unset/unavailable policy. An unset source score preserves the existing pair unless the user explicitly approves clearing it. Test zero, missing, valid and invalid scores across both source scales.
- **Source:** foundation `apply_import_chunk_v1:2303–2304,2330–2331`.

### F06 · P2 · MAL XML score does not reach the normal rating projection

- **User scenario:** Import a valid XML score8 and open the rating editor.
- **Current behavior:** XML drafts preserve raw8/MAL_10 but omit `normalizedRating`; SQL only supplies a POINT_10 fallback. New titles can look unrated; existing titles can retain an old rating. **Actual-source parser confirms the missing normalized value; SQL consequence is source-traced.**
- **Repair/proof:** Normalize valid XML scores1–10; keep0 unset and reject invalid ranges. Verify parser → payload → SQL → ordinary Library rating, reusing the existing XML tests with the missing assertion.
- **Source:** `Packages/KuroModules/Sources/KuroLibrary/MALExportParser.swift:22`; foundation `apply_import_chunk_v1:2297,2324`.

### F07 · P2 · Identical reimports report changes and advance revisions

- **User scenario:** Import the same source again without changing any effective field.
- **Current behavior:** Existing rows are counted as updated and entry/Home revisions advance. `v_unchanged` is never incremented; native count types omit unchanged. **Locally reproduced: updated1, unchanged0, entry revision1→2, Home revision2→3.**
- **Repair/proof:** Compare effective approved fields before writing. Record Kept/Unchanged without changing the row or publication revision. Decode/display that disposition. A fresh identical import and a same-job transport replay are different tests and should both behave correctly.
- **Source:** foundation `apply_import_chunk_v1:2157–2342`; `Packages/KuroModules/Sources/KuroLibrary/LibraryImportBatch.swift` count models.

### F08 · P2 · Cross-page duplicate/source changes can wedge a chunk

- **User scenario:** The provider list changes during offset pagination, causing an entry to appear again with different data; or two external references resolve to the same internal entry.
- **Current behavior:** Within-batch deduplication works. A changed body for an already-receipted item raises `IDEMPOTENCY_CONFLICT`, rolling back that chunk. Different references to the same newly added internal entry can become a baseline conflict. These prevent duplicate rows but do not give users a usable disposition.
- **Repair/proof:** Distinguish duplicate source appearances, source changes and immutable transport replay. Preserve the attempted body; handle deliberate updated input under a new action/baseline. Surface source-change conflicts without discarding committed pages. Test duplicate IDs within/across pages and two refs resolving to one entry. Do not claim a point-in-time provider snapshot from offset paging.
- **Source:** `LibraryImportBatch.prepare`; foundation `apply_import_chunk_v1:2199–2205`; `MALAccountList.url` and paging checks.

### F09 · P1 · Durable partial jobs are invisible after reopening the app

- **User scenario:** Force-close the app mid-import, then reopen Profile or Home.
- **Current behavior:** Pages are persisted, but Profile recreates its coordinator without discovering pending jobs. Closing Profile clears visible retry selections. Hashed filenames and cursor/page records do not provide a recoverable source description. Re-entering precisely the same selection may resume; a visible product Resume flow is absent.
- **Repair/proof:** Extend the existing journal with an account-scoped manifest: source/provider identity, selected media/statuses, action/job identity, phase and immutable page reference. Discover it after session restore and show Resume. Test mounted owner → terminate/reopen → visible recovery, not just reopening a journal helper.
- **Source:** `ProfileImportCoordinator.swift:45,168`; `ProfileView.swift:97`; `LibraryImportBatch.swift:217`.

### F10 · P1 · An abandoned job can block subsequent imports indefinitely

- **User scenario:** A failed import is followed by a different username, changed status selection or another XML file.
- **Current behavior:** Only one queued/running job per account/provider is allowed. New selections clear local retry choices, but there is no stop/cancel RPC or active-job discovery surface. The new attempt receives `IMPORT_ALREADY_ACTIVE`.
- **Repair/proof:** Before starting another action, show Resume existing or Stop remaining work. Owner-scoped stop closes only future work and retains committed rows/receipts. Dismissing a screen is not server cancellation. Test different selections and restarting without the original local checkpoint. Do not add a cleanup cron or silently expire customer actions.
- **Source:** foundation `start_library_import_v1:2112`; active index:426; `ProfileImportCoordinator.swift:55,63,103,168`.

### F11 · P1 · XML input is not frozen durably for replay

- **User scenario:** XML application commits, its response is lost, then the file is moved or the app terminates.
- **Current behavior:** The action identity is retained, but the complete canonical XML input is not journaled as provider pages are. The user must manually reselect the same unchanged file; errors expose no structured Retry action. A security-scoped URL is not durable ownership of the original input.
- **Repair/proof:** Persist bounded canonical parsed pages and the manifest before dispatch, using existing protected storage. Resume independently of the external file URL. Test lost response followed by relaunch and removal/change of the selected file.
- **Source:** `ProfileImportCoordinator.swift:199–222`; `LibraryImportBatch.swift` action persistence versus page persistence.

### F12 · P1 · Terminal cleanup has a crash window that can ignore new data

- **User scenario:** A completed300-title import crashes during cleanup; the source later grows to400 titles; the user imports again.
- **Current behavior:** Stream cleanup deletes the page checkpoint before the action identity. A crash between them leaves a ready action but no cursor. Fresh pages are fetched, then the old ready-job shortcut returns old counters without applying the newly fetched items. This scenario is source-traced, not yet crash-injected.
- **Repair/proof:** Atomically persist a terminal state tying action, page and completion together, or use a durable terminal marker before removals. Recover completed cleanup before fetching source data. Separate resume-finalization from a new gesture. One journal reopen/crash-cut regression should prove new source items are applied under a new action.
- **Source:** `ImportsService.swift:286,369`; `ImportsService+MALAccount.swift:37`.

### F13 · P1 · The client loses job identity and meaningful final state

- **User scenario:** Every item is unmatched or conflicted, or only some items commit.
- **Current behavior:** The service returns counters while discarding final state; all structured Profile branches show success. A clean no-op, partial save, all-rejected batch and completed import collapse into a brief count toast.
- **Repair/proof:** Return a typed outcome containing job ID, state, full counts, committed revisions and projection readiness. Complete, partial, kept-only, needs-review and paused are distinct. All-rejected is not success; an unchanged import says “Already in your Library”. Test these outcomes in the real coordinator.
- **Source:** `ImportsService.swift:310–318,719`; `ProfileImportCoordinator.swift:150,217,254`.

### F14 · P1 · Conflicts/unmatched items have no actionable result trail

- **User scenario:** Five titles need review, but the user cannot identify them or retry only those titles.
- **Current behavior:** Receipts store provider/external ID, medium, hash, disposition and detail. Status returns counters; native chunk results are discarded. There is no owner-authorized paged result surface with retained title/source data and approved decisions. An unmatched terminal receipt remains terminal even if catalog mapping later improves.
- **Repair/proof:** Retain the minimum protected data needed to explain/retry an item, resolved internal IDs and approved field decisions. Add a narrow owner-only paged result contract. Resolve unknown identity explicitly; retry selected unresolved items as a new decision with a fresh baseline. Do not create guessed public catalog entries or match by bare numeric ID/name.
- **Source:** foundation `library_import_items:440`; `import_job_status_v1:2442`; `ImportsService.swift:291,711`.

### F15 · P2 · Stay-versus-view navigation is missing

- **User scenario:** Import from Profile while browsing a filtered Collection; decide whether to stay or inspect new titles.
- **Current behavior:** Structured branches create no lasting result card. Existing legacy cards offer dismissal, Undo or Concierge review, with no Collection/imported subset destination.
- **Repair/proof:** Keep one result surface with Stay here and View imported titles. Use typed navigation and affected internal IDs; preserve prior filters/scroll unless navigation is chosen. Include an obvious exit from the temporary import filter. Verify both choices and account switching with the result open.
- **Source:** `ProfileImportCoordinator.swift:179`; `ProfileView.swift:604,997`.

### F16 · P2 · Structured imports have no defined Undo contract

- **User scenario:** After import, regret an update or expect the Undo affordance familiar from Concierge.
- **Current behavior:** Only legacy Apply produces the Undo session/card. Structured jobs have neither before-images nor a compensation action. Stop is not Undo and must not be labelled that way.
- **Repair/proof:** At minimum disclose the supported recovery before confirmation and preserve default existing values. If structured Undo is included, record before-images only for applied fields, condition compensation on matching revision/lifecycle, remove only still-unedited entries created by this action and skip later changes with reasons. Never reuse a legacy session against a structured job. Do not add a destructive “delete every imported title” shortcut.
- **Source:** `ProfileImportCoordinator.swift:242,586`; foundation `library_import_items`.

### F17 · P1 · Already-mounted Collection and Releases do not refresh

- **User scenario:** Import successfully, close Profile and return to the Collection already mounted underneath; expect new titles and reminders.
- **Current behavior:** Structured hooks refresh Library and Home. Library refresh does not emit change sinks; Collection's initial task runs once and series reload depends on filter/medium changes. The legacy Profile path explicitly refreshes Collection/Releases; the structured path bypasses it.
- **Repair/proof:** Add one bounded, account-scoped completion/partial-commit publication to the existing Collection and Releases/reminder owners. Refresh the visible query without resetting the user's state. Test an already-mounted populated Collection; an initial fresh launch misses this defect.
- **Source:** `LibraryActions.swift:130`; `LibraryStore.swift:163`; `EditorialCollectionView.swift:223`; `ProfileImportCoordinator.swift:390`.

### F18 · P1 · Completion can succeed despite a failed Library refresh

- **User scenario:** Server writes succeed; the Library read gets503 or fails decoding, while Home RPCs succeed.
- **Current behavior:** LibraryActions swallows refresh errors and proceeds to Home readiness. The import can clear its action and announce completion with a stale Library/editor projection.
- **Repair/proof:** Carry typed projection readiness. Show “Saved; Library refresh pending” and retain recoverable finalization, or wait for the required authoritative read. Never repeat committed writes merely to refresh a screen. Inject one Library-read failure after commit, then recover without duplicate effects.
- **Source:** `LibraryActions.swift:140,156`; `ImportsService.swift:310`; `HomeStore.prepareImportHome`.

### F19 · P1 · An authoritative cleared label/unit falls back to stale detail data

- **User scenario:** After fixing F03, integer7 intentionally clears an old precise selection; a detail sheet still holds its older4.5 snapshot.
- **Current behavior:** `row.progressLabel ?? serverLabel` and `row.unitId ?? serverUnitId` revive old values when the newer authoritative Library row contains nil. The final fallback also needs matching-lifecycle scrutiny.
- **Repair/proof:** A known, sufficiently recent same-lifecycle Library row is authoritative, including nil. Use server fallback only when the matching authoritative value is unavailable. Preserve pending/confirmed revision ordering. Test a held detail snapshot against a newer cleared row and a replacement lifecycle.
- **Source:** `Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift:91,98`.

### F20 · P2 · Import publication repeatedly rereads the whole Library

- **User scenario:** Import a substantial list while remaining able to use Home.
- **Current behavior:** Each100-item chunk refreshes the entire Library and Home, page completion repeats it, and final Home preparation refreshes again. This creates avoidable growing full-library work. It is a source-traced call pattern, not a measured live degradation incident.
- **Repair/proof:** Publish committed revision/progress incrementally; coalesce bounded Home refreshes and reconcile required Library/visible Collection state at deliberate boundaries. Remove duplicate refreshes before building a new cache. Assert request counts on a multi-page import and reuse one bounded performance sample; no extreme load gate.
- **Source:** `ImportsService.swift:299,310`; `LibraryActions.swift:130,140`; `LibraryStore.swift:172`.

### F21 · P2 · Imported metadata is not represented in the ordinary Library projection

- **User scenario:** Expect imported volumes, dates, repeats, source privacy, score scale and custom-list memberships to survive and be inspectable.
- **Current behavior:** Some fields are stored in SQL but ordinary LibraryEntry/row projection does not expose them. Legacy UserList synthesizes nil volumes/dates and false privacy. Home has a separate volumes field. The existing Concierge text export is explicitly a bounded title/status/progress export, not a complete provider-fidelity backup.
- **Repair/proof:** Define which fields are editable, retained/read-only and unavailable. Put needed typed metadata with the Library owner. Do not treat the legacy false privacy placeholder as authorization. If full export is promised, supply a separate lossless contract; do not falsely label the existing text export lossless. Test round-trip for promised fields, including fractional labels and raw score/scale.
- **Source:** `Kuro/Imports/ImportLibraryProjectionModels.swift:75`; `LibraryRowTransport.swift`; `ImportsService.swift:497,563`; foundation structured metadata columns.

### F22 · P2 · Semantic validation permits invalid data and opaque chunk failure

- **User scenario:** Select a malformed XML export containing a negative progress, unknown status or an oversized external identifier.
- **Current behavior:** Actual-source parser execution accepts progress−2, status `banana` and an entry outside the already-closed myanimelist element. Numeric parse failures can become missing values. SQL accepts a ten-digit pattern then casts to int32; external ID3000000000 raises22003. **Parser cases and SQL overflow reproduced separately.**
- **Repair/proof:** Validate root/entry hierarchy, supported medium/status, numeric ranges and missing-versus-invalid semantics at the canonical input boundary; retain server validation. Report item rejection versus invalid whole request honestly. A malformed item must not masquerade as absent metadata or erase existing values. Add these small cases to existing parser/SQL tests.
- **Source:** `MALExportParser.swift:110,174`; foundation `apply_import_chunk_v1:2200,2215,2224`.

### F23 · P2 · Failure actions do not distinguish Retry, Reconnect and Fix input

- **User scenario:** MAL expires, permission is denied, a provider page is malformed, or the user cancels the file picker.
- **Current behavior:** MAL offers Retry for every non-cancellation error, including errors the same request cannot repair. XML reduces permission, size, format and picker errors to a generic failure.
- **Repair/proof:** Use typed actionable failures: Retry for transient transport/uncertain delivery, Reconnect for provider authentication, Choose another file for invalid input, neutral dismissal for picker cancellation, and a precise source-limit explanation. Never silently treat denied/private lists as empty. Test representative failures, not every message string.
- **Source:** `ProfileImportCoordinator.swift:152,220`; `MALAccountList` failure/limit definitions.

### F24 · P2 · Repeating AniList titles cannot be selected

- **User scenario:** Import a rewatch/re-read list and expect repeating titles to be included.
- **Current behavior:** Backend supports REPEATING but the sheet exposes Current, Completed, Planning, Paused and Dropped only.
- **Repair/proof:** Add Repeating to source selection or explicitly disclose exclusion. Do not infer that every repeated title is completed or use highest-ever progress as the new current position. Test the real selected request and final status.
- **Source:** `Kuro/Views/ConciergeView+AniListImport.swift:34`.

### F25 · P2 · Large XML work blocks the main actor without an adequate phase indicator

- **User scenario:** Select a large allowed export and try to scroll, cancel or understand whether the app is working.
- **Current behavior:** The file read, security scan and XML parsing run synchronously in a MainActor coordinator. XML does not set the same processing indicator; OAuth starts before that indicator. This is a source-level responsiveness risk, not a timed freeze measurement.
- **Repair/proof:** Do bounded read/parse work away from the main actor, retain account/cancellation checks before publication, and show one operation phase for connecting/reading/reviewing/applying. Use a representative allowed file for responsiveness, not a screenshot or exhaustive size matrix.
- **Source:** `ProfileImportCoordinator.swift:144,192–205`; parser max32MB/max20,000 entries.

### F26 · P2 · Connected MAL identity and source limitations are incomplete in the UI

- **User scenario:** Connect the wrong provider account or expect MAL comments, privacy and custom lists to transfer.
- **Current behavior:** Profile has Connect-and-import and Disconnect but no clear verified account identity/reimport surface. Copy mentions missing comments but not all unavailable fields. MAL tags are not evidence of equivalent custom-list membership/privacy.
- **Repair/proof:** Show provider username/connection state; separate connect from intentional import/reimport where practical. Explain retained/unavailable fields concisely before confirmation. Disconnect removes credentials, not Kuro titles. Test wrong-account callback/account switch and cancellation using existing generation guards.
- **Source:** `ProfileView.swift:442`; `MALNativeAccountConnector.swift:195`; `MALAccountList.swift:91`.

### F27 · P1 · Unbounded journal accumulation conflicts with account-deletion cleanup bounds

- **User scenario:** Abandon many distinct selections over time, then delete the Kuro account.
- **Current behavior:** Individual checkpoint writes are bounded but total retained storage is not. Cleanup refuses the directory above256 files/32MB or when attribution is unsafe, before removing matching data. Unrelated corrupt files can prevent cleanup of known deleted-account records. It fails honestly, but does not fulfill cleanup. This is source-traced, not a reproduced live deletion incident.
- **Repair/proof:** Bound retained account manifests/pages and define explicit completed-history retention without discarding unresolved actions. Cleanup known attributed data resumably for the exact account; do not guess ownership or erase another account. Test directory limits/corruption with two accounts using the existing journal fixture.
- **Source:** `LibraryImportBatch.swift:260,294`; account deletion's local cleanup contract.

## Important properties already working

- Provider, medium and external ID are a typed namespace. Bare AniList/MAL IDs are not compared with Kuro's internal ID. Same numeric Anime/Manga IDs remain distinct.
- Unique internal list keys prevent duplicate tracked rows. SQL identity resolution rejects ambiguous mappings; within-batch deduplication unions source memberships. These are useful safeguards, not proof of an existing-title consent flow.
- Structured chunks are transactional and bounded; receipts make unchanged-body retries idempotent. Provider pages are persisted before dispatch. A lost chunk response has focused replay evidence.
- The account advisory lock, captured baseline, revision/lifecycle comparison and tombstones protect newer committed edits/removals. Existing concurrent-write tests remain useful. No additional proven outbox overwrite race was found in this pass.
- MAL Anime/Manga cursors advance independently. One completed medium is retained while the other fails. Both Home medium revision floors exist.
- Credential leases, account/OAuth generation guards, protected local files, unavailable-field markers and external-entity rejection already exist. Prepared social/club readers exclude source-private entries. The legacy text detour must not silently drop those protections/fields.
- Legacy Apply/Undo's precise status, compensation and lifecycle fixes remain independently accepted. An import finding here does not invalidate unrelated approved repairs.

## Proper database ingestion and frontend dependency flow

| Stage | Owner and contract | Required invariant |
|---|---|---|
| Read source | Provider adapter under Imports credential/account lease | Bounded pages; explicit source identity and unavailable fields; no token in database/journal |
| Normalize | Shared typed import drafts | Canonical status, valid medium/ID, coupled score, valid progress/date; unavailable differs from clear |
| Resolve | Catalog/provider reference contracts | Unique provider+medium+external → internal identity; unresolved remains visible; no guessed merge |
| Compare | Imports + authoritative Library baseline | Existing/new/changed/needs-review; account/lifecycle/revision plus approved fields |
| Freeze | Existing protected journal | Original action/body/policy/pages persisted before attempted application; restart manifest discoverable |
| Apply | Owner-derived authenticated SQL job/chunk | Server policy enforcement, bounded transaction, no omitted-source deletion, replay-safe receipts and counters |
| Publish | Library authority → Home/Collection/Releases | Committed revisions and correct pending projection; bounded refresh; current account/permission generation |
| Finish | Typed ImportOutcome and retained result | Truthful selected-source coverage, dispositions reconcile, projection ready or explicitly pending |
| Recover | Same Imports owner | Resume same attempted body; stop only remaining work; later approved correction gets fresh baseline |

SQL is the server-side mutation implementation; it must follow Library's semantic tracking rules even when it is a batch procedure. Views and providers must not create their own progress queues or directly reconcile competing Library copies.

Home resume cards read canonical statuses/progress and exact unit labels. Series grouping never replaces independently tracked children. Collection must use the same committed/pending state and show the affected titles when requested. Source membership metadata can feed a future shelf/filter but cannot become a second status field. Recommendations must not consume pending or source-private data outside their approved scope. Club content is refetched under current permission, not carried in an import result or Realtime payload.

The existing two checkpoint columns on server jobs are not proof of server-resumable provider streams: the current implementation's provider cursors live in the device journal and those SQL columns are not updated by the reviewed functions. Cross-device continuation needs either retained provider/source metadata plus a bounded re-read using existing receipts, or a deliberately scoped same-device recovery promise. Do not claim seamless other-device resume until implemented and qualified.

## Decisions for existing titles, duplicates and list meaning

| Case | Recommended behavior |
|---|---|
| New uniquely matched title | Add once with supported selected source fields |
| Already present, identical | Kept/Already in Library; no data or revision change |
| Already present, different | Keep Kuro by default; show explicit current/incoming comparison |
| Existing provider status differs | Move only after approval; “View imported titles” never moves a status |
| Source progress lower | Preserve by default; allow explicit correction/rewatch rather than always choosing maximum |
| Kuro edited since review/job baseline | Conflict, preserve current value, offer refreshed decision |
| Removed since import baseline | Respect tombstone; never recreate automatically |
| Removed then re-added | New lifecycle; old update/Undo cannot touch it |
| Same ID in Anime and Manga | Two independent typed entries |
| Multiple sources refer to same internal title | One tracked row, separate provider refs and source provenance |
| Repeated source row/custom shelves | Deduplicate identity; union valid memberships without duplicating progress authority |
| Missing/private source page or title | Do not infer deletion or empty list; record denial/incomplete coverage |
| Missing note, rating or source metadata | Preserve existing unless an explicit supported clear was approved |
| Catalog identity unresolved | Retain visible Needs review; allow safe mapping/retry later |
| Source offers custom lists | Preserve metadata honestly; expose only supported filters, not invented new status lists |

Every selected canonical source item gets one terminal disposition or an explicit pending state. Counts must reconcile after source duplicate normalization. A transport retry does not count the same receipt twice. Added/Updated are real effects; Kept is not an error; Needs review identifies the affected titles.

## Interruption and recovery contract

| Cut point | Correct user-visible/recovery behavior | Current evidence |
|---|---|---|
| Provider consent cancelled | Return neutrally; no writes; existing connection/list unaffected as appropriate | Guards exist; actual MAL consent journey pending |
| Source read denied/expired | Reconnect or explain access; do not finish as empty | Reader rejects unsafe/incomplete pages; generic UI actions need F23 |
| Before first attempted chunk | Durable selected manifest/page; resume or discard unattempted work | Provider page persistence exists; selection discovery missing |
| After commit, before response | Replay same body/key; server receipt returns original effect once | Existing focused lost-response proof useful |
| After one page/medium, before next | Retain committed entries; resume remaining stream; show partial counts | Independent cursors exist; product recovery missing |
| App closes/Profile dismisses | Cancel current local task, retain server job/journal; show Resume after reopen | F09/F10 open |
| XML file disappears after dispatch | Replay owned immutable canonical input without reselecting file | F11 open |
| Finish commits, projection read fails | Saved; screen refresh pending; retry finalization without reapplying writes | F18 open |
| Terminal cleanup interrupted | Recognize completed action before fetch; new gesture starts a new job | F12 open |
| Stop remaining work | Owner-authorized job transition; already committed titles remain | F10 open |
| Account switches/signs out | Hide prior account content/results, abort publication; keep its durable work isolated | Guards exist; installed import transition proof pending |
| Delete account | Server cascades plus verified Storage barrier and exact-account local cleanup | Fresh deployed qualification required; F27 cleanup bound open |

“Retry” means an immutable attempt, not a new import. “Import again” is a deliberate new action. “Stop” prevents future application. “Undo” is guarded compensation. Keeping these meanings separate is essential for recovery and honest copy.

## Additional user angles to qualify

- **First use versus established Library:** Seed both a new-title and an existing-title case; populated screens reveal issues empty-state fixtures miss.
- **Import while tracking offline:** Pending Kuro edits remain visible. Reconnect uses the same authoritative queue and revision conflict policy; no stale imported projection masks or discards local intent.
- **Tracking during import:** Let users continue normal tracking. A newer edit or removal becomes a protected conflict, not an implicit import override.
- **Wrong provider account:** Show verified identity before application; account-switch/OAuth callbacks cannot attach credentials or outcomes to a different Kuro account.
- **Unknown titles and delayed catalog ingestion:** Personal import references existing catalog identity; a missing match is recoverable metadata, not permission to write global catalog guesses. Worker ingestion and mapping need actual reader proof before populated season/chapter claims.
- **Rewatch, fractional chapters, volumes and editions:** Treat these as actual user identity, not just display strings or a maximum integer. Source limitations must be explicit.
- **Navigation and visibility:** Existing filter may hide imported titles. Result navigation should set an explicit temporary subset/medium rather than saying success while leaving users staring at an apparently unchanged page.
- **Optional Home metadata fails:** Saved tracking remains usable; missing artwork, music or enrichment cannot turn a successful write into a repeat import.
- **Accessibility and clarity:** Results and progress are persistent/VoiceOver-readable; counts and statuses are textual, not only toasts, colors or animations. Large text and cancellation remain usable.
- **Disconnect/delete:** Disconnect provider credentials preserves the Library. Account deletion is a different action requiring physical cleanup proof; neither should be a hidden side effect of import cancellation.
- **Concurrent devices/source changes:** Current receipts/CAS protect applied effects, but exact cross-device provider resume and snapshot completeness remain unqualified. State the actual guarantee rather than assuming it.

## Repair execution within the existing two waves

### Wave 1: finish the shared contract and recovery foundation

1. Keep the old deployment manifest on HOLD. Pin current source and preserve all unrelated work and accepted legacy repairs.
2. Define the typed existing-title policy and outcome/disposition contract first. Extend existing start/apply/status contracts with policy, approved fields, discoverable jobs and owner-only paged results. Add an owner-scoped stop transition. Use backward-compatible defaults that preserve current Kuro values for the new included journey; rehearse old clients separately.
3. Repair structured SQL statuses, coupled progress/unit identity, score pairing, unchanged detection and validation. Preserve transaction receipts, account locks, lifecycle/tombstones and omitted-source non-deletion.
4. Extend the existing journal with discoverable manifests, owned XML pages and atomic terminal state. Bound retention and exact-account deletion. Keep attempted payloads immutable; no new generic state engine.
5. Repair Library's authoritative-nil detail fallback and propagate typed projection readiness. Define one bounded publication fan-out to Home, mounted Collection and Releases.
6. Have focused independent review of changed mutation/recovery/authorization/wire contracts. Reuse unchanged accepted evidence; do not re-review unrelated modules.

**Wave 1 gate:** Default import cannot overwrite existing decisions; attempted actions replay safely; interrupted jobs are discoverable/stoppable; typed outcomes and ingestion fidelity are verified. Source/fixture acceptance does not imply deployment.

### Wave 2: wire the actual user journey and qualify the simulator

1. Fix both real AniList entrypoints to use typed structured input. Route MAL account/file through the same approved decisions/results path. Preserve deliberate legacy flag-off behavior.
2. Add review/progress/result surfaces and Stay/View imported navigation. Expose source identity, unsupported fields, Repeating, actionable errors and reconnect. Keep Stop and any supported Undo distinct.
3. Parse bounded XML off the main actor and wire actual operation phases. Remove duplicate whole-Library refreshes before adding abstractions.
4. Run the affected local checks once on the integrated repaired candidate; repeat only failures or source-invalidated evidence.
5. Regenerate the exact deployment inputs/hashes, compatibility and disable plan only after source/fixture acceptance. Present that concrete changed production set for required approval; do not apply the old draft or blanket-push migrations.
6. After approved deployment, exercise real simulator imports/Home/Collection and bounded live service authorization/cleanup. Keep global Home rollout unchanged; current target has no TestFlight or physical-device gate.

**Wave 2 gate:** Actual visible entrypoints, persistent recovery and result navigation work with the reviewed deployed backend and exact installed simulator artifact. Missing consent/access/service evidence remains specifically BLOCKED, not a reason to repeat unrelated tests.

## Focused verification — enough proof without over-testing

Reuse existing suites and add missing assertions at the appropriate owner. The following are behavior groups, not a requirement for a new test suite per row or arbitrary test count.

| Group | Minimum meaningful proof |
|---|---|
| Real entry chain | Actual AniList preview/confirm produces typed full-list import; both entrypoints and both media; legacy flag-off compatibility |
| Existing-title decisions | New + identical + different existing entries; default keep; approved fields only; edit/remove after review protected |
| Ingestion fidelity | Official MAL statuses; XML normalized score; unset score pair; supplied/omitted/unchanged progress with fractional identity; promised metadata |
| Counts/results | Added/updated/kept/conflict/unmatched reconcile; all-rejected, kept-only and partial states; paged title reasons and selected retry |
| Crash/restart | Lost response replay; restart discovers provider/XML job; file disappears; cleanup crash then source changes; stop admits next action |
| Screen integration | Held detail authoritative nil; mounted Collection/Releases update; Library read failure after commit; Stay versus View subset preserves state |
| Account/privacy | Switch during source/apply/result; wrong OAuth callback rejected; current club authorization; source-private fields stay private |
| Input/errors | Existing XXE/size tests reused; root/status/numeric cases; retry versus reconnect; neutral picker cancellation |
| Bounded work | Assert coalesced request counts on multiple pages; one representative size/responsiveness sample; no full refresh per item |
| Hosted/simulator | After deployment: actual AniList, controlled MAL account/XML, interruptions/account switch, live denied writes and deletion/upload cleanup |

No coverage quota, exhaustive screenshot matrix, mutation test for each guard, extreme session soak, new testing framework or repeated green whole-suite run is warranted. The new failures are concrete missing behavior, not a request to make the gates more stringent.

## Evidence and limits

- [Local database observations](structured-import-deep-repro-summary.json): six observed defects, with desired behavior. [Executable SQL](structured-import-deep-repro.sql), [execution log](structured-import-deep-repro.log), [source pin](structured-import-deep-repro-pin.json). The runner completed; that is not a PASS verdict on the broken behavior. Private PostgreSQL cluster was stopped and removed.
- Focused independent source review of the SQL, native owners and full visible import chain found the additional gaps above. An actual-source XML parser executable confirmed missing normalization and semantic-validation defects: [synthetic harness](mal-xml-parser-audit.swift) and [captured observations](mal-xml-parser-audit-observations.json). No separate parser log was produced; the captured tool stdout is explicitly identified rather than presented as a rerun.
- Existing source/local checks and the previous118-assertion exact bundle rehearsal remain valid for their narrow tested contracts. They did not prove the real AniList confirmation, existing-title consent, visible restart recovery or the newly reproduced structured defects.
- This initiative changed review/evidence/state documents only. No production implementation repair is claimed, and no live customer data, credentials, feature rollout, deployed function, schema or TestFlight artifact changed.
- The read-only live inventory and broader dependencies remain in [backend-integration.md](backend-integration.md), now explicitly held. The candidate source/closure hashes are preserved as an historical draft, not authorized ready-to-apply inputs.

**Acceptance now: REQUEST CHANGES.** Repair the shared contract and real user journey before requesting approval of a revised deployment set. Duplicate prevention alone is insufficient: users must understand what stayed, what changed, what failed and what can safely resume.
