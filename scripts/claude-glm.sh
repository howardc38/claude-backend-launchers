#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_GLM_MODEL="glm-5.2[1m]"
readonly DEFAULT_GLM_FAST_MODEL="glm-4.5-air"
readonly DEFAULT_GLM_BASE_URL="https://api.z.ai/api/anthropic"
readonly DEFAULT_AUTO_COMPACT_WINDOW="1000000"

# Nesting hygiene: do not inherit parent Anthropic endpoint/model settings from
# other proxied, direct-backend, or native Claude sessions.
model="${GLM_MODEL:-$DEFAULT_GLM_MODEL}"
fast_model="${GLM_FAST_MODEL:-$DEFAULT_GLM_FAST_MODEL}"
base_url="${GLM_BASE_URL:-$DEFAULT_GLM_BASE_URL}"
auto_compact_window="${GLM_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"

source "$script_dir/lib/credentials.sh"
cb_load_auth glm
token="$CB_TOKEN"
unset CB_TOKEN

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
