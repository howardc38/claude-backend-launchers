#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/launch.sh"
source "$script_dir/lib/http.sh"
cb_launch_init claudex "$@"
cb_require_jq
if ! inventory="$(cb_http GET /v1/models)"; then
  printf 'claudex: CLIProxyAPI is unreachable or rejected the local client key.\n' >&2
  exit 1
fi
cb_check_model "$CB_WIRE_MODEL" "$inventory"
unset inventory
cb_exec_claude
