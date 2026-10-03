#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_GLM_MODEL="glm-5.3[1m]"
readonly DEFAULT_GLM_FAST_MODEL="glm-5.3-flash[1m]"
readonly DEFAULT_GLM_BASE_URL="https://api.z.ai/api/anthropic"
readonly DEFAULT_AUTO_COMPACT_WINDOW="1000000"
readonly DEFAULT_GLM_EFFORT_LEVEL="max"

# Nesting hygiene: do not inherit parent Anthropic endpoint/model settings from
# other proxied, direct-backend, or native Claude sessions.
model="${GLM_MODEL:-$DEFAULT_GLM_MODEL}"
fast_model="${GLM_FAST_MODEL:-$DEFAULT_GLM_FAST_MODEL}"
base_url="${GLM_BASE_URL:-$DEFAULT_GLM_BASE_URL}"
auto_compact_window="${GLM_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"
effort_level="${GLM_EFFORT_LEVEL:-$DEFAULT_GLM_EFFORT_LEVEL}"

case "$effort_level" in
  low|medium|high|xhigh|max) ;;
  *) printf 'glm-claude: GLM_EFFORT_LEVEL must be low|medium|high|xhigh|max\n' >&2; exit 2 ;;
esac

user_set_effort=0
for arg in "$@"; do
  case "$arg" in
    --effort|--effort=*) user_set_effort=1 ;;
  esac
done
if [[ "$user_set_effort" == 0 ]]; then
  set -- --effort "$effort_level" "$@"
fi

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
  CLAUDE_CODE_SUBAGENT_MODEL="${GLM_SUBAGENT_MODEL:-$model}" \
  CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 \
  CLAUDE_CODE_EFFORT_LEVEL="${effort_level}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  API_TIMEOUT_MS="${GLM_API_TIMEOUT_MS:-3000000}" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="${GLM_MAX_CONTEXT_TOKENS:-1000000}" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${auto_compact_window}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
