#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"

base_url="${CLAUDEX_BASE_URL:-http://127.0.0.1:8317}"
proxy_bin="$(command -v cliproxyapi 2>/dev/null || command -v cli-proxy-api 2>/dev/null || true)"

printf 'CLIProxyAPI binary: %s\n' "${proxy_bin:-missing}"
if [[ -n "$proxy_bin" ]]; then
  "$proxy_bin" -h 2>&1 | head -1 || true
fi

cb_load_auth claudex
printf 'Local client key: %s (value hidden)\n' "$CB_SOURCE"
proxy_key="$CB_TOKEN"
unset CB_TOKEN

if models_json="$(curl --silent --show-error --fail \
  --connect-timeout 2 --max-time 10 \
  -H "Authorization: Bearer ${proxy_key}" \
  "${base_url}/v1/models")"; then
  printf 'Proxy endpoint: reachable at %s\n' "$base_url"
else
  printf 'Proxy endpoint: unreachable or authentication failed at %s\n' "$base_url"
  exit 1
fi

for model in gpt-5.6-sol gpt-5.6-luna; do
  if printf '%s' "$models_json" | grep -Fq "\"${model}\""; then
    printf '%s: available\n' "$model"
  else
    printf '%s: unavailable\n' "$model"
  fi
done
