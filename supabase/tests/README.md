# Disposable database tests (`supabase/tests/`)

Credential-free checks that run against a **throwaway local PostgreSQL 17 cluster**.
They never contact `bkdifromsqxkndnllmdj` / `*.supabase.co`.

> **What this is: an audited schema fixture. It is NOT a complete migration replay,
> and it is NOT Supabase Auth, Realtime, Storage, PostgREST, pg_cron, pg_net or
> the Supabase dashboard.** Platform pieces are documented *stubs*
> (`fixtures/00_platform_stub.sql`). A green run proves the listed authorization and
> transaction behavior for the schema this fixture contains, nothing about production parity.

## Run

```bash
scripts/db/run_local_db_tests.sh                 # whole run (~25 s)
scripts/db/run_local_db_tests.sh --only clubs    # only test files whose name contains "clubs"
scripts/db/run_local_db_tests.sh --report-dir /tmp/kuro-db-reports   # keep replay TSVs + logs
scripts/db/run_local_db_tests.sh --no-tests      # replay reports only
scripts/db/run_local_db_tests.sh --exclude-pending                  # fixture WITHOUT the pending migrations (deployed-chain state)
scripts/db/run_local_db_tests.sh --exclude-migration <basename.sql> # skip one migration (repeatable)
scripts/db/test_guard_env.sh                     # unit check of the environment guard
```

Exit codes: `0` every executed test passed and nothing was BLOCKED; `1` a test failed, or a
prepared migration did not apply to the fixture build; `2` refused by the environment guard;
`3` setup failed (e.g. PostgreSQL 17 not found; set `KURO_PG_BIN`); **`4` every executed test
passed but at least one test file or scope is BLOCKED** (missing fixture object or
unavailable environment). `4` is not a pass: with today's fixture the run always ends in `4`
(see BLOCKED below), which is the honest state.
Optional: `KURO_DB_PORT` (default `54329`; only labels the unix socket, TCP is off).

Requirements: Homebrew `postgresql@17` (`initdb`, `pg_ctl`, `psql`, and its `dblink`
contrib extension for the two-session tests). Docker is not used. Nothing is installed; the
cluster lives in `/tmp/kuro-db-test.*` and is stopped and deleted on exit (trap), including on
failure or Ctrl-C. If PostgreSQL cannot get a System V shared-memory segment (macOS allows 32
host-wide; other local clusters can hold them all), the runner retries the cluster start up to
`KURO_DB_START_ATTEMPTS` (default 40) times, 3 s apart; any other setup failure aborts.

### Three separate verdicts

The summary prints REPLAY, PREPARED, SETUP and TESTS on separate lines. A failed replay file
is **not** a test failure, and passing tests do **not** make the replay complete:

```
REPLAY      : INCOMPLETE -- baseline-first applied 193, failed 62; strict applied 146, failed 109 (the fixture is an audited schema, not a replay)
PREPARED    : every non-excluded supabase/prepared-migrations/*.sql applied to the fixture build
SETUP       : 0 test file(s) BLOCKED (not run), 3 scope(s) BLOCKED by missing fixture objects, 0 in-file BLOCKED marker(s)
TESTS       : 33 test files, 1122 assertions passed, 0 finding markers -> PASS (executed tests only)
LIVE        : 4 requirement(s), NOT PROVEN; mandatory separate live-services release gate
RESULT      : BLOCKED -- executed tests passed, 3 item(s) BLOCKED; NOT a complete verification (exit 4)
```

### Setup completeness (requirement manifest)

Every test file declares, in its header, the fixture objects it depends on:

```
-- @requires <kind> <object>                          file BLOCKED (not run) when missing
-- @requires-for "<scope>" <kind> <object> [marker]   that scope BLOCKED when missing
kinds: table | view | function <regprocedure> | function-body <regprocedure> <marker> | extension
```

Declare **prerequisites** only (tables/functions the test relies on but does not test, the
latest body of an RPC, an extension). An object that a prepared migration introduces is the
subject under test: its absence must FAIL the test, not block it. Current BLOCKED scopes:
`taste_tag_stats` (40) and the latest `delete_user_concierge_data` body (50). The similar-titles
gate skip/run decision (99) is no longer BLOCKED: when `media_similar_seed_state` is absent the
test creates a minimal stand-in and a counting stub core inside its rolled-back transaction, so
it proves the wrapper's decision logic (not the real core).

### Pending (prepared, NOT deployed) migrations

`pending_migrations.txt` lists files in `supabase/prepared-migrations/` (deliberately outside
`supabase/migrations/`, so `supabase db push` and `scripts/local_cd.sh` cannot deploy them) that
have **not** been applied to production (deployment is a separate human approval). The fixture
replays **every** `supabase/prepared-migrations/*.sql` by default, so the tests assert the fixed
behavior; `--exclude-pending` rebuilds the fixture without the listed files and the tests of the
fix then fail at their first assertion on purpose (the red half of the red/green evidence).
Status corrected 2026-11-01: the nine `20261005*` files are in `supabase/migrations/` (deployed
chain) and the four 2026-10-07/08 series/import files were applied on 2026-10-08
(`docs/handoffs/2026-10-08-backend-integration/approved-deployment-live-evidence.md`), so they are
no longer listed. The byte-identical `20261005*` copies still in `supabase/prepared-migrations/`
are replayed ONCE (`replay_migrations.sh` dedupes by basename and refuses two different files
under one name). Pending now:

| File | Fixes | Tests |
| --- | --- | --- |
| `20261007120000_feature_flag_overrides.sql` | per-account flag overrides (not live: PGRST205) | `95_feature_flag_overrides`, `50` (its FK is in the reviewed CASCADE set) |
| `20261101000000_release_schedule_and_themes_v2.sql` | spec 3.1-3.3 release/theme RPCs, D10 certainty (confirmed = instant only), per-source credit hosts, service-role writers, `finish_series_enrichment_v1` theme-ownership predicate | `98` |
| `20261101010000_perf_hotpaths.sql` | similar-titles gate (transactional dirty table), nightly rolling re-stale, audit retention, CONCURRENTLY matviews, change-aware `updated_at` | `99` |
| `20261101010100_perf_drop_duplicate_indexes.sql` (needs 010000; **no-transaction file**) | 22 exact duplicate indexes + unused audit-state index, `DROP INDEX CONCURRENTLY` | `99` |
| `20261101020000_bridge_identity_fix.sql` | legacy bridge natural key + one-time re-key with collision rule | `91`, `94` (accepts both key spellings) |
| `20261101030000_auth_hardening.sql` | `check_email_exists` no longer callable by anon/authenticated (D13) | `92` |
| `20261102100000_contact_messages.sql` | contact form table (service role only, no client policies), 12-month purge + daily cron, `user_id` SET NULL on account deletion | `93`, `50` (its FK is in the reviewed SET NULL set) |

A file whose first 10 lines contain `-- kuro:replay-no-transaction` holds statements that cannot
run in a transaction block; `replay_migrations.sh` applies it without `-1` (it must manage its
own transactional parts). Apply it in production with plain `psql -v ON_ERROR_STOP=1 -f`, never in
a single transaction.

`supabase/prepared-migrations/opt-in/` is **not** replayed and is not a migration: it holds the
one-time, human-approved F16 historical-row repair (`20261005180100_list_user_id_lowercase_backfill.sql`),
exercised only by `12_...sql` inside a rolled-back transaction.

To deploy one after approval: `git mv supabase/prepared-migrations/<file> supabase/migrations/`,
delete its line from the list (never edit the migration), then use the normal approved deployment
path. Run `prerequisites/delete_account_prereqs.sql` (read-only, below) on the approved target first.

## What the run does

1. guard + guard unit check, then `initdb` + start a socket-only cluster in a temp dir.
2. Load `fixtures/00_platform_stub.sql`: roles `anon` / `authenticated` (NOBYPASSRLS),
   `service_role` (BYPASSRLS), `authenticator`, `supabase_admin`; stub `auth` schema
   (`auth.users`, `auth.uid()/role()/jwt()` reading `request.jwt.claims` like Supabase);
   `extensions` schema + `pgcrypto`/`pg_trgm`; Supabase's default grants to the API roles;
   db-level `search_path = "$user", public, extensions`; stub `storage.buckets/objects`;
   `supabase_realtime` publication (membership only); **stub** `cron.*` (records, never
   runs) with a synthetic `pg_extension` row so `create extension pg_cron` is a no-op;
   **stub** `net.http_post/get` (no-ops, never open a socket).
3. Replay `supabase/migrations/*.sql` plus `supabase/prepared-migrations/*.sql` three ways (one
   transaction per file, a failing file is rolled back and replay continues; **no migration is
   ever edited**):
   - `strict`: empty DB, filename order. The honest "fresh rebuild".
   - `baseline-post`: the baseline `20260807000000`, then only later files.
   - `baseline-first`: the baseline first, then the whole chain in order (the baseline is
     applied again at its own slot). **This builds the fixture the tests run on.**
4. Setup completeness: every test file's requirement manifest is checked against the fixture.
5. Run `rls/*.sql` against the `baseline-first` database (each file in one rolled-back transaction).
6. Run `concurrency/*.sql`, each in its **own fresh clone** of the fixture (they COMMIT), with
   `lib/10_concurrency_helpers.sql`: actors are real separate backends opened with `dblink` over
   the same throwaway socket; the psql session only orchestrates and waits on observable state
   (`pg_locks` lock waits, `dblink_is_busy`), never on a fixed sleep.

### Safety guard

`scripts/db/guard_env.sh` refuses to start if **any** environment variable value contains
the production ref or `supabase.co/.in/.com`, if `DATABASE_URL`, `SUPABASE_DB_URL`,
`SUPABASE_URL`, `POSTGRES_URL`, `DB_URL` or `PGHOST` points at anything other than
localhost / loopback / a unix-socket directory (including `?host=` overrides,
multi-host lists and `localhost.evil.com` / userinfo tricks), if `PGHOSTADDR` is not
loopback, or if `PGSERVICE`/`PGSERVICEFILE` is set. It prints the variable *name*, never
its value. `scripts/db/test_guard_env.sh` runs 29 accept/reject cases against the real
guard function and is executed first on every run. After the guard the runner pins
`PGHOST` to its own socket directory and verifies the target (`data_directory` is the
temp dir, no TCP, connection via socket). The dblink actors connect to that same socket.

### How access is judged

User-visible assertions run as `SET LOCAL ROLE authenticated` (or `anon`) with
`set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)`, the
PostgREST path; service-role steps run as `SET LOCAL ROLE service_role`. The superuser session
is used only to seed rows, to stand in for GoTrue's admin user deletion (labelled), and to read
back catalogs. `00_harness_and_preconditions.sql` proves the roles are non-superuser /
non-bypassrls, that `auth.uid()` follows the claims, and that the assertions are not vacuous.
`tests.uid(n)` contains hex **letters**, so upper/lower-case id checks are meaningful.

## Replay results (PostgreSQL 17.10; 245 migrations + 20 prepared files, 9 of them duplicates applied once; 2026-11-01; reproduce with the runner)

| Mode | Files applied | Files failed |
| --- | ---: | ---: |
| `strict` (empty DB, filename order) | 146 | 109 |
| `baseline-post` (baseline, then only later files) | 5 | 18 |
| `baseline-first` (fixture build) | 193 | 62 |

Every prepared file applies in `baseline-first` (the PREPARED verdict). In `baseline-post` the
club/import/barrier files fail with `relation ... does not exist` because that mode has no club
tables (they come only from the pre-baseline chain). They are deliberately **not** guarded with
`to_regclass`: a security fix that silently skips is worse than a loud failure. (The one
exception is `20261005170000`: a missing `user_lists` view cannot leak, so it only notices.)

Why the numbers are far above the "~12 files" in `supabase/migrations/README_baseline_capture.md`:
that figure is a **static scan of eager statements**; actual replay is dynamic. `language sql`
functions are validated at `CREATE`, `CREATE TABLE ... REFERENCES` needs the target, and a
failed file leaves its objects uncreated so dependents fail too.

`baseline-first` root causes of the 62 failures (3 + 2 + 1 direct, 56 cascade):

- **3 files**: `public.user_lists` (a view defined only in `legacy_sql/08_create_user_lists_view.sql`)
  is not created by any migration and not captured by the baseline: `20260203183000`,
  `20260203223000`, `20260205231000` (`curated_rails` then fails, and its dependents cascade).
- **2 files**: `20260203190000`, `20260203201000` insert `editorial_penalty_tags` /
  `editorial_tag_boosts` rows whose `tag_id` FK targets exist only in production *data*
  (baseline captures no data). This blocks the whole `editorial_*` -> taste/realm
  matview tree (`20260731060000` ... `20260807010000`).
- **1 file**: `20260203235500` calls unqualified `similarity()` under `search_path = public`;
  it fails here because the stub places pg_trgm in `extensions`. Fixture choice, not proven
  chain defect.
- **56 files**: cascades from the above.

Consequence for fidelity: policies and function bodies changed by a failing file are **not**
in the fixture (notably `20260206150000` security_invoker on views, `20260731060000` taste
tables, `20260806020000` the newer `delete_user_concierge_data`). Tests that depend on such
objects are `BLOCKED` through the requirement manifest, not faked.

## Coverage

| File | Covers |
| --- | --- |
| `00_harness_and_preconditions.sql` | role posture, claim path, negative controls, fixture preconditions |
| `10_user_lists.sql` | `anime_user_lists`, `manga_user_lists`: owner CRUD, other user denied, same numeric id in anime vs manga distinct, anon denied; **F16**: owner's UPPER-case id accepted and stored canonical, other user's id in any spelling denied, unique key across spellings; **F40**: the reconstructed legacy `user_lists` view leaks before and not after the actual prepared migration file is applied to it (owner access kept, anon reads 0 rows; grants unchanged on purpose) |
| `12_list_user_id_backfill.sql` | **F16** opt-in historical repair: default mode refuses on a collision and changes nothing; `keep_newest` leaves no non-canonical row and no duplicate, newest row wins, other users untouched |
| `20_clubs.sql` | club tables for owner / member / outsider / anon / revoked through the real RPCs; raw per-user rows own-only (F34), cross-member bundle counts (F36), removal through `remove_club_member` + block + restore + rejoin (F35), departed rows kept but excluded and private |
| `30_social_comments.sql` | `title_comments`, `title_comment_reactions` via `shares_club_with` (club-mate, stranger, anon, leaver, archived club) |
| `40_streaming_and_taste.sql` | `user_streaming_services`, taste tables owner isolation and grants; `taste_tag_stats` scope BLOCKED |
| `50_account_deletion_fk_and_rpc.sql` | FK delete rules to `auth.users`; `delete_user_concierge_data` authorization; the delete-account order emulated (barrier -> club lifecycle -> RPC -> both id spellings -> auth last): no TEXT row, comment or orphan club survives, the shared club keeps an owner (F37/F45); latest-RPC-body scope BLOCKED |
| `51_account_deletion_barrier.sql` | **F38** single session: service-role-only entry, every guarded write refused for the user (own JWT and service role, upper-case spelling, joins, club creation, legacy comments, concierge runs), deletes allowed, other users unaffected, barrier outlives the auth user, 7-day retention, posture |
| `60_club_role_guard.sql` | **R1** (pending `20261005120000`): no `club_members` role / identity writes via the table API; legit flows |
| `61_club_rail_insert_policy.sql` | **R2** (pending `20261005120100`): direct `club_rails` INSERT only for owner/admin |
| `62_comment_reaction_visibility.sql` | **R3** (pending `20261005120200`): `toggle_comment_reaction` respects `shares_club_with` |
| `63_club_privacy_levels_and_open_items.sql` | polls/votes/reactions through the RPCs; bundle per privacy level; R4 and R5 now asserted as implemented (own-row raw reads, DEFINER aggregates, departed vote excluded, voluntary leaver rejoins with a valid code) |
| `64_club_privacy_aggregates.sql` | **F34 + F36 together** at private / status / progress levels and in 2-member clubs: raw reads own-only; counts across members; opted-out (private) members never counted; progress only at effective progress level; no cross-member count below 3 members; no notes/ratings; departed votes/reactions excluded; DEFINER posture and grants |
| `65_club_membership_lifecycle.sql` | **F35** removal (RPC) vs leave, block / restore / rejoin, owner row protected, oldest-admin transfer; **F39** empty club never joinable; **F37** account-deletion club step through the same lifecycle; dashboard-style auth deletion settles clubs through the cascade |
| `66_club_realtime_signals.sql` | **F42** server side: activity revision bumps, membership revocation states (removed / left / club_deleted), per-subscriber RLS, no table-API writes, publication membership, payload without user ids; Realtime delivery BLOCKED |
| `70_import_apply_undo_transactions.sql` | Apply/Undo transactions (`20261005130000`; owned by lane L2a, see its header); since 2026-11-01 expectations follow the live guarded Undo of `20261008100000` (tracking identity journalled; lifecycle-less journals skipped as `legacy_lifecycle_unavailable`) |
| `91_bridge_identity_fix.sql` | legacy unit bridge natural key: delete-all + re-insert cycle (dated and undated), foreign-owned unit untouched, one-time re-key with the collision rule, stale withdrawals, idempotence, service-role-only repair |
| `92_auth_hardening.sql` | **D13** `check_email_exists`: anon / authenticated / PUBLIC denied, service_role answers |
| `93_contact_messages.sql` | contact form storage: RLS on with no policies, anon/authenticated denied SELECT/INSERT/UPDATE/DELETE (also for their own `user_id`) and the purge, CHECK constraints (enums, email, lengths), purge deletes only rows older than 12 months, one daily cron job, account deletion sets `user_id` NULL |
| `98_release_schedule_and_themes_v2.sql` | spec 3.1-3.3: grants (user RPC authenticated only, public reads anon+authenticated, writers service_role only, no table-API writes), tracked-status scope and per-user isolation, next unit per title, AniList fallback and delay precedence, estimate threshold 0.7 (0.70 shown, 0.69 hidden: real comparison), estimates never in `home_events_page_v1`, window/precision rules (confirmed needs an instant), per-source credit-link hosts (writer + CHECK, look-alike hosts rejected), ISO-only instants (`infinity`/`tomorrow`/`epoch` rejected), idempotent natural keys, all-or-nothing validation codes, constraint backstops, themes order/flags and convergence with `finish_series_enrichment_v1`, which can no longer delete `upsert_theme_links_v1`-owned rows |
| `99_perf_hotpaths.sql` | similar-titles gate posture and transactional dirty rows (real change only; ON CONFLICT no-ops excluded), the wrapper's skip/run decision with a stub core (skip when clean, run on change or stale seed, lock-busy `-1` keeps the dirty row), nightly rolling re-stale, cron command rewrites, unread matview dropped, CONCURRENTLY refresh, audit retention rule + batching, change-aware `updated_at` (anime/manga only), 22 duplicate indexes dropped with survivors intact, exactness guard |
| `concurrency/90_deletion_write_barrier.sql` | **F38** two sessions, both orders: an in-flight writer makes the barrier wait, then its row is cleaned and later writes are refused; a barrier first makes a concurrent write wait and fail |
| `concurrency/91_club_lifecycle_join_race.sql` | **F39** two sessions, both orders: lifecycle first -> the waiting join gets INVALID_CODE, no stray membership; join first -> the waiting lifecycle keeps the club and transfers ownership to the joiner |

Edge-function tests (no database): `supabase/functions/delete-account/*_test.ts`

```bash
deno test --no-prompt supabase/functions/delete-account/
deno check supabase/functions/delete-account/real_client_shapes.ts supabase/functions/delete-account/index.ts   # needs esm.sh
```

## Prerequisites checklist (read-only, approved target only)

`prerequisites/delete_account_prereqs.sql` lists, as one result table, what the hardened
deletion and the prepared migrations need on a deployed-equivalent database (F45): the guarded
tables and their `user_id` types, `service_role` DELETE grants and BYPASSRLS, FK delete rules,
the latest `delete_user_concierge_data` body, the `media` bucket, the `user_lists` view options,
the F41 grant/policy state, F16 casing counts and collisions, orphan / ownerless clubs, and
whether each prepared object is deployed. It runs in one `READ ONLY` transaction with timeouts
and ends with ROLLBACK, and it **refuses** (exit 3, nothing queried) unless called with
`-v approved_target=<current_database()>` and `-v approval_ref=<approval record>` and connected to
that database. It has been exercised against the local fixture only; it has NOT been run against
production.

## Findings (status after the prepared fixes; none is deployed)

1. **Club role self-escalation**: pending `20261005120000` (column-level UPDATE grant), test `60`.
2. **Raw per-user club rows readable by any member** (F34): prepared `20261005150000`
   (own-row SELECT + authorized DEFINER bundles); tests `20`, `63`, `64`.
3. **Bundle cross-member statuses empty under RLS** (F36): prepared `20261005150000`; tests `20`, `64`.
4. **Removal not sticky / departed activity counted** (F35): prepared `20261005150000`
   (`remove_club_member` + block + `restore_club_member`; exclusion in aggregates); tests `20`,
   `63`, `65`. The app's leave dialog copy ("You'll need a new invite code to rejoin") is not true
   for voluntary leave and must change in Swift (lane L1).
5. **`toggle_comment_reaction`** visibility: pending `20261005120200`, test `62`.
6. **Deletion leftovers** (F37/F38/F39): prepared `20261005140000` + `20261005150000` and the
   delete-account function (barrier first, shared club lifecycle, both id spellings); tests
   `50`, `51`, `65`, `concurrency/90`, `concurrency/91`.
7. **Policy vs RPC mismatch on `club_rails` INSERT**: pending `20261005120100`, test `61`.
8. **Legacy `public.user_lists` view** (F40): prepared `20261005170000`; whether the deployed view
   leaks is UNVERIFIED (see the checklist).
9. **UPPER-case `uuidString` vs lower-case RLS** (F16): prepared `20261005180000` (canonical-case
   trigger) + opt-in historical repair; the Swift adapter canonicalization is lane L1's.

## BLOCKED (not faked) and recovery

| Item | Why blocked | Recovery path |
| --- | --- | --- |
| Full migration replay / production schema equality (F43) | 62 files fail even baseline-first (user_lists view, tag-id data FKs, pg_trgm placement) | capture plain views + minimal seed data in a **new** baseline-style migration (needs approval), or the full local stack below loaded with an approved read-only schema snapshot |
| `taste_tag_stats` isolation; latest `delete_user_concierge_data` body | their files do not replay | same as above; the scopes stop being BLOCKED automatically once the objects exist (requirement manifest) |
| Production state of `public.user_lists`, grants, bucket, casing (F40/F45/F16) | read-only facts about the deployed database | `prerequisites/delete_account_prereqs.sql` on the approved target |
| Storage objects, GoTrue admin delete, live PostgREST error mapping, Realtime delivery (F44) | stub only; Docker is not available here, so no local Supabase stack | see the runbook below |

### F44 recovery runbook (full local stack; nothing here touches production)

1. Prerequisites (separate approval for local tooling): Docker Desktop (or colima) and the
   Supabase CLI; `supabase start` in the repo starts Postgres, GoTrue, PostgREST, Realtime and
   Storage on localhost.
2. Schema: an approved **read-only** schema snapshot of a deployed-equivalent database
   (for example `supabase db dump --schema public,storage --linked -f /tmp/schema.sql`, which
   reads production and therefore needs its own explicit approval; or an approved staging
   project), loaded into the local stack database
   (`psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f /tmp/schema.sql`), then the
   prepared files in order (`120000` ... `180000`).
3. Fixtures: create the `media` bucket and two or three users through the local GoTrue admin API
   with the local service key printed by `supabase status`.
4. Rerun and record separately from fixture results:
   - delete-account served locally (`supabase functions serve delete-account`): success path
     (Storage objects of the user gone, other user's kept, auth user gone last), a forced Storage
     failure (auth user kept, retry succeeds), and a write with the deleted user's still-valid
     access token after deletion (must be refused by the barrier: PostgREST maps 42501 to 403);
   - PostgREST HTTP mapping of `REMOVED_FROM_CLUB`, `NOT_ADMIN`, `ACCOUNT_DELETION_IN_PROGRESS`
     and the column-privilege denial of `20261005120000`;
   - Realtime: two clients subscribed to `club_activity_signals` (`club_id=eq.<club>`) and
     `club_membership_signals` (`user_id=eq.<me>`); run the removal / leave / club-delete steps of
     `66_club_realtime_signals.sql` and check that the removed member receives `state = removed`
     and stops receiving the club's activity events;
   - the SQL suites in this directory against that database (role/claim switching as here).
