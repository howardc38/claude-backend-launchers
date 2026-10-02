#!/usr/bin/env bash
set -euo pipefail

base_url="${CLAUDEX_BASE_URL:-http://127.0.0.1:8317}"
keychain_service="${CLAUDEX_KEYCHAIN_SERVICE:-cliproxyapi-claudex}"
proxy_bin="$(command -v cliproxyapi 2>/dev/null || true)"

printf 'CLIProxyAPI binary: %s\n' "${proxy_bin:-missing}"
if [[ -n "$proxy_bin" ]]; then
  "$proxy_bin" -h 2>&1 | head -1 || true
fi

if security find-generic-password -a "$(id -un)" -s "$keychain_service" >/dev/null 2>&1; then
  printf 'Local client key: Keychain service %s (value hidden)\n' "$keychain_service"
  proxy_key="$(security find-generic-password -a "$(id -un)" -s "$keychain_service" -w 2>/dev/null)"
else
  printf 'Local client key: missing\n'
  exit 1
fi

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
