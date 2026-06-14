#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_MIMO_MODEL="mimo-v2.5-pro[1m]"
readonly DEFAULT_MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="mimo-claude-code"

# Nesting 衛生：唔繼承 parent session 嘅 ANTHROPIC_BASE_URL / ANTHROPIC_MODEL /
# ANTHROPIC_SMALL_FAST_MODEL。否則由一個已 set 咗呢啲 env 嘅 session（例如 claude-cc
# 指住 proxy）嵌套 call mimo-claude 時，child 會連錯 endpoint / 用錯 model。
# 想覆寫請用 MIMO_* 變數（MIMO_MODEL / MIMO_BASE_URL / MIMO_FAST_MODEL）。
model="${MIMO_MODEL:-$DEFAULT_MIMO_MODEL}"
base_url="${MIMO_BASE_URL:-$DEFAULT_MIMO_BASE_URL}"
small_fast_model="${MIMO_FAST_MODEL:-$model}"
keychain_service="${MIMO_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

resolve_token() {
  if [[ -n "${MIMO_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${MIMO_ANTHROPIC_AUTH_TOKEN}"
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
Missing Mimo auth token.

Provide it with one of:
  export MIMO_ANTHROPIC_AUTH_TOKEN='...'
  export ANTHROPIC_AUTH_TOKEN='...'
  export ANTHROPIC_API_KEY='...'

Or store it in the macOS Keychain:
  ${script_dir}/setup-mimo-keychain.sh

Then run:
  ${script_dir}/claude-mimo.sh
EOF
  exit 1
fi

exec env \
  ANTHROPIC_BASE_URL="${base_url}" \
  ANTHROPIC_MODEL="${model}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" \
  ANTHROPIC_SMALL_FAST_MODEL="${small_fast_model}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
