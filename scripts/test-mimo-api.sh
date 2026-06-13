#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_MIMO_MODEL="mimo-v2.5-pro"
readonly DEFAULT_MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic"
readonly DEFAULT_KEYCHAIN_SERVICE="mimo-claude-code"

base_url="${MIMO_BASE_URL:-$DEFAULT_MIMO_BASE_URL}"
model="${MIMO_MODEL:-$DEFAULT_MIMO_MODEL}"
keychain_service="${MIMO_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

resolve_token() {
  if [[ -n "${MIMO_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    printf '%s' "${MIMO_ANTHROPIC_AUTH_TOKEN}"
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
  echo "Missing MiMo token. Run setup-mimo-keychain.sh first." >&2
  exit 1
fi

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
