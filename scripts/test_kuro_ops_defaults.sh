#!/usr/bin/env bash
# Offline checks: project-root resolution in this checkout, and local_cd.sh
# defaulting DEPLOY_SUPABASE to 0. Sources default logic only. No network,
# no deploy, no secret values printed.
#
#   bash scripts/test_kuro_ops_defaults.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/kuro_project_root.sh"
LOCAL_CD="$SCRIPT_DIR/local_cd.sh"
RUNNER="$SCRIPT_DIR/run_media_relations_refresh.sh"
pass=0

ok() {
  pass=$((pass + 1))
  printf 'ok %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

git_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
script_relative="$(cd "$SCRIPT_DIR/.." && pwd)"

unset KURO_PROJECT_ROOT
got="$(/bin/bash "$RESOLVER")"
[[ "$got" == "$git_root" ]] || fail "project root in this checkout"
ok "project root in this checkout"

override_dir="$(mktemp -d)"
override_expected="$(cd "$override_dir" && pwd)"
got="$(KURO_PROJECT_ROOT="$override_dir" /bin/bash "$RESOLVER")"
[[ "$got" == "$override_expected" ]] || fail "KURO_PROJECT_ROOT override"
ok "KURO_PROJECT_ROOT override"

fake_bin="$(mktemp -d)"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$fake_bin/git"
chmod +x "$fake_bin/git"
got="$(env -u KURO_PROJECT_ROOT PATH="$fake_bin:/usr/bin:/bin" /bin/bash "$RESOLVER")"
if [[ -d "/Applications/Kuro" ]]; then
  [[ "$got" == "/Applications/Kuro" ]] || fail "legacy root when git is unavailable"
  ok "legacy /Applications/Kuro when git is unavailable"
else
  [[ "$got" == "$script_relative" ]] || fail "repo-relative root when git and legacy path are unavailable"
  ok "repo-relative root when git and legacy path are unavailable"
fi
got="$(env KURO_PROJECT_ROOT="$override_dir" PATH="$fake_bin:/usr/bin:/bin" /bin/bash "$RESOLVER")"
[[ "$got" == "$override_expected" ]] || fail "override wins when git is unavailable"
ok "KURO_PROJECT_ROOT wins when git is unavailable"

if ! command -v node >/dev/null 2>&1; then
  fail "node is required to check the dashboard resolver call"
fi
node_got="$(node -e 'const {execFileSync}=require("child_process"); process.stdout.write(execFileSync("/bin/bash",[process.argv[1]],{encoding:"utf8"}).trim());' "$RESOLVER")"
[[ "$node_got" == "$git_root" ]] || fail "node exec of project root"
ok "node exec of project root"

# Load the actual dashboard sources with an inert HTTP listener. No port is opened,
# no launchctl command is executed, and only the disposable report root is used.
node - "$SCRIPT_DIR" "$override_expected" <<'NODE' || fail "dashboard report roots"
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const [scripts, root] = process.argv.slice(2);
for (const [file, envKey, directory] of [
  ['synopsis_dashboard_server.js', 'SYNOPSIS_REPORTS_DIR', 'synopsis-enrichment'],
  ['catalog_safety_dashboard_server.js', 'CATALOG_SAFETY_REPORTS_DIR', 'catalog-safety'],
  ['provider_availability_dashboard_server.js', 'PROVIDER_AVAILABILITY_REPORTS_DIR', 'provider-availability'],
]) {
  for (const explicitReport of [null, path.join(root, 'custom-reports')]) {
    let resolverCalls = 0;
    const context = {
      __dirname: scripts,
      process: { env: explicitReport ? { [envKey]: explicitReport } : {} },
      console: { log() {} },
      require(name) {
        if (name === 'http') return { createServer: () => ({ listen() {} }) };
        if (name === 'child_process') return {
          execSync() { throw new Error('operational commands are forbidden in this check'); },
          execFileSync(command, args, options) {
            resolverCalls++;
            assert.equal(command, '/bin/bash');
            assert.deepEqual(Array.from(args), [path.join(scripts, 'kuro_project_root.sh')]);
            return execFileSync(command, Array.from(args), {
              ...options, env: { PATH: process.env.PATH, KURO_PROJECT_ROOT: root },
            });
          },
        };
        return require(name);
      },
    };
    vm.runInNewContext(fs.readFileSync(path.join(scripts, file), 'utf8') + '\nglobalThis.reportRoot = REPORT_DIR;', context);
    assert.equal(context.reportRoot, explicitReport || path.join(root, 'reports', directory));
    assert.equal(resolverCalls, explicitReport ? 0 : 1);
  }
}
NODE
ok "three dashboard report roots and explicit overrides"

(
  unset DEPLOY_SUPABASE
  export KURO_LOCAL_CD_SOURCE_DEFAULTS_ONLY=1
  # shellcheck source=local_cd.sh
  source "$LOCAL_CD"
  [[ "${DEPLOY_SUPABASE}" == "0" ]]
) || fail "DEPLOY_SUPABASE default"
ok "DEPLOY_SUPABASE defaults to 0"

(
  export DEPLOY_SUPABASE=1
  export KURO_LOCAL_CD_SOURCE_DEFAULTS_ONLY=1
  # shellcheck source=local_cd.sh
  source "$LOCAL_CD"
  [[ "${DEPLOY_SUPABASE}" == "1" ]]
) || fail "DEPLOY_SUPABASE=1 preserved"
ok "DEPLOY_SUPABASE=1 preserved"

tmp="$(mktemp -d)"
own_env="$tmp/media-relations.env"
fallback_plist="$tmp/other.plist"
cat >"$own_env" <<'EOF'
SUPABASE_URL=https://own.example
SUPABASE_SERVICE_ROLE_KEY=kuro-ops-test-role-own
EOF
cat >"$fallback_plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key>
    <string>https://fallback.example</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key>
    <string>kuro-ops-test-role-fallback</string>
  </dict>
</dict>
</plist>
EOF

(
  export SUPABASE_URL="https://env.example"
  export SUPABASE_SERVICE_ROLE_KEY="kuro-ops-test-role-env"
  export KURO_MEDIA_RELATIONS_SOURCE_ONLY=1
  export MEDIA_RELATIONS_CONFIG="$own_env"
  export MEDIA_RELATIONS_FALLBACK_PLISTS="$fallback_plist"
  # shellcheck source=run_media_relations_refresh.sh
  source "$RUNNER"
  kuro_media_relations_resolve_settings
  [[ "${SUPABASE_URL}" == "https://env.example" ]]
  [[ "${SUPABASE_SERVICE_ROLE_KEY}" == "kuro-ops-test-role-env" ]]
) >/dev/null || fail "environment pair should win"
ok "environment pair before media-relations config"

(
  unset SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY
  export KURO_MEDIA_RELATIONS_SOURCE_ONLY=1
  export MEDIA_RELATIONS_CONFIG="$own_env"
  export MEDIA_RELATIONS_FALLBACK_PLISTS="$fallback_plist"
  # shellcheck source=run_media_relations_refresh.sh
  source "$RUNNER"
  kuro_media_relations_resolve_settings
  [[ "${SUPABASE_URL}" == "https://own.example" ]]
  [[ "${SUPABASE_SERVICE_ROLE_KEY}" == "kuro-ops-test-role-own" ]]
) >/dev/null || fail "complete owned pair should win"
ok "complete owned pair wins"

partial_env="$tmp/url-only.env"
printf '%s\n' 'SUPABASE_URL=https://own.example' >"$partial_env"
key_only_env="$tmp/key-only.env"
printf '%s\n' 'SUPABASE_SERVICE_ROLE_KEY=kuro-ops-test-role-own-key' >"$key_only_env"
reject_incomplete() {
  local label="$1"
  local missing_name="$2"
  shift 2
  local err_file="$tmp/incomplete-${label}.err"
  local out_file="$tmp/incomplete-${label}.out"
  if "$@" >"$out_file" 2>"$err_file"; then
    fail "incomplete owned pair (${label}) should exit non-zero"
  fi
  grep -q "$missing_name" "$err_file" || fail "incomplete owned pair (${label}) should name ${missing_name}"
  if grep -F -q -e 'kuro-ops-test-role' -e 'https://' "$err_file" "$out_file"; then
    fail "incomplete owned pair (${label}) printed a setting value"
  fi
}
reject_incomplete url-only SUPABASE_SERVICE_ROLE_KEY \
  env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY \
  KURO_MEDIA_RELATIONS_SOURCE_ONLY=1 \
  MEDIA_RELATIONS_CONFIG="$partial_env" \
  MEDIA_RELATIONS_FALLBACK_PLISTS="$fallback_plist" \
  /bin/bash -c 'source "$1" && kuro_media_relations_resolve_settings' _ "$RUNNER"
reject_incomplete key-only SUPABASE_URL \
  env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY \
  KURO_MEDIA_RELATIONS_SOURCE_ONLY=1 \
  MEDIA_RELATIONS_CONFIG="$key_only_env" \
  MEDIA_RELATIONS_FALLBACK_PLISTS="$fallback_plist" \
  /bin/bash -c 'source "$1" && kuro_media_relations_resolve_settings' _ "$RUNNER"
reject_incomplete env-url-only SUPABASE_SERVICE_ROLE_KEY \
  env -u SUPABASE_SERVICE_ROLE_KEY \
  SUPABASE_URL="https://env.example" \
  KURO_MEDIA_RELATIONS_SOURCE_ONLY=1 \
  MEDIA_RELATIONS_CONFIG="$own_env" \
  MEDIA_RELATIONS_FALLBACK_PLISTS="$fallback_plist" \
  /bin/bash -c 'source "$1" && kuro_media_relations_resolve_settings' _ "$RUNNER"
ok "incomplete owned pair fails"

partial_plist="$tmp/url-only.plist"
key_only_plist="$tmp/key-only.plist"
bridge_plist="$tmp/bridge.plist"
write_plist() {
  local path="$1"
  local url="${2:-}"
  local key="${3:-}"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0">' \
      '<dict>' \
      '  <key>EnvironmentVariables</key>' \
      '  <dict>'
    if [[ -n "$url" ]]; then
      printf '%s\n' '    <key>SUPABASE_URL</key>' "    <string>${url}</string>"
    fi
    if [[ -n "$key" ]]; then
      printf '%s\n' '    <key>SUPABASE_SERVICE_ROLE_KEY</key>' "    <string>${key}</string>"
    fi
    printf '%s\n' '  </dict>' '</dict>' '</plist>'
  } >"$path"
}
write_plist "$partial_plist" "https://partial.example" ""
write_plist "$key_only_plist" "" "kuro-ops-test-role-other"
write_plist "$bridge_plist" "https://bridge.example" "kuro-ops-test-role-bridge"
(
  unset SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY
  export KURO_MEDIA_RELATIONS_SOURCE_ONLY=1
  export MEDIA_RELATIONS_CONFIG="$tmp/does-not-exist"
  export MEDIA_RELATIONS_FALLBACK_PLISTS="${partial_plist}:${bridge_plist}"
  # shellcheck source=run_media_relations_refresh.sh
  source "$RUNNER"
  kuro_media_relations_resolve_settings
  [[ "${SUPABASE_URL}" == "https://bridge.example" ]]
  [[ "${SUPABASE_SERVICE_ROLE_KEY}" == "kuro-ops-test-role-bridge" ]]
) >/dev/null || fail "complete bridge plist should win over a partial one"
bridge_err="$tmp/bridge-partial.err"
bridge_out="$tmp/bridge-partial.out"
if (
  unset SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY
  export KURO_MEDIA_RELATIONS_SOURCE_ONLY=1
  export MEDIA_RELATIONS_CONFIG="$tmp/does-not-exist"
  export MEDIA_RELATIONS_FALLBACK_PLISTS="${partial_plist}:${key_only_plist}"
  # shellcheck source=run_media_relations_refresh.sh
  source "$RUNNER"
  kuro_media_relations_resolve_settings
  [[ -z "${SUPABASE_URL:-}" ]]
  [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]
  kuro_media_relations_require_settings
) >"$bridge_out" 2>"$bridge_err"; then
  fail "partial bridge plists should not form a pair"
fi
grep -q 'SUPABASE_URL' "$bridge_err" || fail "partial bridges should name SUPABASE_URL"
grep -q 'SUPABASE_SERVICE_ROLE_KEY' "$bridge_err" || fail "partial bridges should name SUPABASE_SERVICE_ROLE_KEY"
if grep -F -q -e 'kuro-ops-test-role' -e 'https://' "$bridge_err" "$bridge_out"; then
  fail "partial bridge output included a setting value"
fi
ok "bridge plist is used only when it contains both"

err_file="$tmp/missing.err"
if (
  unset SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY
  export KURO_MEDIA_RELATIONS_SOURCE_ONLY=1
  export MEDIA_RELATIONS_CONFIG="$tmp/does-not-exist"
  export MEDIA_RELATIONS_FALLBACK_PLISTS=""
  # shellcheck source=run_media_relations_refresh.sh
  source "$RUNNER"
  kuro_media_relations_resolve_settings
  kuro_media_relations_require_settings
) >"$tmp/missing.out" 2>"$err_file"; then
  fail "missing settings should exit non-zero"
fi
grep -q 'SUPABASE_URL' "$err_file" || fail "missing message should name SUPABASE_URL"
grep -q 'SUPABASE_SERVICE_ROLE_KEY' "$err_file" || fail "missing message should name SUPABASE_SERVICE_ROLE_KEY"
if grep -q 'kuro-ops-test-role' "$err_file" "$tmp/missing.out"; then
  fail "missing-settings output included a credential placeholder"
fi
ok "missing settings exit non-zero without secret values"

rm -rf "$override_dir" "$fake_bin" "$tmp"
printf 'passed=%s\n' "$pass"
