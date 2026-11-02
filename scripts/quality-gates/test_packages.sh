#!/usr/bin/env bash
# Quality gate: build and test the local Swift package Packages/KuroModules
# (KuroCore, KuroLibrary, KuroSupabase) on the macOS host. No network, no simulator.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGE_PATH="$REPO_ROOT/Packages/KuroModules"

if ! command -v swift >/dev/null 2>&1; then
  echo "[packages] FAIL: swift toolchain not found"
  exit 1
fi

echo "[packages] swift test --package-path Packages/KuroModules"
if swift test --package-path "$PACKAGE_PATH"; then
  echo "[packages] PASS"
  exit 0
fi

echo "[packages] FAIL"
exit 1
