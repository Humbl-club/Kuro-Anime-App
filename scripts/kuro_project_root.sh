#!/usr/bin/env bash
# Checkout root for run_media_relations_refresh.sh, unified_local_dashboard_server.js,
# and local_cd.sh. Source this file for kuro_resolve_project_root, or execute it to print the root.
# 1. KURO_PROJECT_ROOT, when set
# 2. else `git rev-parse --show-toplevel` when git can see this script's repo
# 3. else /Applications/Kuro, only when that directory exists
#    (reached only when KURO_PROJECT_ROOT is unset and git root is unavailable)
# 4. else this script's repo-relative default (parent of scripts/)

_KURO_RESOLVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kuro_resolve_project_root() {
  if [[ -n "${KURO_PROJECT_ROOT:-}" ]]; then
    if [[ -d "${KURO_PROJECT_ROOT}" ]]; then
      (cd "${KURO_PROJECT_ROOT}" && pwd) || printf '%s\n' "${KURO_PROJECT_ROOT}"
    else
      printf '%s\n' "${KURO_PROJECT_ROOT}"
    fi
    return 0
  fi

  local git_root=""
  if command -v git >/dev/null 2>&1; then
    git_root="$(git -C "${_KURO_RESOLVER_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -n "${git_root}" ]]; then
    printf '%s\n' "${git_root}"
    return 0
  fi

  if [[ -d "/Applications/Kuro" ]]; then
    printf '%s\n' "/Applications/Kuro"
    return 0
  fi

  (cd "${_KURO_RESOLVER_DIR}/.." && pwd)
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  kuro_resolve_project_root
fi
