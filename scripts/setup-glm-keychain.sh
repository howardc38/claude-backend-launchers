#!/usr/bin/env bash
set -euo pipefail

if ! command -v security >/dev/null 2>&1; then
  echo "macOS Keychain 'security' command not found." >&2
  exit 1
fi

service="${GLM_KEYCHAIN_SERVICE:-glm-claude-code}"

read -r -s -p "GLM / Z.AI auth token: " token
echo

if [[ -z "${token}" ]]; then
  echo "Token cannot be empty." >&2
  exit 1
fi

if [[ ! "${token}" =~ ^[A-Za-z0-9]{32}\.[A-Za-z0-9_-]+$ && ! "${token}" =~ ^(sk|tp)-[A-Za-z0-9_-]+$ ]]; then
  echo "Token format looks unusual. Expected Z.AI key like '<32 chars>.<secret>' or sk-/tp-prefixed key." >&2
  exit 1
fi

security add-generic-password -U -a "${USER}" -s "${service}" -w "${token}"
echo "Stored or updated token in macOS Keychain service '${service}'."
