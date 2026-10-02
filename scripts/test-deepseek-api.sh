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

# DeepSeek 嘅 Anthropic-compatible endpoint 用 DeepSeek-native 認證:
# `Authorization: Bearer <key>`（同 DeepSeek native API 一致；亦接受 x-api-key）。
# ⚠️ 同 MiMo 唔一樣 —— MiMo 嗰個 endpoint 用 `api-key` header。
# 收到 HTTP 200 + JSON 即代表 endpoint + key 通（即使 reasoning 食晒少量 max_tokens、
# content 為空，200 已足以證明連線同認證 OK）。
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
