# Kuro: complete imports, recovery and Library/Home integration

## 1. Execution contract and fixed decisions

> Continue the existing Kuro implementation and resolve all 27 findings in the import user-journey review. Preserve unrelated dirty changes and previously accepted repairs.
>
> Complete the shared backend contracts, reliable AniList/MAL ingestion, existing-title review, durable recovery, guarded Undo, persistent results and Library/Home/Collection integration.
>
> Use two implementation waves. Establish shared contracts before parallel implementation. Coordinate exclusive file ownership and independently review changed authentication, authorization, mutation, recovery and deployment code.
>
> Reuse meaningful existing evidence. Add tests for important missing behavior; do not introduce coverage quotas, extreme load requirements, repeated unchanged suites or a new testing framework.
>
> Finish with the exact installed simulator build using the reviewed live backend. Prepare and review the precise deployment delta before seeking required deployment approval. Do not upload to TestFlight or activate global Home rollout.
>
> Report actual evidence and precise blockers. A successful build or fixture test cannot establish live integration.

**Canonical implementation document:** save this specification as `/Users/max/Kuro-Anime-App/docs/plans/2026-10-08-import-library-home-completion.md` before runtime implementation begins. Link it from the existing [27-finding review](/Users/max/Kuro-Anime-App/docs/handoffs/2026-10-08-backend-integration/import-user-journey-review.md). Keep the review as the finding register rather than creating another competing register.

**Decisions confirmed:**

- Preserve existing Kuro values by default; permit explicit reviewed updates.
- Include guarded Undo for structured imports, including partially completed imports.
- Guarantee same-device recovery after dismissal, restart and uncertain delivery.
- Another device may inspect or stop a server job. Cross-device continuation is excluded.
- Include AniList account input, MAL OAuth account input and MAL XML, for Anime and Manga.
- Library remains the sole tracking authority. Imported-title navigation is a filter over that Library.
- Keep the existing two waves, architecture, design system and account/permission guards.
- Preserve the decisions against an old-session backfill and deletion-barrier cron.

| Decision priority | Weight |
|---|---:|
| Correctness, privacy and recovery | 35% |
| Maintainability and ownership | 25% |
| Compatibility and integration | 20% |
| Verification quality | 10% |
| Simplicity and efficiency | 10% |

Weights resolve tradeoffs. They cannot offset a privacy failure, unexpected overwrite or unrecoverable advertised workflow.

## 2. Product behavior and ownership

### The complete user journey

1. **Choose source**
   - Show verified MAL account identity and connection state.
   - Support reconnect, import again and disconnect without removing Kuro titles.
   - Include AniList Repeating alongside the existing status choices.
   - Explain unavailable fields before confirmation.

2. **Read and review**
   - Read selected source streams into protected, bounded storage without changing the Library.
   - Show New titles, Already in Kuro, Changes available and Needs review.
   - Display incomplete reads as incomplete. Provider denial, missing pages or cancellation cannot become an empty successful import.
   - A complete confirmation requires exhaustion of every selected medium.

3. **Approve**
   - Default: add new titles and keep all existing Kuro values.
   - Offer “Review updates to existing titles”.
   - Show current and incoming values for affected fields; approve updates explicitly.
   - Freeze the approved decisions and their revision/lifecycle expectations before application.

4. **Apply**
   - Show actual committed counts and progress.
   - Closing the screen retains the job. Stopping remaining work preserves committed titles.
   - An uncertain response triggers reconciliation/replay of the original action.

5. **Results**
   - Persist Added, Updated, Kept/Unchanged and Needs review, with paged title details.
   - Offer **Stay here**, **View imported titles**, **View full Collection** and **Undo saved changes**.
   - All-rejected results say that nothing was applied. A clean no-op says the titles are already in the Library.
   - A committed import with failed projection refresh says “Saved; refreshing your Library”.

6. **Recover**
   - Home and Profile expose pending imports after session restore.
   - Resume, reconnect, inspect results or stop are available according to the actual state.
   - Resolving a completed conflict/unmatched item starts a new reviewed action for the selected items.

### Exact merge rules

- Existing status, progress, rating, notes and retained source metadata remain unchanged unless approved.
- Approval applies only to the selected fields. Missing/unavailable input never means clear.
- This implementation does not clear existing fields merely because the provider supplies an empty value; deliberate clearing remains an ordinary Kuro edit.
- Score value, scale and normalized rating form one coupled value.
- Progress, precise label and unit identity form one coupled value.
- Changed integer progress clears incompatible precise identity; unavailable or unchanged progress preserves compatible identity.
- Rewatch/re-read can intentionally reduce progress. Do not universally choose the highest value.
- Identical effective input produces Kept/Unchanged without a row or Home revision bump.
- Later edits/removals/replacement lifecycles produce a conflict.
- Source omission never deletes a Kuro title.
- Provider identity remains `(provider, medium, external ID)`.
- Duplicate appearances collapse into one canonical item. Valid memberships are combined; contradictory core values require review.
- Manual matching is limited to unresolved items, stays local to the import decision and never rewrites global catalog mappings.

### Capability placement

- **Imports:** source adapters, review decisions, jobs, manifests, immutable replay, results and import compensation.
- **Library:** authoritative tracking semantics, confirmed/pending projection and account-scoped mutation sequencing.
- **Catalog:** provider identity resolution, title metadata and approved series relationships.
- **Home:** consumption of Library state and committed serving revisions.
- **Collection:** visible query and temporary imported-title filtering.
- **Releases:** reminder reconciliation after relevant committed changes.
- **Identity:** credential leases, account generation and deletion coordination.

Views own presentation state. They do not write raw database rows, create independent tracking queues or decide replay policy.

## 3. Wave 1 — backend contracts and durable recovery

### Shared types and API contracts

The lead establishes these types before agents edit consumers:

- `ImportSelection`: source identity, provider, media and status selection.
- `ImportReviewItem`: provider reference, resolved internal identity, current/incoming fields, expected revision/lifecycle and proposed disposition.
- `ImportDecision`: add, keep, approved field updates or defer for review.
- `ImportOutcome`: job identity, phase, complete counts, per-medium coverage, committed revisions and projection readiness.
- `ImportFailure`: actionable transient, uncertain-delivery, authentication, access, validation, limit and conflict cases.
- `ImportUndoOutcome`: reverted and skipped items with reasons.

Use versioned structured contracts for the repaired journey:

| Contract | Responsibility |
|---|---|
| `start_library_import_v2` | Idempotent job admission with source identity and selection |
| `prepare_import_chunk_v2` | Normalize, resolve and stage bounded review items without Library writes |
| `apply_import_chunk_v2` | Apply immutable approved decisions with server-enforced policy and receipts |
| `finish_library_import_v2` | Finish only after selected streams and staged items are accounted for |
| `import_job_status_v2` | Counts, phase, coverage, revisions and Undo/finalization state |
| `import_jobs_page_v2` | Owner-only active jobs and recent results |
| `import_items_page_v2` | Owner-only paged decisions, dispositions and explanations |
| `cancel_library_import_v2` | Stop remaining application while retaining committed changes |
| `undo_library_import_chunk_v2` | Bounded, replay-safe guarded compensation |

Keep existing contract signatures available. Preserve legacy Concierge Apply/Undo behavior and its accepted repairs. Compatibility adapters must not expose an unguarded route into the new job’s approved writes.

### Database implementation

- Extend existing job/item storage instead of creating a parallel import subsystem.
- Store normalized review data, approved field decisions, resolved internal IDs, application receipts and necessary before-images under owner authorization.
- Capture the review baseline per item. Compare it again during application.
- Keep application chunks at a maximum of 100 items and result pages at 50 items.
- Commit each chunk’s writes, receipts, counters and publication changes atomically.
- Validate provider IDs before casts; normalize official MAL spellings; reject invalid ranges and malformed semantic input.
- Preserve supported privacy, volumes, repeats, dates, notes, score provenance and memberships.
- Require authentication-derived ownership, RLS, restricted grants and explicit function search paths.
- Lock application, stop and Undo through the existing account/job sequencing mechanisms. A stop arriving after a committed chunk preserves that chunk and prevents subsequent application.
- Do not report externally verified provider completeness: the server verifies recorded stream termination and staged-item accounting.

### Guarded Undo

- Capture before-images and post-write revision/lifecycle for actual changes only.
- Restore an updated item only when its lifecycle and post-import revision still match.
- Remove an added item only when it is still the unedited lifecycle created by that import.
- Preserve titles edited, removed or replaced afterward; report skipped reasons.
- Refuse Undo dispatch while affected titles have unsent local changes. Offer synchronization first.
- Stop an active import before compensating its committed changes.
- Use one immutable Undo action identity with bounded chunks and receipts.
- Keep the latest ten terminal jobs’ detailed results and Undo data per account. Older jobs retain summary/provenance and explicitly report that Undo history is unavailable. Pruning occurs during normal terminal-job maintenance; add no scheduler.

### Durable journal

Extend the existing protected journal with one authoritative manifest containing account, source selection, action/job identity, phase, page references and finalization state.

- Persist immutable provider/XML pages before application.
- Discover manifests after session restoration.
- Replace separate terminal deletions with an atomic completion marker; subsequent cleanup is repeatable.
- A completed action and a new import gesture cannot reuse the same identity.
- Parse XML away from the main actor, with cancellation and account checks before publication.
- Enforce the existing per-record bound plus a 64 MiB active-data budget per account.
- Refuse additional preparation cleanly when the budget is exhausted; never silently discard active input.
- Remove acknowledged source payload after durable terminal state. Results and Undo come from owner-authorized server contracts.
- Attribute new storage by account directory. Delete exact-account data in bounded passes; unrelated corrupt records cannot prevent removal of safely attributed records.
- Preserve unknown legacy files rather than guessing their ownership.

### Wave 1 acceptance

- All six reproduced SQL defects are corrected.
- Default imports preserve existing choices.
- Immutable application and compensation replay safely.
- Interrupted jobs are discoverable and stoppable.
- Results explain every canonical item.
- Account isolation and deletion cleanup remain correct.
- Changed high-risk contracts receive focused independent acceptance.

## 4. Wave 2 — real screens, integration and simulator delivery

### Native implementation

- Route both actual AniList entrypoints through typed structured preparation. Cached display text cannot become authoritative import input.
- Route MAL account and XML through the same review/application/result owner.
- Implement persistent review, operation progress, results and recovery surfaces.
- Wire Repeating, verified provider identity, source limitations and typed failure actions.
- Keep picker cancellation neutral; distinguish Retry, Reconnect and Choose another file.
- Keep results account-keyed and accessible with VoiceOver and large text.
- “Stay here” preserves navigation, filters and position.
- “View imported titles” opens the affected internal IDs as a temporary Collection filter. Undo removes reverted additions from that result view without inventing a second list.

### Projection integration

- Fix authoritative optional-value handling: a newer matching Library row’s nil unit/label cannot fall back to old detail data.
- Return typed Library refresh results rather than swallowing errors.
- Publish committed changes through one bounded account-scoped integration hook.
- Refresh mounted Home, the visible Collection query and affected Releases state.
- Coalesce refreshes at source-page/application boundaries; remove duplicate refreshes.
- Do not reread the full Library after every chunk or tracking tap.
- Keep pending local changes visible and preserve account/permission generation checks.
- Treat optional artwork/enrichment failure independently from saved tracking.

### Existing backend integration

- Retain the reviewed legacy Apply/Undo, AniList, deletion and retrieval repairs.
- Reinspect effective live versions, grants, policies and migration history before assembling the revised deployment.
- Add forward repairs; preserve historical inputs/checksums and never blanket-push the migration directory.
- Reassemble the exact guarded SQL transaction and named Edge closures only after the repaired contracts pass.
- Include populated series/unit reader proof in the disposable fixture. Live catalog backfill and worker activation remain outside this deployment; real unresolved catalog entries use honest singleton/unavailable behavior.
- Present the exact changed production set, affected behavior and disable/recovery procedure for required approval.
- After approved deployment, verify effective contracts before enabling local simulator overrides.
- Build/install the exact verified simulator candidate and run the actual included journeys.
- Keep global rollout unchanged. No archive, TestFlight upload or App Store submission.

### Coordination

After the lead freezes contracts, use disjoint ownership:

- Backend job/ingestion/Undo implementation.
- Journal/XML/recovery implementation.
- Native review/results/navigation implementation.
- Library/Home/Collection/Releases integration.
- Focused independent reviewer for changed high-risk seams.

The lead owns shared composition, migration assembly, deployment inputs and canonical documentation. Coordinate with the already-authorized Home/series chat before shared edits. No two lanes edit the same file concurrently.

## 5. Verification, success gates and future rules

### Focused verification

Reuse existing tests and extend them where these behaviors are missing:

| Group | Required proof |
|---|---|
| Actual entrypoints | Real AniList preview→confirm chain; both media; MAL account/XML; legacy compatibility |
| Existing Library | New, identical and different entries; default keep; approved fields only; later edit/removal protection |
| Fidelity | Official MAL statuses, XML ratings, coupled score/progress identity, unavailable fields and promised metadata |
| Results | Correct counts; all-rejected, partial and no-op; title reasons; Stay/View actions |
| Recovery | Lost response, restart discovery, missing XML file, terminal-cleanup interruption, stop then new import |
| Undo | Added/updated compensation, uncertain response replay, later edits/replacement skipped, pending local change guard |
| Integration | Mounted Collection/Releases, held detail snapshot, Library-read failure after commit, account transition |
| Safety | Owner/outsider authorization, current club permission, account deletion and retained-input cleanup |
| Efficiency | Multi-page request counts and one representative bounded responsiveness sample |

Run affected checks during work. Run the integrated required checks once on the final candidate. Repeat only after changed source or unresolved failures invalidate evidence.

After deployment, exercise real simulator AniList, controlled MAL account/XML, interruption/restart, results navigation, tracking and account transitions. Requalify changed live authorization and deletion/upload cleanup using recorded disposable resources and the existing bounded limits.

### Four binary gates

1. **Source safety:** reviewed policy, ingestion fidelity, replay, Undo and privacy have no unresolved in-scope defect.
2. **Product integration:** actual entrypoints, persistent recovery/results and shared projections work.
3. **Backend qualification:** exact approved deployment identities and relevant live behavior are verified.
4. **Simulator delivery:** exact installed build completes the included journeys; disposable cleanup and disable/recovery are verified.

Use `PASS`, `FAIL` or `BLOCKED`. Missing provider consent or live evidence remains a specific blocker. Fixture limitations do not repeatedly fail unrelated checks.

### Lasting implementation rules

- One named lifecycle owner and narrow typed API per capability.
- No alternative Library authority or raw writers in views.
- Immutable attempted actions; explicit missing versus clear semantics.
- Account leases for private async work and permission checks for club-derived content.
- Persistent outcomes for operations that can partially commit.
- No hard line caps. Review roughly 400–600-line files and 350–500-line stateful types for mixed responsibilities; split by ownership, lifetime or failure policy.
- Independent review for changed auth, permission, mutation recovery and deployment contracts.
- Update the three canonical state documents, finding dispositions and permitted memory extension once per completed initiative.
- Do not claim production readiness from local tests or simulator installation alone.

**Completion verdict:** the repaired import/Library/Home scope is integrated and qualified on the installed simulator against the reviewed live backend. TestFlight and public release remain outside this implementation.


## Execution checkpoint — exact approved backend and visible Home

The original specification above remains the execution contract. The user approved the exact four-input SQL/six-Edge set, which is deployed and effective-postflight verified. Real v2 import and corrected Realtime checks pass with administrative disposable cleanup. Native Home/detail fidelity repairs pass focused review/rendered checks; the actual Library query repair makes restored Home visible. Final cache-selection correction is source accepted, built, exactly installed and actual Anime→Manga selection verified. MAL login is dismissed; a controlled MAL user account is unavailable, specifically blocking account connector qualification. Independent provider/installed journeys remain pending; public CDN propagation remains a disclosed failed observation. See [current evidence](../handoffs/2026-10-08-backend-integration/approved-deployment-live-evidence.md) and [four gates](../handoffs/2026-10-08-backend-integration/import-v2-gates.json). No TestFlight, global activation or broader deployment.


### Linked native visual refinement

The user requested a cohesive visual polish plan after reviewing the installed translation, including image-led first-title/import actions, neutral colors and Profile. [Native design polish](2026-10-08-native-design-polish.md) governs this presentation workstream. Functional contracts, findings and recovery remain governed here. Current native technical checks do not constitute owner visual acceptance. The polish initiative is planned; no runtime change follows from saving its specification.
