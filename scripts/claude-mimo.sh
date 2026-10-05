#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/launch.sh"
cb_launch_init mimo "$@"

# MiMo-specific stream safeguards remain separate from shared launch policy.
cb_setting CB_FIRST_BYTE_TIMEOUT STREAM_FIRST_BYTE_TIMEOUT_MS 90000
cb_setting CB_IDLE_TIMEOUT STREAM_IDLE_TIMEOUT_MS 90000
cb_setting CB_MAX_RETRIES MAX_RETRIES 3
cb_setting CB_NONSTREAMING_FALLBACK DISABLE_NONSTREAMING_FALLBACK 0
for value_name in CB_FIRST_BYTE_TIMEOUT CB_IDLE_TIMEOUT CB_MAX_RETRIES; do
  cb_validate_positive "$value_name" "${!value_name}"
done
cb_validate_boolean CB_NONSTREAMING_FALLBACK "$CB_NONSTREAMING_FALLBACK"
export API_FORCE_IDLE_TIMEOUT=1
export CLAUDE_STREAM_FIRST_BYTE_TIMEOUT_MS="$CB_FIRST_BYTE_TIMEOUT"
export CLAUDE_STREAM_IDLE_TIMEOUT_MS="$CB_IDLE_TIMEOUT"
export CLAUDE_CODE_MAX_RETRIES="$CB_MAX_RETRIES"
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="$CB_NONSTREAMING_FALLBACK"
cb_exec_claude
