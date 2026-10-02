#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_BASE_URL="http://127.0.0.1:8317"
readonly DEFAULT_KEYCHAIN_SERVICE="cliproxyapi-claudex"

base_url="${CLAUDEX_BASE_URL:-$DEFAULT_BASE_URL}"
keychain_service="${CLAUDEX_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"
model="${CLAUDEX_MODEL:-gpt-5.6-luna}"

case "${1:-}" in
  --sol) model="gpt-5.6-sol" ;;
  --luna|'') model="gpt-5.6-luna" ;;
  *) printf 'Usage: %s [--sol|--luna]\n' "$0" >&2; exit 2 ;;
esac

proxy_key="${CLAUDEX_PROXY_KEY:-}"
if [[ -z "$proxy_key" ]]; then
  proxy_key="$(security find-generic-password \
    -a "$(id -un)" -s "$keychain_service" -w 2>/dev/null || true)"
fi
if [[ -z "$proxy_key" ]]; then
  printf 'Error: local CLIProxyAPI key not found in Keychain service %s\n' "$keychain_service" >&2
  exit 1
fi

models_json="$(curl --silent --show-error --fail \
  --connect-timeout 2 --max-time 10 \
  -H "Authorization: Bearer ${proxy_key}" \
  "${base_url}/v1/models")"
if ! printf '%s' "$models_json" | grep -Fq "\"${model}\""; then
  printf 'Error: %s is not listed by CLIProxyAPI\n' "$model" >&2
  exit 1
fi

payload="$(printf '{"model":"%s","max_tokens":32,"stream":false,"messages":[{"role":"user","content":"Reply with exactly OK"}]}' "$model")"
response="$(curl --silent --show-error --fail \
  --max-time 120 \
  -H "Authorization: Bearer ${proxy_key}" \
  -H 'Content-Type: application/json' \
  -H 'anthropic-version: 2023-06-01' \
  -d "$payload" \
  "${base_url}/v1/messages")"

if command -v jq >/dev/null 2>&1; then
  reply="$(printf '%s' "$response" | jq -r '.content[]? | select(.type == "text") | .text' | head -1)"
else
  reply="$(printf '%s' "$response" | grep -o '"text":"[^"]*"' | head -1)"
fi

if [[ -z "$reply" ]]; then
  printf 'Error: proxy returned no text content\n' >&2
  exit 1
fi

printf 'CLIProxyAPI smoke test OK (%s): %s\n' "$model" "$reply"
