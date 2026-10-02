#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_GLM_MODEL="glm-5.2"
readonly DEFAULT_GLM_BASE_URL="https://api.z.ai/api/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="glm-claude-code"

base_url="${GLM_BASE_URL:-$DEFAULT_GLM_BASE_URL}"
model="${GLM_MODEL:-$DEFAULT_GLM_MODEL}"
keychain_service="${GLM_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

# Raw curl talks directly to Z.AI. Claude Code's [1m] suffix is a client-side
# convention, so strip it for this smoke test.
api_model="${model%[[]1m[]]}"

resolve_token() {
  if [[ -n "${GLM_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${GLM_ANTHROPIC_AUTH_TOKEN}"
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
  echo "Missing GLM token. Run setup-glm-keychain.sh first." >&2
  exit 1
fi

curl --silent --show-error --fail \
  --url "${base_url}/v1/messages" \
  --header "x-api-key: ${token}" \
  --header "anthropic-version: 2023-06-01" \
  --header "Content-Type: application/json" \
  --data @- <<EOF
{
  "model": "${api_model}",
  "max_tokens": 32,
  "messages": [
    {
      "role": "user",
      "content": "Reply with exactly: ok"
    }
  ]
}
EOF
