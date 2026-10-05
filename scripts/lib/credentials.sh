#!/usr/bin/env bash
# Shared credential precedence; diagnostic failures never print store stderr.
cb_credentials_lib_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$cb_credentials_lib_dir/backends.sh"

cb_backend() {
  cb_profile "$1" || return $?
  local service_var="${CB_PREFIX}_KEYCHAIN_SERVICE" entry_var="${CB_PREFIX}_PASS_ENTRY"
  CB_SERVICE="${!service_var:-$CB_SERVICE}"
  CB_PASS_ENTRY="${!entry_var:-claude-backends/$CB_BACKEND}"
  CB_ACCOUNT="${CLAUDE_BACKEND_CREDENTIAL_ACCOUNT:-$(id -un)}"
  CB_STORE="${CLAUDE_BACKEND_CREDENTIAL_STORE:-auto}"
  case "$CB_STORE" in
    auto|keychain|secret-service|pass|env) ;;
    *) printf 'Credential store must be auto|keychain|secret-service|pass|env\n' >&2; return 2 ;;
  esac
}

cb_read_store() {
  local store="$1" status
  local command=()
  CB_TOKEN=""
  case "$store" in
    keychain)
      [[ "$(uname -s)" == Darwin ]] && command -v security >/dev/null 2>&1 || return 1
      command=(security find-generic-password -a "$CB_ACCOUNT" -s "$CB_SERVICE" -w) ;;
    secret-service)
      command -v secret-tool >/dev/null 2>&1 || return 1
      command=(secret-tool lookup service "$CB_SERVICE" account "$CB_ACCOUNT") ;;
    pass)
      command -v pass >/dev/null 2>&1 || return 1
      command=(pass show "$CB_PASS_ENTRY") ;;
    *) return 1 ;;
  esac
  if CB_TOKEN="$("${command[@]}" 2>/dev/null)"; then
    [[ "$store" != pass ]] || CB_TOKEN="${CB_TOKEN%%$'\n'*}"
  else
    status=$?
    CB_TOKEN=""
    CB_STORE_FAILURES="${CB_STORE_FAILURES:+$CB_STORE_FAILURES; }$store (exit $status)"
    return 1
  fi
  [[ -n "$CB_TOKEN" ]] || return 1
  CB_SOURCE="$store"
}

cb_load_auth() {
  cb_backend "$1" || return $?
  CB_STORE_FAILURES=""
  CB_TOKEN="${!CB_ENV:-}"; CB_SOURCE="$CB_ENV"
  [[ -z "$CB_TOKEN" ]] || return 0
  if [[ "$CB_STORE" == auto ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
      cb_read_store keychain && return 0
    elif [[ "$(uname -s)" == Linux && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
      cb_read_store secret-service && return 0
    fi
    cb_read_store pass && return 0
  elif [[ "$CB_STORE" != env ]]; then
    cb_read_store "$CB_STORE" && return 0
  fi
  # Legacy standalone API environment support; never reuse it for claudex.
  if [[ "$CB_BACKEND" != claudex ]]; then
    for CB_SOURCE in ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY; do
      CB_TOKEN="${!CB_SOURCE:-}"
      [[ -z "$CB_TOKEN" ]] || return 0
    done
  fi
  CB_TOKEN=""; CB_SOURCE=none
  printf 'No credential could be loaded for %s. Run scripts/setup-credential.sh %s, or set %s.\n' "$CB_BACKEND" "$CB_BACKEND" "$CB_ENV" >&2
  if [[ -n "$CB_STORE_FAILURES" ]]; then
    printf 'Credential store lookup failed: %s. Check the entry, keyring unlock, or GPG decryption.\n' "$CB_STORE_FAILURES" >&2
  fi
  return 1
}
