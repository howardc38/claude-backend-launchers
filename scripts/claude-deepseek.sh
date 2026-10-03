#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The main, fast, and subagent models default to deepseek-v4-flash.
# Keep [1m] on the main model so Claude Code uses the full 1M context window
# instead of its 200K fallback for unknown third-party model IDs. This supported
# client-side suffix is stripped before sending requests to the provider.
# DeepSeek documents native 1M support for Flash; a local Claude Code smoke test
# also returned successfully with contextWindow=1000000 for Flash[1m].
readonly DEFAULT_DEEPSEEK_MODEL="deepseek-v4-flash[1m]"
readonly DEFAULT_DEEPSEEK_FAST_MODEL="deepseek-v4-flash"
readonly DEFAULT_DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic"
readonly DEFAULT_DEEPSEEK_EFFORT_LEVEL="max"

# Explicitly pin the auto-compact window to 1M, matching Claude Code's default
# for [1m] models. Lower DEEPSEEK_AUTO_COMPACT_WINDOW to compact earlier.
readonly DEFAULT_AUTO_COMPACT_WINDOW="1000000"

# Do not inherit the parent's ANTHROPIC_BASE_URL, ANTHROPIC_MODEL, or
# ANTHROPIC_SMALL_FAST_MODEL, which could route a nested session to the wrong
# endpoint. Override with DEEPSEEK_* variables instead.
model="${DEEPSEEK_MODEL:-$DEFAULT_DEEPSEEK_MODEL}"
fast_model="${DEEPSEEK_FAST_MODEL:-$DEFAULT_DEEPSEEK_FAST_MODEL}"
base_url="${DEEPSEEK_BASE_URL:-$DEFAULT_DEEPSEEK_BASE_URL}"
auto_compact_window="${DEEPSEEK_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"
effort_level="${DEEPSEEK_EFFORT_LEVEL:-$DEFAULT_DEEPSEEK_EFFORT_LEVEL}"
skip_permissions="${DEEPSEEK_SKIP_PERMISSIONS:-1}"

case "$skip_permissions" in
  0|1) ;;
  *)
    printf 'deepseek-claude: DEEPSEEK_SKIP_PERMISSIONS must be 0 or 1\n' >&2
    exit 2
    ;;
esac

user_set_permissions=0
for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
      user_set_permissions=1
      ;;
  esac
done

if [[ "$skip_permissions" == "1" && "$user_set_permissions" == "0" ]]; then
  set -- --dangerously-skip-permissions "$@"
fi

source "$script_dir/lib/credentials.sh"
cb_load_auth deepseek
token="$CB_TOKEN"
unset CB_TOKEN

# This launcher maps Opus/Sonnet to the selected main model and Haiku/small-fast
# to the fast model. Set both ANTHROPIC_AUTH_TOKEN (Authorization: Bearer) and
# ANTHROPIC_API_KEY (x-api-key); DeepSeek's /anthropic endpoint accepts both.
exec env \
  ANTHROPIC_BASE_URL="${base_url}" \
  ANTHROPIC_MODEL="${model}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast_model" \
  ANTHROPIC_SMALL_FAST_MODEL="${fast_model}" \
  CLAUDE_CODE_SUBAGENT_MODEL="${fast_model}" \
  CLAUDE_CODE_EFFORT_LEVEL="${effort_level}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${auto_compact_window}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
