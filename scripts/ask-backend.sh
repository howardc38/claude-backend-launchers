#!/usr/bin/env bash
set -euo pipefail

# ask-backend — call a backend LLM agent from Claude Code or any shell.
#
# Run the backend launcher in headless print mode (claude -p). First use
# `env -u` to clear inherited ANTHROPIC_* endpoint/model settings, then pin
# the backend-specific base URL so the child connects to the correct endpoint,
# even when called from a parent session configured for another proxy.
#
# Usage:
#   ask-backend <backend> <prompt> [extra claude flags...]
#   ask-backend --list | -h | --help
#
# backend: mimo | deepseek | glm
#
# Examples:
#   ask-backend mimo "explain the TCP three-way handshake in one sentence"
#   ask-backend deepseek "review this function: ..."
#   ask-backend deepseek "update the README" --permission-mode acceptEdits   # Allow file edits
#
# Output: the backend agent's final answer as plain text on stdout.
# Each launcher loads its own token from the environment or OS credential store.

prog="ask-backend"

usage() {
  cat <<EOF
Usage: ${prog} <backend> <prompt> [extra claude flags...]
       ${prog} --list

backends:
  mimo       MiMo v2.6 Pro    (https://api.xiaomimimo.com/anthropic)
  deepseek   DeepSeek V4 Flash (https://api.deepseek.com/anthropic)
  glm        GLM 5.3          (https://api.z.ai/api/anthropic)

examples:
  ${prog} mimo "explain the TCP handshake in one line"
  ${prog} deepseek "review this code: ..."
EOF
}

# The engine lives in <repo>/scripts/ and the root entrypoint executes it by
# absolute path, so derive the repository root from this script's location.
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -P -- "${script_dir}/.." && pwd)"

case "${1:-}" in
  ""|-h|--help)
    usage
    exit 0
    ;;
  --list)
    echo "mimo"
    echo "deepseek"
    echo "glm"
    exit 0
    ;;
esac

backend="$1"
shift

if [[ $# -lt 1 ]]; then
  echo "Error: missing <prompt>." >&2
  usage >&2
  exit 2
fi

prompt="$1"
shift
# Remaining "$@" contains optional extra flags; an empty "$@" is safe in Bash 3.2 with set -u.

user_set_permissions=0
for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
      user_set_permissions=1
      ;;
  esac
done
if [[ "$user_set_permissions" == 0 ]]; then
  set -- --permission-mode default "$@"
fi

# Clear inherited endpoint/model settings so nested calls use the intended backend.
# Generic parent credentials belong to that session, not the selected backend.
strip_env=(
  -u ANTHROPIC_AUTH_TOKEN
  -u ANTHROPIC_API_KEY
  -u ANTHROPIC_BASE_URL
  -u ANTHROPIC_MODEL
  -u ANTHROPIC_SMALL_FAST_MODEL
  -u ANTHROPIC_DEFAULT_OPUS_MODEL
  -u ANTHROPIC_DEFAULT_SONNET_MODEL
  -u ANTHROPIC_DEFAULT_HAIKU_MODEL
)

# Pass the prompt as an argument. `< /dev/null` avoids claude -p waiting three
# seconds for piped stdin and emitting a warning during agent-to-backend calls.
# To pass file contents through stdin, use the launcher directly:
# `deepseek-claude -p "..." < file`.
case "${backend}" in
  mimo)
    exec env "${strip_env[@]}" \
      MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic" \
      "${repo_dir}/mimo-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  deepseek)
    exec env "${strip_env[@]}" \
      DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic" \
      "${repo_dir}/deepseek-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  glm)
    exec env "${strip_env[@]}" \
      GLM_BASE_URL="https://api.z.ai/api/anthropic" \
      "${repo_dir}/glm-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  *)
    echo "Error: unknown backend '${backend}'. Use: mimo | deepseek | glm (see --list)." >&2
    usage >&2
    exit 2
    ;;
esac
