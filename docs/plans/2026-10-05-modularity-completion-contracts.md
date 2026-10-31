# Modularity completion: frozen shared contracts (pass 2)

Frozen by the lead before lanes run in parallel. A lane that needs a change writes the request into its report; only the lead edits this file. Rulings: [ledger](2026-10-05-modularity-completion-ledger.md). Findings: [contract](../handoffs/2026-10-05-whole-codebase-modularity-contract.md), [register](2026-10-05-modularity-completion-register.csv).

## 1. Rate-limit gate (F32), landed

`supabase/functions/_shared/rate_limit_gate.ts` (+ `_test.ts`, 6 tests). Handlers keep their own `check_concierge_rate_limit` RPC call and pass the raw result through `interpretRateLimit`; `rateLimitBlockedResponse(decision, json)` returns the stopping response or `null`.

| RPC result | Decision | HTTP |
| --- | --- | --- |
| `data.allowed === true`, no error | allowed | proceeds |
| `data.allowed === false` | denied | 429 `{error:"Rate limited", retry_after_s}` + `Retry-After` |
| error, null data, or no boolean `allowed` | unavailable | 503 `{error:"Rate limiter unavailable", retry_after_s}` + `Retry-After` (no write, no provider charge) |

Applies to all eight call sites: apply, undo, parse, resolve, recommend, retrieve-assist, retrieve-feedback, import-anilist. Each owning lane replaces its inline `if (rl && rl.allowed === false)` with the gate and tests one limiter-error case through its real handler. The fake (`_shared/test_fake_supabase.ts`, L2a) gains a `rateLimitError` option.

## 2. Alias normalization (F31)

One module `supabase/functions/_shared/alias_normalization.ts` (L2b creates it) exporting `normalizeAliasKey(raw)` (the key Parse and Apply both use) and `aliasLookupKeys(raw): string[]` (the new key first, then the legacy Apply key when different, deduplicated). Parse reads aliases with `aliasLookupKeys`; Apply records with `normalizeAliasKey`. Existing persisted aliases written by the old weaker Apply normalization stay readable through the legacy key; no data migration. `concierge-apply/apply_plan.ts` (L2a) imports it once L2b reports it landed; until then it keeps its local function.

## 3. Apply / Undo wire contract v2 (P2-R2)

Existing fields keep their meaning; everything below is additive unless marked CHANGED.

**Apply request** `POST /concierge-apply` `{ items: Item[], idempotencyKey?: string }`. `idempotencyKey` is a client-generated UUID, one per user action; the server stores it on the session (unique per user). Item identity validation (F14, CHANGED): `mediaId` must be a positive safe integer, `mediaType` `ANIME|MANGA`, `status` in the medium's vocabulary; anything else is HTTP 400 `{error, code:"INVALID_ITEM", index}` and nothing is written. Quantity fields (progress, rating) stay clamped.

**Apply response** `{ success, sessionId, applied[], skipped[], conflicts[], errors[], status, undoable, replayed }`:
- `success` is true only when every item was accepted (unchanged meaning).
- `status`: `applied` (all accepted), `partial` (at least one accepted and at least one conflict/error), `none` (nothing accepted, nothing written), `failed` (HTTP 500/503, see below).
- `undoable`: true iff the session has at least one journaled applied item.
- `replayed`: true when an identical `idempotencyKey` returned the stored outcome without re-applying.
- Accepted item writes + their journal rows + the session transition commit in ONE database transaction. A returned journal or session error means the whole Apply rolled back and the response is HTTP 500 `{error, status:"failed", retryable:true}`. A retry with the same `idempotencyKey` is safe.
- Season/episode annotations never overwrite existing authored notes (F15, CHANGED): notes are written only when the item carries explicit notes; the structural `S{n}E{m}` text is used only for a NEW row's notes.
- Limiter: see section 1.

**Undo request** `POST /concierge-undo` `{ sessionId }` (unchanged).

**Undo response** `{ success, sessionId, reverted[], skipped[], warnings[], errors[], status }`:
- Undo is one conditional transaction per session. For each journaled item it compares the CURRENT row to the journaled after-image field by field (list_type, progress, rating, notes, verdict) and reverts only fields still equal to what the import wrote; an add whose row is unchanged is deleted. A later edit keeps its value; a row deleted after import stays deleted. Both are reported in `skipped[]` with `{mediaType, mediaId, reason}`, `reason` in `edited_since_import | deleted_since_import`.
- `status`: `undone` (every item resolved: reverted or skipped), `partial` is not used (a failure rolls the transaction back and the session stays `applied`, HTTP 500 `{error, retryable:true}`).
- An already-undone session is HTTP 200 `status:"undone"` with empty `reverted` (idempotent). HTTP 404 only when the session does not exist, is not the caller's, or has no journaled items. `partial` Apply sessions are Undo-eligible.
- The session status becomes `cancelled` only after every item resolved.

**Journal schema (prepared forward migration, L2a):** `import_session_items` keeps its columns and gains `after_values jsonb` (the values the import wrote for the fields it touched) and `reverted_at timestamptz`; `import_sessions` gains `idempotency_key text` with a partial unique index per user. The transaction is exposed as service-role-only RPCs `apply_import_session(p_user_id, p_session_id, p_idempotency_key, p_items)` and `undo_import_session(p_user_id, p_session_id)`; the handler derives `p_user_id` from the verified JWT (never from the body). SECURITY DEFINER with `SET search_path = public, extensions`, EXECUTE revoked from PUBLIC/anon/authenticated. File goes in `supabase/prepared-migrations/` (outside the deploy path) and is registered by the lead in `supabase/tests/pending_migrations.txt`.

**Swift side (wave 2, after the backend lands):** `ImportsService` sends `idempotencyKey`, decodes `status`/`undoable`/`replayed`/`skipped`, and the Concierge view shows an accurate partial summary with Undo when `undoable`. Until the Apply deploy, an old server omits the new fields: the client treats missing `status` as the old behavior (`ImportReconciler.sendsStoredRatingAndNotes` remains the deploy switch).

### 3a. As implemented by L2a (approved by the lead; additive to the contract above)

- `reverted[]` entries: `{mediaType, mediaId, undoType: "deleted"|"restored", fields?}`; `skipped[]`: `{mediaType, mediaId, reason: "edited_since_import"|"deleted_since_import", fields?}` (an update can appear in both). Undo `warnings[]` carry `invalid_journal_identity`, `no_after_image`, `unrestorable_before_value`.
- Undo keeps HTTP 409 `{error: "Can only undo the most recent import session"}` (existing behavior); 404 body is always `{error: "No applied session to undo"}`; a malformed `sessionId` is 400 `{error, code: "INVALID_SESSION_ID"}`; a malformed `idempotencyKey` (not 1-128 of `[A-Za-z0-9_-]`) is 400 `{error, code: "INVALID_IDEMPOTENCY_KEY"}`.
- `INVALID_ITEM` also covers a non-object item; the `mediaId` upper bound is the int4 column bound 2147483647 (a larger id cannot be stored). `status: "none"` with `success: true` for an all-skip request; empty `items` returns the full shape (`applied: []`, not `0`).
- 500 bodies are `{error, status: "failed", retryable: true}` and never carry database error text; 503/429 bodies are the shared gate's.
- RPC result shapes: `apply_import_session` -> `{session_id, replayed, undoable, applied[], skipped[], conflicts[], errors[]}`; `undo_import_session` -> `{result: undone|already_undone|not_found|not_latest, session_id?, reverted[], skipped[], warnings[]}`. Planned item: `{media_type, media_id, import_action, expected, insert_values?, update_values?, journal: {raw, parsed, candidates, confidence}}`.
- Import-origin taste marking is now REQUIRED and inside the transaction (the context row is never visible to other transactions); alias recording and `log_concierge_run` are OPTIONAL, after commit, best-effort.
- Deploy order: migration (after approval, moved out of `prepared-migrations/`), then `concierge-apply` and `concierge-undo` together, then the Swift change. Swift must send `idempotencyKey`, read `status`/`undoable`/`replayed`/`skipped`, show `code`/`index` on a 400 and `retryable` on a 500, narrow `writesSeasonNote` to new rows only and set `sendsStoredRatingAndNotes = false`.

## 4. Club policy (P2-R1), applied by L3

Raw SELECT on `club_votes`, `club_rail_item_reactions` and `club_members` shows a member only their own rows (plus member metadata the product already shows: display name, role). Counts, poll results, reaction totals, member counts and status counts are computed by authorized SECURITY DEFINER aggregate functions that check `is_club_member(auth.uid())`, respect `sharing_level` for per-user details, and exclude departed members. `fetch_club_bundle`/`fetch_club_bundle_loading` keep their response shape. Removal: owner/admin removal inserts a block row so `join_club` refuses that user until an owner/admin restores them; leave deletes the membership and the user may rejoin with a still-valid invite. Account deletion goes through one club-lifecycle function shared with `leave_club` (ownership transfer, empty-club cleanup under a lock, re-check at delete time).

### 4a. As implemented by L3 (club policy refinements, approved by the lead)

- Removal is the RPC `remove_club_member` (owner/admin; never the owner; admins cannot remove admins) which records a block; `join_club` refuses with `REMOVED_FROM_CLUB` until `restore_club_member`. Leaving adds no block. The table DELETE policy is narrowed to one's own non-owner row (a table-API delete of another member's row cannot see it under own-row SELECT).
- Raw `club_members` is own-row only for everyone, owners included; other members' metadata reaches the app only through the authorized bundle, so owners cannot bypass the private / fewer-than-3-member gating. The bundle grants drop `service_role` (no caller).
- Below 3 members the bundle returns `member_status_counts = null` (the product's existing "fewer than 3 members: only own data" k>=3 rule). Private clubs with 3 or more members keep the anonymous count over the other members (spec: private members contribute anonymously). Residual owner decision: a unanimous count in a small group reveals the whole group; reaction/vote counts in 2-member clubs identify the other member (pre-existing).
- One lifecycle (`_club_member_depart` -> `_club_settle`) is shared by `leave_club` and account deletion; an AFTER DELETE trigger also settles clubs when an owner row disappears by any path. Account deletion uses `begin_account_deletion` (exclusive per-user advisory lock + barrier row); a BEFORE trigger on the user-keyed tables takes the shared lock and refuses writes with 42501 `ACCOUNT_DELETION_IN_PROGRESS` (proven for READ COMMITTED only).
- Realtime: `club_members` stays OUT of the publication. Two signal tables, `club_activity_signals` (per-club revision, no user ids, filter `club_id=eq.`) and `club_membership_signals` (per-user state member/left/removed/club_deleted, own-row, filter `user_id=eq.`), written by DEFINER triggers and published. Swift subscribes to those (native work reconciled by the lead in wave 2).
- Error codes carried in MESSAGE and HINT: `REMOVED_FROM_CLUB`, `NOT_ADMIN`, `NOT_A_MEMBER`, `CANNOT_REMOVE_SELF`, `ACCOUNT_DELETION_IN_PROGRESS` (SQLSTATE 42501).
- List `user_id` is canonicalized by a BEFORE INSERT/UPDATE trigger (`lower(btrim())`); the opt-in historical repair lives in `prepared-migrations/opt-in/` and is never replayed or registered. Clients must send lower-case ids in filters.

## 5. Test host and verification rules

- The unit-test host runs `FixtureHost` (landed): fixture URL/key, in-memory auth storage, deny-all sessions, no launch restore. `KuroTests/FixtureHostTests` proves it.
- Run Swift tests with `-only-testing:KuroTests/<SuiteStructName>` and your OWN `-derivedDataPath` and `-resultBundlePath` under the scratchpad lane directory; read `totalTestCount` from `xcrun xcresulttool get test-results summary --path <bundle>`; a zero count is not evidence.
- Never run the whole suite, `local_cd.sh`, exporters, live workers or anything against the linked/production project. The lead runs the integrated suites once on the final tree.
- Mutation checks: exact reverse replacement in a short window; never restore a whole file from a backup; `rg MUTATION Kuro KuroTests Packages supabase scripts` must be empty before you report.
