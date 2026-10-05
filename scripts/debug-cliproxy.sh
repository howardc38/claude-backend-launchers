#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"
source "$script_dir/lib/http.sh"
cb_settings claudex
cb_refresh_models
cb_require_jq
proxy_bin="$(command -v cliproxyapi 2>/dev/null || command -v cli-proxy-api 2>/dev/null || true)"
printf 'CLIProxyAPI binary: %s\n' "${proxy_bin:-missing}"
cb_load_auth claudex
printf 'Local client key: %s (value hidden)\n' "$CB_SOURCE"
if ! inventory="$(cb_http GET /v1/models)"; then
  printf 'Proxy endpoint: unreachable or authentication failed\n' >&2; exit 1
fi
printf 'Proxy endpoint: reachable at %s\n' "$CB_BASE_URL"
if ! models="$(printf '%s' "$inventory" | cb_model_ids)"; then
  printf 'Proxy returned an invalid model inventory.\n' >&2; exit 1
fi
printf 'Available models:\n%s\n' "$models"
cb_check_model "$CB_WIRE_MODEL" "$inventory"
printf 'Selected model: %s (available)\n' "$CB_MODEL"
unset CB_TOKEN inventory models
