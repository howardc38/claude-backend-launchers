#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_MIMO_MODEL="mimo-v2.6-pro[1m]"
readonly DEFAULT_MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="mimo-claude-code"
readonly DEFAULT_MIMO_EFFORT_LEVEL="max"
readonly DEFAULT_MAX_CONTEXT_TOKENS="1048576"
# Leave 256K tokens of headroom for MiMo's reasoning/output and Claude Code's
# tool results instead of waiting until the full 1M window is exhausted.
readonly DEFAULT_AUTO_COMPACT_WINDOW="786432"
readonly DEFAULT_API_TIMEOUT_MS="600000"
readonly DEFAULT_STREAM_FIRST_BYTE_TIMEOUT_MS="90000"
readonly DEFAULT_STREAM_IDLE_TIMEOUT_MS="90000"
readonly DEFAULT_MAX_RETRIES="3"
readonly DEFAULT_TOOL_CONCURRENCY="3"
readonly DEFAULT_DISABLE_NONSTREAMING_FALLBACK="0"

# Nesting 衛生：唔繼承 parent session 嘅 ANTHROPIC_BASE_URL / ANTHROPIC_MODEL /
# ANTHROPIC_SMALL_FAST_MODEL。否則由一個已 set 咗呢啲 env 嘅 proxied session
# 嵌套 call mimo-claude 時，child 會連錯 endpoint / 用錯 model。
# 想覆寫請用 MIMO_* 變數（MIMO_MODEL / MIMO_BASE_URL / MIMO_FAST_MODEL）。
model="${MIMO_MODEL:-$DEFAULT_MIMO_MODEL}"
base_url="${MIMO_BASE_URL:-$DEFAULT_MIMO_BASE_URL}"
small_fast_model="${MIMO_FAST_MODEL:-$model}"
keychain_service="${MIMO_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"
effort_level="${MIMO_EFFORT_LEVEL:-$DEFAULT_MIMO_EFFORT_LEVEL}"
max_context_tokens="${MIMO_MAX_CONTEXT_TOKENS:-$DEFAULT_MAX_CONTEXT_TOKENS}"
auto_compact_window="${MIMO_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"
api_timeout_ms="${MIMO_API_TIMEOUT_MS:-$DEFAULT_API_TIMEOUT_MS}"
stream_first_byte_timeout_ms="${MIMO_STREAM_FIRST_BYTE_TIMEOUT_MS:-$DEFAULT_STREAM_FIRST_BYTE_TIMEOUT_MS}"
stream_idle_timeout_ms="${MIMO_STREAM_IDLE_TIMEOUT_MS:-$DEFAULT_STREAM_IDLE_TIMEOUT_MS}"
max_retries="${MIMO_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
tool_concurrency="${MIMO_TOOL_CONCURRENCY:-$DEFAULT_TOOL_CONCURRENCY}"
disable_nonstreaming_fallback="${MIMO_DISABLE_NONSTREAMING_FALLBACK:-$DEFAULT_DISABLE_NONSTREAMING_FALLBACK}"
skip_permissions="${MIMO_SKIP_PERMISSIONS:-1}"

case "$effort_level" in
  low|medium|high|xhigh|max) ;;
  *)
    printf 'mimo-claude: MIMO_EFFORT_LEVEL must be low|medium|high|xhigh|max\n' >&2
    exit 2
    ;;
esac

case "$skip_permissions" in
  0|1) ;;
  *)
    printf 'mimo-claude: MIMO_SKIP_PERMISSIONS must be 0 or 1\n' >&2
    exit 2
    ;;
esac

case "$disable_nonstreaming_fallback" in
  0|1) ;;
  *)
    printf 'mimo-claude: MIMO_DISABLE_NONSTREAMING_FALLBACK must be 0 or 1\n' >&2
    exit 2
    ;;
esac

for value_name in \
  max_context_tokens auto_compact_window api_timeout_ms \
  stream_first_byte_timeout_ms stream_idle_timeout_ms max_retries tool_concurrency; do
  value="${!value_name}"
  case "$value" in
    ''|*[!0-9]*|0)
      printf 'mimo-claude: %s must be a positive integer\n' "$value_name" >&2
      exit 2
      ;;
  esac
done

user_set_effort=0
user_set_permissions=0
for arg in "$@"; do
  case "$arg" in
    --effort|--effort=*)
      user_set_effort=1
      ;;
    --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
      user_set_permissions=1
      ;;
  esac
done

if [[ "$user_set_effort" == "0" ]]; then
  set -- --effort "$effort_level" "$@"
fi

if [[ "$skip_permissions" == "1" && "$user_set_permissions" == "0" ]]; then
  set -- --dangerously-skip-permissions "$@"
fi

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
  CLAUDE_CODE_SUBAGENT_MODEL="${small_fast_model}" \
  CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 \
  CLAUDE_CODE_EFFORT_LEVEL="${effort_level}" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="${max_context_tokens}" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${auto_compact_window}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  API_TIMEOUT_MS="${api_timeout_ms}" \
  API_FORCE_IDLE_TIMEOUT=1 \
  CLAUDE_STREAM_FIRST_BYTE_TIMEOUT_MS="${stream_first_byte_timeout_ms}" \
  CLAUDE_STREAM_IDLE_TIMEOUT_MS="${stream_idle_timeout_ms}" \
  CLAUDE_CODE_MAX_RETRIES="${max_retries}" \
  CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY="${tool_concurrency}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${disable_nonstreaming_fallback}" \
  claude "$@"
