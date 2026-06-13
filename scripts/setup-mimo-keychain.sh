#!/usr/bin/env bash
set -euo pipefail

if ! command -v security >/dev/null 2>&1; then
  echo "macOS Keychain 'security' command not found." >&2
  exit 1
fi

service="${MIMO_KEYCHAIN_SERVICE:-mimo-claude-code}"

read -r -s -p "Mimo auth token: " token
echo

if [[ -z "${token}" ]]; then
  echo "Token cannot be empty." >&2
  exit 1
fi

if [[ ! "${token}" =~ ^(sk|tp)-[A-Za-z0-9_-]+$ ]]; then
  echo "Token format looks wrong. Expected Xiaomi MiMo API key starting with 'sk-' or 'tp-'." >&2
  exit 1
fi

security add-generic-password -U -a "${USER}" -s "${service}" -w "${token}"
echo "Stored or updated token in macOS Keychain service '${service}'."
