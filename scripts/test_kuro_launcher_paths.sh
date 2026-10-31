#!/usr/bin/env bash
# Offline check: the three Swift workers compile and report under the checkout
# kuro_resolve_project_root returns. A disposable KURO_PROJECT_ROOT and a stub
# compiler/runner record those paths. Does not invoke swiftc or start a worker.
#
#   bash scripts/test_kuro_launcher_paths.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0

ok() {
  pass=$((pass + 1))
  printf 'ok %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

checkout="$(mktemp -d)"
checkout="$(cd "$checkout" && pwd)"
trap 'rm -rf "$checkout"' EXIT

record="$checkout/record.tsv"
stub="$checkout/stub-swiftc"
cat >"$stub" <<'STUB'
#!/bin/bash
set -euo pipefail
record="${KURO_LAUNCHER_RECORD:?}"
{
  printf 'compile'
  for arg in "$@"; do
    printf '\t%s' "$arg"
  done
  printf '\n'
} >>"$record"

output=""
previous=""
for arg in "$@"; do
  if [[ "$previous" == "-o" ]]; then
    output="$arg"
  fi
  previous="$arg"
done
[[ -n "$output" ]]
cat >"$output" <<'RUNNER'
#!/bin/bash
set -euo pipefail
record="${KURO_LAUNCHER_RECORD:?}"
reported=0
for key in SYNOPSIS_REPORTS_DIR CATALOG_SAFETY_REPORTS_DIR PROVIDER_AVAILABILITY_REPORTS_DIR; do
  value="${!key:-}"
  if [[ -n "$value" ]]; then
    printf 'report\t%s\t%s\n' "$key" "$value" >>"$record"
    reported=1
  fi
done
[[ "$reported" -eq 1 ]]
RUNNER
chmod +x "$output"
STUB
chmod +x "$stub"

assert_launcher() {
  local name="$1"
  local script="$2"
  local report_key="$3"
  local report_folder="$4"
  local worker_name="$5"
  shift 5
  : >"$record"
  env \
    -u SYNOPSIS_REPORTS_DIR \
    -u CATALOG_SAFETY_REPORTS_DIR \
    -u PROVIDER_AVAILABILITY_REPORTS_DIR \
    KURO_PROJECT_ROOT="$checkout" \
    KURO_SWIFTC="$stub" \
    KURO_LAUNCHER_RECORD="$record" \
    /bin/bash "$script"

  local compile_line report_line source expected expected_report expected_bin
  compile_line="$(grep '^compile	' "$record")"
  report_line="$(grep '^report	' "$record")"
  expected_report="$checkout/reports/$report_folder"
  expected_bin="$expected_report/$worker_name"
  case "$compile_line" in
    *"	-o	${expected_bin}") ;;
    *) fail "$name compiler output is outside the checkout" ;;
  esac
  for source in "$@"; do
    expected="$checkout/scripts/$source"
    case "$compile_line" in
      *"	${expected}	"*|*"	${expected}") ;;
      *) fail "$name source $source is outside the checkout" ;;
    esac
  done
  [[ "$report_line" == "report	${report_key}	${expected_report}" ]] || fail "$name report path is outside the checkout"
  if grep -F -q '/Applications/Kuro' "$record"; then
    fail "$name recorded /Applications/Kuro"
  fi
  ok "$name sources and report stay under the checkout"
}

assert_launcher synopsis \
  "$SCRIPT_DIR/run_synopsis_enrichment.sh" \
  SYNOPSIS_REPORTS_DIR \
  synopsis-enrichment \
  synopsis_enrichment_worker \
  synopsis_quality.swift \
  synopsis_run.swift \
  synopsis_enrichment_worker.swift

assert_launcher catalog-safety \
  "$SCRIPT_DIR/run_catalog_safety.sh" \
  CATALOG_SAFETY_REPORTS_DIR \
  catalog-safety \
  catalog_safety_worker \
  catalog_safety_decision.swift \
  catalog_safety_run.swift \
  catalog_safety_worker.swift

assert_launcher provider-availability \
  "$SCRIPT_DIR/run_provider_availability.sh" \
  PROVIDER_AVAILABILITY_REPORTS_DIR \
  provider-availability \
  provider_availability_worker \
  provider_availability_matching.swift \
  provider_availability_run.swift \
  provider_availability_worker.swift

printf 'passed=%s\n' "$pass"
