#!/usr/bin/env bash
# Read-only evidence validation; this gate never creates accounts or makes live calls.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
exec python3 "$ROOT_DIR/fastlane/check_live_service_evidence.py"
