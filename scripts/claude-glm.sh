#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_GLM_MODEL="glm-5.2[1m]"
readonly DEFAULT_GLM_FAST_MODEL="glm-4.5-air"
readonly DEFAULT_GLM_BASE_URL="https://api.z.ai/api/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="glm-claude-code"
readonly DEFAULT_AUTO_COMPACT_WINDOW="1000000"

# Nesting hygiene: do not inherit parent Anthropic endpoint/model settings from
# other proxied, direct-backend, or native Claude sessions.
model="${GLM_MODEL:-$DEFAULT_GLM_MODEL}"
fast_model="${GLM_FAST_MODEL:-$DEFAULT_GLM_FAST_MODEL}"
base_url="${GLM_BASE_URL:-$DEFAULT_GLM_BASE_URL}"
keychain_service="${GLM_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"
auto_compact_window="${GLM_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"

resolve_token() {
  if [[ -n "${GLM_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${GLM_ANTHROPIC_AUTH_TOKEN}"
    return 0
  fi

  if command -v security >/dev/null 2>&1; then
    token_from_keychain="$(security find-generic-password -a "${USER}" -s "${keychain_service}" -w 2>/dev/null || true)"
    if [[ -n "${token_from_keychain}" ]]; then
      printf '%s' "${token_from_keychain}"
      return 0
    fi
  fi

  if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${ANTHROPIC_AUTH_TOKEN}"
    return 0
  fi

  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    printf '%s' "${ANTHROPIC_API_KEY}"
    return 0
  fi

  return 0
}

token="$(resolve_token)"

if [[ -z "${token}" ]]; then
  cat >&2 <<EOF
Missing GLM / Z.AI auth token.

Provide it with one of:
  export GLM_ANTHROPIC_AUTH_TOKEN='...'
  export ANTHROPIC_AUTH_TOKEN='...'
  export ANTHROPIC_API_KEY='...'

Or store it in the macOS Keychain:
  ${script_dir}/setup-glm-keychain.sh

Then run:
  ${script_dir}/claude-glm.sh
EOF
  exit 1
fi

exec env \
  ANTHROPIC_BASE_URL="${base_url}" \
  ANTHROPIC_MODEL="${model}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast_model" \
  ANTHROPIC_SMALL_FAST_MODEL="${fast_model}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  API_TIMEOUT_MS="${API_TIMEOUT_MS:-3000000}" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${auto_compact_window}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
