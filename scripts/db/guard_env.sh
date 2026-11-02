#!/usr/bin/env bash
# guard_env.sh -- refuse to run database tooling against anything but a local,
# throwaway Postgres.  Source this file and call `kuro_db_guard_env`.
#
# Rejects (returns non-zero and prints WHICH variable, never its value):
#   * any environment variable VALUE containing the production project ref
#     (bkdifromsqxkndnllmdj) or a supabase.co / supabase.in / supabase.com host
#     (matched CASE-INSENSITIVELY)
#   * DATABASE_URL / SUPABASE_DB_URL / SUPABASE_URL / POSTGRES_URL / DB_URL, and ANY
#     variable whose value is a postgres:// or postgresql:// URL, whose host is not
#     localhost / 127.0.0.1 / ::1 / a unix-socket path (including a `?host=` /
#     `hostaddr=` override, percent-encoded keywords, and key=value DSNs with spaces
#     around `=`)
#   * the same connection strings carrying a `service=` / `servicefile=` parameter
#     (libpq service indirection can redirect to any server)
#   * PGHOST not localhost / loopback / absolute socket directory
#   * PGHOSTADDR not loopback
#   * PGSERVICE / PGSERVICEFILE (cannot be verified; could redirect anywhere)
#
# No credentials are read, logged or required.  Pure bash + sed.

# ---- helpers ---------------------------------------------------------------

# Lower-case a string (bash 3.2 has no ${var,,}).
kuro_db_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Percent-decode a string (libpq decodes URI keywords AND values).
kuro_db_pct_decode() {
  local s="${1//\\/\\\\}"
  printf '%b' "${s//%/\\x}"
}

# 0 if $1 is a host we accept as local.
kuro_db_host_is_local() {
  local h="$1"
  h="${h#[}"; h="${h%]}"             # strip IPv6 brackets
  case "$h" in
    ""|localhost|127.0.0.1|::1) return 0 ;;
    /*) return 0 ;;                  # unix-socket directory
  esac
  return 1
}

# Prints the host(s) (one per line) a connection string or DSN points at.
# An empty host (e.g. postgres:///db) is printed as an empty line (= local socket).
kuro_db_hosts_of() {
  local s="$1" rest authority hostport query p
  if [[ "$s" == *"://"* ]]; then
    rest="${s#*://}"
    query=""
    if [[ "$rest" == *\?* ]]; then query="${rest#*\?}"; rest="${rest%%\?*}"; fi
    authority="${rest%%/*}"
    authority="${authority##*@}"     # drop userinfo (everything up to the LAST @)
    local IFS=','
    for hostport in $authority; do
      if [[ "$hostport" == \[* ]]; then
        p="${hostport%%]*}]"          # [::1]:5432 -> [::1]
      else
        p="${hostport%%:*}"           # host:port  -> host
      fi
      printf '%s\n' "$p"
    done
    # libpq URIs allow host=/hostaddr= in the query string; they override.
    local kv lk
    query="$(kuro_db_pct_decode "$query")"
    IFS='&'
    for kv in $query; do
      lk="$(kuro_db_lower "$kv")"
      case "$lk" in
        host=*|hostaddr=*) printf '%s\n' "${kv#*=}" ;;
      esac
    done
  else
    # key=value DSN ("host=foo port=5432 dbname=x"; libpq allows spaces around '=');
    # no host key = local socket.
    local tok lk found=0
    s="$(printf '%s' "$s" | sed -E 's/[[:space:]]*=[[:space:]]*/=/g')"
    for tok in $s; do
      lk="$(kuro_db_lower "$tok")"
      case "$lk" in
        host=*|hostaddr=*) printf '%s\n' "${tok#*=}"; found=1 ;;
      esac
    done
    [ "$found" -eq 1 ] || printf '\n'
  fi
}

# 0 if every host in connection string $1 is local.
kuro_db_url_is_local() {
  local h
  while IFS= read -r h; do
    kuro_db_host_is_local "$h" || return 1
  done < <(kuro_db_hosts_of "$1")
  return 0
}

# 0 if connection string $1 (URL or key=value DSN) carries libpq service indirection.
kuro_db_conn_has_service() {
  local l query kv tok
  l="$(kuro_db_lower "$1")"
  if [[ "$l" == *"://"* ]]; then
    query=""
    l="${l#*://}"
    if [[ "$l" == *\?* ]]; then query="${l#*\?}"; fi
    query="$(kuro_db_pct_decode "$query")"
    local IFS='&'
    for kv in $query; do
      case "$kv" in service=*|servicefile=*) return 0 ;; esac
    done
    return 1
  fi
  l="$(printf '%s' "$l" | sed -E 's/[[:space:]]*=[[:space:]]*/=/g')"
  for tok in $l; do
    case "$tok" in service=*|servicefile=*) return 0 ;; esac
  done
  return 1
}

# 0 if $1 mentions production / hosted Supabase (case-insensitive).
kuro_db_value_is_prod() {
  local v
  v="$(kuro_db_lower "$1")"
  case "$v" in
    *bkdifromsqxkndnllmdj*|*supabase.co*|*supabase.in*|*supabase.com*) return 0 ;;
  esac
  return 1
}

# ---- the guard -------------------------------------------------------------

# Returns 0 if the CURRENT environment is safe; otherwise prints reasons to
# stderr and returns 2.  Reads the live environment (`env`), so a unit test can
# drive it with `env VAR=... bash -c '. guard_env.sh; kuro_db_guard_env'`.
kuro_db_guard_env() {
  local bad=0 line name value lv
  while IFS= read -r line; do
    name="${line%%=*}"
    value="${line#*=}"
    if ! [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      # continuation line of a multi-line value: still scan it for production markers
      if kuro_db_value_is_prod "$line"; then
        echo "guard_env: REFUSING: a multi-line environment value references production / hosted Supabase" >&2
        bad=1
      fi
      continue
    fi

    if kuro_db_value_is_prod "$value"; then
      echo "guard_env: REFUSING: \$$name references production / hosted Supabase" >&2
      bad=1
      continue
    fi

    # Any variable holding a postgres:// URL is judged like a connection variable,
    # whatever its name.
    lv="$(kuro_db_lower "$value")"
    case "$lv" in
      postgres://*|postgresql://*)
        if ! kuro_db_url_is_local "$value"; then
          echo "guard_env: REFUSING: \$$name holds a postgres URL that does not point at localhost / a unix socket" >&2
          bad=1
        fi
        if kuro_db_conn_has_service "$value"; then
          echo "guard_env: REFUSING: \$$name holds a postgres URL with service= indirection" >&2
          bad=1
        fi ;;
    esac

    case "$name" in
      DATABASE_URL|SUPABASE_DB_URL|SUPABASE_URL|POSTGRES_URL|POSTGRES_URL_NON_POOLING|DB_URL|POSTGRESQL_URL)
        if [ -n "$value" ] && ! kuro_db_url_is_local "$value"; then
          echo "guard_env: REFUSING: \$$name does not point at localhost / a unix socket" >&2
          bad=1
        fi
        if [ -n "$value" ] && kuro_db_conn_has_service "$value"; then
          echo "guard_env: REFUSING: \$$name carries service= indirection" >&2
          bad=1
        fi ;;
      PGHOST)
        if [ -n "$value" ] && ! kuro_db_host_is_local "$value"; then
          echo "guard_env: REFUSING: \$PGHOST is not localhost / a unix-socket directory" >&2
          bad=1
        fi ;;
      PGHOSTADDR)
        if [ -n "$value" ] && [ "$value" != "127.0.0.1" ] && [ "$value" != "::1" ]; then
          echo "guard_env: REFUSING: \$PGHOSTADDR is not a loopback address" >&2
          bad=1
        fi ;;
      PGSERVICE|PGSERVICEFILE)
        if [ -n "$value" ]; then
          echo "guard_env: REFUSING: \$$name is set (service files can redirect to any server)" >&2
          bad=1
        fi ;;
    esac
  done < <(env)

  [ "$bad" -eq 0 ] || return 2
  return 0
}
