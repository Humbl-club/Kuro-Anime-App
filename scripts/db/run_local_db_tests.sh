#!/usr/bin/env bash
# run_local_db_tests.sh -- disposable, credential-free local database verification.
#
#   scripts/db/run_local_db_tests.sh [--only <substring[,substring...]>] [--report-dir <dir>] [--no-tests]
#                                    [--exclude-pending] [--exclude-migration <basename>]...
#
#   --exclude-pending     build the fixture WITHOUT the prepared-not-deployed migrations
#                         listed in supabase/tests/pending_migrations.txt (= deployed-chain
#                         state; tests written for the fixed behavior then FAIL on purpose)
#   --exclude-migration   skip one migration file by basename (repeatable)
#
# What it does
#   1. refuses to run if ANY environment variable points at anything but a local
#      socket/localhost, or mentions the production project / supabase.co
#      (scripts/db/guard_env.sh, unit-checked first by scripts/db/test_guard_env.sh)
#   2. initdb's a THROWAWAY PostgreSQL 17 cluster in a mktemp dir, listening on a
#      unix socket ONLY (no TCP), and always stops + deletes it on exit
#   3. loads supabase/tests/fixtures/00_platform_stub.sql (STUB roles, auth, storage,
#      cron, net -- documented stubs, not Supabase)
#   4. replays supabase/migrations three ways and reports exactly which files apply:
#        strict          empty DB, filename order        (the honest "fresh rebuild")
#        baseline-post   baseline, then only later files (literal README reading)
#        baseline-first  baseline first, then the whole chain  (builds the FIXTURE)
#   5. setup-completeness check: every test file declares the fixture objects it
#      depends on in its header (see "Requirement manifest" below). A missing hard
#      requirement marks the FILE BLOCKED (not run, never PASS); a missing
#      `@requires-for` requirement marks that named SCOPE BLOCKED.
#   6. runs the RLS / authorization tests in supabase/tests/rls/*.sql against the
#      baseline-first database as roles authenticated/anon (never as superuser)
#   7. runs the two-session interleaving tests in supabase/tests/concurrency/*.sql,
#      each in its OWN fresh clone of the baseline-first database (they COMMIT);
#      actors are real separate backends opened with dblink over the same socket
#
# THIS IS AN AUDITED SCHEMA FIXTURE, NOT A COMPLETE MIGRATION REPLAY, and it is NOT
# Supabase Auth / Realtime / Storage / PostgREST / pg_cron / pg_net.
# Replay completeness and test results are reported SEPARATELY: a failed replay
# file is not a test failure, and passing tests do not make the replay complete.
#
# Requirement manifest (header lines of a test file; objects only, no quotes):
#   -- @requires <kind> <object>                      file BLOCKED when missing
#   -- @requires-for "<scope>" <kind> <object> [marker]  scope BLOCKED when missing
#   kinds: table | view | function (regprocedure signature) |
#          function-body <signature> <marker> (latest body contains <marker>) |
#          extension (available to CREATE EXTENSION)
#   Declare PREREQUISITES only. An object a prepared migration introduces is the
#   subject under test: its absence must FAIL the test, not block it.
#
# Exit: 0 local SQL assertions passed and no SQL prerequisite was BLOCKED;
#         genuine service requirements remain LIVE REQUIRED in a separate gate
#       1 a test failed, or a prepared migration did not apply to the fixture
#       2 refused by the environment guard
#       3 setup failed (no PostgreSQL 17 binaries, cluster did not start, ...)
#       4 every executed test passed but at least one test file or scope is
#         BLOCKED (missing fixture object or unavailable environment): NOT a pass
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
tests_dir="$repo/supabase/tests"

only=""; report_dir="${KURO_DB_REPORT_DIR:-}"; run_tests=1; exclude_pending=0; exclude=""; qualification_sql=""; qualification_report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only="${2:-}"; shift 2 ;;
    --report-dir) report_dir="${2:-}"; shift 2 ;;
    --no-tests) run_tests=0; shift ;;
    --qualification-sql) qualification_sql="${2:-}"; shift 2 ;;
    --qualification-report) qualification_report="${2:-}"; shift 2 ;;
    --exclude-pending) exclude_pending=1; shift ;;
    --exclude-migration) exclude="$exclude ${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,57p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

# Prepared-not-deployed migrations (sidecar list; the migration files themselves are never edited).
pending_file="$tests_dir/pending_migrations.txt"
pending=""
[ -f "$pending_file" ] && pending="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$pending_file" | grep -v '^$' | tr '\n' ' ')"
[ "$exclude_pending" -eq 1 ] && exclude="$exclude $pending"
for f in $exclude $pending; do
  [ -f "$repo/supabase/migrations/$f" ] || [ -f "$repo/supabase/prepared-migrations/$f" ] || { echo "run_local_db_tests: '$f' (excluded/pending) is not a file in supabase/migrations or supabase/prepared-migrations" >&2; exit 64; }
done
export KURO_REPLAY_EXCLUDE="$exclude"

# ---- 1. environment guard ---------------------------------------------------
# shellcheck source=guard_env.sh
. "$here/guard_env.sh"
if ! kuro_db_guard_env; then
  echo "run_local_db_tests: environment refused (see above). Nothing was started." >&2
  exit 2
fi
if ! "$here/test_guard_env.sh" >/dev/null 2>&1; then
  echo "run_local_db_tests: guard unit check FAILED; refusing to continue. Run scripts/db/test_guard_env.sh" >&2
  exit 2
fi
echo "guard: environment clean; guard unit check passed"
n_pending="$(printf '%s\n' $pending | grep -c .)"
if [ "$n_pending" -gt 0 ]; then
  if [ "$exclude_pending" -eq 1 ]; then
    echo "pending: fixture EXCLUDES the $n_pending prepared-not-deployed migration(s) listed in supabase/tests/pending_migrations.txt (deployed-chain state)"
  else
    echo "pending: fixture INCLUDES $n_pending prepared-NOT-DEPLOYED migration(s) (supabase/tests/pending_migrations.txt); use --exclude-pending for the deployed-chain state:"
  fi
  printf '           %s\n' $pending
fi
[ -n "${exclude// /}" ] && echo "excluded from every replay mode on request:$exclude"

# ---- locate PostgreSQL 17 ---------------------------------------------------
pg_bin=""
for cand in "${KURO_PG_BIN:-}" /opt/homebrew/opt/postgresql@17/bin /usr/local/opt/postgresql@17/bin /usr/lib/postgresql/17/bin; do
  [ -n "$cand" ] && [ -x "$cand/initdb" ] && [ -x "$cand/pg_ctl" ] && [ -x "$cand/psql" ] && { pg_bin="$cand"; break; }
done
if [ -z "$pg_bin" ]; then
  echo "run_local_db_tests: PostgreSQL 17 binaries not found (set KURO_PG_BIN). Nothing was started." >&2
  exit 3
fi
export PATH="$pg_bin:$PATH"
pg_major="$(psql --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
if [ "$pg_major" != "17" ] && [ "${KURO_ALLOW_PG_MAJOR:-}" != "1" ]; then
  echo "run_local_db_tests: expected PostgreSQL 17, found $pg_major (set KURO_ALLOW_PG_MAJOR=1 to override)" >&2
  exit 3
fi

port="${KURO_DB_PORT:-54329}"
[[ "$port" =~ ^[0-9]{4,5}$ ]] || { echo "KURO_DB_PORT must be a 4-5 digit port" >&2; exit 64; }

# ---- 2. throwaway cluster ---------------------------------------------------
tmp="$(mktemp -d /tmp/kuro-db-test.XXXXXX)" || exit 3
case "$tmp" in /tmp/kuro-db-test.*) ;; *) echo "unexpected temp dir $tmp" >&2; exit 3 ;; esac
started=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ "$started" -eq 1 ]; then
    pg_ctl -D "$tmp/data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  case "$tmp" in /tmp/kuro-db-test.*) rm -rf "$tmp" ;; esac
  echo "teardown: throwaway cluster stopped and $tmp removed"
  exit "$rc"
}
trap cleanup EXIT INT TERM HUP

# Scrub anything libpq could read, then pin the connection to OUR socket.
unset PGHOSTADDR PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGOPTIONS PGSSLMODE PGSYSCONFDIR \
      PGREQUIRESSL PGSSLROOTCERT PGSSLCERT PGSSLKEY PGCHANNELBINDING PGTARGETSESSIONATTRS \
      DATABASE_URL SUPABASE_DB_URL SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY
export PGHOST="$tmp" PGPORT="$port" PGUSER=postgres PGDATABASE=postgres PGCONNECT_TIMEOUT=5 PSQLRC=/dev/null
kuro_db_guard_env || exit 2   # re-check the pinned environment

start_cluster() {   # one initdb + start attempt; 0 on success
  rm -rf "$tmp/data"
  locale_arg="--locale=C.UTF-8"
  # Apply the fixture memory profile during bootstrap too. mmap dynamic memory
  # lives in OUR data directory; this does not remove PostgreSQL's mandatory
  # small SysV interlock or authorize touching another project's IPC resources.
  fixture_memory=(-c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=30)
  initdb -D "$tmp/data" -U postgres -E UTF8 "$locale_arg" --auth-local=trust --auth-host=reject "${fixture_memory[@]}" >"$tmp/initdb.log" 2>&1 \
    || { rm -rf "$tmp/data"; locale_arg="--locale=C"; initdb -D "$tmp/data" -U postgres -E UTF8 "$locale_arg" --auth-local=trust --auth-host=reject "${fixture_memory[@]}" >"$tmp/initdb.log" 2>&1; } \
    || return 1
  pg_ctl -D "$tmp/data" -l "$tmp/postgres.log" -w \
    -o "-c listen_addresses='' -c unix_socket_directories='$tmp' -c port=$port -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=30 -c log_min_messages=warning" \
    start >/dev/null 2>&1
}
# Bounded retry ONLY for System V shared-memory exhaustion (macOS kern.sysv.shmmni is 32
# segments host-wide and every running PostgreSQL holds one; other projects' clusters can
# use them all). Any other failure aborts immediately.
attempt=1; max_attempts="${KURO_DB_START_ATTEMPTS:-40}"
until start_cluster; do
  if grep -qs 'shmget' "$tmp/initdb.log" "$tmp/postgres.log" && [ "$attempt" -lt "$max_attempts" ]; then
    [ "$attempt" -eq 1 ] && echo "note: no free System V shared-memory segment (host-wide limit); retrying up to $max_attempts times, 3 s apart"
    attempt=$((attempt+1)); : > "$tmp/postgres.log"; sleep 3; continue
  fi
  echo "cluster setup failed (attempt $attempt):"; cat "$tmp/initdb.log" "$tmp/postgres.log" 2>/dev/null | tail -20; exit 3
done
started=1
[ "$attempt" -gt 1 ] && echo "note: cluster started on attempt $attempt"

# Target identity: this must be OUR throwaway cluster, on a socket, with no TCP.
dd="$(psql -X -Atc 'show data_directory')"
dd_real="$(cd "$dd" 2>/dev/null && pwd -P)"
mine_real="$(cd "$tmp/data" && pwd -P)"
listen="$(psql -X -Atc 'show listen_addresses')"
inet="$(psql -X -Atc 'select coalesce(inet_server_addr()::text, $$socket$$)')"
if [ "$dd_real" != "$mine_real" ] || [ -n "$listen" ] || [ "$inet" != "socket" ]; then
  echo "target identity check FAILED (data_directory=$dd_real listen='$listen' via=$inet); aborting" >&2
  exit 3
fi
echo "target: throwaway PostgreSQL $(psql -X -Atc 'show server_version') on unix socket $tmp (port label $port), TCP disabled, data_directory=$mine_real"
fixture_memory_summary="$(psql -X -Atc "select 'main='||current_setting('shared_memory_type')||', dynamic='||current_setting('dynamic_shared_memory_type')||', buffers='||current_setting('shared_buffers')||', connections='||current_setting('max_connections')")"
echo "fixture memory: $fixture_memory_summary"

reports="$tmp/reports"; mkdir -p "$reports"

new_db() {   # new_db <name> : empty database + platform stubs
  psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "create database $1" || return 1
  psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "$tests_dir/fixtures/00_platform_stub.sql" >/dev/null 2>"$reports/stub-$1.log" \
    || { echo "platform stub failed for $1:"; cat "$reports/stub-$1.log"; return 1; }
}

# ---- 3/4. replay ------------------------------------------------------------
echo
echo "================ migration replay (supabase/migrations, $(ls "$repo"/supabase/migrations/*.sql | wc -l | tr -d ' ') files) ================"
for mode in strict baseline-post baseline-first; do
  db="kuro_$(echo "$mode" | tr '-' '_')"
  new_db "$db" || exit 3
  PGDATABASE="$db" "$here/replay_migrations.sh" "$mode" "$reports/replay-$mode.tsv" || exit 3
done

echo
echo "---- baseline-post (baseline, then only later files): object counts in kuro_baseline_post ----"
PGDATABASE=kuro_baseline_post psql -X -At -F ' ' -c "
  select 'public tables:', count(*) from pg_tables where schemaname='public'
  union all select 'public matviews:', count(*) from pg_matviews where schemaname='public'
  union all select 'public policies:', count(*) from pg_policies where schemaname='public'
  union all select 'public constraints (all types):', count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname='public'"
grep -oE 'create policy "[^"]+" on public\.[a-z_]+' "$repo/supabase/migrations/20260807000000_baseline_capture_v1.sql" \
  | sed -E 's/create policy "([^"]+)" on public\.([a-z_]+)/\2|\1/' | sort -u > "$reports/baseline-policies-declared.txt"
PGDATABASE=kuro_baseline_post psql -X -At -c "select tablename||'|'||policyname from pg_policies where schemaname='public'" | sort -u > "$reports/baseline-policies-present.txt"
echo "baseline declares $(wc -l < "$reports/baseline-policies-declared.txt" | tr -d ' ') distinct policies; baseline-post has $(comm -12 "$reports/baseline-policies-declared.txt" "$reports/baseline-policies-present.txt" | wc -l | tr -d ' ') of them."
echo "not created in baseline-post (the baseline dependency-guards them on tables/functions that only the pre-baseline chain creates, e.g. club tables and is_club_member):"
comm -23 "$reports/baseline-policies-declared.txt" "$reports/baseline-policies-present.txt" | sed 's/^/    /'
echo "expected here: README_baseline_capture.md's 106 constraints / 26 policies are reached only once club_rail_items and is_club_member exist."
echo "In baseline-post they do not (pre-baseline chain files create them), so the baseline's own guards (to_regclass('public.club_rail_items'))"
echo "skip exactly 1 FK (club_rail_item_reactions_rail_item_id_fkey) and 2 policies (club_reactions_*): 105 constraints / 24 policies is the consistent result."
echo
echo "---- baseline-post per-file result ----"
cut -f1-2,4 "$reports/replay-baseline-post.tsv" | tr '\t' ' '
echo
echo "---- strict (empty DB, filename order): failures grouped by first error ----"
awk -F'\t' '$1=="FAIL"{print $4}' "$reports/replay-strict.tsv" | sed -E 's/"[^"]*"/"…"/g' | sort | uniq -c | sort -rn | head -25
echo
echo "---- baseline-first (FIXTURE build): failing files ----"
awk -F'\t' '$1=="FAIL"{printf "FAIL  %s\n        %s\n", $2, $4}' "$reports/replay-baseline-first.tsv"

if [ -n "$report_dir" ]; then
  mkdir -p "$report_dir" && cp "$reports"/replay-*.tsv "$report_dir"/ && echo "replay reports copied to $report_dir"
fi


# ---- replay completeness (reported on its own, never folded into test results) ----
replay_count() {   # replay_count <tsv> <PASS|FAIL> : counted like replay_migrations.sh (PRE-APPLY row excluded)
  awk -F'\t' -v s="$2" '$1==s && $3!="PRE-APPLY"' "$1" | wc -l | tr -d ' '
}
bf_pass="$(replay_count "$reports/replay-baseline-first.tsv" PASS)"; bf_fail="$(replay_count "$reports/replay-baseline-first.tsv" FAIL)"
st_pass="$(replay_count "$reports/replay-strict.tsv" PASS)";         st_fail="$(replay_count "$reports/replay-strict.tsv" FAIL)"
prepared_list="$( [ -d "$repo/supabase/prepared-migrations" ] && ( cd "$repo/supabase/prepared-migrations" && ls -1 ./*.sql 2>/dev/null | sed 's|^\./||' ) )"
prepared_failed=""
for f in $prepared_list; do
  st="$(awk -F'\t' -v f="$f" '$2==f && $3!="PRE-APPLY"{print $1}' "$reports/replay-baseline-first.tsv" | tail -1)"
  [ "$st" = "FAIL" ] && prepared_failed="$prepared_failed $f"
done

# ---- requirement manifest check (F43: missing objects => BLOCKED, never PASS) ----
# req_check <db> <file> prints one line per MISSING requirement:
#   HARD<TAB><kind object>            or   SOFT<TAB><scope><TAB><kind object>
req_check() {
  local db="$1" file="$2" sql="" i=0 line kind obj marker scope rest expr
  local -a kinds=() descs=() scopes=()
  while IFS= read -r line; do
    scope=""
    case "$line" in
      "-- @requires-for "*)
        rest="${line#-- @requires-for }"
        scope="$(printf '%s' "$rest" | sed -nE 's/^"([^"]+)".*/\1/p')"
        rest="$(printf '%s' "$rest" | sed -E 's/^"[^"]+"[[:space:]]*//')" ;;
      "-- @requires "*) rest="${line#-- @requires }" ;;
      *) continue ;;
    esac
    case "$rest" in *"'"*) echo "HARD	malformed requirement (quote) in $(basename "$file"): $line"; continue ;; esac
    kind="$(printf '%s' "$rest" | awk '{print $1}')"; obj="$(printf '%s' "$rest" | awk '{print $2}')"; marker="$(printf '%s' "$rest" | awk '{print $3}')"
    case "$kind" in
      table)         expr="exists (select 1 from pg_class where oid = to_regclass('$obj') and relkind in ('r','p'))" ;;
      view)          expr="exists (select 1 from pg_class where oid = to_regclass('$obj') and relkind = 'v')" ;;
      function)      expr="to_regprocedure('$obj') is not null" ;;
      function-body) expr="coalesce((select position('$marker' in prosrc) > 0 from pg_proc where oid = to_regprocedure('$obj')), false)" ;;
      extension)     expr="exists (select 1 from pg_available_extensions where name = '$obj')" ;;
      *) echo "HARD	unknown requirement kind '$kind' in $(basename "$file")"; continue ;;
    esac
    kinds[$i]="$kind"; descs[$i]="$kind $obj${marker:+ ~ $marker}"; scopes[$i]="$scope"
    sql="$sql${sql:+ union all }select $i where not ($expr)"
    i=$((i+1))
  done < "$file"
  [ -n "$sql" ] || return 0
  local missing
  missing="$(PGDATABASE="$db" psql -X -At -v ON_ERROR_STOP=1 -c "$sql" 2>&1)" || { echo "HARD	requirement query failed: $missing"; return 0; }
  for i in $missing; do
    if [ -n "${scopes[$i]}" ]; then printf 'SOFT\t%s\t%s\n' "${scopes[$i]}" "${descs[$i]}"; else printf 'HARD\t%s\n' "${descs[$i]}"; fi
  done
}

# ---- 6/7. tests ---------------------------------------------------------------
fail=0
n_files=0; n_ok=0; n_blocked=0; n_find=0; n_files_blocked=0; n_scopes_blocked=0; n_live_required=0
: > "$reports/blocked-scopes.txt"
run_one() {   # run_one <file> <db> <label> [extra psql args...]
  local f="$1" db="$2" label="$3"; shift 3
  local name log rc ok bl fi_ live_ hard soft
  name="$(basename "$f")"; log="$reports/$label-$name.log"
  n_files=$((n_files+1))
  req="$(req_check kuro_baseline_first "$f")"
  hard="$(printf '%s\n' "$req" | awk -F'\t' '$1=="HARD"{print $2}')"
  soft="$(printf '%s\n' "$req" | awk -F'\t' '$1=="SOFT"{print $2" (missing "$3")"}')"
  if [ -n "$hard" ]; then
    n_files_blocked=$((n_files_blocked+1))
    printf 'BLOCKED %-40s not run: missing fixture prerequisite(s)\n' "$name"
    printf '%s\n' "$hard" | sed 's/^/        missing: /'
    printf '%s\n' "$hard" | sed "s|^|$name: whole file -- missing |" >> "$reports/blocked-scopes.txt"
    return 0
  fi
  ( cd "$repo" && PGDATABASE="$db" psql -X -q -v ON_ERROR_STOP=1 "$@" -f "$f" >/dev/null 2>"$log" ); rc=$?
  ok=$(grep -c 'TEST ok:' "$log"); bl=$(grep -c 'TEST BLOCKED:' "$log"); fi_=$(grep -c 'TEST FINDING:' "$log")
  live_=$(grep -c 'TEST LIVE REQUIRED:' "$log")
  n_live_required=$((n_live_required+live_))
  n_ok=$((n_ok+ok)); n_blocked=$((n_blocked+bl)); n_find=$((n_find+fi_))
  cat "$log" >> "$reports/all-notices.log"
  if [ -n "$soft" ]; then
    printf '%s\n' "$soft" | sed "s|^|$name: |" >> "$reports/blocked-scopes.txt"
    n_scopes_blocked=$((n_scopes_blocked + $(printf '%s\n' "$soft" | grep -c .)))
  fi
  if [ "$rc" -eq 0 ]; then
    printf 'PASS  %-40s %3d assertions, %d blocked markers, %d findings%s\n' "$name" "$ok" "$bl" "$fi_" \
      "$([ -n "$soft" ] && printf ', %d scope(s) BLOCKED' "$(printf '%s\n' "$soft" | grep -c .)")"
  else
    fail=1
    printf 'FAIL  %-40s after %d assertions\n' "$name" "$ok"
    grep -E 'ERROR|TEST FAIL|HARNESS|FIXTURE PRECONDITION|DETAIL|CONTEXT' "$log" | sed 's/^/        /' | head -12
  fi
}

selected_test() {
  [ -z "$only" ] && return 0
  local pattern
  local patterns
  IFS=',' read -r -a patterns <<< "$only"
  for pattern in "${patterns[@]}"; do
    [ -n "$pattern" ] && [[ "$1" == *"$pattern"* ]] && return 0
  done
  return 1
}

if [ "$run_tests" -eq 1 ]; then
  echo
  echo "================ RLS / authorization tests on kuro_baseline_first ================"
  echo "FIXTURE: audited schema fixture (stubs + baseline-first application). NOT a complete migration replay."
  echo "         NOT Supabase Auth / Realtime / Storage / PostgREST / pg_cron / pg_net."
  export PGDATABASE=kuro_baseline_first
  psql -X -q -v ON_ERROR_STOP=1 -f "$tests_dir/lib/00_test_helpers.sql" >/dev/null 2>"$reports/helpers.log" \
    || { echo "test helpers failed to load:"; cat "$reports/helpers.log"; exit 3; }
  : > "$reports/all-notices.log"
  for f in "$tests_dir"/rls/*.sql; do
    selected_test "$(basename "$f")" || continue
    run_one "$f" kuro_baseline_first rls
  done

  conc_files=()
  for f in "$tests_dir"/concurrency/*.sql; do
    [ -f "$f" ] || continue
    selected_test "$(basename "$f")" || continue
    conc_files+=("$f")
  done
  if [ "${#conc_files[@]}" -gt 0 ]; then
    echo
    echo "================ two-session interleaving tests (one fresh fixture clone per file) ================"
    echo "ACTORS: separate PostgreSQL backends via dblink on this throwaway socket; orchestrator waits on pg_locks state."
    k=0
    for f in "${conc_files[@]}"; do
      k=$((k+1)); cdb="kuro_conc_$k"
      psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "create database $cdb template kuro_baseline_first" >"$reports/conc-$k.log" 2>&1 \
        || { echo "concurrency clone failed:"; cat "$reports/conc-$k.log"; exit 3; }
      PGDATABASE="$cdb" psql -X -q -v ON_ERROR_STOP=1 -f "$tests_dir/lib/10_concurrency_helpers.sql" >/dev/null 2>>"$reports/conc-$k.log" \
        || { echo "concurrency helpers failed to load:"; cat "$reports/conc-$k.log"; exit 3; }
      run_one "$f" "$cdb" conc -v conn="host=$tmp port=$port dbname=$cdb user=postgres"
    done
  fi

  echo
  echo "---- findings (observed behavior; NOT fixed here) ----"
  grep -h 'TEST FINDING:' "$reports/all-notices.log" | sed -E 's/^.*TEST FINDING: /  * /' | awk '!seen[$0]++'
  echo
  echo "---- BLOCKED (not faked; reason + recovery) ----"
  grep -h 'TEST BLOCKED:' "$reports/all-notices.log" | sed -E 's/^.*TEST BLOCKED: /  - /' | awk '!seen[$0]++'
  sed 's/^/  - setup completeness: /' "$reports/blocked-scopes.txt"
  echo
  echo "---- LIVE REQUIRED (separate evidence layer; not proven by this fixture) ----"
  grep -h 'TEST LIVE REQUIRED:' "$reports/all-notices.log" | sed -E 's/^.*TEST LIVE REQUIRED: /  - /' | awk '!seen[$0]++'
  if [ -n "$report_dir" ]; then cp "$reports"/*.log "$reports/blocked-scopes.txt" "$report_dir"/ 2>/dev/null || true; fi
fi

# ---- summary: replay, setup completeness and tests are separate verdicts ------
# Qualification uses this exact audited fixture and its RLS/indexes. Socket guard applies.
if [ -n "$qualification_sql" ]; then
  if [ ! -f "$qualification_sql" ] || [ -z "$qualification_report" ]; then
    echo "Qualification requires a SQL file and report path"; exit 64
  fi
  PGDATABASE=kuro_baseline_first psql -X -q -v ON_ERROR_STOP=1 -f "$qualification_sql" >"$qualification_report" 2>&1 || fail=1
  echo "Qualification report: $qualification_report"
fi

total_blocked=$((n_blocked + n_scopes_blocked + n_files_blocked))
echo
echo "================ SUMMARY (three separate verdicts) ================"
printf 'REPLAY      : INCOMPLETE -- baseline-first applied %s, failed %s; strict applied %s, failed %s (the fixture is an audited schema, not a replay)\n' \
  "$bf_pass" "$bf_fail" "$st_pass" "$st_fail"
if [ -n "${prepared_failed// /}" ]; then
  fail=1
  echo "PREPARED    : FAIL -- prepared migration(s) did not apply to the fixture build, so tests cannot exercise them:$prepared_failed"
else
  echo "PREPARED    : every non-excluded supabase/prepared-migrations/*.sql applied to the fixture build"
fi
if [ "$run_tests" -eq 1 ]; then
  printf 'SETUP       : %d test file(s) BLOCKED (not run), %d scope(s) BLOCKED by missing fixture objects, %d in-file BLOCKED marker(s)\n' \
    "$n_files_blocked" "$n_scopes_blocked" "$n_blocked"
  printf 'TESTS       : %d test files, %d assertions passed, %d finding markers -> %s\n' \
    "$n_files" "$n_ok" "$n_find" "$([ "$fail" -eq 0 ] && echo 'PASS (executed tests only)' || echo FAIL)"
  printf 'LIVE        : %d requirement(s), NOT PROVEN; mandatory separate live-services release gate\n' "$n_live_required"
  echo "PROVEN: RLS/RPC/transaction behavior on the tables listed in supabase/tests/README.md, for the schema this fixture contains."
  echo "NOT PROVEN: full migration replay; production schema equality; Supabase Auth/Realtime/Storage/PostgREST behavior; edge functions; any file listed as FAIL above; every BLOCKED item."
fi
if [ "$run_tests" -eq 1 ] && { [ "$n_files" -eq 0 ] || [ "$n_ok" -eq 0 ]; }; then
  echo "RESULT      : FAIL -- no SQL assertions executed"
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "RESULT      : FAIL"
  exit 1
fi
if [ "$run_tests" -eq 1 ] && [ "$total_blocked" -gt 0 ]; then
  echo "RESULT      : BLOCKED -- executed tests passed, $total_blocked item(s) BLOCKED; NOT a complete verification (exit 4)"
  exit 4
fi
echo "RESULT      : PASS (local SQL only; no live-service acceptance)"
exit 0
