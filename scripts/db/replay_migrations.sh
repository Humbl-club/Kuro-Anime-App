#!/usr/bin/env bash
# replay_migrations.sh -- replay supabase/migrations/*.sql into a THROWAWAY local
# database and record, per file, PASS or FAIL (+ first error line).
#
#   replay_migrations.sh <mode> <report.tsv>
#
# Modes (all use one transaction per file, like `supabase db push`; a failing
# file is rolled back entirely and replay CONTINUES so the full picture is shown):
#   strict          empty database, files in filename order.  This is the honest
#                   "fresh rebuild from the repo" result.
#   baseline-first  apply 20260807000000_baseline_capture_v1.sql first (so the
#                   tables earlier files eagerly reference exist), then every file
#                   in filename order (the baseline is applied again at its own slot,
#                   which is its documented idempotent re-apply).  This builds the
#                   AUDITED SCHEMA FIXTURE the RLS tests run on.  It is NOT a
#                   complete migration replay.
#   baseline-post   ONLY the baseline, then only the migrations after it, in order
#                   (literal "baseline then what follows" reading of
#                   supabase/migrations/README_baseline_capture.md).
#
# Exclusions: KURO_REPLAY_EXCLUDE may hold whitespace-separated migration basenames
# (set by run_local_db_tests.sh --exclude-pending / --exclude-migration).  Each is
# recorded as a SKIP row (tag EXCLUDED) instead of being applied, in every mode.
#
# Never edits a migration.  Connection comes from PGHOST/PGPORT/PGUSER/PGDATABASE
# which the caller (run_local_db_tests.sh) sets to the throwaway cluster; this
# script re-runs the environment guard and additionally refuses a non-socket,
# non-loopback PGHOST.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=guard_env.sh
. "$here/guard_env.sh"
kuro_db_guard_env || exit 2

mode="${1:-}"; report="${2:-}"
[ -n "$mode" ] && [ -n "$report" ] || { echo "usage: $0 <strict|baseline-first|baseline-post> <report.tsv>" >&2; exit 64; }
kuro_db_host_is_local "${PGHOST:-}" || { echo "replay: PGHOST must be a local socket dir/loopback" >&2; exit 2; }
[ -n "${PGHOST:-}" ] || { echo "replay: PGHOST must be set to the throwaway socket dir" >&2; exit 2; }

mig="$repo/supabase/migrations"
prepared="$repo/supabase/prepared-migrations"   # PREPARED-NOT-DEPLOYED: never inside supabase/migrations (CD would push them)
baseline="20260807000000_baseline_capture_v1.sql"
[ -f "$mig/$baseline" ] || { echo "replay: baseline file missing" >&2; exit 2; }

: > "$report"
n_pass=0; n_fail=0

excluded=" ${KURO_REPLAY_EXCLUDE:-} "
excluded="$(printf '%s' "$excluded" | tr '\n\t' '  ')"

apply_one() {   # apply_one <file> <tag>
  local f="$1" tag="$2" out rc err
  if [[ "$excluded" == *" $f "* ]]; then
    printf 'SKIP\t%s\tEXCLUDED\t\n' "$f" >> "$report"; return 0
  fi
  local path="$mig/$f"; [ -f "$path" ] || path="$prepared/$f"
  out="$(psql -X -q -1 -v ON_ERROR_STOP=1 -f "$path" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'PASS\t%s\t%s\t\n' "$f" "$tag" >> "$report"; n_pass=$((n_pass+1))
  else
    err="$(printf '%s\n' "$out" | grep -m1 -E 'ERROR|FATAL' | sed -E 's/^psql:[^:]*:[0-9]+: //' | cut -c1-220)"
    [ -n "$err" ] || err="$(printf '%s\n' "$out" | head -1 | cut -c1-220)"
    printf 'FAIL\t%s\t%s\t%s\n' "$f" "$tag" "$err" >> "$report"; n_fail=$((n_fail+1))
  fi
}

all_files() { ( { ( cd "$mig" && ls -1 ./*.sql ); [ -d "$prepared" ] && ( cd "$prepared" && ls -1 ./*.sql 2>/dev/null ); } | sed 's|^\./||' | LC_ALL=C sort ); }

case "$mode" in
  strict)
    while IFS= read -r f; do apply_one "$f" ORDER; done < <(all_files) ;;
  baseline-first)
    apply_one "$baseline" PRE-APPLY
    while IFS= read -r f; do apply_one "$f" ORDER; done < <(all_files) ;;
  baseline-post)
    apply_one "$baseline" BASELINE
    while IFS= read -r f; do
      [[ "$f" > "$baseline" ]] && apply_one "$f" POST
    done < <(all_files) ;;
  *) echo "replay: unknown mode '$mode'" >&2; exit 64 ;;
esac

# Summary counts exclude the baseline PRE-APPLY row (it is applied a second time at its own slot).
f_pass="$(awk -F'\t' '$1=="PASS" && $3!="PRE-APPLY"' "$report" | wc -l | tr -d ' ')"
f_fail="$(awk -F'\t' '$1=="FAIL" && $3!="PRE-APPLY"' "$report" | wc -l | tr -d ' ')"
f_skip="$(awk -F'\t' '$1=="SKIP"' "$report" | wc -l | tr -d ' ')"
pre="$(awk -F'\t' '$3=="PRE-APPLY"{print $1}' "$report")"
printf 'replay[%s]: %d files applied, %d files failed%s%s (details: %s)\n' "$mode" "$f_pass" "$f_fail" \
  "$([ "$f_skip" -gt 0 ] && printf ', %d excluded on request' "$f_skip")" "${pre:+; baseline PRE-APPLY: $pre}" "$report"
exit 0
