#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_DEEPSEEK_MODEL="deepseek-v4-pro"
readonly DEFAULT_DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="deepseek-claude-code"

base_url="${DEEPSEEK_BASE_URL:-$DEFAULT_DEEPSEEK_BASE_URL}"
model="${DEEPSEEK_MODEL:-$DEFAULT_DEEPSEEK_MODEL}"
keychain_service="${DEEPSEEK_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

resolve_token() {
  if [[ -n "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN}"
    return 0
  fi

  if command -v security >/dev/null 2>&1; then
    token_from_keychain="$(security find-generic-password -a "${USER}" -s "${keychain_service}" -w 2>/dev/null || true)"
    if [[ -n "${token_from_keychain}" ]]; then
      printf '%s' "${token_from_keychain}"
      return 0
    fi
  fi

  if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${ANTHROPIC_AUTH_TOKEN}"
    return 0
  fi

  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    printf '%s' "${ANTHROPIC_API_KEY}"
    return 0
  fi

  return 0
}

token="$(resolve_token)"

if [[ -z "${token}" ]]; then
  echo "Missing DeepSeek token. Run setup-deepseek-keychain.sh first." >&2
  exit 1
fi

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
