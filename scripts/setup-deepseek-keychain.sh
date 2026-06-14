#!/usr/bin/env bash
set -euo pipefail

if ! command -v security >/dev/null 2>&1; then
  echo "macOS Keychain 'security' command not found." >&2
  exit 1
fi

service="${DEEPSEEK_KEYCHAIN_SERVICE:-deepseek-claude-code}"

read -r -s -p "DeepSeek auth token: " token
echo

if [[ -z "${token}" ]]; then
  echo "Token cannot be empty." >&2
  exit 1
fi

if [[ ! "${token}" =~ ^sk-[A-Za-z0-9_-]+$ ]]; then
  echo "Token format looks wrong. Expected a DeepSeek API key starting with 'sk-'." >&2
  exit 1
fi

security add-generic-password -U -a "${USER}" -s "${service}" -w "${token}"
echo "Stored or updated token in macOS Keychain service '${service}'."
