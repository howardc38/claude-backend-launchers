#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"

if [[ $# -lt 1 || $# -gt 2 || "${1:-}" == --help ]]; then
  printf 'Usage: %s mimo|deepseek|glm|claudex [auto|keychain|secret-service|pass]\n' "$0"
  exit 2
fi
if [[ $# == 2 ]]; then
  export CLAUDE_BACKEND_CREDENTIAL_STORE="$2"
fi
cb_backend "$1"
store="$CB_STORE"
if [[ "$store" == auto ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    store=keychain
  elif command -v secret-tool >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    store=secret-service
  elif command -v pass >/dev/null 2>&1; then
    store=pass
  else
    printf 'Install libsecret-tools with an unlocked desktop keyring, or initialize pass/GPG on a headless host.\n' >&2
    exit 1
  fi
fi
case "$store" in
  keychain) [[ "$(uname -s)" == Darwin ]] && command -v security >/dev/null || exit 1 ;;
  secret-service) command -v secret-tool >/dev/null || exit 1 ;;
  pass) command -v pass >/dev/null || exit 1 ;;
  *) printf 'Choose keychain, secret-service or pass for persistent storage.\n' >&2; exit 2 ;;
esac

# Read from stdin with terminal echo disabled; no key in shell history or files.
read -r -s -p "$CB_BACKEND credential: " token
printf '\n' >&2
if [[ -z "$token" || "$token" == *[$' \t\r\n']* ]]; then
  printf 'Credential must be non-empty and contain no whitespace.\n' >&2
  exit 2
fi
case "$store" in
  keychain) security add-generic-password -U -a "$CB_ACCOUNT" -s "$CB_SERVICE" -w "$token" ;;
  secret-service) printf '%s' "$token" | secret-tool store --label="Claude backend: $CB_BACKEND" service "$CB_SERVICE" account "$CB_ACCOUNT" ;;
  pass) printf '%s\n' "$token" | pass insert --multiline --force "$CB_PASS_ENTRY" >/dev/null ;;
esac
unset token
printf 'Stored %s credential in %s.\n' "$CB_BACKEND" "$store"
