#!/usr/bin/env bash
# Go uses native IDs; each model has its own window and reasoning controls.
cb_go_lib_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

cb_go_resolve() {
  command -v python3 >/dev/null 2>&1 || { printf 'OpenCode Go requires Python 3.9+.\n' >&2; return 1; }
  local settings
  if ! settings="$(python3 "$cb_go_lib_dir/../opencode-go-proxy.py" describe "$CB_WIRE_MODEL" "$CB_EFFORT")"; then
    return 2
  fi
  local context output
  read -r CB_MODEL context output <<<"$settings"
  CB_WIRE_MODEL="$CB_MODEL"; CB_FAST_MODEL="$CB_MODEL"; CB_SUBAGENT_MODEL="$CB_MODEL"
  cb_setting CB_MAX_CONTEXT_TOKENS MAX_CONTEXT_TOKENS "$context"
  cb_validate_positive CB_MAX_CONTEXT_TOKENS "$CB_MAX_CONTEXT_TOKENS" || return $?
  if [[ "$CB_MAX_CONTEXT_TOKENS" -gt "$context" || "$CB_MAX_CONTEXT_TOKENS" -lt 4 ]]; then
    printf 'OpenCode Go context/output overrides exceed the selected model limits.\n' >&2
    return 2
  fi
  local default_output="$((CB_MAX_CONTEXT_TOKENS / 4))" default_compact
  [[ "$default_output" -le "$output" ]] || default_output="$output"
  cb_setting CB_GO_MAX_OUTPUT_TOKENS MAX_OUTPUT_TOKENS "$default_output"
  cb_validate_positive CB_GO_MAX_OUTPUT_TOKENS "$CB_GO_MAX_OUTPUT_TOKENS" || return $?
  if [[ "$CB_GO_MAX_OUTPUT_TOKENS" -gt "$output" || "$CB_GO_MAX_OUTPUT_TOKENS" -ge "$CB_MAX_CONTEXT_TOKENS" ]]; then
    printf 'OpenCode Go context/output overrides exceed the selected model limits.\n' >&2
    return 2
  fi
  default_compact="$((CB_MAX_CONTEXT_TOKENS * 3 / 4))"
  if [[ "$default_compact" -gt "$((CB_MAX_CONTEXT_TOKENS - CB_GO_MAX_OUTPUT_TOKENS))" ]]; then
    default_compact="$((CB_MAX_CONTEXT_TOKENS - CB_GO_MAX_OUTPUT_TOKENS))"
  fi
  cb_setting CB_COMPACT_WINDOW AUTO_COMPACT_WINDOW "$default_compact"
  cb_validate_positive CB_COMPACT_WINDOW "$CB_COMPACT_WINDOW" || return $?
  if [[ "$CB_MAX_CONTEXT_TOKENS" -gt "$context" || "$CB_GO_MAX_OUTPUT_TOKENS" -gt "$output" || "$((CB_COMPACT_WINDOW + CB_GO_MAX_OUTPUT_TOKENS))" -gt "$CB_MAX_CONTEXT_TOKENS" ]]; then
    printf 'OpenCode Go context/output overrides exceed the selected model limits.\n' >&2
    return 2
  fi
}
