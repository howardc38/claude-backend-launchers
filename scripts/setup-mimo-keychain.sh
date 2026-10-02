#!/usr/bin/env bash
# Backwards-compatible alias; now supports macOS and Linux.
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/setup-credential.sh" mimo "$@"
