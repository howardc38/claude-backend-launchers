#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_KEYCHAIN_SERVICE="deepseek-claude-code"
keychain_service="${DEEPSEEK_KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"

mask() {
  local value="$1"
  local len="${#value}"
  if (( len <= 8 )); then
    printf '%s' '********'
    return 0
  fi
  printf '%s...%s' "${value:0:4}" "${value: -4}"
}

if [[ -n "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  prefix="invalid"
  [[ "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN}" =~ ^sk- ]] && prefix="sk"
  echo "source=DEEPSEEK_ANTHROPIC_AUTH_TOKEN prefix=${prefix} value=$(mask "${DEEPSEEK_ANTHROPIC_AUTH_TOKEN}")"
  exit 0
fi

if command -v security >/dev/null 2>&1; then
  keychain_value="$(security find-generic-password -a "${USER}" -s "${keychain_service}" -w 2>/dev/null || true)"
  if [[ -n "${keychain_value}" ]]; then
    prefix="invalid"
    [[ "${keychain_value}" =~ ^sk- ]] && prefix="sk"
    echo "source=macOS-keychain service=${keychain_service} prefix=${prefix} value=$(mask "${keychain_value}")"
    exit 0
  fi
fi

if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  prefix="invalid"
  [[ "${ANTHROPIC_AUTH_TOKEN}" =~ ^sk- ]] && prefix="sk"
  echo "source=ANTHROPIC_AUTH_TOKEN prefix=${prefix} value=$(mask "${ANTHROPIC_AUTH_TOKEN}")"
  exit 0
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  prefix="invalid"
  [[ "${ANTHROPIC_API_KEY}" =~ ^sk- ]] && prefix="sk"
  echo "source=ANTHROPIC_API_KEY prefix=${prefix} value=$(mask "${ANTHROPIC_API_KEY}")"
  exit 0
fi

echo "source=none"
