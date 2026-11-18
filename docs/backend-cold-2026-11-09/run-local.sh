#!/bin/bash
# Synthetic native PostgreSQL test. No credentials, network listener or production calls.
set -euo pipefail
pg_bin=/opt/homebrew/opt/postgresql@17/bin
cold_dir=$(mktemp -d /tmp/kuro-cold-catalogue.XXXXXX)
trap '"$pg_bin/pg_ctl" -D "$cold_dir/data" -m fast -w stop >/dev/null 2>&1 || true' EXIT
"$pg_bin/initdb" -D "$cold_dir/data" -U postgres -E UTF8 --locale=C --auth-local=trust --auth-host=reject >"$cold_dir/initdb.log"
start_cluster() {
 "$pg_bin/pg_ctl" -D "$cold_dir/data" -l "$cold_dir/postgres.log" -o "-k $cold_dir -p 54329 -c listen_addresses='' -c jit=off -c shared_buffers=16MB -c max_connections=10 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap" -w start >/dev/null
}
psql_local() { "$pg_bin/psql" -X -h "$cold_dir" -p 54329 -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
start_cluster
psql_local -f docs/backend-cold-2026-11-09/cold-catalogue-fixture.sql
"$pg_bin/pg_ctl" -D "$cold_dir/data" -m fast -w stop >/dev/null
start_cluster
psql_local -f docs/backend-cold-2026-11-09/cold-local-state.sql -f docs/backend-cold-2026-11-09/cold-catalogue-cases.sql -f supabase/migrations/20261109123758_cold_catalogue_reads_v1.sql
"$pg_bin/pg_ctl" -D "$cold_dir/data" -m fast -w stop >/dev/null
start_cluster
psql_local -f docs/backend-cold-2026-11-09/cold-local-state.sql -f docs/backend-cold-2026-11-09/cold-catalogue-assertions.sql
