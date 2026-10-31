> **Authorized repairs are now IN PROGRESS:** see [REPAIR_LEDGER.md](REPAIR_LEDGER.md). Historical closure claims below are not restored by source edits.

# Execution ledger — Home and Anime/Manga detail, 7 October 2026

**Independent review update (7 October 2026): REQUEST CHANGES.** [R01–R16](INDEPENDENT_REVIEW.md) and [actual-source reproduction results](independent-review/repro-results.txt) supersede this ledger's earlier “approval only” and “no rule break” conclusions. Native delivery and foundation qualification are incomplete. Five focused package tests were freshly repeated and pass; three SQLite defects and rapid-tap loss were reproduced. Fresh PostgreSQL rerun was blocked before tests by host shared-memory exhaustion. The remaining entries below preserve the implementation author's original claims, not independent confirmation. Nothing was deployed or enabled by this review.

Closure pass on the existing dirty modular tree, then the “finish first plan” pass, then a gate recalibration (docs only). Design hashes were not re-checked. Nothing was deployed. Flags stay off. The prepared migration stays in `supabase/prepared-migrations/`.

**Wording:** “Concierge apply/undo” means the **import-session RPCs** (`apply_import_session` / `undo_import_session`) used by the archived Concierge **sheet** and structured import — not bringing Concierge back as a pager page. “Pending progress map” means the in-memory optimistic progress on `HomeStore` after a +1 tap — not a chat UI.

| Item | Status | Evidence |
| --- | --- | --- |
| Revision fence on progress, status, removal | Local, flag-gated | `SupabaseLibraryBackend` uses `apply_progress_mutations_v1` and `apply_remove_mutations_v1` only when `series_foundation_v1` is on. Notes, rating and verdict stay on PATCH and still advance `server_revision`. |
| Import-session apply/undo on the receipt | Local in prepared migration | `20261007040000` adds `_apply_progress_mutations_for_user`, `_fence_set_progress_status`, and replaces `apply_import_session` / `undo_import_session` so progress and status go through the receipt. Notes/rating stay direct. `81_import_session_receipt.sql` 20 assertions PASS. Not deployed. Concierge remains a sheet (`taste_deck_v1` at 100%). |
| Shared pending progress map | Local | `HomeStore.displayedProgress` / `pendingPosition` / `advance(...)`. Home, anime detail, manga detail, and series Collection children read one map after a progress tap. Receipt ack clears the pending key after `LibraryStore.adoptServerProgress`. Tap does not reload the bundle. Not a chat overlay. |
| Race rows | PASS | `93_series_fence_races.sql` 22 assertions. Progress versus note, add/delete/add lifecycle, import versus local edit, membership removal versus a comment. |
| Imports | PASS on throwaway PostgreSQL and package tests | `81_library_import_counts.sql` 9 assertions. Package tests cover 0/1/50 chunking, duplicate collapse, score 0 and private notes. MAL account API stays unavailable. AniList text preview remains while the foundation flag is off. |
| Bundles | Wired behind the native flag | Collection calls `collection_series_page_v1`. Home load-more uses `next_cursor`. A season change replaces the in-flight detail request. |
| Query plans | Inner EXPLAIN at 1M; 10M optional | `db/explain-largest-fixture.txt` — Home active uses `idx_anime_user_lists_home_active` (est. ~837k matching rows, Limit 12). Detail user row is PK lookup `rows=1`. Collection group-then-limit estimates `rows=1000000` then Limit 30. 100k and 1M loaded; 10M timed out on insert. Not a release blocker. |
| Outbox | Account-scoped drain, undo, conflict | Pending rows are read by account. Foreground and reconnect drain at most 50. Unsent undo restores `priorPosition`. A conflict offers keep-server or reapply. |
| Screens | Compared at 320/390/430 | Poster under `screenshots/poster/`. Native under `screenshots/native/` via `HomeCompositionSnapshotTests`. `composition-differences.md` lists prototype chrome differences; no first-plan rule break; no layout fix. |
| Release | Blocked on owner deploy approval only | Flags off. No `db push`, no edge deploy, no flag enablement. Pre-user soak is not a hard gate. |

## Hard gates (must pass or owner-approve before / around ship)

| Check | Result |
| --- | --- |
| Revision fence, replay, conflict, fractional label, tombstone | PASS earlier (`80_series_home_foundation.sql`) and still in the prepared migration |
| Progress versus note, new lifecycle, import versus local edit, membership versus comment | PASS (`93_series_fence_races.sql`, 22) |
| Import counts 0/1/50, score 0, private notes, omission | PASS (`81_library_import_counts.sql`, 9) |
| Import-session apply/undo receipts + idempotent replay | PASS (`81_import_session_receipt.sql`, 20) |
| 100k / 1M inner plans | PASS (`explain-largest-fixture.txt`) |
| iOS build | PASS. `xcodebuild` Kuro, iPhone 17 Pro simulator, exit 0. Snapshot suite PASS. |
| Native versus prototype screenshots at 320, 390, 430 | PASS (captured; rule checklist clean) |
| Owner-approved migrate + flag cohorts | NOT DONE. Awaiting explicit approval |
| Physical device VoiceOver and haptics | NOT RUN — required before `series_home_native_v1` goes to 100%, not before foundation migrate |
| Live check after deploy | NOT RUN — required after deploy, not as a pre-user soak |

## Optional / not release blockers (pre-user)

| Check | Result |
| --- | --- |
| 10M plans | OPTIONAL — NOT RUN (insert timeout). Growth curiosity only |
| 1000/5000 sessions, burst, soak | OPTIONAL — NOT RUN. Disproportionate hard gate with no production users; useful later as load tooling |
| Independent review | OPTIONAL — NOT RUN |

Order when a later approval exists: additive migration, then a build that can talk to it, then flag cohorts. Rollback is flag off. Do not drop receipts or the SQLite outbox file.
