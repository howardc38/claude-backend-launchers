#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_KEYCHAIN_SERVICE="glm-claude-code"
keychain_service="${GLM_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

mask() {
  local value="$1"
  local len="${#value}"
  if (( len <= 8 )); then
    printf '%s' '********'
    return 0
  fi
  printf '%s...%s' "${value:0:4}" "${value: -4}"
}

classify() {
  local value="$1"
  if [[ "${value}" =~ ^[A-Za-z0-9]{32}\. ]]; then
    printf '%s' 'zai-dot'
  elif [[ "${value}" =~ ^sk- ]]; then
    printf '%s' 'sk'
  elif [[ "${value}" =~ ^tp- ]]; then
    printf '%s' 'tp'
  else
    printf '%s' 'invalid'
  fi
}

if [[ -n "${GLM_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  echo "source=GLM_ANTHROPIC_AUTH_TOKEN prefix=$(classify "${GLM_ANTHROPIC_AUTH_TOKEN}") value=$(mask "${GLM_ANTHROPIC_AUTH_TOKEN}")"
  exit 0
fi

if command -v security >/dev/null 2>&1; then
  keychain_value="$(security find-generic-password -a "${USER}" -s "${keychain_service}" -w 2>/dev/null || true)"
  if [[ -n "${keychain_value}" ]]; then
    echo "source=macOS-keychain service=${keychain_service} prefix=$(classify "${keychain_value}") value=$(mask "${keychain_value}")"
    exit 0
  fi
fi

if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  echo "source=ANTHROPIC_AUTH_TOKEN prefix=$(classify "${ANTHROPIC_AUTH_TOKEN}") value=$(mask "${ANTHROPIC_AUTH_TOKEN}")"
  exit 0
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "source=ANTHROPIC_API_KEY prefix=$(classify "${ANTHROPIC_API_KEY}") value=$(mask "${ANTHROPIC_API_KEY}")"
  exit 0
fi

echo "source=none"
