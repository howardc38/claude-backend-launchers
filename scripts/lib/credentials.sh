#!/usr/bin/env bash
# Shared by launchers, setup, diagnostics and API smoke tests (Bash 3.2+).
# CB_TOKEN is private to the caller; never print it from diagnostics.

cb_backend() {
  CB_BACKEND="$1"
  case "$1" in
    mimo) CB_PREFIX=MIMO; CB_ENV=MIMO_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=mimo-claude-code ;;
    deepseek) CB_PREFIX=DEEPSEEK; CB_ENV=DEEPSEEK_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=deepseek-claude-code ;;
    glm) CB_PREFIX=GLM; CB_ENV=GLM_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=glm-claude-code ;;
    claudex) CB_PREFIX=CLAUDEX; CB_ENV=CLAUDEX_PROXY_KEY; CB_SERVICE=cliproxyapi-claudex ;;
    *) printf 'Unknown backend: %s\n' "$1" >&2; return 2 ;;
  esac
  local service_var="${CB_PREFIX}_KEYCHAIN_SERVICE"
  local entry_var="${CB_PREFIX}_PASS_ENTRY"
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
  local store="$1"
  CB_TOKEN=""
  case "$store" in
    keychain)
      [[ "$(uname -s)" == Darwin ]] && command -v security >/dev/null 2>&1 || return 1
      CB_TOKEN="$(security find-generic-password -a "$CB_ACCOUNT" -s "$CB_SERVICE" -w 2>/dev/null)" || return 1
      ;;
    secret-service)
      command -v secret-tool >/dev/null 2>&1 || return 1
      CB_TOKEN="$(secret-tool lookup service "$CB_SERVICE" account "$CB_ACCOUNT" 2>/dev/null)" || return 1
      ;;
    pass)
      command -v pass >/dev/null 2>&1 || return 1
      CB_TOKEN="$(pass show "$CB_PASS_ENTRY" 2>/dev/null)" || return 1
      # pass permits notes below the password; only the first line is the key.
      CB_TOKEN="${CB_TOKEN%%$'\n'*}"
      ;;
    *) return 1 ;;
  esac
  [[ -n "$CB_TOKEN" ]] || return 1
  CB_SOURCE="$store"
}

cb_load_auth() {
  cb_backend "$1" || return $?
  CB_TOKEN="${!CB_ENV:-}"
  CB_SOURCE="$CB_ENV"
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
  # Legacy standalone API env support. Never use Anthropic auth for claudex.
  if [[ "$CB_BACKEND" != claudex ]]; then
    for CB_SOURCE in ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY; do
      CB_TOKEN="${!CB_SOURCE:-}"
      [[ -z "$CB_TOKEN" ]] || return 0
    done
  fi
  CB_TOKEN=""; CB_SOURCE=none
  printf 'No credential for %s. Run scripts/setup-credential.sh %s, or set %s.\n' "$CB_BACKEND" "$CB_BACKEND" "$CB_ENV" >&2
  return 1
}
