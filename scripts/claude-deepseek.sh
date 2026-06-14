#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# DeepSeek 官方 doc 明講：Anthropic 路徑唔好加 [1m]（佢當係 formatting artifact）。
# 主 model = deepseek-v4-pro（opus-equivalent）；fast = deepseek-v4-flash（sonnet/haiku-equivalent）。
readonly DEFAULT_DEEPSEEK_MODEL="deepseek-v4-pro"
readonly DEFAULT_DEEPSEEK_FAST_MODEL="deepseek-v4-flash"
readonly DEFAULT_DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="deepseek-claude-code"

# Nesting 衛生：唔繼承 parent session 嘅 ANTHROPIC_BASE_URL / ANTHROPIC_MODEL /
# ANTHROPIC_SMALL_FAST_MODEL（否則由 claude-cc 等已 set 咗 env 嘅 session 嵌套 call
# 時會連錯 endpoint）。想覆寫請用 DEEPSEEK_* 變數。
model="${DEEPSEEK_MODEL:-$DEFAULT_DEEPSEEK_MODEL}"
fast_model="${DEEPSEEK_FAST_MODEL:-$DEFAULT_DEEPSEEK_FAST_MODEL}"
base_url="${DEEPSEEK_BASE_URL:-$DEFAULT_DEEPSEEK_BASE_URL}"
keychain_service="${DEEPSEEK_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

resolve_token() {
  if [[ -n "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN}"
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
Missing DeepSeek auth token.

Provide it with one of:
  export DEEPSEEK_ANTHROPIC_AUTH_TOKEN='sk-...'
  export ANTHROPIC_AUTH_TOKEN='sk-...'
  export ANTHROPIC_API_KEY='sk-...'

Or store it in the macOS Keychain:
  ${script_dir}/setup-deepseek-keychain.sh

Then run:
  ${script_dir}/claude-deepseek.sh
EOF
  exit 1
fi

# DeepSeek 官方推薦：opus/sonnet -> pro，haiku/small-fast -> flash（慳 quota）。
# 認證：同時 set ANTHROPIC_AUTH_TOKEN（-> Authorization: Bearer）同 ANTHROPIC_API_KEY
# （-> x-api-key）；DeepSeek /anthropic endpoint 兩者皆收。
exec env \
  ANTHROPIC_BASE_URL="${base_url}" \
  ANTHROPIC_MODEL="${model}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast_model" \
  ANTHROPIC_SMALL_FAST_MODEL="${fast_model}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
