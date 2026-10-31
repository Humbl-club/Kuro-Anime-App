#!/usr/bin/env bash
# test_guard_env.sh -- unit check for scripts/db/guard_env.sh.
# Runs the REAL guard function in clean subshell environments (env -i + only the
# variable under test) and asserts accept/reject.  No database, no network.
#
#   scripts/db/test_guard_env.sh        # exit 0 = all cases behave
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/guard_env.sh"

pass=0; fail=0

# run_case <expect: accept|reject> <label> VAR=value [VAR=value ...]
run_case() {
  local expect="$1" label="$2"; shift 2
  local out rc
  out="$(env -i PATH="$PATH" "$@" bash -c ". '$guard'; kuro_db_guard_env" 2>&1)"; rc=$?
  local got="accept"; [ "$rc" -ne 0 ] && got="reject"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf '  ok   %-7s %s\n' "$expect" "$label"
  else
    fail=$((fail+1)); printf '  FAIL expected %s, got %s: %s\n         output: %s\n' "$expect" "$got" "$label" "$out"
  fi
}

echo "guard_env unit check"
echo "--- must ACCEPT (local targets) ---"
run_case accept "empty environment"                       X=1
run_case accept "PGHOST=/tmp/kuro-sock (unix socket)"     PGHOST=/tmp/kuro-sock
run_case accept "PGHOST=localhost"                        PGHOST=localhost
run_case accept "PGHOST=127.0.0.1"                        PGHOST=127.0.0.1
run_case accept "PGHOSTADDR=::1"                          PGHOSTADDR=::1
run_case accept "DATABASE_URL localhost"                  DATABASE_URL=postgres://postgres@localhost:54329/kuro_test
run_case accept "DATABASE_URL 127.0.0.1"                  DATABASE_URL=postgresql://u:p@127.0.0.1:54322/postgres
run_case accept "DATABASE_URL socket (no host)"           DATABASE_URL=postgres:///kuro_test
run_case accept "DATABASE_URL ?host=/socket"              "DATABASE_URL=postgres:///kuro_test?host=/tmp/kuro-sock"
run_case accept "SUPABASE_URL local stack"                SUPABASE_URL=http://127.0.0.1:54321
run_case accept "SUPABASE_DB_URL IPv6 loopback"           "SUPABASE_DB_URL=postgres://postgres@[::1]:54322/postgres"
run_case accept "DSN host=localhost"                      "DATABASE_URL=host=localhost port=5432 dbname=x"
run_case accept "DSN with spaces around = (local)"        "DATABASE_URL=host = localhost dbname = x"
run_case accept "URL with harmless query params"          "DATABASE_URL=postgres://localhost/db?sslmode=disable&application_name=svc"
run_case accept "unnamed var holding a LOCAL postgres URL" FOO=postgres://postgres@127.0.0.1:54329/kuro_test

echo "--- must REJECT (production / remote / unverifiable) ---"
run_case reject "PGHOST = prod db host"                   PGHOST=db.bkdifromsqxkndnllmdj.supabase.co
run_case reject "DATABASE_URL = prod"                     DATABASE_URL=postgresql://postgres:x@db.bkdifromsqxkndnllmdj.supabase.co:5432/postgres
run_case reject "SUPABASE_URL = prod"                     SUPABASE_URL=https://bkdifromsqxkndnllmdj.supabase.co
run_case reject "SUPABASE_DB_URL = pooler"                SUPABASE_DB_URL=postgres://postgres.abc:x@aws-0-eu-central-1.pooler.supabase.com:6543/postgres
run_case reject "prod ref hidden in an unrelated var"     SOME_OTHER_VAR=https://bkdifromsqxkndnllmdj.example.org/rest
run_case reject "supabase.co in an unrelated var"         MY_API=https://abc.supabase.co/functions/v1/x
run_case reject "PGHOST = arbitrary remote"               PGHOST=db.example.com
run_case reject "PGHOST = private IP"                     PGHOST=10.0.0.5
run_case reject "PGHOSTADDR = public IP"                  PGHOSTADDR=8.8.8.8
run_case reject "PGSERVICE set"                           PGSERVICE=prod
run_case reject "PGSERVICEFILE set"                       PGSERVICEFILE=/etc/pg_service.conf
run_case reject "DATABASE_URL localhost-prefix bypass"    DATABASE_URL=postgres://u:p@localhost.evil.com/db
run_case reject "DATABASE_URL userinfo bypass"            DATABASE_URL=postgres://localhost@evil.com/db
run_case reject "DATABASE_URL ?host= override to remote"  "DATABASE_URL=postgres://localhost/db?host=evil.com"
run_case reject "DATABASE_URL multi-host with remote"     DATABASE_URL=postgres://localhost:5432,evil.com:5432/db
run_case reject "DSN host=remote"                         "DATABASE_URL=host=evil.com dbname=x"
run_case reject "SUPABASE_URL remote non-prod"            SUPABASE_URL=https://staging.example.com

echo "--- must REJECT: service= indirection (URL query, DSN, encoded keyword, servicefile) ---"
run_case reject "URL ?service=prod (socket host)"         "DATABASE_URL=postgres:///db?service=prod"
run_case reject "URL ?service= with localhost host"       "DATABASE_URL=postgres://localhost/db?service=prod"
run_case reject "URL ?servicefile="                       "DATABASE_URL=postgres://localhost/db?servicefile=/tmp/pg_service.conf"
run_case reject "URL percent-encoded keyword %73ervice="  "DATABASE_URL=postgres://localhost/db?%73ervice=prod"
run_case reject "URL upper-case SERVICE="                 "DATABASE_URL=postgres://localhost/db?SERVICE=prod"
run_case reject "URL service= after other params"         "SUPABASE_DB_URL=postgres://localhost/db?sslmode=disable&service=prod"
run_case reject "DSN service=prod"                        "DATABASE_URL=dbname=x service=prod"
run_case reject "DSN host=localhost service=prod"         "DATABASE_URL=host=localhost service=prod"
run_case reject "DSN service = prod (spaces around =)"    "DATABASE_URL=dbname = x service = prod"
run_case reject "unnamed var: postgres URL with service=" "FOO=postgres://localhost/db?service=prod"

echo "--- must REJECT: other bypasses of host detection ---"
run_case reject "URL percent-encoded ?%68ost=evil.com"    "DATABASE_URL=postgres://localhost/db?%68ost=evil.com"
run_case reject "DSN host = evil.com (spaces around =)"   "DATABASE_URL=host = evil.com dbname = x"
run_case reject "unnamed var: REMOTE postgres URL"        FOO=postgres://u:p@evil.com/db

echo "--- must REJECT: production markers are matched case-insensitively ---"
run_case reject "SUPABASE.CO upper-case host"             MY_API=https://abc.SUPABASE.CO
run_case reject "prod ref upper-case"                     X=https://BKDIFROMSQXKNDNLLMDJ.example.org
run_case reject "PGHOST mixed-case prod host"             PGHOST=DB.Bkdifromsqxkndnllmdj.Supabase.Co
run_case reject "SUPABASE_URL upper-case supabase.in"     SUPABASE_URL=HTTPS://ABC.SUPABASE.IN
run_case reject "mixed-case Supabase.Com pooler"          DATABASE_URL=postgres://u@aws-0.pooler.Supabase.Com:6543/postgres

echo
echo "guard_env unit check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
