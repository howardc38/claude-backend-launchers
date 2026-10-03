#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_GLM_MODEL="glm-5.3"
readonly DEFAULT_GLM_BASE_URL="https://api.z.ai/api/anthropic"

base_url="${GLM_BASE_URL:-$DEFAULT_GLM_BASE_URL}"
model="${GLM_MODEL:-$DEFAULT_GLM_MODEL}"

# Raw curl talks directly to Z.AI. Claude Code's [1m] suffix is a client-side
# convention, so strip it for this smoke test.
api_model="${model%[[]1m[]]}"

source "$script_dir/lib/credentials.sh"
cb_load_auth glm
token="$CB_TOKEN"
unset CB_TOKEN

curl --silent --show-error --fail \
  --connect-timeout 10 --max-time 60 \
  --url "${base_url}/v1/messages" \
  --header "x-api-key: ${token}" \
  --header "anthropic-version: 2023-06-01" \
  --header "Content-Type: application/json" \
  --data @- <<EOF
{
  "model": "${api_model}",
  "max_tokens": 256,
  "thinking": { "type": "disabled" },
  "messages": [
    {
      "role": "user",
      "content": "Reply with exactly: ok"
    }
  ]
}
EOF
