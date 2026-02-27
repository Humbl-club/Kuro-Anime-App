#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOCAL_CICD_LOG_DIR:-$ROOT_DIR/reports/local-cicd}"
mkdir -p "$LOG_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/ci-$TS.log"
STATUS_FILE="$LOG_DIR/latest-ci-status.json"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
status="success"
exit_code=0

{
  echo "[local-ci-runner] started_at=$started_at"
  echo "[local-ci-runner] log_file=$LOG_FILE"
  "$ROOT_DIR/scripts/local_ci.sh"
} > >(tee "$LOG_FILE") 2>&1 || {
  exit_code=$?
  status="failed"
}

ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat >"$STATUS_FILE" <<JSON
{
  "status": "$status",
  "exit_code": $exit_code,
  "started_at": "$started_at",
  "ended_at": "$ended_at",
  "log_file": "$LOG_FILE"
}
JSON

echo "[local-ci-runner] status=$status exit_code=$exit_code"
exit "$exit_code"
