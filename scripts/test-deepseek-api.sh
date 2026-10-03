#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_DEEPSEEK_MODEL="deepseek-v4-pro"
readonly DEFAULT_DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic"

base_url="${DEEPSEEK_BASE_URL:-$DEFAULT_DEEPSEEK_BASE_URL}"
model="${DEEPSEEK_MODEL:-$DEFAULT_DEEPSEEK_MODEL}"

source "$script_dir/lib/credentials.sh"
cb_load_auth deepseek
token="$CB_TOKEN"
unset CB_TOKEN

# DeepSeek's Anthropic-compatible endpoint accepts its native authentication:
# `Authorization: Bearer <key>`; x-api-key is also accepted.
# MiMo's endpoint uses the `api-key` header instead.
# HTTP 200 with JSON confirms connectivity and authentication, even when
# reasoning consumes the small max_tokens budget and leaves content empty.
curl --silent --show-error --fail \
  --url "${base_url}/v1/messages" \
  --header "Authorization: Bearer ${token}" \
  --header "Content-Type: application/json" \
  --data @- <<EOF
{
  "model": "${model}",
  "max_tokens": 64,
  "messages": [
    {
      "role": "user",
      "content": "Reply with exactly: ok"
    }
  ]
}
EOF
