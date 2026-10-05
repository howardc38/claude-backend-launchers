#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -P -- "$script_dir/.." && pwd)"
source "$script_dir/lib/backends.sh"

usage() {
  printf 'Usage: ask-backend mimo|deepseek|glm <prompt> [extra Claude flags...]\n'
  printf '       ask-backend --list\n\n'
  local backend
  for backend in mimo deepseek glm; do
    cb_profile "$backend"
    printf '  %-10s %s (%s)\n' "$backend" "$CB_DEFAULT_MODEL" "$CB_DEFAULT_URL"
  done
  printf '\nUses default permission mode; existing permission rules still apply.\n'
}
case "${1:-}" in
  ''|-h|--help) usage; exit 0 ;;
  --list) printf 'mimo\ndeepseek\nglm\n'; exit 0 ;;
esac
backend="$1"; shift
case "$backend" in
  mimo|deepseek|glm) ;;
  *) printf 'Unknown backend: %s\n' "$backend" >&2; usage >&2; exit 2 ;;
esac
[[ $# -ge 1 ]] || { printf 'Missing prompt.\n' >&2; usage >&2; exit 2; }
prompt="$1"; shift
export CLAUDE_BACKEND_HEADLESS_DEFAULT=1
cb_profile "$backend"
export "${CB_PREFIX}_BASE_URL=$CB_DEFAULT_URL"
# Generic parent credentials belong to that session, never the selected backend.
unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_MODEL
unset ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
# Keep the prompt behind -- so selector-looking text stays literal.
exec "$repo_dir/${backend}-claude" -p "$@" -- "$prompt" < /dev/null
