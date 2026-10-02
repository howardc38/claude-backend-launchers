#!/usr/bin/env bash
# Tibo-style Claude Code launcher: Claude Code harness + GPT-5.6 via CLIProxyAPI.
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"

readonly DEFAULT_BASE_URL="http://127.0.0.1:8317"
readonly DEFAULT_MODEL="gpt-5.6-sol"
readonly DEFAULT_LUNA_MODEL="gpt-5.6-luna"
readonly DEFAULT_TERRA_MODEL="gpt-5.6-terra"
readonly DEFAULT_EFFORT="max"
readonly DEFAULT_CONCURRENCY="3"
readonly DEFAULT_MAX_CONTEXT_TOKENS="1050000"

base_url="${CLAUDEX_BASE_URL:-$DEFAULT_BASE_URL}"
active_model="${CLAUDEX_MODEL:-$DEFAULT_MODEL}"
effort="${CLAUDEX_EFFORT:-$DEFAULT_EFFORT}"
concurrency="${CLAUDEX_CONCURRENCY:-$DEFAULT_CONCURRENCY}"
max_context_tokens="${CLAUDEX_MAX_CONTEXT_TOKENS:-$DEFAULT_MAX_CONTEXT_TOKENS}"
skip_permissions="${CLAUDEX_SKIP_PERMISSIONS:-1}"
args=()
user_set_permissions=0

while (($#)); do
  case "$1" in
    --sol|--big|--gpt-5.6-sol)
      active_model="$DEFAULT_MODEL"
      ;;
    --luna|--mini|--gpt-5.6-luna)
      active_model="$DEFAULT_LUNA_MODEL"
      ;;
    --terra|--gpt-5.6-terra)
      active_model="$DEFAULT_TERRA_MODEL"
      ;;
    *)
      case "$1" in
        --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
          user_set_permissions=1
          ;;
      esac
      args+=("$1")
      ;;
  esac
  shift
done

case "$effort" in
  none|low|medium|high|xhigh|max) ;;
  *)
    printf 'claudex: invalid CLAUDEX_EFFORT=%q (use none|low|medium|high|xhigh|max)\n' "$effort" >&2
    exit 2
    ;;
esac

case "$concurrency" in
  ''|*[!0-9]*|0)
    printf 'claudex: CLAUDEX_CONCURRENCY must be a positive integer\n' >&2
    exit 2
    ;;
esac

case "$max_context_tokens" in
  ''|*[!0-9]*|0)
    printf 'claudex: CLAUDEX_MAX_CONTEXT_TOKENS must be a positive integer\n' >&2
    exit 2
    ;;
esac

case "$skip_permissions" in
  0|1) ;;
  *)
    printf 'claudex: CLAUDEX_SKIP_PERMISSIONS must be 0 or 1\n' >&2
    exit 2
    ;;
esac

if ! command -v claude >/dev/null 2>&1; then
  printf 'claudex: Claude Code (claude) is not installed or not on PATH\n' >&2
  exit 1
fi

cb_load_auth claudex
proxy_key="$CB_TOKEN"
unset CB_TOKEN

models_json=""
if ! models_json="$(curl --silent --show-error --fail \
  --connect-timeout 2 --max-time 10 \
  -H "Authorization: Bearer ${proxy_key}" \
  "${base_url}/v1/models")"; then
  printf 'claudex: CLIProxyAPI is not reachable or rejected the local key at %s\n' "$base_url" >&2
  printf 'Start CLIProxyAPI with your OS service manager or cli-proxy-api --config <config.yaml>\n' >&2
  exit 1
fi

if ! printf '%s' "$models_json" | grep -Fq "\"${active_model}\""; then
  printf 'claudex: model %s is not available through the current Codex OAuth account\n' "$active_model" >&2
  exit 1
fi
unset models_json

launch_flags=(--model "$active_model" --effort "$effort")
if [[ "$skip_permissions" == "1" && "$user_set_permissions" == "0" ]]; then
  launch_flags+=(--dangerously-skip-permissions)
fi

# macOS Bash 3.2 + `set -u` treats an empty "${args[@]}" expansion as an
# unbound variable. Build a command array that is always non-empty, and only
# expand args when the caller supplied passthrough arguments.
claude_command=(claude "${launch_flags[@]}")
if ((${#args[@]})); then
  claude_command+=("${args[@]}")
fi

exec env \
  -u ANTHROPIC_API_KEY \
  -u CLAUDE_CODE_USE_BEDROCK \
  -u CLAUDE_CODE_USE_VERTEX \
  -u CLAUDE_CODE_USE_FOUNDRY \
  ANTHROPIC_BASE_URL="$base_url" \
  ANTHROPIC_AUTH_TOKEN="$proxy_key" \
  ANTHROPIC_MODEL="$active_model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$active_model" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$active_model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$active_model" \
  ANTHROPIC_SMALL_FAST_MODEL="$active_model" \
  CLAUDE_CODE_SUBAGENT_MODEL="$active_model" \
  CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 \
  CLAUDE_CODE_EFFORT_LEVEL="$effort" \
  CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY="$concurrency" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="$max_context_tokens" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1 \
  ENABLE_TOOL_SEARCH=false \
  "${claude_command[@]}"
