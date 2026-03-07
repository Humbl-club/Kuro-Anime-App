#!/usr/bin/env bash

load_project_public_env() {
  local helper_dir env_file line key value
  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  env_file="$helper_dir/../project_public.env"

  [[ -f "$env_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    case "$key" in
      SUPABASE_URL|SUPABASE_ANON_KEY)
        if [[ -z "${!key:-}" ]]; then
          export "$key=$value"
        fi
        ;;
    esac
  done < "$env_file"
}
