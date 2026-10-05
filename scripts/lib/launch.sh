#!/usr/bin/env bash
# Shared argument resolution and child environment preparation (Bash 3.2+).

cb_launch_lib_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$cb_launch_lib_dir/backends.sh"
source "$cb_launch_lib_dir/credentials.sh"

cb_clear_provider_env() {
  unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
  unset CLAUDE_CODE_USE_ANTHROPIC_AWS CLAUDE_CODE_USE_MANTLE
}

cb_parse_args() {
  CB_ARGS=()
  CB_USER_PERMISSIONS=0
  while (($#)); do
    case "$1" in
      --) CB_ARGS+=("$@"); break ;;
      --model|--effort)
        if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
          printf '%s requires a value\n' "$1" >&2; return 2
        fi
        if [[ "$1" == --model ]]; then CB_MODEL="$2"; else CB_EFFORT="$2"; fi
        shift 2 ;;
      --model=*) CB_MODEL="${1#*=}"; shift ;;
      --effort=*) CB_EFFORT="${1#*=}"; shift ;;
      --sol|--big|--gpt-5.6-sol|--luna|--mini|--gpt-5.6-luna|--terra|--gpt-5.6-terra)
        if [[ "$CB_BACKEND" == claudex ]]; then
          case "$1" in
            --sol|--big|--gpt-5.6-sol) CB_MODEL="$CB_DEFAULT_MODEL" ;;
            --luna|--mini|--gpt-5.6-luna) CB_MODEL="$CB_LUNA_MODEL" ;;
            --terra|--gpt-5.6-terra) CB_MODEL="$CB_TERRA_MODEL" ;;
          esac
        else
          CB_ARGS+=("$1")
        fi
        shift ;;
      --permission-mode)
        [[ $# -ge 2 && -n "$2" ]] || { printf '%s requires a value\n' "$1" >&2; return 2; }
        CB_USER_PERMISSIONS=1; CB_ARGS+=("$1" "$2"); shift 2 ;;
      --permission-mode=*|--dangerously-skip-permissions|--allow-dangerously-skip-permissions)
        CB_USER_PERMISSIONS=1; CB_ARGS+=("$1"); shift ;;
      --agent|--agents|--append-system-prompt|--append-system-prompt-file|--system-prompt|--system-prompt-file|\
      --append-subagent-system-prompt|--append-subagent-system-prompt-file|\
      --settings|--json-schema|--debug-file|--fallback-model|--input-format|--output-format|\
      --max-budget-usd|--max-turns|--permission-prompts|--permission-prompt-tool|--plugin-dir|--plugin-url|\
      --setting-sources|--session-id|--environment|--remote-control-session-name-prefix|--system-prompt-snapshot|\
      --autocompact|-n|--name|--tools|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools|\
      --add-dir|--mcp-config|--betas|--file)
        # Scalar and first variadic values belong to Claude, even if they look
        # like --model, --effort, or a proxy selector. Preserve empty values too.
        [[ $# -ge 2 ]] || { printf '%s requires a value\n' "$1" >&2; return 2; }
        CB_ARGS+=("$1" "$2"); shift 2 ;;
      *) CB_ARGS+=("$1"); shift ;;
    esac
  done
  case "$CB_EFFORT" in
    low|medium|high|xhigh|max) ;;
    *) printf 'Effort must be low|medium|high|xhigh|max; none is unsupported by Claude Code.\n' >&2; return 2 ;;
  esac
  cb_refresh_models || return $?
}

cb_prepare_environment() {
  cb_clear_provider_env
  # Avoid inheriting another backend's transport/context controls.
  unset API_FORCE_IDLE_TIMEOUT CLAUDE_STREAM_FIRST_BYTE_TIMEOUT_MS CLAUDE_STREAM_IDLE_TIMEOUT_MS
  unset CLAUDE_CODE_MAX_RETRIES CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY
  export ANTHROPIC_BASE_URL="$CB_BASE_URL" ANTHROPIC_MODEL="$CB_MODEL"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$CB_MODEL" ANTHROPIC_DEFAULT_SONNET_MODEL="$CB_MODEL"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$CB_FAST_MODEL" ANTHROPIC_SMALL_FAST_MODEL="$CB_FAST_MODEL"
  export CLAUDE_CODE_SUBAGENT_MODEL="$CB_SUBAGENT_MODEL"
  export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 CLAUDE_CODE_EFFORT_LEVEL="$CB_EFFORT"
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CB_MAX_CONTEXT_TOKENS"
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$CB_COMPACT_WINDOW"
  export CLAUDE_CODE_DISABLE_1M_CONTEXT=0
  # An explicit custom window must also override the tagged-ID 1M assumption.
  case "$CB_MODEL" in
    *'[1m]'|*'[1M]')
      [[ "$CB_MAX_CONTEXT_TOKENS" == 1000000 ]] || export CLAUDE_CODE_DISABLE_1M_CONTEXT=1 ;;
  esac
  export API_TIMEOUT_MS="$CB_API_TIMEOUT_MS"
  export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
  export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
  [[ -z "$CB_CONCURRENCY" ]] || export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY="$CB_CONCURRENCY"
  export ANTHROPIC_AUTH_TOKEN="$CB_TOKEN"
  if [[ "$CB_BACKEND" == claudex ]]; then
    unset ANTHROPIC_API_KEY
    export ENABLE_TOOL_SEARCH=false
  else
    export ANTHROPIC_API_KEY="$CB_TOKEN"
    unset ENABLE_TOOL_SEARCH
  fi
}

cb_launch_init() {
  local backend="$1"; shift
  cb_settings "$backend" || return $?
  cb_parse_args "$@" || return $?
  # The headless helper requests a safe default here, after the same parser has
  # identified actual permission options rather than opaque option values.
  if [[ "${CLAUDE_BACKEND_HEADLESS_DEFAULT:-0}" == 1 && "$CB_USER_PERMISSIONS" == 0 ]]; then
    if ((${#CB_ARGS[@]})); then
      CB_ARGS=(--permission-mode default "${CB_ARGS[@]}")
    else
      CB_ARGS=(--permission-mode default)
    fi
    CB_USER_PERMISSIONS=1
    CB_SKIP_PERMISSIONS=0
  fi
  unset CLAUDE_BACKEND_HEADLESS_DEFAULT
  local value_name
  for value_name in CB_MAX_CONTEXT_TOKENS CB_COMPACT_WINDOW CB_API_TIMEOUT_MS; do
    cb_validate_positive "$value_name" "${!value_name}" || return $?
  done
  cb_validate_boolean CB_SKIP_PERMISSIONS "$CB_SKIP_PERMISSIONS" || return $?
  [[ -z "$CB_CONCURRENCY" ]] || cb_validate_positive CB_CONCURRENCY "$CB_CONCURRENCY" || return $?
  if ! command -v claude >/dev/null 2>&1; then
    printf 'Claude Code (claude) is not installed or not on PATH\n' >&2; return 1
  fi
  cb_load_auth "$backend" || return $?
  cb_prepare_environment
}

cb_exec_claude() {
  local command=(claude --model "$CB_MODEL" --effort "$CB_EFFORT")
  if [[ "$CB_SKIP_PERMISSIONS" == 1 && "$CB_USER_PERMISSIONS" == 0 ]]; then
    command+=(--dangerously-skip-permissions)
  fi
  # Bash 3.2 with set -u cannot expand an empty array.
  if ((${#CB_ARGS[@]})); then command+=("${CB_ARGS[@]}"); fi
  unset CB_TOKEN
  exec "${command[@]}"
}
