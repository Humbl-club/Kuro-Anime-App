# SQL function index: method, validation and findings

Companion to `sql-function-index.csv` (E7 deliverable 1). Generated mechanically by `sqlparse.py` + `model.py` + `build_index.py` in this directory from a snapshot of `supabase/migrations/*.sql` (copy in `snap/migrations/`). Read-only on the repo; no remote project contact.

## 1. Snapshot and counts

| item | value |
|---|---|
| migration SQL files parsed | 235 (`git status --short supabase/migrations` was empty at snapshot; README_baseline_capture.md excluded) |
| combined digest of per-file sha256 list (see `sql-chain-snapshot-manifest.csv`) | `4c30e82f19e0241e2d2b67e3e7917fe6dde1e08a428569e74f5da252435206ad` |
| CREATE FUNCTION statements | 261 |
| distinct schema+signature | 144 (131 current, 13 dropped later in the chain) |
| distinct function names | 140 total, 131 current |
| schema of every definition | public (259), unqualified/implicit public (2) -- no `extensions.*` or other schema functions are defined by the chain |
| overloaded names | recommend_ids_premium, browse_anime_page, browse_manga_page, get_manga_chapter_enrich_candidates (older signature dropped, newer current in each case) |
| names with >=5 definitions | recommend_ids_similar_to_seeds 16, rebuild_media_similar_titles 8, fetch_taste_deck_batch 7, fetch_club_bundle 6, delete_user_concierge_data 6, recompute_user_taste_profile 6, discover_bundle 5, concierge_housekeeping 5, record_taste_deck_signal 5 |
| ALTER FUNCTION / ALTER DEFAULT PRIVILEGES / GRANT ON ALL FUNCTIONS statements in chain | 0 / 0 / 0 (only per-signature GRANT/REVOKE: 218 grant + 163 revoke statements, some inside DO blocks) |
| cron.schedule/unschedule/alter_job statements parsed | 65; 19 jobs remain scheduled after replaying schedule/unschedule in order (job names only; commands not copied because some migrations embed secrets) |

## 2. How the parse was validated

1. Independent regex count (comments stripped) of `create [or replace] function` per file equals the tokenizer count in every file (261 = 261); `drop function` 88 = 88.
2. The 16 hosted definitions in `docs/research/2026-09-26-kuro-plan/evidence/live-functions.json` and `live-serving-functions.json` were parsed with the same code and compared with the latest local definition: signature, SECURITY mode, volatility, language and comment-stripped body match for 16/16. **search_path differs for 3**: collection_anime_page, collection_manga_page, collection_feed_page are `set search_path = public` in source (`20260204010500_collection_paging_rpc.sql:41,113`, `20260204133000_collection_feed_paging_rpc.sql:42`) but `public, extensions` in the hosted definitions. The earlier audit compared bodies only; this is source-versus-hosted attribute drift (hosted-only change, no migration in the chain performs it). Source wins for this inventory.
3. `evidence/rpc-review-register.csv` (57 rows): latest definition file:line agrees with this index for all 57; definitions_seen agrees for every row that has a count when counted per function name (the register counts all overloads, e.g. browse_anime_page 4 = 2 + 2). No RPC called by Swift (49 literal `.rpc("...")` names found by grep over Kuro/, same as the canvas) or by edge functions (22 names) or scripts (9 names) lacks a definition in the chain.
4. **Execution check of the ACL model: BLOCKED.** `acl_replay.py` (kept here) starts a private PostgreSQL 17 cluster on loopback and replays only the function-related statements to compare `has_function_privilege` with the static model. It could not start: `initdb` fails with `shmget ... No space left on device` because the other sessions' postgres clusters hold 31-33 SysV segments (`ipcs -m`) against `sysctl kern.sysv.shmmni` = 32. Nothing was killed or changed. Rerun when segments are free: `python3 acl_replay.py` (writes acl-replay-result.tsv, acl-replay-errors.txt).

## 3. ACL model (read this before using the grant columns)

Static replay of every GRANT/REVOKE per signature in chain order. Starting state when a signature is (re)created: EXECUTE for PUBLIC plus anon, authenticated, service_role (Supabase default privileges; same assumption as `supabase/tests/fixtures/00_platform_stub.sql:71-76`, and the repo's own observation in `20260804121000_rebuild_tier_execute_service_role_only.sql:1-4` that `revoke ... from public` left anon/authenticated with EXECUTE "observed in proacl post-push"). CREATE OR REPLACE keeps the ACL; DROP + CREATE resets it. A role can execute if PUBLIC or the role itself is in the set. **This is a prediction from source, not the live proacl** (not queried).

| class | count (current functions) |
|---|---:|
| R11_NO_SEARCH_PATH: no `SET search_path` at all (rule 11 violation) | 7 |
| R11_NO_SEARCH_PATH+DEFINER: no search_path and SECURITY DEFINER | 0 |
| SP_PUBLIC_ONLY(info): search_path is `public` only (rule text says `public, extensions`; pg_trgm lives in public here, so search_*_page work) | 63 |
| SP_VARIANT: other search_path values (pg_temp/auth/information_schema) | 8 |
| DEFINER_NO_EXPLICIT_GRANT: SECURITY DEFINER with no GRANT/REVOKE anywhere in the chain | 10 |
| DEFINER_ANON_EXECUTABLE(static): SECURITY DEFINER and anon can execute per static model (non-trigger) | 64 |
| DEFINER_NO_AUTH_GATE_IN_BODY: definer + anon-executable + no `auth.uid()/auth.role()/auth.jwt()` reference in body | 21 |
| ANON_EXEC_DESPITE_RESTRICTIVE_GRANTS(static)+DEFINER: chain shows restrictive intent (GRANT to authenticated/service_role only, or REVOKE from public/anon/authenticated) yet static model still lets anon execute; DEFINER | 38 |
| ANON_EXEC_DESPITE_RESTRICTIVE_GRANTS(static): same, SECURITY INVOKER | 18 |
| MANY_DEFS: >=5 definitions | 9 |
| SENSITIVE: named in the brief | 7 |

Rule 11 (CLAUDE.md): current functions with **no** search_path: `set_updated_at`, `normalize_title`, `search_titles`, `recommend_ids_by_tag_categories`, `current_season_name`, `generate_invite_code`, `sharing_level_rank` (all SECURITY INVOKER; 3 are trigger/pure helpers). No SECURITY DEFINER function lacks it. 53 functions use exactly `public, extensions`; 63 use `public` only; 8 use variants.

SECURITY DEFINER functions with **no explicit grant/revoke anywhere in the chain** (10): `is_club_owner`, `log_club_event`, `toggle_club_reaction`, `shares_club_with`, `upsert_title_comment`, `delete_title_comment`, `toggle_comment_reaction`, `fetch_friend_activity_for_title`, `count_friends_tracking`, `record_outbound_link`. All 10 gate on `auth.uid()` in the body (UNAUTHENTICATED raise), so default anon EXECUTE is not directly exploitable; they are owned by Clubs/SocialActivity/OutboundTelemetry. They get their privileges only from platform defaults.

Highest-value live verification (static model predicts anon-executable DEFINER writers without an auth gate in the body): `rate_limit_hit(text,integer)` (`20260806000000_security_and_mirror_repair.sql:11` revokes only anon/authenticated, but PUBLIC was never revoked, so the stated repair is a no-op under the model), `llm_global_budget_reserve/finalize` (grant authenticated only, `20260205000500`), `enqueue_media_availability_refresh` and `get_provider_availability_refresh_*` (REVOKE ALL public + GRANT authenticated/service_role in `20260301153000`), `get_provider_availability_refresh_candidates`. Check with `select has_function_privilege('anon','public.rate_limit_hit(text,integer)','execute')` (read-only) against a disposable DB or the live proacl when authorised.

## 4. The brief's sensitive functions

| function | defs | latest effective def | security / search_path | explicit grants in chain | static anon exec | gate in body | owner |
|---|---:|---|---|---|---|---|---|
| `recommend_ids_similar_to_seeds(text,integer[],integer,boolean)` | 16 | `20260806020000_serving_hardening_v1.sql:134` | DEFINER / `public, extensions, pg_temp` | yes (31 events) | Y | auth.uid | Recommendations |
| `fetch_club_bundle(uuid)` | 6 | `20260317110000_fetch_club_bundle_ordering_and_poll_counts.sql:10` | INVOKER / `public` | yes (6 events) | Y | auth.uid | Clubs |
| `shares_club_with(uuid)` | 1 | `20260224150000_social_activity_layer.sql:44` | DEFINER / `public, extensions` | NONE | Y | auth.uid | SocialActivity |
| `toggle_comment_reaction(uuid,text)` | 1 | `20260224150000_social_activity_layer.sql:191` | DEFINER / `public, extensions` | NONE | Y | auth.uid | SocialActivity |
| `create_club_rail(uuid,text,text)` | 1 | `20260807000000_baseline_capture_v1.sql:2552` | DEFINER / `public` | yes (3 events) | Y | auth.uid | Clubs |
| `add_club_rail_item(uuid,text,integer,text)` | 2 | `20260216193000_add_club_rail_item_structured_errors.sql:4` | DEFINER / `public` | yes (2 events) | Y | auth.uid | Clubs |
| `upsert_title_comment(text,integer,text)` | 1 | `20260224150000_social_activity_layer.sql:117` | DEFINER / `public, extensions` | NONE | Y | auth.uid | SocialActivity |

- `recommend_ids_similar_to_seeds` 16 definitions in: 20260203203000; 20260204233000; 20260204234500; 20260204235500; 20260731060000; 20260731150000; 20260731160000; 20260731180000; 20260731200000; 20260802123000; 20260802140000; 20260802141000; 20260804100000; 20260804130000; 20260804140000; 20260806020000 (full file:line list in the CSV column `earlier_def_files`). Callers: iOS `SupabaseService+Recommendations.swift:54`, edge `concierge-recommend/index.ts:2269`, SQL `fetch_because_you_rail`. Latest (`20260806020000_serving_hardening_v1.sql:134`) is SECURITY DEFINER with `public, extensions, pg_temp`; grants: repeated `GRANT ... TO anon/authenticated` (a REVOKE ALL FROM PUBLIC appears at `20260802123000:615` before the re-grant to anon, authenticated).
- `fetch_club_bundle` is SECURITY INVOKER (RLS carries the privacy projection) with `search_path = public` only; grants are `authenticated` only with no REVOKE from PUBLIC, so anon may call it (returns nothing through RLS). *Prepared, not deployed:* `20261005150000` makes it (and `fetch_club_bundle_loading`) an authorized SECURITY DEFINER aggregate; see section 8.
- `shares_club_with`, `upsert_title_comment`, `toggle_comment_reaction` (all `20260224150000_social_activity_layer.sql`) are DEFINER with `public, extensions`, have **no grant statements at all**, and gate on `auth.uid()` (`shares_club_with` reads `auth.uid()` inside the SQL; it is also used by RLS policy `title_comments_select`).
- `create_club_rail` exists only in the baseline capture (`20260807000000_baseline_capture_v1.sql:2552`, originals lost in the hollowed 2026-02-15 migrations); definer, `search_path = public`, explicit GRANT to anon, authenticated, service_role (2615-2621, inside a DO block guarded by `to_regrole`) and an `auth.uid()` + owner/admin gate in the body.

## 5. Owner distribution (current functions)

| owner | functions |
|---|---:|
| Clubs | 21 |
| Catalog | 20 |
| Taste | 17 |
| Recommendations | 13 |
| Discovery | 11 |
| Concierge | 10 |
| ProviderAvailability | 9 |
| SocialActivity | 6 |
| Search | 5 |
| other | 4 |
| Library | 4 |
| Mirror/Media | 3 |
| Telemetry/Ops | 2 |
| Identity | 2 |
| Imports | 2 |
| OutboundTelemetry | 2 |

Owner mapping is a hand-written name table (`owners.py`, every name mapped, 0 unmapped). Releases has **no** SQL functions (upcoming reads are direct table/view reads from the iOS service); this is itself a finding for the E5 Releases extraction. Cross-capability couplings to keep visible: `shares_club_with`/`count_friends_tracking` (SocialActivity reading club_members), `club_shared_providers` (ProviderAvailability reading club_members), `taste_capture_list_mutation`/`taste_bump_list_updated_at` (triggers on the Library list tables owned by Taste/Library), `acquire_import_lock` (named "import" but used only by catalog bulk-import/mirror/chapter-enrich edge functions, not user-list Imports), `delete_user_concierge_data` (Identity deletion calling Concierge/Clubs data).

## 6. Dependencies not defined in the chain

- `user_lists` view is read by 10 function bodies (recommend_ids_*, curated_rail_cards, fetch_tonight_shelf, ...) and also by `concierge-recommend/index.ts` (`.from("user_lists")`); no CREATE VIEW for it exists in the 235-file chain (its only CREATE is `legacy_sql/08_create_user_lists_view.sql`; migrations only ALTER it). Matches the earlier audit.
- `media_realm_tier` is read by 8 function bodies. In the chain it is a materialized view only between `20260731150000_realm_graph_v1.sql:285` and `20260804120000_tier_from_effective_and_cron.sql:67-86`, which creates `media_realm_tier_next` as a plain table, drops the matview and renames it into place (then `enable row level security` + policy `media_realm_tier_select_all`). **The chain therefore ends with a TABLE**, consistent with the hosted relkind `r` in schema-modularity-audit.md. The statements that the chain has it as a matview / that production diverges (`README_baseline_capture.md:42-45`, schema-modularity-audit.md section 2, the `media_realm_tier` row of `canvases-canonical/kuro-schema-crossref.canvas.tsx`, commit 39fb922 title) are wrong for the end-of-chain source; they are only true if a replay stops before 20260804120000. Source wins.
- Orphan ACL statement: `20260731070000_taste_math_v2_hotfix.sql:1503` revokes on `purge_taste_import_context()` which is not defined anywhere (guarded by an `exists (select 1 from pg_proc ...)` probe inside a DO block; harmless).

## 7. Limits

- Dynamic SQL built with `format(%I)` is not parsed (9 EXECUTE sites: policy/index/ALTER TABLE only; plus 1 conditional `revoke` inside a DO block that *is* parsed). None creates or grants a function dynamically.
- "tables touched" comes from FROM/JOIN/INTO/UPDATE/DELETE/TRUNCATE tokens in the latest body (CTE names excluded); calls come from `name(` tokens that match a chain-defined function. Calls through dynamic EXECUTE or via views are not seen.
- Policy refs/trigger refs/cron refs show the latest object definition per (table, name); policies dropped later are removed. Hosted-only objects (cron jobs created via the Management API, hosted-only ALTERs such as the collection_* search_path above) are invisible to a source parse.
- Register validation scope: only the RPC subset was cross-checked (49 Swift `.rpc` names = the schema-crossref canvas; `rpc-review-register.csv` 57/57 latest-definition locations agree; 22 edge and 9 script RPC names all resolve). `client-call-register.csv`, `edge-call-register.csv`, `social-call-register.csv` and `operational-call-register.csv` were not diffed row by row. `deno check` fetched modules from deno.land/esm.sh/jsr only; no Supabase endpoint was contacted.
- The static ACL columns (`static_exec_*`, `static_acl_entries`, flags `ANON_EXEC_DESPITE_RESTRICTIVE_GRANTS`, `DEFINER_ANON_EXECUTABLE`) are a model prediction; the execution check is BLOCKED (section 2.4). 56 current functions carry `ANON_EXEC_DESPITE_RESTRICTIVE_GRANTS` (38 DEFINER, 18 INVOKER).

## 8. Prepared, NOT deployed: lane L3 changes (20261005140000 ... 20261005180000)

These live in `supabase/prepared-migrations/` (outside the deploy path) and are NOT in the parsed
chain above; the CSV keeps describing the deployed chain and only points here (`owner_note`) for the
four existing functions they redefine. Deploy order: 140000 -> 150000 -> 160000; 170000 and 180000
are independent. Tests: `supabase/tests/rls/10,12,20,50,51,63,64,65,66_*.sql`,
`supabase/tests/concurrency/90,91_*.sql`. Error codes are in MESSAGE (HINT repeats the new ones).

| Object (file) | Contract: input -> output / errors | Security, search_path | Grants | Authorization, locks, transaction | Callers | Owner |
|---|---|---|---|---|---|---|
| `account_deletion_barriers` table (140000) | `user_id uuid PK, started_at`; no FK on purpose | RLS on, no policies | service_role select/insert/delete; none for anon/authenticated | outlives the auth user; purged by `begin_account_deletion` after 7 days once the auth user is gone | barrier functions | Identity / account deletion |
| `begin_account_deletion(p_user_id uuid)` (140000) | -> `{success, started_at}`; `INVALID_USER_ID` | DEFINER, `public, extensions` | EXECUTE service_role only | exclusive `pg_advisory_xact_lock` on the user key (waits for in-flight guarded writers), idempotent barrier insert, bounded purge; one transaction | `delete-account` edge function (JWT-derived id) | Identity / account deletion |
| `_account_write_guard(text)`, `account_deletion_write_barrier()` trigger fn, `_account_deletion_lock_key(text)` (140000) | refuses with 42501 `ACCOUNT_DELETION_IN_PROGRESS` when a barrier exists | DEFINER (guard, trigger), `public, extensions` | no EXECUTE for public/anon/authenticated | shared advisory lock per row write, then barrier lookup in a new statement (READ COMMITTED); BEFORE INSERT OR UPDATE on anime/manga_user_lists, anime/manga_comments, club_analytics, concierge_events, discover_rail_impressions, rag_retrieval_feedback, concierge_runs; BEFORE INSERT on club_members | every writer of those tables, incl. service role; `join_club` calls the guard first | Identity / account deletion |
| `club_member_blocks` table (150000) | `(club_id, user_id) PK, blocked_by, created_at` | RLS on | select authenticated (policy: owner/admin of the club); all service_role | written only by the `club_members_lifecycle` trigger; cascades with club/user | `join_club`, `restore_club_member` | Clubs |
| `_club_settle(uuid)`, `_club_member_depart(uuid,uuid,text)` (150000) | depart -> `{club_id, outcome left/account_deleted/not_a_member/club_gone, previous_role, club_deleted, owner}` | DEFINER, `public, extensions` | none for public/anon/authenticated | THE membership lifecycle: club row `FOR UPDATE` first, delete membership, then settle: delete an empty club (re-checked in a new statement under the lock) or transfer ownership (oldest admin, else oldest member, deleting users last, `FOR UPDATE` skips concurrently removed candidates) | `leave_club`, `delete_account_club_memberships`, trigger | Clubs |
| `club_members_lifecycle()` trigger fn (150000) | AFTER DELETE on club_members | DEFINER, `public, extensions` | none | block row when another authenticated user removed the member; settle when the owner row disappears by any path (incl. auth.users cascade) | every membership deletion | Clubs |
| `fetch_club_bundle(uuid)` (150000, was INVOKER 20260317110000) | shape unchanged; `NOT_A_MEMBER`, `UNAUTHENTICATED`, `CLUB_NOT_FOUND` | **DEFINER**, `public, extensions` | EXECUTE authenticated only (revoked public/anon/service_role) | explicit `is_club_member` check; member list: private or <3 members -> caller only; item counts: none below 3 members, private club `_tracking_count` (others), status/progress per-status counts over effective rank >= 1; `member_statuses` status at rank >= 1, progress at rank >= 2; votes/reactions of current members only | Swift `ClubsStore` | Clubs |
| `fetch_club_bundle_loading(uuid)` (150000, was INVOKER 20260318104000) | shape unchanged | **DEFINER**, `public, extensions` | EXECUTE authenticated only | explicit `is_club_member` check; counts of current members | Swift `ClubsStore` | Clubs |
| `join_club(text)` (150000, was 20260218141754) | adds `REMOVED_FROM_CLUB`; an empty (orphaned) club -> `INVALID_CODE` | DEFINER, `public, extensions` | EXECUTE authenticated (revoked public/anon) | barrier guard first (user lock), then club row `FOR UPDATE` (serializes with the lifecycle and other joins: member cap), block check | Swift `ClubsStore` | Clubs |
| `leave_club(uuid)` (150000, was 20260209202000) | unchanged `{success}` / `NOT_A_MEMBER` | DEFINER, `public, extensions` | EXECUTE authenticated | `_club_member_depart(club, caller, 'left')` | Swift `ClubsStore` | Clubs |
| `remove_club_member(uuid,uuid)` (150000, new) | -> `{success, removed}`; `NOT_ADMIN`, `NOT_A_MEMBER`, `CANNOT_REMOVE_SELF` | DEFINER, `public, extensions` | EXECUTE authenticated | club row lock; owner/admin only; never the owner; admins cannot remove admins; trigger records the block | none yet (no removal UI); replaces the direct table DELETE, which own-row SELECT makes ineffective | Clubs |
| `restore_club_member(uuid,uuid)` (150000, new) | -> `{success, restored}`; `NOT_ADMIN` | DEFINER, `public, extensions` | EXECUTE authenticated | owner/admin only; deletes the block (no membership created) | none yet | Clubs |
| `delete_account_club_memberships(uuid)` (150000, new) | -> `{success, memberships_removed, clubs_deleted, ownership_transferred}`; `DELETION_NOT_STARTED`, `INVALID_USER_ID` | DEFINER, `public, extensions` | EXECUTE service_role only | exclusive user lock, requires the barrier, lifecycle per membership in club_id order (lock order: user lock, then club rows); retry-safe | `delete-account` edge function | Clubs / account deletion |
| policies (150000) | `club_members_select_own`, `club_votes_select_own`, `club_reactions_select_own` replace the three `*_select_member`; `club_members_delete_self` (own non-owner row) replaces `club_members_delete_self_or_admin` | - | - | raw per-user rows own-only (F34) | PostgREST / Realtime | Clubs |
| `club_activity_signals`, `club_membership_signals`, `_club_activity_bump(uuid)`, `club_realtime_signal()` (160000) | activity `(club_id, revision, changed_at)`; membership `(user_id, club_id, state member/left/removed/club_deleted, revision, changed_at)` | trigger fns DEFINER, `public, extensions` | select authenticated (RLS: member of club / own rows); no table-API writes | AFTER triggers on clubs, rails, items, polls, votes, reactions, members; both tables in `supabase_realtime`; club_members stays out | Swift club realtime coordinator (lane L1) | Clubs realtime |
| `public.user_lists` view (170000) | unchanged columns | `security_invoker = on` | unchanged (anon reads 0 rows under invoker; a revoke would break anon-executable INVOKER readers) | base-table owner RLS applies to the caller; no-op (NOTICE) if the view is absent | concierge-recommend, recommend SQL functions | Library |
| `list_user_id_canonical_case()` trigger fn (180000) | normalizes `user_id := lower(btrim(user_id))` | INVOKER, `public, extensions` | none needed (trigger) | BEFORE INSERT OR UPDATE OF user_id on anime/manga_user_lists, before the RLS WITH CHECK | every list writer | Library |
| opt-in `prepared-migrations/opt-in/20261005180100_list_user_id_lowercase_backfill.sql` | one DO block; default refuses with `COLLISIONS_PRESENT`; `-v resolve_collisions=keep_newest` keeps the newest row | runs as the approved operator | - | single transaction, post-condition check; never auto-applied | operator, after the read-only counts | Library |
