#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_MIMO_MODEL="mimo-v2.6-pro"
readonly DEFAULT_MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic"

base_url="${MIMO_BASE_URL:-$DEFAULT_MIMO_BASE_URL}"
model="${MIMO_MODEL:-$DEFAULT_MIMO_MODEL}"

source "$script_dir/lib/credentials.sh"
cb_load_auth mimo
token="$CB_TOKEN"
unset CB_TOKEN

# MiMo's Anthropic-compatible endpoint authenticates with the `api-key` header
# (verified against Xiaomi's API docs + a live HTTP 200 smoke test). Do NOT "fix"
# this to `x-api-key` — that's the Anthropic-native header, not MiMo's.
# (`Authorization: Bearer ${token}` is also accepted by MiMo if you prefer.)
curl --silent --show-error --fail \
  --url "${base_url}/v1/messages" \
  --header "api-key: ${token}" \
  --header "Content-Type: application/json" \
  --data @- <<EOF
{
  "model": "${model}",
  "max_tokens": 32,
  "thinking": { "type": "disabled" },
  "messages": [
    {
      "role": "user",
      "content": "Reply with exactly: ok"
    }
  ]
}
EOF
